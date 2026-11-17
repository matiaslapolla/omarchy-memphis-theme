-- This file replaces the hyprland.lua that Omarchy renders from colors.toml,
-- so it sets the border colors itself. Keep them equal to
-- hyprland_active_border and hyprland_inactive_border in colors.toml.
local active_border_color = { colors = { "rgb(000080)", "rgb(1084d0)" }, angle = 0 }
local inactive_border_color = { colors = { "rgb(808080)", "rgb(b5b5b5)" }, angle = 0 }

hl.config({
  general = {
    border_size = 3,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },

    groupbar = {
      text_color = "rgb(ffffff)",
      text_color_inactive = "rgb(c0c0c0)",
      col = {
        active = "rgb(000080)",
        inactive = "rgb(808080)",
      },
    },
  },

  decoration = {
    rounding = 0,

    shadow = {
      enabled = false,
    },

    blur = {
      enabled = false,
    },
  },

  animations = {
    enabled = false,
  },
})
