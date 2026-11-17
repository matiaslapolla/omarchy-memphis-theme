#!/usr/bin/env bash
# Generates the preview images and backgrounds of the three Memphis Variants.
# Usage: extras/assets/gen-images.sh <repo-root>
set -euo pipefail
root=$1
font=$(fc-match -f '%{file}' monospace)

# rect x0 y0 x1 y1 color  (inclusive pixel coords)
rect() { printf "fill %s rectangle %d,%d %d,%d " "$5" "$1" "$2" "$3" "$4"; }

# The palette globals FACE, HI, HI2, LO, LO2, FIELD, TERM_BG, TERM_FG, DESK,
# WORD and WSHADOW are set by palette() for each Variant.

# Win98 raised box: HI / HI2 top-left, LO / LO2 bottom-right.
raised() {
  local x0=$1 y0=$2 x1=$3 y1=$4
  rect "$x0" "$y0" "$x1" "$y1" "$FACE"
  rect "$x0" "$y0" "$x1" "$y0" "$HI"; rect "$x0" "$y0" "$x0" "$y1" "$HI"
  rect $((x0+1)) $((y0+1)) $((x1-1)) $((y0+1)) "$HI2"; rect $((x0+1)) $((y0+1)) $((x0+1)) $((y1-1)) "$HI2"
  rect "$x0" "$y1" "$x1" "$y1" "$LO2"; rect "$x1" "$y0" "$x1" "$y1" "$LO2"
  rect $((x0+1)) $((y1-1)) $((x1-1)) $((y1-1)) "$LO"; rect $((x1-1)) $((y0+1)) $((x1-1)) $((y1-1)) "$LO"
}

# Win98 sunken field: LO / LO2 top-left, HI2 / HI bottom-right.
sunken() {
  local x0=$1 y0=$2 x1=$3 y1=$4 fill=$5
  rect "$x0" "$y0" "$x1" "$y1" "$fill"
  rect "$x0" "$y0" "$x1" "$y0" "$LO"; rect "$x0" "$y0" "$x0" "$y1" "$LO"
  rect $((x0+1)) $((y0+1)) $((x1-1)) $((y0+1)) "$LO2"; rect $((x0+1)) $((y0+1)) $((x0+1)) $((y1-1)) "$LO2"
  rect "$x0" "$y1" "$x1" "$y1" "$HI"; rect "$x1" "$y0" "$x1" "$y1" "$HI"
  rect $((x0+1)) $((y1-1)) $((x1-1)) $((y1-1)) "$HI2"; rect $((x1-1)) $((y0+1)) $((x1-1)) $((y1-1)) "$HI2"
}

# Status-field (shallow) sunken box.
shallow() {
  local x0=$1 y0=$2 x1=$3 y1=$4
  rect "$x0" "$y0" "$x1" "$y0" "$LO"; rect "$x0" "$y0" "$x0" "$y1" "$LO"
  rect "$x0" "$y1" "$x1" "$y1" "$HI"; rect "$x1" "$y0" "$x1" "$y1" "$HI"
}

