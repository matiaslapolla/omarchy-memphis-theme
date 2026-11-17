# Plan: Memphis theme

Spec: `docs/specs/memphis-theme.md`. U1, U2 and U3 run in parallel in separate subagents. Each one touches only its files. U4 runs after them.

## U1 — Theme files
- **Files:** `colors.toml`, `hyprland.lua`, `shell.toml`, `icons.theme`, `backgrounds/`, `preview.png`, `preview-unlock.png`, `unlock.png`, `fonts/`, `tests/render.sh`
- **Steps:**
  1. Copy the key set from stock `retro-82/colors.toml`. Fill it with the spec palette.
  2. Write `hyprland.lua` from the stock `lumon` and `solitude` examples.
  3. Render `shell.toml.tpl` with the new colors. Change the Win98 values. Add the bevel keys.
  4. Generate the backgrounds and the preview images with ImageMagick.
  5. Download W95FA from FontsArena. Check that the license is OFL. Add `OFL.txt`.
  6. Write `tests/render.sh`: a dry render of all templates into a temporary dir.
- **Check:** `tests/render.sh` exits 0 with no warnings.

## U2 — Bevel bar
- **Files:** `extras/bar-bevel/build.sh`, `extras/bar-bevel/bevel.qml.snippet`, `tests/bar-bevel.sh`
- **Steps:**
  1. Read `omarchy-plugin-clone` to copy its id rewrite.
  2. Write `build.sh <plugins-dir>`: copy, rewrite the id, insert the snippet after the background `Rectangle`.
  3. Fail with a clear message if the anchor is missing.
  4. Write `tests/bar-bevel.sh`: build into a temporary dir, check the manifest, run `qmllint` on both files and compare the errors.
- **Check:** `tests/bar-bevel.sh` exits 0.

## U3 — Hooks and Installer
- **Files:** `extras/hooks/{theme-set,post-boot,post-update}`, `install.sh`, `uninstall.sh`, `tests/hooks.sh`, `tests/install.sh`, `tests/stubs/`
- **Steps:**
  1. Read `omarchy-hook`, `omarchy-bar-use` and `omarchy-bar-position` to learn the real calls.
  2. Write the Theme hook with Saved state, as in the spec.
  3. Write `install.sh` and `uninstall.sh` with `--dry-run` and `--no-packages`.
  4. Write stub commands that log their arguments to a file.
  5. Write the tests: a temporary `HOME`, stubs first on `PATH`, memphis then jade-horse.
- **Check:** `tests/hooks.sh` and `tests/install.sh` exit 0.

## U4 — Docs and publish
- **Files:** `README.md`, `LICENSE`, `tests/run.sh`, `.gitignore`
- **Steps:**
  1. Write `tests/run.sh`: shellcheck plus the three tests.
  2. Write the README: screenshot slot, install, uninstall, what changes, disclaimer.
  3. Add an MIT license for our files. W95FA keeps OFL.
  4. Run `tests/run.sh`. Commit. Create the public repo with `devflow gh-org --account matiaslapolla`. Push.
- **Check:** `gh repo view matiaslapolla/omarchy-memphis-theme` shows the repo as public.
