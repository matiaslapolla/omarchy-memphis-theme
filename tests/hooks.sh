#!/bin/bash
# Runs the Memphis hooks under a temporary HOME with stub gsettings, hyprctl
# and omarchy. A switch to memphis and back to jade-horse must leave gsettings,
# shell.json and gtk-4.0/gtk.css byte-identical to the seed. The theme hook
# must never switch the bar engine.

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

# A bar engine switch during `omarchy theme set` races the theme apply.
assert_no_bar_switch() {
  local log="$1"
  if grep -E '^omarchy bar (use|reset)' "$log"; then
    fail "theme-set switched the bar engine"
  fi
}

# Omarchy writes theme.name and resets gtk-theme before the hook runs.
switch_to() {
  local slug="$1" gtk_theme="$2"
  mkdir -p "${THEME_NAME%/*}"
  echo "$slug" >"$THEME_NAME"
  gsettings set "$GS" gtk-theme "$gtk_theme"
  local before
  before=$(wc -l <"$STUB_STATE/calls.log")
  bash "$HOOKS/theme-set" "$slug" 2>>"$TMP/stderr.log"
  assert_no_bar_switch <(tail -n +"$((before + 1))" "$STUB_STATE/calls.log")
}

# The seed bar engine is memphis.bar, as install.sh leaves it. Pass "" for the
# stock bar (no .bar.id) or another id for a custom bar.
seed() {
  local bar_id="${1-memphis.bar}"
  rm -rf "$HOME" "$STUB_STATE" "$TMP/themes" "$TMP/icons"
  mkdir -p "$HOME" "$STUB_STATE"
  : >"$STUB_STATE/calls.log"

  gsettings set "$GS" gtk-theme "Adwaita-dark"
  gsettings set "$GS" cursor-theme "'Yaru'"
  gsettings set "$GS" cursor-size 24
  gsettings set "$GS" font-name "'Adwaita Sans 11'"

  mkdir -p "$CONFIG/omarchy" "$CONFIG/gtk-4.0"
  jq -S --arg id "$bar_id" 'if $id == "" then . else .bar.id = $id end' >"$SHELL_JSON" <<'JSON'
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
ok "memphis applies gtk-theme, cursor, font and position"

eq "$(head -n 3 "$GTK4_CSS")" "/* memphis:begin */
@import url(\"file://$TMP/themes/Chicago95/gtk-4.0/gtk.css\");
/* memphis:end */" "gtk.css block"
cmp <(tail -n +4 "$GTK4_CSS") "$TMP/seed/gtk.css" || fail "gtk.css lines outside the block changed"
ok "memphis adds the gtk-4.0 import block first and keeps the other lines"

eq "$(cat "$SAVED")" "cursor_theme='Yaru'
cursor_size=24
font_name='Adwaita Sans 11'
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

# ------------------------------------------------------------ Variants

# memphis-gray gets the full Win98 look. memphis-dark keeps Omarchy's dark GTK
# theme and drops the Chicago95 import, and the first saved state survives.
seed
switch_to memphis-gray Adwaita
eq "$(gs gtk-theme)" "'Chicago95'" "memphis-gray gtk-theme"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "memphis-gray cursor-theme"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "memphis-gray bar position"
grep -qxF '/* memphis:begin */' "$GTK4_CSS" || fail "memphis-gray did not add the gtk.css block"
cp "$SAVED" "$TMP/saved.gray"
ok "memphis-gray applies gtk-theme, cursor, position and the gtk.css block"

switch_to memphis-dark Adwaita-dark
eq "$(gs gtk-theme)" "'Adwaita-dark'" "memphis-dark gtk-theme"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "memphis-dark cursor-theme"
eq "$(gs font-name)" "'W95FA 11'" "memphis-dark font-name"
eq "$(cursor)" "Chicago95_Cursor_Black 24" "memphis-dark hyprctl setcursor"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "memphis-dark bar position"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "memphis-dark left the Chicago95 import in gtk.css"
cmp "$TMP/saved.gray" "$SAVED" || fail "a switch between Memphis slugs changed saved.env"
ok "memphis-dark keeps the dark GTK theme, removes the import and keeps the saved state"

switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "memphis-gray then memphis-dark then jade-horse restores the seed"

seed
switch_to memphis Adwaita
switch_to memphis-dark Adwaita-dark
eq "$(gs gtk-theme)" "'Adwaita-dark'" "memphis-dark after memphis gtk-theme"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "memphis-dark after memphis left the import in gtk.css"
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "memphis then memphis-dark then jade-horse restores the seed"

seed
switch_to memphis-dark Adwaita-dark
eq "$(gs gtk-theme)" "'Adwaita-dark'" "memphis-dark first gtk-theme"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "memphis-dark changed gtk.css"
grep -qx 'gtk4_css_existed=1' "$SAVED" || fail "memphis-dark saved the wrong gtk.css state: $(cat "$SAVED")"
switch_to jade-horse Adwaita-dark
assert_seed_restored
assert_no_live_calls
ok "memphis-dark from another theme leaves gtk.css alone and restores the seed"

# ------------------------------------------------------------ jade-horse

switch_to jade-horse Adwaita-dark
assert_seed_restored
eq "$(cursor)" "Yaru 24" "hyprctl setcursor on restore"
ok "jade-horse restores gsettings, position and gtk.css byte-identically"

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
eq "$(jq -r '.bar.id' "$SHELL_JSON")" "memphis.bar" "bar id without the memphis.bar plugin"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "bar position without the memphis.bar plugin"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "gtk.css changed without Chicago95"
for word in Chicago95 Chicago95_Cursor_Black font; do
  grep -q "$word" "$TMP/stderr.log" || fail "no warning about $word"
done
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "missing dependencies are skipped with a warning and restore still works"

# ------------------------------------------------------------ superseded switch

# Omarchy runs the hook for a batch even after a newer switch replaced it.
seed
mkdir -p "${THEME_NAME%/*}"
echo tokyo-night >"$THEME_NAME"
bash "$HOOKS/theme-set" memphis 2>>"$TMP/stderr.log"
[[ ! -s $STUB_STATE/calls.log ]] || fail "a superseded memphis hook ran: $(cat "$STUB_STATE/calls.log")"
[[ ! -e $SAVED ]] || fail "a superseded memphis hook wrote saved.env"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "a superseded memphis hook changed gtk.css"
ok "theme-set skips memphis when theme.name names a newer theme"

switch_to memphis Adwaita
cp "$SAVED" "$TMP/saved.memphis"
: >"$STUB_STATE/calls.log"
bash "$HOOKS/theme-set" jade-horse 2>>"$TMP/stderr.log"
[[ ! -s $STUB_STATE/calls.log ]] || fail "a superseded restore ran: $(cat "$STUB_STATE/calls.log")"
cmp "$TMP/saved.memphis" "$SAVED" || fail "a superseded restore changed saved.env"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "cursor-theme after a superseded restore"
grep -qxF '/* memphis:begin */' "$GTK4_CSS" || fail "a superseded restore removed the gtk.css block"
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "theme-set skips the restore when theme.name is still memphis"

seed
bash "$HOOKS/theme-set" memphis 2>>"$TMP/stderr.log"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "cursor-theme without theme.name"
switch_to jade-horse Adwaita-dark
assert_seed_restored
ok "theme-set runs when theme.name is missing"

# ------------------------------------------------------------ XDG_CONFIG_HOME

# Omarchy reads its config from $HOME/.config whatever XDG_CONFIG_HOME says.
seed
XDG_CONFIG_HOME="$TMP/xdg" switch_to memphis Adwaita
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "bar position with XDG_CONFIG_HOME"
XDG_CONFIG_HOME="$TMP/xdg" switch_to jade-horse Adwaita-dark
cmp "$TMP/seed/shell.json" "$SHELL_JSON" || fail "shell.json differs from the seed with XDG_CONFIG_HOME"
[[ ! -e $TMP/xdg/omarchy ]] || fail "theme-set wrote Omarchy config under XDG_CONFIG_HOME"
rm -rf "$TMP/xdg"
ok "theme-set finds the bar under \$HOME/.config when XDG_CONFIG_HOME is elsewhere"

# ------------------------------------------------------------ lost saved state

# A lost saved.env while Memphis is applied must not save Memphis values.
seed
switch_to memphis Adwaita
rm -f "$SAVED"
switch_to memphis Adwaita
for key in cursor_theme font_name bar_position; do
  ! grep -q "^$key=" "$SAVED" || fail "saved.env kept the Memphis $key: $(cat "$SAVED")"
done
! grep -q '^bar_id=' "$SAVED" || fail "saved.env holds a bar_id: $(cat "$SAVED")"
grep -qx 'gtk4_css_existed=1' "$SAVED" || fail "saved.env lost the user's gtk.css: $(cat "$SAVED")"
: >"$STUB_STATE/calls.log"
switch_to jade-horse Adwaita-dark
if grep -E 'set org.gnome.desktop.interface (cursor-theme|font-name)|bar position' "$STUB_STATE/calls.log"; then
  fail "the restore wrote Memphis values back"
fi
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "cursor-theme after a lost saved state"
eq "$(gs font-name)" "'W95FA 11'" "font-name after a lost saved state"
eq "$(jq -r '.bar.position' "$SHELL_JSON")" "bottom" "bar position after a lost saved state"
eq "$(jq -r '.bar.id' "$SHELL_JSON")" "memphis.bar" "bar id after a lost saved state"
cmp "$TMP/seed/gtk.css" "$GTK4_CSS" || fail "gtk.css differs from the seed after a lost saved state"
[[ ! -e $SAVED ]] || fail "saved.env was not deleted"
ok "a lost saved state does not save or restore Memphis values"

seed
rm -f "$GTK4_CSS"
switch_to memphis Adwaita
rm -f "$SAVED"
switch_to memphis Adwaita
grep -qx 'gtk4_css_existed=0' "$SAVED" || fail "a gtk.css with only our block counts as the user's: $(cat "$SAVED")"
switch_to jade-horse Adwaita-dark
[[ ! -e $GTK4_CSS ]] || fail "gtk.css with only our block was left behind"
ok "a gtk.css that holds only the Memphis block does not count as the user's"

# ------------------------------------------------------------ bar engine

# install.sh owns the bar engine. theme-set keeps any engine under every theme.
for engine in "" local.neon-bar; do
  seed "$engine"
  switch_to memphis Adwaita
  cmp <(jq -S 'del(.bar.position)' "$TMP/seed/shell.json") <(jq -S 'del(.bar.position)' "$SHELL_JSON") ||
    fail "memphis changed shell.json beyond the position with engine [${engine:-omarchy.bar}]"
  switch_to jade-horse Adwaita-dark
  assert_seed_restored
done
ok "theme-set keeps the stock bar and a custom bar as the engine"

# A bar_id line from an older hook must not switch the engine back.
seed
switch_to memphis Adwaita
printf '%s\n' 'bar_id=omarchy.bar' >>"$SAVED"
: >"$TMP/stderr.log"
switch_to jade-horse Adwaita-dark
assert_seed_restored
eq "$(jq -r '.bar.id' "$SHELL_JSON")" "memphis.bar" "bar id after a legacy bar_id"
[[ ! -s $TMP/stderr.log ]] || fail "a legacy bar_id caused warnings: $(cat "$TMP/stderr.log")"
ok "a legacy bar_id in saved.env is ignored and the restore completes"

seed
switch_to memphis Adwaita
switch_to jade-horse Adwaita-dark
assert_no_bar_switch "$STUB_STATE/calls.log"
ok "theme-set never runs omarchy bar use or omarchy bar reset"

# ------------------------------------------------------------ post-boot

seed
mkdir -p "${THEME_NAME%/*}"
echo memphis >"$THEME_NAME"
rm -f "$STUB_STATE/hyprctl.cursor"
bash "$HOOKS/post-boot"
eq "$(cursor)" "Chicago95_Cursor_Black 24" "post-boot setcursor"
eq "$(gs cursor-theme)" "'Chicago95_Cursor_Black'" "post-boot cursor-theme"
for slug in memphis-gray memphis-dark; do
  echo "$slug" >"$THEME_NAME"
  rm -f "$STUB_STATE/hyprctl.cursor"
  bash "$HOOKS/post-boot"
  eq "$(cursor)" "Chicago95_Cursor_Black 24" "post-boot setcursor under $slug"
done
for slug in jade-horse memphis-old; do
  echo "$slug" >"$THEME_NAME"
  rm -f "$STUB_STATE/hyprctl.cursor"
  : >"$STUB_STATE/calls.log"
  bash "$HOOKS/post-boot"
  [[ ! -s $STUB_STATE/calls.log ]] || fail "post-boot ran commands under $slug"
done
ok "post-boot sets the cursor only under a Memphis slug"

# ------------------------------------------------------------ post-update

seed
FAKE_REPO="$TMP/fake-repo"
mkdir -p "$FAKE_REPO/extras/bar-bevel" "$CONFIG/omarchy/themes"
ln -s "$FAKE_REPO" "$CONFIG/omarchy/themes/memphis"
cat >"$FAKE_REPO/extras/bar-bevel/build.sh" <<'BUILD'
#!/bin/bash
set -euo pipefail
[[ ${FAKE_BUILD_FAIL:-0} == 0 ]] || exit 1
printf '%s\n' "$1" >>"$STUB_STATE/build.args"
mkdir -p "$1/memphis.bar"
echo '{"id": "memphis.bar", "rebuilt": true}' >"$1/memphis.bar/manifest.json"
BUILD

bash "$HOOKS/post-update"
eq "$(jq -r '.rebuilt' "$CONFIG/omarchy/plugins/memphis.bar/manifest.json")" "true" "rebuild"
eq "$(cat "$STUB_STATE/build.args")" "$CONFIG/omarchy/plugins" "build.sh argument"
[[ -z $(find "$CONFIG/omarchy/plugins" -maxdepth 1 -name '.memphis-*') ]] || fail "post-update left a build dir"
ok "post-update rebuilds memphis.bar with build.sh on the plugins dir"

rm -f "$STUB_STATE/build.args"
echo '{"id": "memphis.bar"}' >"$CONFIG/omarchy/plugins/memphis.bar/manifest.json"
XDG_CONFIG_HOME="$TMP/xdg" bash "$HOOKS/post-update"
eq "$(jq -r '.rebuilt' "$CONFIG/omarchy/plugins/memphis.bar/manifest.json")" "true" "rebuild with XDG_CONFIG_HOME"
eq "$(cat "$STUB_STATE/build.args")" "$CONFIG/omarchy/plugins" "build.sh argument with XDG_CONFIG_HOME"
ok "post-update uses \$HOME/.config when XDG_CONFIG_HOME is elsewhere"

omarchy bar use memphis.bar >/dev/null
: >"$STUB_STATE/calls.log"
: >"$TMP/stderr.log"
FAKE_BUILD_FAIL=1 bash "$HOOKS/post-update" 2>>"$TMP/stderr.log"
[[ ! -e $CONFIG/omarchy/plugins/memphis.bar ]] || fail "a failed build kept the stale memphis.bar"
eq "$(jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON")" "omarchy.bar" "bar after a failed build"
grep -q '^omarchy bar reset$' "$STUB_STATE/calls.log" || fail "no omarchy bar reset after a failed build"
grep -q '^notify-send ' "$STUB_STATE/calls.log" || fail "no notification after a failed build"
grep -q 'build.sh failed' "$TMP/stderr.log" || fail "no warning after a failed build"
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