# palette <variant>: the colors of shell.toml, colors.toml and the desktop.
palette() {
  LO2='#000000'
  case "$1" in
    memphis)
      FACE='#C0C0C0' HI='#FFFFFF' HI2='#DFDFDF' LO='#808080' FIELD='#FFFFFF'
      TERM_BG='#E8E8E8' TERM_FG='#000000'
      DESK='#008080' WORD='#FFFFFF' WSHADOW='#004848' BG_NAME=teal
      ;;
    memphis-gray)
      FACE='#A8A8A8' HI='#D8D8D8' HI2='#C4C4C4' LO='#6E6E6E' FIELD='#E4E4E4'
      TERM_BG='#B4B4B4' TERM_FG='#000000'
      DESK='#008080' WORD='#FFFFFF' WSHADOW='#004848' BG_NAME=teal
      ;;
    memphis-dark)
      FACE='#3A3A3A' HI='#5C5C5C' HI2='#4A4A4A' LO='#121212' FIELD='#1E1E1E'
      TERM_BG='#262626' TERM_FG='#D8D8D8'
      DESK='#004040' WORD='#C0C0C0' WSHADOW='#002020' BG_NAME=dark-teal
      ;;
    *) echo "gen-images.sh: unknown Variant $1" >&2; return 1 ;;
  esac
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
assets=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# gen_theme <variant> <theme-dir>
gen_theme() {
  local out=$2
  palette "$1"

  # --- preview.png: desktop mock, 2560x1440 ---------------------------------
  W=2560 H=1440 BAR=40
  by=$((H-BAR))
  wx0=320 wy0=150 wx1=2239 wy1=1249 B=3
  # Terminal window: 3px horizontal gradient #000080 -> #1084D0 around the
  # terminal background of the Variant.
  magick -size $((wx1-wx0+1))x$((wy1-wy0+1)) -define gradient:direction=east gradient:'#000080-#1084D0' \
    -fill "$TERM_BG" -draw "rectangle $B,$B $((wx1-wx0-B)),$((wy1-wy0-B))" \
    -font "$font" -pointsize 44 -fill "$TERM_FG" -annotate +40+80 'C:\\>' \
    -fill "$TERM_FG" -draw "rectangle 160,86 186,91" \
    "$tmp/window.png"

  draw="$(rect 0 "$by" $((W-1)) $((H-1)) "$FACE")$(rect 0 "$by" $((W-1)) "$by" "$HI")"
  # Workspace buttons at the left: the first one is pressed.
  draw+="$(sunken 6 $((by+6)) 37 $((by+34)) "$HI2")"
  draw+="$(raised 42 $((by+6)) 73 $((by+34)))"
  draw+="$(raised 78 $((by+6)) 109 $((by+34)))"
  # Status area at the right.
  draw+="$(shallow $((W-260)) $((by+6)) $((W-7)) $((by+34)))"

  magick -size ${W}x${H} xc:"$DESK" +antialias -draw "$draw" \
    "$tmp/window.png" -geometry +${wx0}+${wy0} -composite \
    -strip -depth 8 "$out/preview.png"

  # --- preview-unlock.png: lock mock, 1920x1080 -----------------------------
  W=1920 H=1080 bw=640 bh=120
  x0=$(((W-bw)/2)) y0=$(((H-bh)/2)) x1=$((x0+bw-1)) y1=$((y0+bh-1))
  draw="$(raised $x0 $y0 $x1 $y1)"
  draw+="$(sunken $((x0+24)) $((y0+36)) $((x1-24)) $((y1-36)) "$FIELD")"
  # Password dots.
  for i in 0 1 2 3; do
    cx=$((x0+48+i*28)) cy=$(((y0+y1)/2))
    draw+="fill $TERM_FG rectangle $((cx-5)),$((cy-5)) $((cx+5)),$((cy+5)) "
  done
  magick -size ${W}x${H} xc:"$DESK" +antialias -draw "$draw" -strip "$out/preview-unlock.png"

  # --- unlock.png: lock-screen image, 800x188 -------------------------------
  W=800 H=188 bw=720 bh=124
  x0=$(((W-bw)/2)) y0=$(((H-bh)/2)) x1=$((x0+bw-1)) y1=$((y0+bh-1))
  draw="$(raised $x0 $y0 $x1 $y1)"
  draw+="$(rect $((x0+3)) $((y0+3)) $((x1-3)) $((y0+28)) '#000080')"
  magick -size ${W}x${H} xc:"$DESK" +antialias -draw "$draw" \
    -size $((bw-6))x26 -define gradient:direction=east gradient:'#000080-#1084D0' \
    -geometry +$((x0+3))+$((y0+3)) -composite -strip -depth 8 "$out/unlock.png"

  # Backgrounds: the desktop color of the Variant, with and without the wordmark.
  mkdir -p "$out/backgrounds"
  rm -f "$out"/backgrounds/*.png

  # 0-teal-omarchy.png: Omarchy's own wordmark (logo.txt) in white with a hard
  # Win98 drop shadow. Omarchy cover-crops the wallpaper, and a 1440x2560
  # portrait screen shows only the central 1215 px of the 3840 px width, so the
  # 81-column wordmark at 12 px per cell (972 px) must stay narrower than that.
  wordmark() { python3 -I "$assets/wordmark.py" "$assets/omarchy-wordmark.txt" 12 24 3840 2160 "$@"; }
  magick -size 3840x2160 xc:"$DESK" +antialias \
    -draw "$(wordmark 6 6 "$WSHADOW") $(wordmark 0 0 "$WORD")" \
    -type Palette -strip "$out/backgrounds/0-$BG_NAME-omarchy.png"

  magick -size 3840x2160 xc:"$DESK" -define png:color-type=2 -strip "$out/backgrounds/1-$BG_NAME.png"
}

gen_theme memphis "$root"
gen_theme memphis-gray "$root/variants/memphis-gray"
gen_theme memphis-dark "$root/variants/memphis-dark"
