#!/bin/bash
# Runs the Memphis hooks under a temporary HOME with stub gsettings, hyprctl
# and omarchy. A switch to memphis and back to jade-horse must leave gsettings,
# the bar and gtk-4.0/gtk.css byte-identical to the seed.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOKS="$ROOT/extras/hooks"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export STUB_STATE="$TMP/stub"
export PATH="$ROOT/tests/stubs:$PATH"
export MEMPHIS_THEME_DIRS="$TMP/themes"
export MEMPHIS_ICON_DIRS="$TMP/icons"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE
mkdir -p "$HOME" "$STUB_STATE"

PASS=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
ok() {
  PASS=$((PASS + 1))
  echo "ok - $*"
}
eq() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }

for cmd in gsettings hyprctl omarchy; do
  [[ $(command -v "$cmd") == "$ROOT/tests/stubs/$cmd" ]] || fail "$cmd does not resolve to the stub"
done

CONFIG="$HOME/.config"
SAVED="$HOME/.local/state/memphis/saved.env"
GTK4_CSS="$CONFIG/gtk-4.0/gtk.css"
SHELL_JSON="$CONFIG/omarchy/shell.json"
THEME_NAME="$HOME/.local/state/omarchy/current/theme.name"
GS="org.gnome.desktop.interface"

gs() { gsettings get "$GS" "$1"; }
cursor() { cat "$STUB_STATE/hyprctl.cursor" 2>/dev/null || true; }

# Omarchy writes theme.name and resets gtk-theme before the hook runs.
switch_to() {
  local slug="$1" gtk_theme="$2"
  mkdir -p "${THEME_NAME%/*}"
  echo "$slug" >"$THEME_NAME"
  gsettings set "$GS" gtk-theme "$gtk_theme"
  bash "$HOOKS/theme-set" "$slug" 2>>"$TMP/stderr.log"
}

seed() {
  rm -rf "$HOME" "$STUB_STATE" "$TMP/themes" "$TMP/icons"
  mkdir -p "$HOME" "$STUB_STATE"

  gsettings set "$GS" gtk-theme "Adwaita-dark"
  gsettings set "$GS" cursor-theme "'Yaru'"
  gsettings set "$GS" cursor-size 24
  gsettings set "$GS" font-name "'Adwaita Sans 11'"

  mkdir -p "$CONFIG/omarchy" "$CONFIG/gtk-4.0"
  jq -S . >"$SHELL_JSON" <<'JSON'
{"version": 1, "bar": {"position": "top", "background": "opaque",
 "layout": {"left": ["omarchy.workspaces"], "center": ["omarchy.clock"], "right": ["omarchy.tray"]}},
 "plugins": []}
JSON
  # An unrelated rule plus Omarchy's glass block, and no final newline.
  printf '%s\n%s\n%s\n%s' \
    'window.unrelated { color: red; }' \
    '/* omarchy-glass begin */' \
    '@import url("file:///usr/share/omarchy/default/gtk/glass.css");' \
    '/* omarchy-glass end */' >"$GTK4_CSS"

  mkdir -p "$TMP/themes/Chicago95/gtk-4.0" "$TMP/icons/Chicago95_Cursor_Black/cursors"
  touch "$TMP/themes/Chicago95/index.theme" "$TMP/themes/Chicago95/gtk-4.0/gtk.css"
  mkdir -p "$CONFIG/omarchy/plugins/memphis.bar"
  echo '{"id": "memphis.bar", "kinds": ["bar"], "entryPoints": {"bar": "Bar.qml"}}' \
    >"$CONFIG/omarchy/plugins/memphis.bar/manifest.json"
  mkdir -p "$HOME/.local/share/fonts/memphis"
  if [[ -f $ROOT/fonts/W95FA.otf ]]; then
    cp "$ROOT/fonts/W95FA.otf" "$HOME/.local/share/fonts/memphis/"
  else
    echo "not a real font" >"$HOME/.local/share/fonts/memphis/W95FA.otf"
  fi

  : >"$STUB_STATE/calls.log"
  rm -rf "$TMP/seed"
  mkdir -p "$TMP/seed"
  cp -a "$STUB_STATE/gsettings" "$TMP/seed/gsettings"
  cp "$SHELL_JSON" "$TMP/seed/shell.json"
  cp "$GTK4_CSS" "$TMP/seed/gtk.css"
}

