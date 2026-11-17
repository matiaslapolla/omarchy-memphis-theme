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
  (cd "$ROOT" && tar --exclude=.git --exclude=.worktrees -cf - .) | tar -xf - -C "$repo"
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
    record)
      cat >"$repo/extras/bar-bevel/build.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$1" >>"$STUB_STATE/build.args"
mkdir -p "$1/memphis.bar"
echo '{"id": "memphis.bar", "kinds": ["bar"]}' >"$1/memphis.bar/manifest.json"
BUILD
      ;;
    real)
      if [[ ! -f $repo/extras/bar-bevel/build.sh ]] ||
        [[ ! -d ${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/bar ]]; then
        cat >"$repo/extras/bar-bevel/build.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
if [[ -e $1/memphis.bar && $(jq -r .id "$1/memphis.bar/manifest.json") != memphis.bar ]]; then exit 1; fi
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
GRAY_LINK="$CONFIG/omarchy/themes/memphis-gray"
DARK_LINK="$CONFIG/omarchy/themes/memphis-dark"
FONT_DIR="$HOME/.local/share/fonts/memphis"
PLUGIN="$CONFIG/omarchy/plugins/memphis.bar"
SHELL_JSON="$CONFIG/omarchy/shell.json"

bar_id() { if [[ -s $SHELL_JSON ]]; then jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON"; else echo omarchy.bar; fi; }

# Prints the omarchy, gsettings and hyprctl calls, one per line.
live_calls() { grep -E '^(omarchy|gsettings|hyprctl) ' "$STUB_STATE/calls.log" || true; }

set_bar_id() {
  mkdir -p "${SHELL_JSON%/*}"
  jq -nS --arg id "$1" '{bar: {id: $id, position: "top"}}' >"$SHELL_JSON"
}

# ------------------------------------------------------------ dry run

fresh_home
before=$(snapshot)
out=$(bash "$REPO/install.sh" --dry-run)
[[ $(snapshot) == "$before" ]] || fail "install --dry-run changed HOME"
[[ $out == *"[dry-run]"* ]] || fail "install --dry-run printed no actions"
[[ $out == *"[dry-run] yay -S"* ]] || fail "install --dry-run did not show the yay step"
[[ $out == *"[dry-run] omarchy bar use memphis.bar"* ]] || fail "install --dry-run did not show the bar switch"
[[ ! -s $STUB_STATE/calls.log ]] || fail "install --dry-run ran commands: $(cat "$STUB_STATE/calls.log")"
ok "install --dry-run prints the actions and changes nothing"

bash "$REPO/install.sh" -h | grep -q -- '--no-packages' || fail "-h does not list --no-packages"
if bash "$REPO/install.sh" --bogus >/dev/null 2>&1; then fail "install accepted an unknown option"; fi
ok "install -h prints usage and an unknown option fails"

# ------------------------------------------------------------ install

out=$(bash "$REPO/install.sh" --no-packages)
[[ -L $LINK && $(readlink -f "$LINK") == "$REPO" ]] || fail "theme link missing or wrong"
[[ -L $GRAY_LINK && $(readlink -f "$GRAY_LINK") == "$REPO/variants/memphis-gray" ]] || fail "memphis-gray link missing or wrong"
[[ -L $DARK_LINK && $(readlink -f "$DARK_LINK") == "$REPO/variants/memphis-dark" ]] || fail "memphis-dark link missing or wrong"
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
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-*') ]] || fail "install left a build dir"
! grep -q '^yay ' "$STUB_STATE/calls.log" || fail "--no-packages ran yay"
[[ $(live_calls) == "omarchy bar use memphis.bar" ]] || fail "install ran other live commands: $(live_calls)"
for slug in memphis memphis-gray memphis-dark; do
  [[ $out == *"omarchy theme set $slug"$'\n'* || $out == *"omarchy theme set $slug" ]] ||
    fail "install did not print the command for $slug"
done
ok "install --no-packages links the three Variants, copies hooks and font, builds the bar"

[[ $(bar_id) == memphis.bar ]] || fail "install did not make memphis.bar the bar engine: $(bar_id)"
[[ $out == *"Switching the bar from omarchy.bar to memphis.bar"* ]] || fail "install did not say it switches the bar"
ok "install switches the bar engine from the stock bar to memphis.bar"

: >"$STUB_STATE/calls.log"
bash "$REPO/install.sh" --no-packages >/dev/null
[[ -z $(find "$CONFIG/omarchy" -maxdepth 2 -name 'memphis-theme.old.*') ]] ||
  fail "a second install moved the theme link aside"
[[ $(readlink -f "$LINK") == "$REPO" ]] || fail "a second install broke the link"
[[ -z $(live_calls) ]] || fail "a second install ran live commands: $(live_calls)"
[[ $(bar_id) == memphis.bar ]] || fail "a second install changed the bar engine"
ok "a second install keeps the link, the bar engine and moves nothing aside"

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
set_theme memphis-dark
before=$(snapshot)
if bash "$REPO/uninstall.sh" >"$TMP/out" 2>&1; then fail "uninstall ran while memphis-dark is current"; fi
[[ $(snapshot) == "$before" ]] || fail "a refused uninstall changed HOME under memphis-dark"
ok "uninstall refuses while a Memphis slug is the current theme"

! bash "$REPO/uninstall.sh" -h | grep -q -- '--no-packages' || fail "uninstall -h still lists --no-packages"
ok "uninstall has no --no-packages option"

set_theme jade-horse
before=$(snapshot)
: >"$STUB_STATE/calls.log"
out=$(bash "$REPO/uninstall.sh" --dry-run)
[[ $(snapshot) == "$before" ]] || fail "uninstall --dry-run changed HOME"
[[ ! -s $STUB_STATE/calls.log ]] || fail "uninstall --dry-run ran commands"
[[ $out == *"[dry-run] omarchy bar reset"* ]] || fail "uninstall --dry-run did not show the bar reset"
ok "uninstall --dry-run changes nothing"

out=$(bash "$REPO/uninstall.sh")
for link in "$LINK" "$GRAY_LINK" "$DARK_LINK"; do
  [[ ! -e $link && ! -L $link ]] || fail "uninstall left the theme link $link"
done
for event in theme-set post-boot post-update; do
  [[ ! -e $CONFIG/omarchy/hooks/$event.d/memphis ]] || fail "uninstall left the $event hook"
done
[[ ! -e $PLUGIN ]] || fail "uninstall left memphis.bar"
[[ ! -e $FONT_DIR ]] || fail "uninstall left the font"
[[ $out == *"yay -R chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git"* ]] ||
  fail "uninstall did not print the package removal command"
! grep -q '^yay ' "$STUB_STATE/calls.log" || fail "uninstall ran yay"
[[ $(live_calls) == "omarchy bar reset" ]] || fail "uninstall ran other live commands: $(live_calls)"
# Omarchy keeps shell.json; only the bar id goes.
leftover=$(find "$HOME" -path "$HOME/.local/state" -prune -o -path "$SHELL_JSON" -prune -o \( -type f -o -type l \) -print)
[[ -z $leftover ]] || fail "uninstall left files: $leftover"
ok "uninstall removes hooks, the three links, bevel bar and font and leaves packages"

[[ $(bar_id) == omarchy.bar ]] || fail "uninstall left the bar engine on $(bar_id)"
grep -qx memphis.bar "$STUB_STATE/bar-reset.plugins" || fail "uninstall removed memphis.bar before the bar reset"
ok "uninstall resets the bar engine to omarchy.bar before it removes memphis.bar"

# ------------------------------------------------------------ custom bar

fresh_home
set_bar_id local.neon-bar
cp "$SHELL_JSON" "$TMP/shell.seed"
bash "$REPO/install.sh" --no-packages >"$TMP/out" 2>&1
[[ -f $PLUGIN/manifest.json ]] || fail "install with a custom bar did not build memphis.bar"
cmp "$TMP/shell.seed" "$SHELL_JSON" || fail "install changed shell.json with a custom bar"
[[ -z $(live_calls) ]] || fail "install with a custom bar ran live commands: $(live_calls)"
grep -q 'the bar uses local.neon-bar' "$TMP/out" || fail "install did not warn about the custom bar"
grep -q 'omarchy bar use memphis.bar' "$TMP/out" || fail "install did not print the bar command"
ok "install keeps a custom bar engine, warns and prints the command"

set_theme jade-horse
bash "$REPO/uninstall.sh" >/dev/null
cmp "$TMP/shell.seed" "$SHELL_JSON" || fail "uninstall changed shell.json with a custom bar"
[[ -z $(live_calls) ]] || fail "uninstall with a custom bar ran live commands: $(live_calls)"
[[ ! -e $PLUGIN ]] || fail "uninstall left memphis.bar with a custom bar"
ok "uninstall keeps a custom bar engine and removes memphis.bar"

fresh_home
set_bar_id omarchy.bar
bash "$REPO/install.sh" --no-packages >/dev/null
[[ $(bar_id) == memphis.bar ]] || fail "install did not switch an explicit omarchy.bar: $(bar_id)"
ok "install switches an explicit omarchy.bar id to memphis.bar"

# A failing omarchy, first on PATH, for the bar commands only.
mkdir -p "$TMP/failbin"
cat >"$TMP/failbin/omarchy" <<'STUB'
#!/bin/bash
printf 'omarchy %s\n' "$*" >>"$STUB_STATE/calls.log"
exit 1
STUB
chmod 755 "$TMP/failbin/omarchy"

set_theme jade-horse
PATH="$TMP/failbin:$PATH" bash "$REPO/uninstall.sh" >"$TMP/out" 2>&1 || fail "uninstall failed when the bar reset failed"
[[ -f $PLUGIN/manifest.json ]] || fail "uninstall removed memphis.bar although the bar reset failed"
grep -q "Run 'omarchy bar reset'" "$TMP/out" || fail "uninstall did not tell the user to reset the bar"
ok "uninstall keeps memphis.bar when omarchy bar reset fails"

fresh_home
PATH="$TMP/failbin:$PATH" bash "$REPO/install.sh" --no-packages >"$TMP/out" 2>&1 || fail "install failed when the bar switch failed"
[[ -f $PLUGIN/manifest.json && -L $LINK ]] || fail "a failed bar switch undid the install"
grep -q 'omarchy bar use failed' "$TMP/out" || fail "install did not warn about the failed bar switch"
ok "install warns and finishes when omarchy bar use fails"

# ------------------------------------------------------------ old theme dir

# omarchy-theme-list shows every entry in themes/, so the old dir goes outside it.
fresh_home
mkdir -p "$LINK"
echo "user theme" >"$LINK/colors.toml"
bash "$REPO/install.sh" --no-packages >/dev/null
old_dirs=("$CONFIG/omarchy"/memphis-theme.old.*)
[[ -f ${old_dirs[0]}/colors.toml ]] || fail "the old theme dir was not moved to memphis-theme.old.<timestamp>"
((${#old_dirs[@]} == 1)) || fail "install moved the old theme dir more than once"
[[ -L $LINK && $(readlink -f "$LINK") == "$REPO" ]] || fail "the link was not created after the move"
themes=$(find "$CONFIG/omarchy/themes" -mindepth 1 -maxdepth 1 -printf '%f\n')
[[ $(sort <<<"$themes" | tr '\n' ' ') == "memphis memphis-dark memphis-gray " ]] ||
  fail "themes/ holds more than the three Memphis links: $themes"
ok "install moves an old theme dir out of themes/ to memphis-theme.old.<timestamp>"

# ------------------------------------------------------------ XDG_CONFIG_HOME

# Omarchy reads hooks, themes and plugins from $HOME/.config only.
fresh_home
XDG_CONFIG_HOME="$TMP/xdg" bash "$REPO/install.sh" --no-packages >/dev/null
[[ -L $LINK && $(readlink -f "$LINK") == "$REPO" ]] || fail "install with XDG_CONFIG_HOME did not link under \$HOME/.config"
[[ $(bar_id) == memphis.bar ]] || fail "install with XDG_CONFIG_HOME did not switch the bar under \$HOME/.config"
[[ -f $CONFIG/omarchy/hooks/theme-set.d/memphis ]] || fail "install with XDG_CONFIG_HOME did not put the hooks under \$HOME/.config"
[[ -f $PLUGIN/manifest.json ]] || fail "install with XDG_CONFIG_HOME did not build the bar under \$HOME/.config"
[[ ! -e $TMP/xdg ]] || fail "install wrote under XDG_CONFIG_HOME: $(find "$TMP/xdg")"
XDG_CONFIG_HOME="$TMP/xdg" bash "$REPO/uninstall.sh" >/dev/null
[[ ! -e $LINK && ! -e $PLUGIN && ! -e $CONFIG/omarchy/hooks/theme-set.d/memphis ]] ||
  fail "uninstall with XDG_CONFIG_HOME left files under \$HOME/.config"
[[ $(bar_id) == omarchy.bar ]] || fail "uninstall with XDG_CONFIG_HOME did not reset the bar"
ok "install and uninstall use \$HOME/.config when XDG_CONFIG_HOME is elsewhere"

# ------------------------------------------------------------ build.sh call

RECORD_REPO="$TMP/repo-record"
make_repo "$RECORD_REPO" record
fresh_home
bash "$RECORD_REPO/install.sh" --no-packages >/dev/null
[[ $(cat "$STUB_STATE/build.args") == "$CONFIG/omarchy/plugins" ]] ||
  fail "install did not call build.sh on the plugins dir: $(cat "$STUB_STATE/build.args")"
ok "install builds the bar with build.sh on the plugins dir"

fresh_home
mkdir -p "$PLUGIN"
echo '{"id": "someone.else"}' >"$PLUGIN/manifest.json"
bash "$REPO/install.sh" --no-packages >"$TMP/out" 2>&1 || fail "install failed on a foreign memphis.bar"
[[ $(jq -r .id "$PLUGIN/manifest.json") == someone.else ]] || fail "install replaced a foreign memphis.bar"
grep -q 'bevel bar build failed' "$TMP/out" || fail "no warning for a foreign memphis.bar"
[[ -z $(live_calls) ]] || fail "install switched the bar to a foreign memphis.bar: $(live_calls)"
ok "install leaves a foreign memphis.bar, warns and keeps the bar engine"

# ------------------------------------------------------------ failed build

FAIL_REPO="$TMP/repo-fail"
make_repo "$FAIL_REPO" fail
fresh_home
bash "$FAIL_REPO/install.sh" --no-packages >"$TMP/out" 2>&1 || fail "install failed when the build failed"
grep -q 'bevel bar build failed' "$TMP/out" || fail "no warning for the failed build"
[[ -z $(live_calls) ]] || fail "a failed build still switched the bar: $(live_calls)"
[[ ! -e $PLUGIN ]] || fail "a failed build left memphis.bar"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-*' 2>/dev/null) ]] || fail "a failed build left a build dir"
[[ -L $LINK && -f $CONFIG/omarchy/hooks/theme-set.d/memphis ]] || fail "a failed build stopped the install"
ok "a failed bar build warns and the install continues"

echo "install.sh: $PASS checks passed"
