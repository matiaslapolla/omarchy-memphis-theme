#!/bin/bash
# Installs the Memphis theme: packages, font, theme link, hooks and the bevel
# bar. The only live change is the bar engine switch to memphis.bar, which
# looks the same as the stock bar under other themes. It does not apply the
# theme. Run `omarchy theme set memphis` (or memphis-gray, memphis-dark)
# afterwards.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGES=(chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git)
HOOK_EVENTS=(theme-set post-boot post-update)

# Omarchy reads its config from $HOME/.config and ignores XDG_CONFIG_HOME.
OMARCHY_CONFIG="$HOME/.config/omarchy"
THEMES_DIR="$OMARCHY_CONFIG/themes"
# The Memphis slugs. memphis is the repo root, the others are in variants/.
SLUGS=(memphis memphis-gray memphis-dark)
HOOKS_DIR="$OMARCHY_CONFIG/hooks"
PLUGINS_DIR="$OMARCHY_CONFIG/plugins"
SHELL_JSON="$OMARCHY_CONFIG/shell.json"
BAR_ID="memphis.bar"
DEFAULT_BAR_ID="omarchy.bar"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/memphis"

DRY_RUN=0
NO_PACKAGES=0

usage() {
  cat <<USAGE
Usage: ./install.sh [--dry-run] [--no-packages] [-h]

Installs the Memphis theme without applying it. When the bar is the stock
omarchy.bar, it switches the bar engine to the bevel bar memphis.bar.

  --dry-run       Print each action and change nothing
  --no-packages   Skip the yay install of ${PACKAGES[*]}
  -h, --help      Show this help

After the install, run one of:
  omarchy theme set memphis
  omarchy theme set memphis-gray
  omarchy theme set memphis-dark
USAGE
}

while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-packages) NO_PACKAGES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

say() { printf '==> %s\n' "$*"; }
warn() { printf 'install.sh: %s\n' "$*" >&2; }

run() {
  if ((DRY_RUN)); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

install_packages() {
  if ((NO_PACKAGES)); then
    say "Skipping packages (--no-packages)"
    return
  fi
  if ! command -v yay >/dev/null 2>&1; then
    warn "yay not found; install ${PACKAGES[*]} by hand"
    return
  fi
  say "Installing packages: ${PACKAGES[*]}"
  run yay -S --needed "${PACKAGES[@]}" || warn "yay failed; the hook skips what is missing"
}

install_font() {
  local fonts=() file
  for file in "$REPO"/fonts/*.otf "$REPO"/fonts/*.ttf; do
    if [[ -f $file ]]; then fonts+=("$file"); fi
  done
  if ((${#fonts[@]} == 0)); then
    warn "no font in $REPO/fonts; skipping the font"
    return
  fi
  say "Installing font into $FONT_DIR"
  run mkdir -p "$FONT_DIR"
  run cp -f -- "${fonts[@]}" "$FONT_DIR/"
  [[ ! -f $REPO/fonts/OFL.txt ]] || run cp -f -- "$REPO/fonts/OFL.txt" "$FONT_DIR/"
  if command -v fc-cache >/dev/null 2>&1; then
    run fc-cache -f "$FONT_DIR" || warn "fc-cache failed"
  fi
}

variant_dir() {
  if [[ $1 == memphis ]]; then
    printf '%s\n' "$REPO"
  else
    printf '%s\n' "$REPO/variants/$1"
  fi
}

link_theme() {
  local slug="$1" link="$THEMES_DIR/$1" source
  source=$(variant_dir "$slug")
  if [[ ! -d $source ]]; then
    warn "$source not found; skipping $slug"
    return
  fi
  if [[ -L $link && $(readlink -f "$link") == "$source" ]]; then
    say "Theme link already in place: $link"
    return
  fi
  run mkdir -p "$THEMES_DIR"
  # omarchy-theme-list shows every entry in themes/, so the old dir goes outside it.
  if [[ -e $link || -L $link ]]; then
    local old_dir
    old_dir="$OMARCHY_CONFIG/$slug-theme.old.$(date +%Y%m%d%H%M%S)"
    say "Moving the old theme dir $link to $old_dir"
    run mv -- "$link" "$old_dir"
  fi
  say "Linking $source to $link"
  run ln -s -- "$source" "$link"
}

install_hooks() {
  local event
  for event in "${HOOK_EVENTS[@]}"; do
    say "Installing $event hook: $HOOKS_DIR/$event.d/memphis"
    run mkdir -p "$HOOKS_DIR/$event.d"
    run cp -- "$REPO/extras/hooks/$event" "$HOOKS_DIR/$event.d/memphis"
    run chmod 755 "$HOOKS_DIR/$event.d/memphis"
  done
}

# build.sh swaps the plugin in atomically and refuses a memphis.bar that is
# not its own build.
build_bar() {
  local build="$REPO/extras/bar-bevel/build.sh"
  if [[ ! -f $build ]]; then
    warn "$build not found; the bar stays $DEFAULT_BAR_ID"
    return 1
  fi
  say "Building the bevel bar into $PLUGINS_DIR/$BAR_ID"
  if ! run bash "$build" "$PLUGINS_DIR"; then
    warn "the bevel bar build failed; the bar stays $DEFAULT_BAR_ID"
    return 1
  fi
}

# Prints the bar id in shell.json. An unset id means the stock bar.
current_bar_id() {
  [[ -s $SHELL_JSON ]] || { echo "$DEFAULT_BAR_ID"; return 0; }
  jq -r --arg default "$DEFAULT_BAR_ID" '.bar.id // $default' "$SHELL_JSON"
}

# The theme hook does not switch the bar engine, because a switch during
# `omarchy theme set` races the theme apply and breaks the new bar. The bevel
# lines draw only under a theme that sets bar.bevel-light and bar.bevel-dark,
# so memphis.bar stays the engine under every theme.
use_bevel_bar() {
  local bar_id
  if ! bar_id=$(current_bar_id); then
    warn "cannot read $SHELL_JSON; to use the bevel bar, run: omarchy bar use $BAR_ID"
    return
  fi
  case "$bar_id" in
    "$BAR_ID")
      say "The bar already uses $BAR_ID"
      ;;
    "$DEFAULT_BAR_ID")
      if ! command -v omarchy >/dev/null 2>&1; then
        warn "omarchy not found; to use the bevel bar, run: omarchy bar use $BAR_ID"
        return
      fi
      say "Switching the bar from $DEFAULT_BAR_ID to $BAR_ID (the shell reloads the bar)"
      run omarchy bar use "$BAR_ID" ||
        warn "omarchy bar use failed; to use the bevel bar, run: omarchy bar use $BAR_ID"
      ;;
    *)
      warn "the bar uses $bar_id, so it stays. To use the bevel bar, run: omarchy bar use $BAR_ID"
      ;;
  esac
}

if ((DRY_RUN)); then say "Dry run: nothing changes"; fi
install_packages
install_font
for slug in "${SLUGS[@]}"; do link_theme "$slug"; done
install_hooks
if build_bar; then use_bevel_bar; fi

echo
if ((DRY_RUN)); then
  echo "Dry run done. After a real install, apply Memphis with:"
else
  echo "Memphis is installed. Apply a Variant with one of:"
fi
echo
for slug in "${SLUGS[@]}"; do echo "  omarchy theme set $slug"; done
