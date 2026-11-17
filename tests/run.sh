#!/usr/bin/env bash
# Runs the linter and every test. Set SHELLCHECK to a binary path when the
# binary on PATH does not run.
set -euo pipefail

cd "$(dirname "$0")/.."

shellcheck_cmd=("${SHELLCHECK:-shellcheck}")
if ! "${shellcheck_cmd[@]}" --version >/dev/null 2>&1 && command -v mise >/dev/null 2>&1; then
  shellcheck_cmd=(mise exec shellcheck -- shellcheck)
fi
if ! "${shellcheck_cmd[@]}" --version >/dev/null 2>&1; then
  echo "run.sh: shellcheck does not run; set SHELLCHECK=/path/to/shellcheck" >&2
  exit 1
fi

"${shellcheck_cmd[@]}" install.sh uninstall.sh extras/hooks/* extras/bar-bevel/build.sh \
  extras/assets/gen-images.sh tests/*.sh
echo "shellcheck: OK"

for theme in . variants/*/; do
  bash tests/render.sh "$theme" >/dev/null
  echo "tests/render.sh $theme: OK"
done

for test in tests/contrast.sh tests/variants.sh tests/bar-bevel.sh tests/hooks.sh tests/install.sh; do
  bash "$test" >/dev/null
  echo "$test: OK"
done