assert_seed_restored() {
  # Omarchy, not the hook, owns gtk-theme; switch_to already reset it.
  diff -r "$TMP/seed/gsettings" "$STUB_STATE/gsettings" || fail "gsettings differ from the seed"
  cmp "$TMP/seed/shell.json" "$SHELL_JSON" || fail "shell.json differs from the seed"
  if [[ -f $TMP/seed/gtk.css ]]; then
    cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "gtk.css differs from the seed"
  else
    [[ ! -e $GTK4_CSS ]] || fail "gtk.css was created and left behind"
  fi
  [[ ! -e $SAVED ]] || fail "saved.env was not deleted"
}

assert_no_live_calls() {
  if grep -E 'theme set|restart|reload|refresh' "$STUB_STATE/calls.log"; then
    fail "a hook ran a live Omarchy or Hyprland command"
  fi
}

# ------------------------------------------------------------ memphis

seed
switch_to memphis Adwaita
eq "$(gs gtk-theme)" "'Chicago95'" "gtk-theme"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "cursor-theme"
eq "$(gs cursor-size)" "24" "cursor-size"
eq "$(gs font-name)" "'W95FA 11'" "font-name"
eq "$(cursor)" "Chicago95_Cursor_Black 24" "hyprctl setcursor"
eq "$(jq -r '.bar.id' "$SHELL_JSON")" "memphis.bar" "bar id"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "bar position"
ok "memphis applies gtk-theme, cursor, font, bar and position"

eq "$(head -n 3 "$GTK4_CSS")" "/* memphis:begin */
@import url(\"file://$TMP/themes/Chicago95/gtk-4.0/gtk.css\");
/* memphis:end */" "gtk.css block"
cmp <(tail -n +4 "$GTK4_CSS") "$TMP/seed/gtk.css" || fail "gtk.css lines outside the block changed"
ok "memphis adds the gtk-4.0 import block first and keeps the other lines"

eq "$(cat "$SAVED")" "cursor_theme='Yaru'
cursor_size=24
font_name='Adwaita Sans 11'
bar_id=omarchy.bar
bar_position=top
gtk4_css_existed=1" "saved.env"
ok "memphis writes the saved state"

cp "$SAVED" "$TMP/saved.first"
cp "$GTK4_CSS" "$TMP/gtk.first"
switch_to memphis Adwaita
cmp "$TMP/saved.first" "$SAVED" || fail "a second memphis switch changed saved.env"
cmp "$TMP/gtk.first" "$GTK4_CSS" || fail "a second memphis switch changed gtk.css"
eq "$(grep -c 'memphis:begin' "$GTK4_CSS")" "1" "block count"
ok "memphis to memphis keeps the first saved state and one block"

# ------------------------------------------------------------ jade-horse

switch_to jade-horse Adwaita-dark
assert_seed_restored
eq "$(cursor)" "Yaru 24" "hyprctl setcursor on restore"
ok "jade-horse restores gsettings, bar, position and gtk.css byte-identically"

cp "$STUB_STATE/calls.log" "$TMP/calls.before"
bash "$HOOKS/theme-set" jade-horse 2>>"$TMP/stderr.log"
cmp "$TMP/calls.before" "$STUB_STATE/calls.log" || fail "a switch without saved state ran commands"
assert_seed_restored
ok "a non-memphis switch without saved state does nothing"
assert_no_live_calls
ok "no live omarchy or hyprland command ran"

# ------------------------------------------------------------ no gtk.css

seed
rm -f "$GTK4_CSS" "$TMP/seed/gtk.css"
switch_to memphis Adwaita
[[ -f $GTK4_CSS ]] || fail "gtk.css was not created"
grep -q 'gtk-4.0/gtk.css' "$GTK4_CSS" || fail "gtk.css lacks the import"
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "a gtk.css created by the hook is removed on restore"

# ------------------------------------------------------------ missing deps

seed
rm -rf "$TMP/themes" "$TMP/icons" "$CONFIG/omarchy/plugins/memphis.bar" "$HOME/.local/share/fonts/memphis"
: >"$TMP/stderr.log"
switch_to memphis Adwaita
eq "$(gs gtk-theme)" "'Adwaita'" "gtk-theme without Chicago95"
eq "$(gs cursor-theme)" "'Yaru'" "cursor-theme without the cursor theme"
eq "$(gs font-name)" "'Adwaita Sans 11'" "font-name without the font"
eq "$(jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON")" "omarchy.bar" "bar id without memphis.bar"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "bar position without memphis.bar"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "gtk.css changed without Chicago95"
for word in Chicago95 Chicago95_Cursor_Black font memphis.bar; do
  grep -q "$word" "$TMP/stderr.log" || fail "no warning about $word"
