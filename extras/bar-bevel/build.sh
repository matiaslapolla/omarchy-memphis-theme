#!/bin/bash
# Build the Bevel bar: copy the stock Omarchy bar plugin into
# <plugins-dir>/memphis.bar and add a Win98 bevel edge to its Bar.qml.

set -euo pipefail

SOURCE_ID="omarchy.bar"
NEW_ID="memphis.bar"
DISPLAY_NAME="Memphis bar"
MARKER="// memphis-bevel"
ANCHOR='color: root.transparent ? "transparent" : (root.glassy ? root.glassBackground : root.background)'

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
snippet="$script_dir/bevel.qml.snippet"

fail() {
  echo "bar-bevel: $*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: build.sh <plugins-dir>

Copies \$OMARCHY_PATH/shell/plugins/bar (default OMARCHY_PATH: /usr/share/omarchy)
into <plugins-dir>/$NEW_ID and inserts the Win98 bevel edge into Bar.qml.
It does not switch the active bar.
USAGE
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi
(( $# == 1 )) || { usage >&2; exit 2; }
[[ -n $1 ]] || fail "plugins dir is empty"

plugins_dir=$1
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
omarchy_path=${omarchy_path%/}
source_dir="$omarchy_path/shell/plugins/bar"
source_manifest="$source_dir/manifest.json"
target_dir="$plugins_dir/$NEW_ID"

[[ -f $snippet ]] || fail "snippet not found: $snippet"
[[ -f $source_manifest ]] || fail "stock bar manifest not found: $source_manifest"
[[ -f $source_dir/Bar.qml ]] || fail "stock Bar.qml not found: $source_dir/Bar.qml"
source_manifest_id=$(jq -r '.id // ""' "$source_manifest") || fail "cannot read $source_manifest"
[[ $source_manifest_id == "$SOURCE_ID" ]] || fail "$source_manifest has id '$source_manifest_id', expected '$SOURCE_ID'"

# Replace only a Bevel bar from an earlier build, never another plugin.
if [[ -L $target_dir ]]; then
  fail "$target_dir is a symlink; refusing to replace it"
elif [[ -e $target_dir ]]; then
  existing_id=$(jq -r '.id // ""' "$target_dir/manifest.json" 2>/dev/null || true)
  [[ $existing_id == "$NEW_ID" ]] || fail "$target_dir exists and is not a $NEW_ID build; refusing to replace it"
fi

# Same as omarchy-plugin-clone: built-in ids inside the plugin code stay as
# stable IPC targets, and clonedFrom routes them to this manifest id.
update_manifest() {
  local target_dir="$1"
  local source_id="$2"
  local new_id="$3"
  local display_name="$4"
  local manifest="$target_dir/manifest.json"

  jq \
    --arg id "$new_id" \
    --arg name "$display_name" \
    --arg sourceId "$source_id" '
      .id = $id |
      .name = $name |
      if (.barWidget | type) == "object" then
        .barWidget.displayName = $name
      else
        .
      end |
      .omarchy = (
        (if (.omarchy | type) == "object" then .omarchy else {} end) +
        { clonedFrom: $sourceId }
      ) |
      del(.omarchy.clonePaths)
    ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

record_build() {
  local manifest="$1/manifest.json"
  local version sha

  version=$(OMARCHY_PATH="$omarchy_path" omarchy-version 2>/dev/null) || version="unknown"
  sha=$(sha256sum "$source_dir/Bar.qml")
  sha=${sha%% *}
  jq --arg version "$version" --arg sha "$sha" '
      .omarchy.memphisBevel = { omarchyVersion: $version, barQmlSha256: $sha }
    ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

# Prints the line number of the background Rectangle's closing brace, or fails
# unless the four-line block occurs exactly once.
find_anchor() {
  local bar_qml="$1"
  local result hits line

  result=$(awk -v anchor="$ANCHOR" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    { text[NR] = trim($0) }
    END {
      for (i = 3; i < NR; i++) {
        if (text[i] == anchor && text[i - 1] == "anchors.fill: parent" &&
            text[i - 2] == "Rectangle {" && text[i + 1] == "}") {
          hits++
          at = i + 1
        }
      }
      printf "%d %d\n", hits, at
    }
  ' "$bar_qml")
  read -r hits line <<<"$result"
  (( hits == 1 )) ||
    fail "anchor found $hits times in $bar_qml (expected 1): the background Rectangle with '$ANCHOR'. The stock bar changed; update extras/bar-bevel."
  echo "$line"
}

# insert_snippet <bar-qml> <line>
insert_snippet() {
  local bar_qml="$1"
  local line="$2"
  local count

  awk -v at="$line" -v snippet="$snippet" '
    { print }
    NR == at { while ((getline l < snippet) > 0) print l; close(snippet) }
  ' "$bar_qml" >"$bar_qml.tmp"
  mv "$bar_qml.tmp" "$bar_qml"

  count=$(grep -c -F "$MARKER" "$bar_qml" || true)
  (( count == 1 )) || fail "marker '$MARKER' appears $count times in the patched Bar.qml (expected 1)"
}

# Checked on the stock file, before anything is written.
anchor_line=$(find_anchor "$source_dir/Bar.qml")

mkdir -p "$plugins_dir"
# A hidden dir in the same filesystem: the shell skips dot dirs, and the final
# rename is atomic.
stage=$(mktemp -d "$plugins_dir/.memphis-bar.XXXXXX")
cleanup() {
  if [[ -n ${stage:-} && -d $stage ]]; then rm -rf "$stage"; fi
}
trap cleanup EXIT

cp -aL "$source_dir/." "$stage/"
chmod 755 "$stage"
update_manifest "$stage" "$SOURCE_ID" "$NEW_ID" "$DISPLAY_NAME"
record_build "$stage"
insert_snippet "$stage/Bar.qml" "$anchor_line"

if [[ -e $target_dir ]]; then
  # After the exchange, $stage holds the old build and cleanup removes it.
  if ! mv --exchange -T "$stage" "$target_dir" 2>/dev/null; then
    old="$plugins_dir/.memphis-bar.old.$$"
    mv -T "$target_dir" "$old"
    mv -T "$stage" "$target_dir"
    stage=$old
  fi
else
  mv -T "$stage" "$target_dir"
  stage=""
fi

echo "Built $NEW_ID in $target_dir"
