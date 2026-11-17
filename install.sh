#!/bin/bash
# Installs the Memphis theme: packages, font, theme link, hooks and the bevel
# bar. It applies nothing live. Run `omarchy theme set memphis` afterwards.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGES=(chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git)
HOOK_EVENTS=(theme-set post-boot post-update)

# Omarchy reads its config from $HOME/.config and ignores XDG_CONFIG_HOME.
OMARCHY_CONFIG="$HOME/.config/omarchy"
THEMES_DIR="$OMARCHY_CONFIG/themes"
THEME_LINK="$THEMES_DIR/memphis"
HOOKS_DIR="$OMARCHY_CONFIG/hooks"
PLUGINS_DIR="$OMARCHY_CONFIG/plugins"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/memphis"

DRY_RUN=0
NO_PACKAGES=0

usage() {
  cat <<USAGE
Usage: ./install.sh [--dry-run] [--no-packages] [-h]

Installs the Memphis theme without applying it.

  --dry-run       Print each action and change nothing
  --no-packages   Skip the yay install of ${PACKAGES[*]}
  -h, --help      Show this help

After the install, run: omarchy theme set memphis
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

link_theme() {
  if [[ -L $THEME_LINK && $(readlink -f "$THEME_LINK") == "$REPO" ]]; then
    say "Theme link already in place: $THEME_LINK"
    return
  fi
  run mkdir -p "$THEMES_DIR"
  # omarchy-theme-list shows every entry in themes/, so the old dir goes outside it.
  if [[ -e $THEME_LINK || -L $THEME_LINK ]]; then
    local old_dir
    old_dir="$OMARCHY_CONFIG/memphis-theme.old.$(date +%Y%m%d%H%M%S)"
    say "Moving the old theme dir $THEME_LINK to $old_dir"
    run mv -- "$THEME_LINK" "$old_dir"
  fi
  say "Linking $REPO to $THEME_LINK"
  run ln -s -- "$REPO" "$THEME_LINK"
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
    warn "$build not found; the bar stays omarchy.bar"
    return
  fi
  say "Building the bevel bar into $PLUGINS_DIR/memphis.bar"
  run bash "$build" "$PLUGINS_DIR" || warn "the bevel bar build failed; Memphis keeps omarchy.bar"
}

if ((DRY_RUN)); then say "Dry run: nothing changes"; fi
install_packages
install_font
link_theme
install_hooks
build_bar

echo
if ((DRY_RUN)); then
  echo "Dry run done. After a real install, apply Memphis with:"
else
  echo "Memphis is installed. Apply it with:"
fi
echo
echo "  omarchy theme set memphis"
