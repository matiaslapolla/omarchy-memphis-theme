#!/bin/bash
# Runs install.sh and uninstall.sh against a copy of the repo under a
# temporary HOME with stub commands first on PATH. Nothing live changes.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export STUB_STATE="$TMP/stub"
export PATH="$ROOT/tests/stubs:$PATH"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE

PASS=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
ok() {
  PASS=$((PASS + 1))
  echo "ok - $*"
}

for cmd in gsettings hyprctl omarchy yay fc-cache sudo; do
  [[ $(command -v "$cmd") == "$ROOT/tests/stubs/$cmd" ]] || fail "$cmd does not resolve to the stub"
done

# A copy of the repo, so the theme link points into the temp dir. The real
# build.sh is used when it exists; otherwise a stub stands in for it.
make_repo() {
  local repo="$1" build_mode="$2"
  mkdir -p "$repo"
  (cd "$ROOT" && tar --exclude=.git -cf - .) | tar -xf - -C "$repo"
  if [[ ! -f $repo/fonts/W95FA.otf ]]; then
    mkdir -p "$repo/fonts"
    echo "fake font" >"$repo/fonts/W95FA.otf"
    echo "fake license" >"$repo/fonts/OFL.txt"
  fi
  mkdir -p "$repo/extras/bar-bevel"
  case "$build_mode" in
    fail)
      printf '#!/bin/bash\necho "anchor not found" >&2\nexit 1\n' >"$repo/extras/bar-bevel/build.sh"
      ;;
    real)
      if [[ ! -f $repo/extras/bar-bevel/build.sh ]] ||
        [[ ! -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/bar ]]; then
        cat >"$repo/extras/bar-bevel/build.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
mkdir -p "$1/memphis.bar"
echo '{"id": "memphis.bar", "kinds": ["bar"]}' >"$1/memphis.bar/manifest.json"
BUILD
      fi
      ;;
  esac
}

fresh_home() {
  rm -rf "$HOME" "$STUB_STATE"
  mkdir -p "$HOME" "$STUB_STATE"
  : >"$STUB_STATE/calls.log"
}

snapshot() {
  (
    cd "$HOME"
    find . -printf '%p %y %m %l\n' | sort
    find . -type f -exec sha256sum {} + | sort
  )
}

set_theme() {
  mkdir -p "$HOME/.local/state/omarchy/current"
  echo "$1" >"$HOME/.local/state/omarchy/current/theme.name"
}

REPO="$TMP/repo"
make_repo "$REPO" real
CONFIG="$HOME/.config"
LINK="$CONFIG/omarchy/themes/memphis"
FONT_DIR="$HOME/.local/share/fonts/memphis"
PLUGIN="$CONFIG/omarchy/plugins/memphis.bar"

# ------------------------------------------------------------ dry run

fresh_home
before=$(snapshot)
out=$(bash "$REPO/install.sh" --dry-run)
[[ $(snapshot) == "$before" ]] || fail "install --dry-run changed HOME"
[[ $out == *"[dry-run]"* ]] || fail "install --dry-run printed no actions"
[[ $out == *"[dry-run] yay -S"* ]] || fail "install --dry-run did not show the yay step"
[[ ! -s $STUB_STATE/calls.log ]] || fail "install --dry-run ran commands: $(cat "$STUB_STATE/calls.log")"
ok "install --dry-run prints the actions and changes nothing"

bash "$REPO/install.sh" -h | grep -q -- '--no-packages' || fail "-h does not list --no-packages"
if bash "$REPO/install.sh" --bogus >/dev/null 2>&1; then fail "install accepted an unknown option"; fi
ok "install -h prints usage and an unknown option fails"

# ------------------------------------------------------------ install

out=$(bash "$REPO/install.sh" --no-packages)
[[ -L $LINK && $(readlink -f "$LINK") == "$REPO" ]] || fail "theme link missing or wrong"
for event in theme-set post-boot post-update; do
  hook="$CONFIG/omarchy/hooks/$event.d/memphis"
  [[ -f $hook ]] || fail "$event hook missing"
  [[ $(stat -c %a "$hook") == 755 ]] || fail "$event hook mode is not 755"
  cmp "$REPO/extras/hooks/$event" "$hook" || fail "$event hook differs from the repo"