done
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "missing dependencies are skipped with a warning and restore still works"

# ------------------------------------------------------------ post-boot

seed
mkdir -p "${THEME_NAME%/*}"
echo memphis >"$THEME_NAME"
rm -f "$STUB_STATE/hyprctl.cursor"
bash "$HOOKS/post-boot"
eq "$(cursor)" "Chicago95_Cursor_Black 24" "post-boot setcursor"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "post-boot cursor-theme"
echo jade-horse >"$THEME_NAME"
rm -f "$STUB_STATE/hyprctl.cursor"
: >"$STUB_STATE/calls.log"
bash "$HOOKS/post-boot"
[[ ! -s $STUB_STATE/calls.log ]] || fail "post-boot ran commands under another theme"
ok "post-boot sets the cursor only under memphis"

# ------------------------------------------------------------ post-update

seed
FAKE_REPO="$TMP/fake-repo"
mkdir -p "$FAKE_REPO/extras/bar-bevel" "$CONFIG/omarchy/themes"
ln -s "$FAKE_REPO" "$CONFIG/omarchy/themes/memphis"
cat >"$FAKE_REPO/extras/bar-bevel/build.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
[[ ${FAKE_BUILD_FAIL:-0} == 0 ]] || exit 1
mkdir -p "$1/memphis.bar"
echo '{"id": "memphis.bar", "rebuilt": true}' >"$1/memphis.bar/manifest.json"
BUILD

bash "$HOOKS/post-update"
eq "$(jq -r '.rebuilt' "$CONFIG/omarchy/plugins/memphis.bar/manifest.json")" "true" "rebuild"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-build.*') ]] || fail "post-update left a build dir"
ok "post-update rebuilds an installed memphis.bar"

omarchy bar use memphis.bar >/dev/null
: >"$STUB_STATE/calls.log"
: >"$TMP/stderr.log"
FAKE_BUILD_FAIL=1 bash "$HOOKS/post-update" 2>>"$TMP/stderr.log"
[[ ! -e $CONFIG/omarchy/plugins/memphis.bar ]] || fail "a failed build kept the stale memphis.bar"
eq "$(jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON")" "omarchy.bar" "bar after a failed build"
grep -q '^omarchy bar reset$' "$STUB_STATE/calls.log" || fail "no omarchy bar reset after a failed build"
grep -q '^notify-send ' "$STUB_STATE/calls.log" || fail "no notification after a failed build"
grep -q 'build.sh failed' "$TMP/stderr.log" || fail "no warning after a failed build"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-build.*') ]] || fail "post-update left a build dir"
ok "a failed rebuild removes memphis.bar, resets the bar and notifies"

mkdir -p "$CONFIG/omarchy/plugins/memphis.bar"
echo '{"id": "someone.else"}' >"$CONFIG/omarchy/plugins/memphis.bar/manifest.json"
FAKE_BUILD_FAIL=1 bash "$HOOKS/post-update" 2>>"$TMP/stderr.log"
eq "$(jq -r '.id' "$CONFIG/omarchy/plugins/memphis.bar/manifest.json")" "someone.else" "foreign plugin"
rm -rf "$CONFIG/omarchy/plugins/memphis.bar"
: >"$STUB_STATE/calls.log"
bash "$HOOKS/post-update"
[[ ! -e $CONFIG/omarchy/plugins/memphis.bar ]] || fail "post-update built a bar that was not installed"
[[ ! -s $STUB_STATE/calls.log ]] || fail "post-update ran commands without memphis.bar"
ok "post-update leaves a foreign memphis.bar and does nothing when none is installed"

echo "hooks.sh: $PASS checks passed"
