#!/usr/bin/env bash
# Generates the preview images and backgrounds of the Memphis theme.
# Usage: extras/assets/gen-images.sh <repo-root>
set -euo pipefail
out=$1
font=$(fc-match -f '%{file}' monospace)

# rect x0 y0 x1 y1 color  (inclusive pixel coords)
rect() { printf "fill %s rectangle %d,%d %d,%d " "$5" "$1" "$2" "$3" "$4"; }

# Win98 raised box: white / #DFDFDF top-left, #808080 / black bottom-right.
raised() {
  local x0=$1 y0=$2 x1=$3 y1=$4
  rect "$x0" "$y0" "$x1" "$y1" '#C0C0C0'
  rect "$x0" "$y0" "$x1" "$y0" '#FFFFFF'; rect "$x0" "$y0" "$x0" "$y1" '#FFFFFF'
  rect $((x0+1)) $((y0+1)) $((x1-1)) $((y0+1)) '#DFDFDF'; rect $((x0+1)) $((y0+1)) $((x0+1)) $((y1-1)) '#DFDFDF'
  rect "$x0" "$y1" "$x1" "$y1" '#000000'; rect "$x1" "$y0" "$x1" "$y1" '#000000'
  rect $((x0+1)) $((y1-1)) $((x1-1)) $((y1-1)) '#808080'; rect $((x1-1)) $((y0+1)) $((x1-1)) $((y1-1)) '#808080'
}

# Win98 sunken field: #808080 / black top-left, #DFDFDF / white bottom-right.
sunken() {
  local x0=$1 y0=$2 x1=$3 y1=$4 fill=$5
  rect "$x0" "$y0" "$x1" "$y1" "$fill"
  rect "$x0" "$y0" "$x1" "$y0" '#808080'; rect "$x0" "$y0" "$x0" "$y1" '#808080'
  rect $((x0+1)) $((y0+1)) $((x1-1)) $((y0+1)) '#000000'; rect $((x0+1)) $((y0+1)) $((x0+1)) $((y1-1)) '#000000'
  rect "$x0" "$y1" "$x1" "$y1" '#FFFFFF'; rect "$x1" "$y0" "$x1" "$y1" '#FFFFFF'
  rect $((x0+1)) $((y1-1)) $((x1-1)) $((y1-1)) '#DFDFDF'; rect $((x1-1)) $((y0+1)) $((x1-1)) $((y1-1)) '#DFDFDF'
}

# Status-field (shallow) sunken box.
shallow() {
  local x0=$1 y0=$2 x1=$3 y1=$4
  rect "$x0" "$y0" "$x1" "$y0" '#808080'; rect "$x0" "$y0" "$x0" "$y1" '#808080'
  rect "$x0" "$y1" "$x1" "$y1" '#FFFFFF'; rect "$x1" "$y0" "$x1" "$y1" '#FFFFFF'
}

# --- preview.png: desktop mock, 2560x1440 ---------------------------------
W=2560 H=1440 BAR=40
by=$((H-BAR))
wx0=320 wy0=150 wx1=2239 wy1=1249 B=3
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Window border: 3px horizontal gradient #000080 -> #1084D0 with a black inside.
magick -size $((wx1-wx0+1))x$((wy1-wy0+1)) -define gradient:direction=east gradient:'#000080-#1084D0' \
  -fill '#000000' -draw "rectangle $B,$B $((wx1-wx0-B)),$((wy1-wy0-B))" \
  -font "$font" -pointsize 44 -fill '#C0C0C0' -annotate +40+80 'C:\\>' \
  -fill '#C0C0C0' -draw "rectangle 160,86 186,91" \
  "$tmp/window.png"

draw="$(rect 0 "$by" $((W-1)) $((H-1)) '#C0C0C0')$(rect 0 "$by" $((W-1)) "$by" '#FFFFFF')"
# Workspace buttons at the left: the first one is pressed.
draw+="$(sunken 6 $((by+6)) 37 $((by+34)) '#DFDFDF')"
draw+="$(raised 42 $((by+6)) 73 $((by+34)))"
draw+="$(raised 78 $((by+6)) 109 $((by+34)))"
# Status area at the right.
draw+="$(shallow $((W-260)) $((by+6)) $((W-7)) $((by+34)))"

magick -size ${W}x${H} xc:'#008080' +antialias -draw "$draw" \
  "$tmp/window.png" -geometry +${wx0}+${wy0} -composite \
  -strip -depth 8 "$out/preview.png"

# --- preview-unlock.png: lock mock, 1920x1080 -----------------------------
W=1920 H=1080 bw=640 bh=120
x0=$(((W-bw)/2)) y0=$(((H-bh)/2)) x1=$((x0+bw-1)) y1=$((y0+bh-1))
draw="$(raised $x0 $y0 $x1 $y1)"
draw+="$(sunken $((x0+24)) $((y0+36)) $((x1-24)) $((y1-36)) '#FFFFFF')"
# Password dots.
for i in 0 1 2 3; do
  cx=$((x0+48+i*28)) cy=$(((y0+y1)/2))
  draw+="fill #000000 rectangle $((cx-5)),$((cy-5)) $((cx+5)),$((cy+5)) "
done
magick -size ${W}x${H} xc:'#008080' +antialias -draw "$draw" -strip "$out/preview-unlock.png"

# --- unlock.png: lock-screen image, 800x188 -------------------------------
W=800 H=188 bw=720 bh=124
x0=$(((W-bw)/2)) y0=$(((H-bh)/2)) x1=$((x0+bw-1)) y1=$((y0+bh-1))
draw="$(raised $x0 $y0 $x1 $y1)"
draw+="$(rect $((x0+3)) $((y0+3)) $((x1-3)) $((y0+28)) '#000080')"
magick -size ${W}x${H} xc:'#008080' +antialias -draw "$draw" \
  -size $((bw-6))x26 -define gradient:direction=east gradient:'#000080-#1084D0' \
  -geometry +$((x0+3))+$((y0+3)) -composite -strip -depth 8 "$out/unlock.png"

# Backgrounds: original patterns in the Win98 desktop teal.
mkdir -p "$out/backgrounds"

# 0-teal-omarchy.png: Omarchy's own wordmark (logo.txt) in white with a hard
# Win98 drop shadow. Omarchy cover-crops the wallpaper, and a 1440x2560
# portrait screen shows only the central 1215 px of the 3840 px width, so the
# 81-column wordmark at 12 px per cell (972 px) must stay narrower than that.
assets=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
wordmark() { python3 -I "$assets/wordmark.py" "$assets/omarchy-wordmark.txt" 12 24 3840 2160 "$@"; }
magick -size 3840x2160 xc:'#008080' +antialias \
  -draw "$(wordmark 6 6 '#004848') $(wordmark 0 0 '#FFFFFF')" \
  -type Palette -strip "$out/backgrounds/0-teal-omarchy.png"

magick -size 3840x2160 xc:'#008080' -define png:color-type=2 "$out/backgrounds/1-teal.png"
