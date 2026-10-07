# Display: 10-bit over DSC, on a link that can't carry it uncompressed

Panel: EDO OLED 3120×2080, DP1.4 via eDP, touchscreen, rounded corners
(compensated in shell CSS). Pixel clock is 900.864 MHz for both 60 and
120 Hz (the OLED stretches vblank, so both modes share one internal clock).

## Current state (all measured, not guessed)

- **10 bpc with DSC active** — `DSC_Enabled: yes`, `Input_BPC: 10`,
  `crtc-0 Current: 10`. Stock was 18 bpp = 6 bpc + dithering.
- 60 Hz daily driver (`user/hypr/monitors.lua`, scale 2).
- Brightness floor walked 18→88 in a dark room: no tint, no mura, no
  blotches at any step — the low-brightness OLED fix from the M1010 repo
  does not apply to this panel. F1/F2 or `brightnessctl`, max 704.

## The link math (why 18 bpp was forced)

Four lanes of HBR2 leave 2,160,000 usable link units (kernel's 10 kHz·lane
accounting). At 900,864 kHz pixel clock:

| Depth | Required | Fits? |
|---|---|---|
| 18 bpp (6 bpc + dither) | 1,621,555 | yes — stock state |
| 24 bpp (8 bpc) | 2,162,074 | no, by 0.1% |
| 30 bpp (10 bpc) | 2,702,592 | no |
| 30 bpp input, DSC compressed to ~8 | ~720,691 | yes, ⅓ headroom |

The panel decodes DSC 1.2, 4 slices, RGB, 8 and 10 bpc. The link can carry
10-bit only compressed. Stock driver policy: drop depth to make a mode
fit, consider compression only when the uncompressed search *fails*.
So: 18 bpp, 6 bpc, dithering — by default, forever.

## Why the obvious patch is a trap (documented negative result)

The M1010 repo's `prefer-DSC-over-6bpc` patch (fixes exactly this policy)
**black-screens at early KMS on this board** — Meteor Lake/i915. The same
patch works on the ZQC-P (Panther Lake, `xe`). Applied against i915 here,
built fine, and killed the panel at boot; rescue session reverted.
Treated as xe-only, documented upstream. Do not re-apply to i915 boot.

## The runtime path that worked (no kernel patch at all)

i915 ships per-connector debugfs knobs for exactly this:

- `i915_dsc_bpc` — force DSC input depth
- `i915_dsc_fec_support` — force DSC on/off (`kstrtobool`)

Plus the DRM connector property `max bpc` (range 6–12), which caps the
depth before any of this matters. The stack, all runtime, all volatile:

1. **`bitdepth = 10` in the eDP-1 monitor rule** (`user/hypr/monitors.lua`)
   — Hyprland raises the connector `max bpc` property to 10. Harmless
   standalone: if DSC isn't forced, uncompressed 30 bpp doesn't fit and
   the driver falls back to 18 bpp as before. Survives config reloads
   (verified).
2. **`honor-edp-dsc.service`** (`system/systemd/`) →
   `/usr/local/bin/honor-edp-dsc-force` — oneshot, `Before=graphical.target`,
   writes the two debugfs flags. The session's first modeset then computes
   DSC at 10 bpc. The initramfs/early-KMS path is untouched and stock —
   that's the part the patch approach got wrong.
3. Escape hatch (in the unit comment too): a boot that ever comes up
   black on the internal panel → TTY → `systemctl mask honor-edp-dsc`
   → reboot → stock behavior. Stock-UKI fallback entry still exists for
   the paranoid case.

Probe history that got here: DPMS-trigger attempts failed hilariously
(Hyprland 0.56 uses a Lua dispatcher surface — `hyprctl dispatch
'hl.dsp.dpms("off", "eDP-1")'`; the legacy `dispatch dpms off` syntax is
rejected), `max bpc` was found at 8 (property, not EDID, was the cap),
and one auto-revert timer stomped one property write before the install
ran. The measured ladder: 6 bpc+dither → 8 bpc DSC (max bpc still 8) →
**10 bpc DSC** (property 10 + force + one dpms cycle).

## HDR: real hardware, per-content engage (HDR10 OLED)

The panel is a genuine HDR display, not "HDR400" laptop marketing. EDID
(`edid-decode`, full 256 bytes incl. extension):

| Declaration | Value |
|---|---|
| Color space / transfer | BT.2020 + SMPTE ST.2084 (PQ) |
| Peak luminance (10% window) | 1600 nits |
| Full-frame max | 700 nits |
| Black | 0.012 nits |
| Desired content maxFALL | ~703 nits |

### The DisplayID detection gap

All of that is declared in a **DisplayID extension block**, not classic
CTA-861. Hyprland's auto-detection (aquamarine → libdisplay-info) doesn't
parse that form, so `supportsBT2020` / HDR capability read as absent — and
`cm = "hdr"` **silently degrades to sRGB** (`Monitor.cpp`: `supportsHDR() ?
cm : srgb`). The monitor-rule overrides exist for exactly this:
`supports_wide_color = 1, supports_hdr = 1` plus `min_luminance` /
`max_luminance` carrying the panel's real mastering limits into the
SMPTE 2086 metadata blob. With those, the flip is verified:
`Colorspace` property 0 → 9 (BT2020_RGB) and a committed Type-1 metadata
blob over the DSC link.

### Mode choice: per-content, not full-time

Full-time HDR (`cm = "hdr"` desktop) works but tonemaps every SDR app
through PQ — renderers that don't expect it (Brave/Skia) shift color.
Chosen instead: **sRGB desktop, HDR only while fullscreen HDR content
plays**:

