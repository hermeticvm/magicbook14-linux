# Display: what works, what's link-bound, what to not retry

Panel: EDO OLED 3120×2080, DP1.4 via eDP, touchscreen works out of the box,
rounded corners (compensated in shell CSS, not a display problem).

## Working state

- 60 Hz daily driver on battery (`user/hypr/monitors.lua`, scale 2).
  120 Hz works and is one flag away; it costs idle power (see power doc).
- Brightness floor: walked 18→88 steps with the display dark in a dim room,
  camera + eye check: **no tint, no mura, no blotches at any step**. The
  "OLED black-crush at low brightness" fix from the M1010 repo does not apply
  to this panel; none needed.
- Brightness knob: F1/F2 (via `brightnessctl`), max 704.

## The 18 bpp ceiling and the DSC dead end

DPCD readout: sink is **DSC 1.2 capable** (4 slices, RGB, 8/10 bpc), link is
2×HBR2 rates only (no HBR3). 3120×2080@120 needs more bandwidth than 2×HBR2
carries without compression; without DSC the panel runs bpp=18 (6 bpc +
dithering) as stock, and that's what you see.

The obvious fix — prefer DSC in `intel_dp.c`, the same patch that works on
the ZQC-P (Panther Lake, `xe` driver) — **black-screens at early KMS on this
Meteor Lake/i915 board**. Attempted, measured, reverted. The i915 DSC path
for this PTL-derived panel timing evidently isn't ready on 7.2.x. Not retried
per kernel; treat as **xe-only until i915 DSC for MTL eDP matures**. Documented
in the M1010 repo docs (PR #15) so nobody else burns an evening on it.

Safety net from that evening: a stock i915 UKI copy is kept as
`omarchy_linux-omarchy-stock.efi` with a limine entry `linux-omarchy-stock`.
Rescue path: boot stock UKI → remove overlay → reboot. That's also the general
escape hatch for any future early-KMS experiments.

## xe driver note

`8086:7d55` is present in `xe`'s alias table and `xe` loads on this machine —
but i915 owns Meteor Lake by default policy. Forcing `xe` changes the whole
display path (with its own DSC behavior); not chased since the machine is a
daily driver and i915 is correct for everything else.
