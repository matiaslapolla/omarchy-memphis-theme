#!/usr/bin/env bash
# Runs the linter and every test. Set SHELLCHECK to a binary path when the
# binary on PATH does not run.
set -euo pipefail

cd "$(dirname "$0")/.."

shellcheck_bin=${SHELLCHECK:-shellcheck}
if ! "$shellcheck_bin" --version >/dev/null 2>&1; then
  echo "run.sh: '$shellcheck_bin' does not run; set SHELLCHECK=/path/to/shellcheck" >&2
  exit 1
fi

"$shellcheck_bin" install.sh uninstall.sh extras/hooks/* extras/bar-bevel/build.sh \
  extras/assets/gen-images.sh tests/*.sh
echo "shellcheck: OK"

for test in tests/render.sh tests/bar-bevel.sh tests/hooks.sh tests/install.sh; do
  bash "$test" >/dev/null
  echo "$test: OK"
done
