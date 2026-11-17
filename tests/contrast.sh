#!/usr/bin/env bash
# Checks the WCAG contrast of the terminal palette of each Variant.
# Usage: tests/contrast.sh [theme-dir...]   (default: the root and variants/*)
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (($# == 0)); then
  set -- "$repo" "$repo"/variants/*/
fi

python3 -I - "$@" <<'PY'
import sys
import tomllib

MIN_TEXT = 4.2
MIN_FOREGROUND = 7.0
MIN_SELECTION = 4.5
MIN_MUTED = 3.0
COLORS = ["red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown",
          "bright_red", "bright_yellow", "bright_green", "bright_cyan",
          "bright_blue", "bright_magenta"]


def luminance(hex_color):
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


failures = 0
for theme in sys.argv[1:]:
    with open(f"{theme.rstrip('/')}/colors.toml", "rb") as f:
        colors = tomllib.load(f)
    name = theme.rstrip("/").rsplit("/", 1)[-1]
    background = colors["background"]
    checks = [(key, colors[key], background, MIN_TEXT) for key in COLORS]
    checks += [
        ("foreground", colors["foreground"], background, MIN_FOREGROUND),
        ("muted", colors["muted"], background, MIN_MUTED),
        ("selection_foreground", colors["selection_foreground"],
         colors["selection_background"], MIN_SELECTION),
    ]
    for key, fg, bg, minimum in checks:
        ratio = contrast(fg, bg)
        if ratio < minimum:
            failures += 1
            print(f"FAIL: {name} {key} {fg} on {bg}: {ratio:.2f} < {minimum}", file=sys.stderr)

if failures:
    sys.exit(f"contrast.sh: {failures} failure(s)")
print(f"contrast.sh: OK ({len(sys.argv) - 1} palettes)")
PY
