# Context

**Memphis theme**:
An Omarchy theme with a Windows 98 look. The repo root is the theme directory.
_Avoid_: win98 theme, retro theme

**Theme slug**:
The name `memphis`, which Omarchy writes to `~/.local/state/omarchy/current/theme.name`.
_Avoid_: theme id

**Bevel bar**:
The `memphis.bar` shell plugin, a copy of the stock `omarchy.bar` with a 3D edge added at install time. The Installer makes it the Bar engine under every theme. The edge draws only under a theme that sets `bar.bevel-light` and `bar.bevel-dark`.
_Avoid_: bar fork, taskbar

**Bar engine**:
The shell plugin that draws the bar, named by `.bar.id` in `~/.config/omarchy/shell.json`. No id means the stock `omarchy.bar`. The Theme hook never changes it.
_Avoid_: bar plugin, bar option

**Theme hook**:
The script in `extras/hooks/theme-set` that Omarchy runs after each theme switch.
_Avoid_: switch script

**Installer**:
The script `install.sh`. It installs the packages, the font, the theme, the hooks and the Bevel bar, and makes the Bevel bar the Bar engine. It does not apply the theme.
_Avoid_: setup script

**Saved state**:
The file `~/.local/state/memphis/saved.env`, which holds the user's values from before the first switch to Memphis. It does not hold the Bar engine.
_Avoid_: backup
