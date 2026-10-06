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

## xe driver note

`8086:7d55` is present in `xe`'s alias table and `xe` loads here, but
i915 owns Meteor Lake by default policy. Not chased: the runtime DSC
stack above makes the question moot for this machine.
