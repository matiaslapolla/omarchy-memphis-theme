#!/bin/bash
# Removes what install.sh added: the hooks, the theme link, the bevel bar and
# the font. It refuses while memphis is the current theme, because the theme
# hook must restore the user's values first. Packages stay installed.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGES=(chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git)
HOOK_EVENTS=(theme-set post-boot post-update)

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_LINK="$CONFIG_HOME/omarchy/themes/memphis"
HOOKS_DIR="$CONFIG_HOME/omarchy/hooks"
PLUGIN="$CONFIG_HOME/omarchy/plugins/memphis.bar"
SHELL_JSON="$CONFIG_HOME/omarchy/shell.json"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/memphis"
THEME_NAME_FILE="$HOME/.local/state/omarchy/current/theme.name"
SAVED="${XDG_STATE_HOME:-$HOME/.local/state}/memphis/saved.env"

DRY_RUN=0
NO_PACKAGES=0

usage() {
  cat <<USAGE
Usage: ./uninstall.sh [--dry-run] [--no-packages] [-h]

Removes the Memphis hooks, theme link, bevel bar and font. Switch to another
theme first.

  --dry-run       Print each action and change nothing
  --no-packages   Do not print the package removal command
  -h, --help      Show this help
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
      echo "uninstall.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

say() { printf '==> %s\n' "$*"; }
warn() { printf 'uninstall.sh: %s\n' "$*" >&2; }

run() {
  if ((DRY_RUN)); then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ -f $THEME_NAME_FILE && $(<"$THEME_NAME_FILE") == "memphis" ]]; then
  echo "Memphis is the current theme. Switch to another theme first, for example:" >&2
  echo "  omarchy theme set \"Tokyo Night\"" >&2
  echo "Then run ./uninstall.sh again." >&2
  exit 1
fi

if ((DRY_RUN)); then say "Dry run: nothing changes"; fi

for event in "${HOOK_EVENTS[@]}"; do
  hook="$HOOKS_DIR/$event.d/memphis"
  if [[ -e $hook ]]; then
    say "Removing $hook"
    run rm -f -- "$hook"
  fi
done

if [[ -L $THEME_LINK ]]; then
  if [[ $(readlink -f "$THEME_LINK") == "$REPO" ]]; then
    say "Removing the theme link $THEME_LINK"
    run rm -f -- "$THEME_LINK"
  else
    warn "$THEME_LINK points somewhere else; leaving it"
  fi
elif [[ -e $THEME_LINK ]]; then
  warn "$THEME_LINK is not a link from this repo; leaving it (remove it with omarchy theme remove)"
fi

if [[ -e $PLUGIN ]] && [[ $(jq -r '.id // ""' "$PLUGIN/manifest.json" 2>/dev/null) != "memphis.bar" ]]; then
  warn "$PLUGIN is not the Memphis bevel bar; leaving it"
elif [[ -e $PLUGIN ]]; then
  if [[ -s $SHELL_JSON ]] && [[ $(jq -r '.bar.id // ""' "$SHELL_JSON" 2>/dev/null) == "memphis.bar" ]]; then
    warn "the bar still uses memphis.bar; run 'omarchy bar reset' after this"
  fi
  say "Removing the bevel bar $PLUGIN"
  run rm -rf -- "$PLUGIN"
fi

if [[ -d $FONT_DIR ]]; then
  say "Removing the font $FONT_DIR"
  run rm -rf -- "$FONT_DIR"
  if [[ -d ${FONT_DIR%/*} ]] && command -v fc-cache >/dev/null 2>&1; then
    run fc-cache -f "${FONT_DIR%/*}" || warn "fc-cache failed"
  fi
fi

if [[ -f $SAVED ]]; then
  warn "$SAVED still holds your values from before Memphis; it was kept"
fi

echo
echo "Memphis is uninstalled."
if ((!NO_PACKAGES)); then
  echo "The Chicago95 packages stay installed. To remove them, run:"
  echo
  echo "  yay -R ${PACKAGES[*]}"
fi
