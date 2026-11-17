#!/usr/bin/env bash
# Dry render of every stock Omarchy template with a theme's colors.toml.
# Usage: tests/render.sh [theme-dir]   (default: the repo root)
#
# It runs the real omarchy-theme-set-templates under a temporary HOME, so it
# writes only inside a mktemp dir. That script ends with a call to
# omarchy-theme-set-glass, which a no-op stub replaces here. Nothing live is
# touched: no theme switch, no reload, no restart.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
theme=$(cd "${1:-$repo}" && pwd)
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
templates_dir="$omarchy_path/default/themed"
renderer="$omarchy_path/bin/omarchy-theme-set-templates"
color_parser="$omarchy_path/bin/omarchy-theme-color"
colors="$theme/colors.toml"

errors=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  errors=$((errors + 1))
}

for path in "$renderer" "$color_parser" "$colors"; do
  [[ -f $path ]] || { printf 'FAIL: missing %s\n' "$path" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- colors.toml values -----------------------------------------------------

# omarchy-theme-color is the parser the renderer uses. It warns on stderr for
# each key or value that its allowed-character regex rejects.
"$color_parser" --file "$colors" --raw >"$tmp/raw.tsv" 2>"$tmp/raw.err" ||
  fail "omarchy-theme-color --raw exited non-zero"
if [[ -s $tmp/raw.err ]]; then
  fail "omarchy-theme-color rejected values:"
  sed 's/^/  /' "$tmp/raw.err" >&2
fi

declared=$(grep -cE '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=' "$colors" || true)
accepted=$(wc -l <"$tmp/raw.tsv")
((declared == accepted)) || fail "colors.toml declares $declared keys, the parser accepted $accepted"

# Mix tokens such as {{ mix foreground background 34% }} resolve only when
# both colors are #RRGGBB, so every palette color must use that form.
while IFS=$'\t' read -r key value; do
  case "$key" in
    mode) [[ $value == light || $value == dark ]] || fail "mode must be light or dark, got '$value'" ;;
    hyprland_*) [[ $value =~ ^(rgba?\([0-9A-Fa-f]{6,8}\)[[:space:]]*)+(-?[0-9]+deg)?$ ]] || fail "$key is not a Hyprland gradient: '$value'" ;;
    *) [[ $value =~ ^#[0-9A-Fa-f]{6}$ ]] || fail "$key is not #RRGGBB: '$value'" ;;
  esac
done <"$tmp/raw.tsv"

# --- template render --------------------------------------------------------

home="$tmp/home"
next="$home/.local/state/omarchy/current/next-theme"
stubs="$tmp/stubs"
mkdir -p "$next" "$stubs" "$tmp/tmpdir"
cp "$colors" "$next/colors.toml"
printf '#!/bin/sh\nexit 0\n' >"$stubs/omarchy-theme-set-glass"
chmod +x "$stubs/omarchy-theme-set-glass"

HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_STATE_HOME="$home/.local/state" \
  TMPDIR="$tmp/tmpdir" \
  OMARCHY_PATH="$omarchy_path" \
  PATH="$stubs:$omarchy_path/bin:$PATH" \
  bash "$renderer" >"$tmp/render.out" 2>"$tmp/render.err" ||
  fail "omarchy-theme-set-templates exited non-zero"

if [[ -s $tmp/render.err || -s $tmp/render.out ]]; then
  fail "renderer printed output or warnings:"
  cat "$tmp/render.out" "$tmp/render.err" | sed 's/^/  /' >&2
fi

shopt -s nullglob
template_count=0
for tpl in "$templates_dir"/*.tpl; do
  template_count=$((template_count + 1))
  name=${tpl##*/}
  name=${name%.tpl}
  out="$next/$name"
  if [[ ! -f $out ]]; then
    fail "$name was not rendered"
    continue
  fi
  if grep -nE '\{\{[^}]*\}\}' "$out" >"$tmp/unresolved"; then
    fail "$name has $(wc -l <"$tmp/unresolved") line(s) with unresolved tokens, first ones:"
    head -n 3 "$tmp/unresolved" | sed 's/^/  /' >&2
  fi
done
((template_count > 0)) || fail "no templates found in $templates_dir"

# --- theme files that replace rendered ones ---------------------------------

# The theme's hyprland.lua replaces the rendered one, so its border colors
# must match what colors.toml renders to.
for var in active_border_color inactive_border_color; do
  rendered=$(grep -m1 "^local $var = " "$next/hyprland.lua" | tr '[:upper:]' '[:lower:]' || true)
  shipped=$(grep -m1 "^local $var = " "$theme/hyprland.lua" | tr '[:upper:]' '[:lower:]' || true)
  [[ -n $rendered && $rendered == "$shipped" ]] ||
    fail "hyprland.lua $var differs from the render: '${shipped}' vs '${rendered}'"
done

# The theme's shell.toml replaces the generated one completely, so it must
# keep every section and every active key of the template. [font] base-size
# is left to the user on purpose.
sections_and_keys() {
  awk '
    /^[[:space:]]*\[[A-Za-z0-9_-]+\]/ { gsub(/[][[:space:]]/, ""); section = $0; print section; next }
    /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/ { split($0, kv, "="); gsub(/[[:space:]]/, "", kv[1]); print section "." kv[1] }
  ' "$1" | sort -u
}
if [[ -f $theme/shell.toml ]]; then
  while IFS= read -r entry; do
    [[ $entry == font.base-size ]] && continue
    fail "shell.toml lacks '$entry' from the template"
  done < <(comm -23 <(sections_and_keys "$next/shell.toml") <(sections_and_keys "$theme/shell.toml"))
  if grep -qE '^[[:space:]]*base-size[[:space:]]*=' "$theme/shell.toml"; then
    fail "shell.toml sets [font] base-size"
  fi
else
  fail "shell.toml is missing"
fi

if ((errors > 0)); then
  printf 'render.sh: %d failure(s)\n' "$errors" >&2
  exit 1
fi
printf 'render.sh: OK (%s: %d templates rendered, colors.toml valid)\n' "${theme##*/}" "$template_count"
