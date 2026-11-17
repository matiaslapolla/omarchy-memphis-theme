#!/usr/bin/env bash
# Checks that each Variant dir in variants/ is a full theme dir and that it
# shares the root files it does not change.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
files=(colors.toml shell.toml hyprland.lua icons.theme preview.png preview-unlock.png unlock.png)
errors=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  errors=$((errors + 1))
}

# The border colors are the only lines a Variant hyprland.lua may change.
without_borders() { grep -vE '^local (active|inactive)_border_color = ' "$1"; }

count=0
for dir in "$repo"/variants/*/; do
  dir=${dir%/}
  name=${dir##*/}
  count=$((count + 1))
  [[ $name == memphis-* ]] || fail "$name is not a Memphis slug"
  for file in "${files[@]}"; do
    [[ -f $dir/$file && ! -L $dir/$file ]] || fail "$name/$file is missing or a symlink"
  done
  backgrounds=("$dir"/backgrounds/*.png)
  [[ -f ${backgrounds[0]} ]] || fail "$name has no backgrounds"
  if [[ -n $(find "$dir" -type l) ]]; then
    fail "$name holds symlinks, which omarchy-theme-set copies as broken links"
  fi
  cmp -s "$repo/icons.theme" "$dir/icons.theme" || fail "$name/icons.theme differs from the root"
  cmp -s <(without_borders "$repo/hyprland.lua") <(without_borders "$dir/hyprland.lua") ||
    fail "$name/hyprland.lua differs from the root outside the border colors"
done
((count == 2)) || fail "expected 2 Variants in variants/, found $count"

if ((errors > 0)); then
  printf 'variants.sh: %d failure(s)\n' "$errors" >&2
  exit 1
fi
printf 'variants.sh: OK (%d Variants)\n' "$count"
