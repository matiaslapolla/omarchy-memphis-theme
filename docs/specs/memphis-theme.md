# Memphis: a Windows 98 look for Omarchy

**Status:** approved 2026-11-17 · **Source:** chat session 2026-11-17, three research reports

## Problem

Matias wants Omarchy to look like Windows 98. A plain Omarchy theme controls only colors, backgrounds, the icon name and shell colors. The GTK theme, the cursor, the UI font, the bar edge and the bar position need other mechanisms.

## Goal

- One public repo, `matiaslapolla/omarchy-memphis-theme`, gives the full look with one `./install.sh` and one `omarchy theme set memphis`.
- `omarchy theme install <url>` alone gives a colors-only version.
- When the user switches to another theme, the Theme hook reverts every change that is outside the theme.
- The Installer does not apply the theme. It does not reload Hyprland or change gsettings. Its only live change is one bar reload, when it makes the Bevel bar the Bar engine.

## Non-goals

- No Start button. The user opens apps with super+space.
- No window title bars (`hyprbars`) and no floating-window mode.
- No Qt theming. No Microsoft assets: no logo, wallpaper, fonts or cursors from Windows.
- No change to the terminal font. The shell and the terminals keep the user's monospace font.

## Terms

See `CONTEXT.md`: Memphis theme, Theme slug, Bevel bar, Bar engine, Theme hook, Installer, Saved state.

## Design

### Palette

Win98 "Windows Standard" values (98.css, Chicago95, Wine `syscolor.c`):

| Role | Hex |
|---|---|
| Desktop | `#008080` |
| Button face | `#C0C0C0` |
| Light edge / inner light | `#FFFFFF` / `#DFDFDF` |
| Shadow / dark shadow | `#808080` / `#000000` |
| Selection | `#000080`, text `#FFFFFF` |
| Active title gradient | `#000080` → `#1084D0` |
| Inactive title gradient | `#808080` → `#B5B5B5` |
| Tooltip | `#FFFFE1` |

### Theme files (repo root)

- `colors.toml`: `mode = "light"`. The terminal colors use the "Notepad" palette: a `#E8E8E8` background, black text and cursor, a `#000080` selection with white text, and dark Windows console colors that keep a 4.2:1 contrast or more on that gray. `selection` is `#C0C0C0`, because btop, tmux and Neovim draw dark text on it. `accent` is `#000080`. `hyprland_active_border` is the active title gradient. `hyprland_inactive_border` is the inactive gradient.
- `hyprland.lua`: `rounding = 0`, `border_size = 3`, no shadow, no blur, animations off. It also wraps the hyprbars `add_button` call, so the titlebars of floating workspaces are 40 px high with 32 px buttons, instead of 30 and 20. Omarchy drops this file for a git-cloned theme. The Installer links the repo, so Omarchy keeps it.
- `shell.toml`: the full shell template with Win98 values.
  - The bar is button face with black text and a `#000080` active color.
  - Popups, menu, notifications and polkit use button face with a 2 px `#FFFFFF`→`#808080` 45deg border (Qt y-down axis, so 45deg puts white at the top left).
  - The selected menu and launcher row is `#FFFFFF` with `#000080` text and border. Menu.qml draws row subtitles in the menu text color at 52% opacity on the selected row too, so a navy row would hide them. Tooltips are `#FFFFE1`.
  - It adds custom keys `bar.bevel-light = "#FFFFFF"` and `bar.bevel-dark = "#808080"`.
