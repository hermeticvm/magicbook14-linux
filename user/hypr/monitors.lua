-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Internal OLED panel: 60 Hz by default (battery-conscious; 120 Hz costs
-- extra panel power and is worth it mainly on AC). Change it here anytime.
-- bitdepth 10: with DSC forced (honor-edp-dsc.service) this drives the panel
-- at true 10 bpc instead of 6 bpc + dithering. Without DSC the link can't
-- carry it and the driver silently falls back to 18 bpp, as before.
hl.monitor({ output = "eDP-1", mode = "3120x2080@60", position = "auto", scale = omarchy_monitor_scale, bitdepth = 10 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
