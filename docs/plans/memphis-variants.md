# Plan: Memphis Variants

Spec: `docs/specs/memphis-theme.md`, section Variants. One unit on branch `variants`.

## V1 — Palettes and theme dirs
- **Files:** `variants/memphis-{gray,dark}/`, `tests/contrast.sh`, `tests/variants.sh`, `tests/render.sh`, `tests/run.sh`, `extras/assets/gen-images.sh`
- **Steps:**
  1. Write `tests/contrast.sh`. Fix any root color under 4.2:1.
  2. Write the gray and dark `colors.toml`. Run `tests/contrast.sh`.
  3. Derive each `shell.toml` from the root file with the Variant colors.
  4. Copy `hyprland.lua` and `icons.theme`. Change the dark inactive border.
  5. Give `gen-images.sh` one palette per Variant. Generate all images.
  6. Let `tests/render.sh` take a theme dir. Run it on all three.
- **Check:** `tests/run.sh` passes.

## V2 — Hooks and Installer
- **Files:** `extras/hooks/{theme-set,post-boot}`, `install.sh`, `uninstall.sh`, `tests/hooks.sh`, `tests/install.sh`
- **Steps:**
  1. Accept the three Memphis slugs in `theme-set` and `post-boot`. Skip Chicago95 GTK under `memphis-dark`.
  2. Link and unlink the three Variants. Refuse the uninstall under any Memphis slug.
  3. Add the Variant cases to both tests.
- **Check:** `tests/run.sh` passes.

## V3 — Docs
- **Files:** `README.md`, `CONTEXT.md`
- **Check:** the README names the three Variants and their install command.