- `icons.theme`: `Chicago95`.
- `backgrounds/`: images generated with ImageMagick. `0-teal-omarchy.png` is the default: the Omarchy wordmark (`extras/assets/omarchy-wordmark.txt`, a copy of Omarchy's MIT `logo.txt`) in white with a `#004848` shadow at +6+6, 972 px wide in the center of the teal. Omarchy cover-crops the wallpaper, so the wordmark stays inside the central 1215 px that a 1440x2560 portrait screen shows. The other one is solid teal.
- `preview.png`, `preview-unlock.png` and `unlock.png`: generated mock images.
- `fonts/W95FA.otf` with `fonts/OFL.txt` (OFL-1.1, by Alina Sava).

### Bevel bar (`extras/bar-bevel/build.sh`)

- `build.sh <plugins-dir>` copies the stock `$OMARCHY_PATH/shell/plugins/bar` into `<plugins-dir>/memphis.bar`. It sets the manifest id to `memphis.bar` in the same way as `omarchy-plugin-clone`.
- It inserts a 1 px light line on the inner edge that faces the screen and a dark line on the opposite edge into `barStrip`, after the background `Rectangle`. The edge follows `root.position`.
- The lines read `Color.shellValues["bar.bevel-light"]` and `["bar.bevel-dark"]`. A missing key draws nothing, so the plugin is harmless under other themes.
- It exits with a non-zero code if the anchor text is not found. A failed build leaves the user on `omarchy.bar`.
- The Installer makes the Bevel bar the Bar engine once. It stays the engine under every theme, because the lines draw only under a theme that sets `bar.bevel-light` and `bar.bevel-dark`.
- The Theme hook never switches the Bar engine. `omarchy bar use` reloads the shell config. During `omarchy theme set`, that reload races the theme apply over IPC, and the new bar comes up with missing widgets.

### Theme hook (`extras/hooks/theme-set`)

The hook gets the Theme slug as `$1`.

For `memphis`:
1. If Saved state does not exist, write it: `cursor-theme`, `cursor-size`, `font-name` and `.bar.position`.
2. Set gsettings `gtk-theme Chicago95`, `cursor-theme Chicago95_Cursor_Black` and `font-name "W95FA 11"`. Run `hyprctl setcursor`.
3. Add `@import` of the Chicago95 `gtk-4.0/gtk.css` to `~/.config/gtk-4.0/gtk.css`, between marker comments.
4. Set the bar position to `bottom`.

For any other slug, if Saved state exists:
1. Restore each saved value. Remove the marked `@import` block.
2. Delete Saved state.

The hook does not run `omarchy bar use` or `omarchy bar reset`. It ignores a `bar_id` line that an older version wrote to Saved state.

Omarchy resets `gtk-theme` itself on each switch.

`extras/hooks/post-boot` sets the cursor again when the theme is `memphis`, because `~/.config/hypr/cursor.lua` resets it at login.

`extras/hooks/post-update` runs `build.sh` again, so the Bevel bar follows the upstream `Bar.qml` after `omarchy update`. If the build fails, it removes `memphis.bar`. If `memphis.bar` was the Bar engine, it runs `omarchy bar reset` first.

### Installer (`install.sh`, `uninstall.sh`)

- `install.sh` installs `chicago95-gtk-theme-git`, `chicago95-icon-theme-git` and `xcursor-chicago95-git` with `yay`. It copies the font to `~/.local/share/fonts`, runs `fc-cache` and links the repo to `~/.config/omarchy/themes/memphis`. It copies the three hooks into the `.d` hook dirs and builds the Bevel bar.
- After a successful build, the Installer sets the Bar engine:
  - If `.bar.id` is unset or `omarchy.bar`, it runs `omarchy bar use memphis.bar` and prints this step. The shell reloads the bar.
  - If `.bar.id` is `memphis.bar`, it does nothing.
  - If `.bar.id` names another bar, it keeps that bar. It prints a warning and the command `omarchy bar use memphis.bar`.
- Saved state does not record the Bar engine.
- If the theme dir exists and is not our link, it moves it to `~/.config/omarchy/memphis-theme.old.<timestamp>`, outside `themes/`, so `omarchy-theme-list` does not show it.
- `--no-packages` skips `yay`. `--dry-run` prints each action and changes nothing.
- At the end it prints `omarchy theme set memphis`. It does not run it.
- `uninstall.sh` removes the hooks, the link, the Bevel bar and the font. If Memphis is active, it tells the user to switch theme first.
- If `.bar.id` is `memphis.bar`, `uninstall.sh` runs `omarchy bar reset` before it removes the plugin. If the reset fails, it keeps the plugin and tells the user to run `omarchy bar reset`.
- `--dry-run` in both scripts prints the `omarchy bar` command and does not run it.

## Acceptance criteria

- [ ] `shellcheck install.sh uninstall.sh extras/hooks/* extras/bar-bevel/build.sh tests/*.sh` passes.
- [ ] `tests/run.sh` passes. It runs the Installer with `--no-packages` under a temporary `HOME` and runs the Theme hook with stub `gsettings`, `hyprctl` and `omarchy` commands.
- [ ] The hook test shows that a switch to `memphis` and then to `jade-horse` leaves gsettings, the bar plugin, the bar position and `gtk-4.0/gtk.css` the same as before.
- [ ] `build.sh` into a temporary dir produces `memphis.bar/manifest.json` with id `memphis.bar`, and `qmllint` reports no new errors in the patched `Bar.qml` relative to the stock file.
- [ ] `colors.toml` renders with `omarchy-theme-set-templates` logic without a missing-key warning. Checked through a dry render into a temporary dir.
- [ ] No file in the repo comes from Microsoft. The README has the trademark disclaimer.
- [ ] No step during the build ran `omarchy theme set`, `omarchy restart`, `hyprctl reload` or a real `gsettings set`.
- [ ] The repo is public at `github.com/matiaslapolla/omarchy-memphis-theme`.
