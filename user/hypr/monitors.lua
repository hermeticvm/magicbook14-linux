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
-- cm = srgb: desktop stays plain sRGB (no skew for apps whose renderers
-- don't expect tonemapping — Brave/Skia etc). HDR engages per fullscreen
-- app via render:cm_auto_hdr (set in hyprland.lua): the panel flips to
-- BT.2020 + PQ just for that surface, back to sRGB when it closes.
-- supports_wide_color/supports_hdr overrides: the panel declares BT.2020 +
-- ST.2084 (1600 nits peak @10% window, 0.012 nit black) in a DisplayID EDID
-- block that Hyprland's auto-detection doesn't parse — without the overrides
-- every HDR path silently degrades to sRGB. min/max_luminance carry the
-- panel's real mastering limits into the HDR metadata blob when it flips.
hl.monitor({
  output = "eDP-1",
  mode = "3120x2080@60",
  position = "auto",
  scale = omarchy_monitor_scale,
  bitdepth = 10,
  supports_wide_color = 1,
  supports_hdr = 1,
  cm = "srgb",
  sdrbrightness = 1.2,
  sdrsaturation = 0.98,
  min_luminance = 0.012,
  max_luminance = 1600,
})

-- External: Kuycon G32P 32" 6K, HDMI path. The sink declares 6144x3456@60
-- (needs HDMI 2.1 FRL + DSC), but i915 7.2.5 has no native FRL training —
-- TMDS modes only. Best real mode: 3840x2160@60; 10 bpc fits the budget
-- (17.8 < 18 Gbps) so the 10-bit panel gets depth. scale 1.25 ≈ the
-- effective dpi of the same panel at 6K@2x on macOS. USB-C path is blocked
-- (EC/UCSI — see the repo docs); HDMI is the working external route.
hl.monitor({
  output = "HDMI-A-1",
  mode = "3840x2160@60",
  position = "auto",
  scale = 1.25,
  bitdepth = 10,
})

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
