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

-- Omarchy's floating-workspace titlebars are set up in
-- default/hypr/workspace-modes.lua, which loads after this file: it sets
-- bar_height 30, then adds buttons of size 20. Wrapping add_button runs our
-- values after Omarchy's. The hyprbars plugin is only in from the second
-- config pass on, so the wrap applies there.
local TITLEBAR_BUTTON_SIZE = 32
local TITLEBAR_HEIGHT = 40
local hyprbars = hl.plugin and hl.plugin.hyprbars
if hyprbars and hyprbars.add_button and not hyprbars.memphis_add_button then
  hyprbars.memphis_add_button = hyprbars.add_button
  local height_set = false
  hyprbars.add_button = function(button)
    if not height_set then
      height_set = true
      hl.config({ plugin = { hyprbars = { bar_height = TITLEBAR_HEIGHT } } })
    end
    if type(button) == "table" then
      button.size = TITLEBAR_BUTTON_SIZE
    end
    return hyprbars.memphis_add_button(button)
  end
end