done
cmp "$REPO/fonts/W95FA.otf" "$FONT_DIR/W95FA.otf" || fail "font not installed"
[[ -f $FONT_DIR/OFL.txt ]] || fail "OFL.txt not installed"
grep -qx "fc-cache -f $FONT_DIR" "$STUB_STATE/calls.log" || fail "fc-cache did not run on the font dir"
[[ $(jq -r .id "$PLUGIN/manifest.json") == "memphis.bar" ]] || fail "memphis.bar not built"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-build.*') ]] || fail "install left a build dir"
! grep -q '^yay ' "$STUB_STATE/calls.log" || fail "--no-packages ran yay"
! grep -qE '^(omarchy|gsettings|hyprctl) ' "$STUB_STATE/calls.log" || fail "install ran a live command"
[[ $out == *"omarchy theme set memphis"* ]] || fail "install did not print the final instruction"
ok "install --no-packages links the theme, copies hooks and font, builds the bar"

bash "$REPO/install.sh" --no-packages >/dev/null
[[ -z $(find "$CONFIG/omarchy/themes" -maxdepth 1 -name 'memphis.bak.*') ]] || fail "a second install made a backup"
[[ $(readlink -f "$LINK") == "$REPO" ]] || fail "a second install broke the link"
ok "a second install keeps the link and makes no backup"

before=$(snapshot)
: >"$STUB_STATE/calls.log"
bash "$REPO/install.sh" --dry-run --no-packages >/dev/null
[[ $(snapshot) == "$before" ]] || fail "install --dry-run changed an installed HOME"
[[ ! -s $STUB_STATE/calls.log ]] || fail "install --dry-run ran commands"
ok "install --dry-run after an install changes nothing"

bash "$REPO/install.sh" >/dev/null
grep -q '^yay -S --needed chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git$' \
  "$STUB_STATE/calls.log" || fail "install without --no-packages did not call yay"
ok "install without --no-packages installs the three packages with yay"

# ------------------------------------------------------------ uninstall

set_theme memphis
before=$(snapshot)
if bash "$REPO/uninstall.sh" >"$TMP/out" 2>&1; then fail "uninstall ran while memphis is current"; fi
grep -q 'Switch to another theme first' "$TMP/out" || fail "uninstall refusal has no message"
[[ $(snapshot) == "$before" ]] || fail "a refused uninstall changed HOME"
ok "uninstall refuses while memphis is the current theme"

set_theme jade-horse
before=$(snapshot)
: >"$STUB_STATE/calls.log"
bash "$REPO/uninstall.sh" --dry-run >/dev/null
[[ $(snapshot) == "$before" ]] || fail "uninstall --dry-run changed HOME"
[[ ! -s $STUB_STATE/calls.log ]] || fail "uninstall --dry-run ran commands"
ok "uninstall --dry-run changes nothing"

out=$(bash "$REPO/uninstall.sh")
[[ ! -e $LINK && ! -L $LINK ]] || fail "uninstall left the theme link"
for event in theme-set post-boot post-update; do
  [[ ! -e $CONFIG/omarchy/hooks/$event.d/memphis ]] || fail "uninstall left the $event hook"
done
[[ ! -e $PLUGIN ]] || fail "uninstall left memphis.bar"
[[ ! -e $FONT_DIR ]] || fail "uninstall left the font"
[[ $out == *"yay -R chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git"* ]] ||
  fail "uninstall did not print the package removal command"
! grep -qE '^(yay|omarchy|gsettings|hyprctl) ' "$STUB_STATE/calls.log" || fail "uninstall ran a live command"
leftover=$(find "$HOME" -path "$HOME/.local/state" -prune -o \( -type f -o -type l \) -print)
[[ -z $leftover ]] || fail "uninstall left files: $leftover"
ok "uninstall removes hooks, link, bevel bar and font and leaves packages"

# ------------------------------------------------------------ backup

fresh_home
mkdir -p "$LINK"
echo "user theme" >"$LINK/colors.toml"
bash "$REPO/install.sh" --no-packages >/dev/null
backups=("$CONFIG/omarchy/themes"/memphis.bak.*)
[[ ${#backups[@]} == 1 && -f ${backups[0]}/colors.toml ]] || fail "the old theme dir was not backed up"
[[ -L $LINK && $(readlink -f "$LINK") == "$REPO" ]] || fail "the link was not created after the backup"
ok "install moves a theme dir that is not our link to memphis.bak.<timestamp>"

# ------------------------------------------------------------ failed build

FAIL_REPO="$TMP/repo-fail"
make_repo "$FAIL_REPO" fail
fresh_home
bash "$FAIL_REPO/install.sh" --no-packages >"$TMP/out" 2>&1 || fail "install failed when the build failed"
grep -q 'bevel bar build failed' "$TMP/out" || fail "no warning for the failed build"
[[ ! -e $PLUGIN ]] || fail "a failed build left memphis.bar"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-build.*') ]] || fail "a failed build left a build dir"
[[ -L $LINK && -f $CONFIG/omarchy/hooks/theme-set.d/memphis ]] || fail "a failed build stopped the install"
ok "a failed bar build warns and the install continues"

echo "install.sh: $PASS checks passed"
