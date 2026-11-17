# Context

**Memphis theme**:
An Omarchy theme with a Windows 98 look. The repo root is the theme directory.
_Avoid_: win98 theme, retro theme

**Theme slug**:
The name `memphis`, which Omarchy writes to `~/.local/state/omarchy/current/theme.name`.
_Avoid_: theme id

**Bevel bar**:
The `memphis.bar` shell plugin, a copy of the stock `omarchy.bar` with a 3D edge added at install time.
_Avoid_: bar fork, taskbar

**Theme hook**:
The script in `extras/hooks/theme-set` that Omarchy runs after each theme switch.
_Avoid_: switch script

**Installer**:
The script `install.sh`, which installs the packages, the font, the theme, the hooks and the bevel bar, without applying the theme.
_Avoid_: setup script

**Saved state**:
The file `~/.local/state/memphis/saved.env`, which holds the user's values from before the first switch to Memphis.
_Avoid_: backup