- `cm = "srgb"` in the eDP-1 rule — desktop colors exactly as before.
- `render:cm_auto_hdr = 1` (`user/hypr/hyprland.lua`) — auto-flips the
  panel for fullscreen apps that *tag* their surfaces HDR (gamescope with
  `--hdr-enabled`, `ENABLE_HDR_WSI`/`DXVK_HDR` wine paths). Verified path
  for those; games.
- **`mpv-hdr`** (`user/local-bin/`) — for mpv, whose
  `--target-colorspace-hint` does *not* tag its surface (measured: Hyprland
  0.56.2 sees an sRGB window during PQ playback), so auto-HDR never
  triggers. The wrapper flips the panel to PQ for the duration of playback
  and restores sRGB on exit (trap, crash-safe; verified 0 → 9 → 0 across
  the connector property). `mpv-hdr file.mkv` is the whole interface.

Browser HDR video (YouTube) depends on Chromium's Wayland color-management
implementation tagging surfaces — untested here; use `mpv-hdr` with
downloads in the meantime.

### What carries HDR on this panel

Everything from the DSC section is the HDR prerequisite: HDR10 needs
10 bpc, and the link only carries it compressed. `hdr_output_metadata`
+ BT.2020 colorspace + DSC all ride the same modeset.

## External displays over USB-C: blocked (M1010 firmware/driver gap)

Chassis: two USB-C ports, both Type-C-subsystem backed (`00:07.0` root port,
`00:0d.0` TB xHCI + `00:0d.3` DMA1; host router `Gen14`, USB4), i915 TC
PHYs (TC#2/TC#3, tbt-alt, 4 lanes). Tested with a 32" 6K TB4-class display
and a 10 Gbps SSD, same ports, same cables, one evening:

| Test | Result |
|---|---|
| SSD in port 1 | **SuperSpeed Plus Gen 2x1, 10 Gbps** on `00:0d.0` — SS lanes fine |
| Display in port 1 | 480 Mbps PCH fallback — SS never connects |
| Display in port 2 | identical 480 Mbps fallback |
| TB4 display on a MacBook | 6K works — display side is healthy |

So: ports carry SS, cable carries SS, display negotiates USB4 fine elsewhere
— but with this host the display's SS lines never come up. No HPD, no TC
messages, no USB4 partner on domain0, nothing for DRM to detect. A
TB4-class display parks its SS lines until USB4 host negotiation succeeds
(it does not fall back to USB3 like the SSD does); the USB4/DP-alt entry
requires host-side PD commands (`Enter Mode` / USB4 Enter) — and on this
machine **Linux has no path to issue them**:

- no UCSI ACPI device in the namespace (`INTC1043` absent; `INTC1042` is
  the sensor hub), so `ucsi_acpi` has nothing to bind
- `/sys/class/typec` never exists — no port class, no mux enumeration
- HONOR's EC owns the PD controller and mux; firmware exposes a private
  `TbtTypeC` SSDT dialect and a `DOCM: Apply CM mode to iTBT0/iTBT1`
  command set (DSDT), no bridge to Linux

USB3 works (SSD proves it: autonomous, no policy needed). USB4-class
peripherals that require host-negotiated entry don't. Until HONOR's EC
speaks UCSI (or someone REs the `TbtTypeC` op-region), external displays
over USB-C are **not achievable on this board under Linux** — same wall as
the battery-limit offsets: EC-owned, dialect-locked. Document upstream if
you own both boards. The built-in HDMI port remains for plain displays.

### Why the monitor still charges the laptop (documented, not bizarre)

The 6K display (Kuycon G32P class) delivers **up to 100 W upstream PD**
through its USB-C input — a documented feature. Why power works while
display doesn't: PD is a CC-line message protocol with independent halves.
Power contracts (source advertises, sink requests) run autonomously on this
EC — every PD charger proves it; the monitor's PSU is just another source
(`ADP1 online=1` while attached, battery full). USB2 pins are always-on;
USB3 trains itself in the PHY (10 Gbps SSD verified). Alt-mode entry
(`Enter Mode` / USB4 Enter) is a **host-issued** PD command — the exact
half HONOR's EC doesn't expose to Linux. Monitor on this laptop = charger,
USB2 hub, USB3-capable port; DP-alt/USB4 dead. Fully consistent.

### HDMI escape hatch (future)

The display also takes HDMI 2.1 / DP inputs (ships USB-C, DP, HDMI cables).
MTL has native HDMI 2.1 silicon, but i915 FRL is still landing upstream
(Intel's 44-patch series); on 7.2.5 only detection/PCON symbols exist —
no native FRL training. So the laptop's HDMI today is TMDS (≈HDMI 2.0):
4K@60, no DSC, no 6K. Revisit when native FRL lands: 6K@60 over
HDMI FRL+DSC would then be on the table.

### Chassis EMI note (keyboard)

While the 6K was connected, the internal PS/2 keyboard (i8042/atkbd — not
USB, no shared data path) showed doubled and dropped keys. Unplug → clean,
replug → jank, A/B verified; an SSD on the same port → no jank. This board
already needed an atkbd phantom-scancode hwdb patch on day one — its
keyboard lines are noise-sensitive. With a TB4 display + PSU + cable into
the chassis: break the ground/EMI path (monitor PSU on a different outlet,
ferrite on the cable, or a powered hub in between) and the jank goes.
Not a Linux bug; electrical.

## xe driver note

`8086:7d55` is present in `xe`'s alias table and `xe` loads here, but
i915 owns Meteor Lake by default policy. Not chased: the runtime DSC
stack above makes the question moot for this machine.
