#!/bin/bash
# Removes what install.sh added: the hooks, the theme link, the bevel bar and
# the font. When memphis.bar is the active bar, it switches the bar back to
# omarchy.bar first. It refuses while memphis is the current theme, because
# the theme hook must restore the user's values first. Packages stay installed.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PACKAGES=(chicago95-gtk-theme-git chicago95-icon-theme-git xcursor-chicago95-git)
HOOK_EVENTS=(theme-set post-boot post-update)

# Omarchy reads its config from $HOME/.config and ignores XDG_CONFIG_HOME.
OMARCHY_CONFIG="$HOME/.config/omarchy"
THEME_LINK="$OMARCHY_CONFIG/themes/memphis"
HOOKS_DIR="$OMARCHY_CONFIG/hooks"
PLUGIN="$OMARCHY_CONFIG/plugins/memphis.bar"
SHELL_JSON="$OMARCHY_CONFIG/shell.json"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/memphis"
THEME_NAME_FILE="$HOME/.local/state/omarchy/current/theme.name"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/memphis"
SAVED="$STATE_DIR/saved.env"

DRY_RUN=0

usage() {
  cat <<USAGE
Usage: ./uninstall.sh [--dry-run] [-h]

Removes the Memphis hooks, theme link, bevel bar and font. When memphis.bar
is the active bar, it runs 'omarchy bar reset' first. Switch to another theme
first.

  --dry-run       Print each action and change nothing
  -h, --help      Show this help
USAGE
}

while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
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

# The bar goes back to omarchy.bar before the plugin goes, so the shell never
# points at a missing bar.
if [[ -e $PLUGIN ]] && [[ $(jq -r '.id // ""' "$PLUGIN/manifest.json" 2>/dev/null) != "memphis.bar" ]]; then
  warn "$PLUGIN is not the Memphis bevel bar; leaving it"
else
  keep_plugin=0
  if [[ -s $SHELL_JSON ]] && [[ $(jq -r '.bar.id // ""' "$SHELL_JSON" 2>/dev/null) == "memphis.bar" ]]; then
    say "Switching the bar from memphis.bar back to omarchy.bar (the shell reloads the bar)"
    if ! run omarchy bar reset; then
      warn "omarchy bar reset failed; keeping $PLUGIN. Run 'omarchy bar reset', then ./uninstall.sh again"
      keep_plugin=1
    fi
  fi
  if [[ -e $PLUGIN ]] && ((!keep_plugin)); then
    say "Removing the bevel bar $PLUGIN"
    run rm -rf -- "$PLUGIN"
  fi
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
elif [[ -e $STATE_DIR/theme-set.lock ]]; then
  say "Removing the theme hook lock $STATE_DIR/theme-set.lock"
  run rm -f -- "$STATE_DIR/theme-set.lock"
  run rmdir --ignore-fail-on-non-empty -- "$STATE_DIR"
fi

echo
echo "Memphis is uninstalled."
echo "The Chicago95 packages stay installed. To remove them, run:"
echo
echo "  yay -R ${PACKAGES[*]}"
