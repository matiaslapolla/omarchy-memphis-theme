#!/bin/bash
# Tests extras/bar-bevel/build.sh. Writes only inside a temporary dir.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build="$repo/extras/bar-bevel/build.sh"
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
stock_bar="$omarchy_path/shell/plugins/bar"
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "ok   - $*"; }
fail() {
  echo "FAIL - $*" >&2
  failures=$((failures + 1))
}
# check <description> <command...>
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}
# expect_eq <description> <actual> <expected>
expect_eq() {
  if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}

no_stage_dirs() {
  local dir="$1" leftover
  [[ -d $dir ]] || return 0
  leftover=$(find "$dir" -mindepth 1 -maxdepth 1 -name '.memphis-bar*' -print -quit)
  [[ -z $leftover ]]
}

marker_count() {
  grep -c -F '// memphis-bevel' "$1" || true
}

# --- first build -------------------------------------------------------------

plugins="$tmp/plugins"
if "$build" "$plugins" >/dev/null; then
  pass "build.sh exits 0"
else
  fail "build.sh exits non-zero"
  exit 1
fi

manifest="$plugins/memphis.bar/manifest.json"
expect_eq "manifest id is memphis.bar" "$(jq -r .id "$manifest")" "memphis.bar"
expect_eq "manifest name is Memphis bar" "$(jq -r .name "$manifest")" "Memphis bar"
expect_eq "clonedFrom is omarchy.bar" "$(jq -r .omarchy.clonedFrom "$manifest")" "omarchy.bar"

stock_sha=$(sha256sum "$stock_bar/Bar.qml")
stock_sha=${stock_sha%% *}
expect_eq "manifest records the stock Bar.qml sha256" "$(jq -r .omarchy.memphisBevel.barQmlSha256 "$manifest")" "$stock_sha"

expect_eq "marker appears once" "$(marker_count "$plugins/memphis.bar/Bar.qml")" 1
check "no staging dir left behind" no_stage_dirs "$plugins"

# --- qmllint: the patched Bar.qml adds no warnings or errors -----------------

if [[ ! -x $qmllint ]]; then
  fail "qmllint not found at $qmllint (set QMLLINT)"
else
  # Quickshell resolves `import qs.X` against the shell root, so qmllint needs
  # an import path that holds a `qs` entry pointing at it.
  mkdir -p "$tmp/imports"
  ln -s "$omarchy_path/shell" "$tmp/imports/qs"

  lint() {
    local rc=0
    "$qmllint" -I "$tmp/imports" "$1" >"$2" 2>&1 || rc=$?
    echo "$rc"
  }
  severity_count() {
    grep -c "^$1:" "$2" || true
  }

  stock_rc=$(lint "$stock_bar/Bar.qml" "$tmp/lint-stock.txt")
  patched_rc=$(lint "$plugins/memphis.bar/Bar.qml" "$tmp/lint-patched.txt")
  stock_warn=$(severity_count Warning "$tmp/lint-stock.txt")
  stock_err=$(severity_count Error "$tmp/lint-stock.txt")
  patched_warn=$(severity_count Warning "$tmp/lint-patched.txt")
  patched_err=$(severity_count Error "$tmp/lint-patched.txt")
  echo "     qmllint stock:   rc=$stock_rc warnings=$stock_warn errors=$stock_err"
  echo "     qmllint patched: rc=$patched_rc warnings=$patched_warn errors=$patched_err"

  expect_eq "qmllint exit code matches stock" "$patched_rc" "$stock_rc"
  if (( patched_warn <= stock_warn && patched_err <= stock_err )); then
    pass "patched Bar.qml has no new qmllint warnings or errors"
  else
    fail "patched Bar.qml has new qmllint findings"
    diff <(sed -E 's/^([A-Za-z]+): [^ ]*Bar\.qml:[0-9]+:[0-9]+:/\1:/' "$tmp/lint-stock.txt" | grep -E '^(Warning|Error):' | sort) \
      <(sed -E 's/^([A-Za-z]+): [^ ]*Bar\.qml:[0-9]+:[0-9]+:/\1:/' "$tmp/lint-patched.txt" | grep -E '^(Warning|Error):' | sort) >&2 || true
  fi
fi

# --- second build replaces the first -----------------------------------------

if "$build" "$plugins" >/dev/null; then
  pass "second build exits 0"
else
  fail "second build exits non-zero"
fi
expect_eq "marker appears once after the second build" "$(marker_count "$plugins/memphis.bar/Bar.qml")" 1
check "no staging dir left after the second build" no_stage_dirs "$plugins"

# --- a foreign memphis.bar is not replaced -----------------------------------

foreign="$tmp/foreign"
mkdir -p "$foreign/memphis.bar"
echo '{"id": "someone.else"}' >"$foreign/memphis.bar/manifest.json"
if "$build" "$foreign" >/dev/null 2>&1; then
  fail "build.sh replaced a memphis.bar dir with another id"
else
  pass "build.sh refuses a memphis.bar dir with another id"
fi
expect_eq "foreign dir is untouched" "$(jq -r .id "$foreign/memphis.bar/manifest.json")" "someone.else"
check "no staging dir left after the refusal" no_stage_dirs "$foreign"

# --- a Bar.qml without the anchor fails cleanly -------------------------------

fake="$tmp/fake-omarchy"
mkdir -p "$fake/shell/plugins"
cp -a "$stock_bar" "$fake/shell/plugins/bar"
sed -i '/color: root.transparent ? "transparent" : (root.glassy ? root.glassBackground : root.background)/d' \
  "$fake/shell/plugins/bar/Bar.qml"
broken="$tmp/broken-plugins"
if OMARCHY_PATH="$fake" "$build" "$broken" >/dev/null 2>"$tmp/broken.err"; then
  fail "build.sh exits 0 without the anchor"
else
  pass "build.sh fails without the anchor"
fi
check "the error names the missing anchor" grep -q 'anchor found 0 times' "$tmp/broken.err"
check "no memphis.bar left after the failure" test ! -e "$broken/memphis.bar"
check "no staging dir left after the failure" no_stage_dirs "$broken"

if (( failures > 0 )); then
  echo "bar-bevel: $failures check(s) failed" >&2
  exit 1
fi
echo "bar-bevel: all checks passed"
