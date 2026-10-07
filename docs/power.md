# Power: measured, not guessed

Battery: 62.5 Wh design, 56.2 Wh full — 89.9% health at 128 cycles (bought used).
All numbers from a USB-C power-meter unless noted; they're reproducible with
`upower` trend lines over a few minutes.

## States (tuned, 60 Hz, dark OLED, brightness 2–10%)

| State | Draw |
|---|---|
| Active heavy use (builds, browsing) | ~15 W |
| Idle, screen on, bright | ~8.6 W |
| Screensaver floor (lock+dim) | ~5.3 W |
| **Suspended, charging** | **46 W** ← odd one |
| Suspended, battery | (parked: not yet re-measured) |

NOTE: the table above was measured before DSC was enabled (display doc);
the DSC engine's idle cost at 60 Hz is not yet re-measured — expect a
small addition, re-run the idle ladder when convenient.

The 46 W suspended-while-charging is the EC topping up in bursts rather than
trickle; harmless but worth knowing when reading the meter.

## What made the difference (and what didn't)

- **Refresh policy: 60 Hz on battery, 120 Hz on AC** — the single biggest
  idle win on the OLED panel is 60 Hz (120 Hz idle is measurably worse;
  the panel stretches vblank, so both modes share one pixel clock and the
  120 Hz mode costs panel time, not link time). `user/local-bin/edp-refresh`
  applies it; triggered by `system/udev/96-honor-edp-refresh.rules` on
  power_supply events (`system/bin/honor-edp-refresh-udev` bridges to the
  session), at login (`user/autostart/honor-edp-refresh.desktop`), and by
  `user/systemd-user/edp-refresh.{service,timer}` — a 60 s
  reconciliation timer. The eval carries every monitor-rule field —
  bitdepth, cm overrides, luminances — because a mode-only eval would
  reset them. Verified live: AC → 120 Hz with DSC still engaged at 10 bpc,
  colorspace sRGB; udev chain end-to-end; timer fires and no-ops.
  Hardened: no-op when current mode already matches (power_supply events
  fire often — capacity polls — and each needless eval is a needless
  modeset/flicker), journal-logged (`logger -t edp-refresh`; udev RUN
  output is otherwise discarded).
  **Why the timer + dynamic config mode exist (both measured incidents):**
  a `@60` literal in monitors.lua made *every* config reload while on AC
  silently modeset 60 Hz (bar-plugin rate pills sed-write + reload → 64
  minutes at 60 Hz on AC, from the kernel modeset log at
  `drm.debug=0x04`). monitors.lua now computes the mode from ADP1 at load
  (io.open works in Hyprland's Lua env), so reloads are policy-correct;
  the timer heals any other actor (runtime evals) within 60 s.
  **Authority rule: nothing else may persist eDP mode changes** —
  `hyprmoncfgd` is unmanaged/disabled (its ~70 s poll re-application of a
  stale captured mode fought this policy; see the display doc); the bar
  plugin's rate pills fall back to runtime-only evals against the dynamic
  mode (their sed no longer matches) and are reverted by the timer within
  60 s — manual override is deliberately ephemeral.
- **Powertop runtime-PM tunables** (`system/systemd/omarchy-powertop-tune.service`
  + `system/tune-scripts/`): runtime PM on 10 PCI devices, NMI watchdog off,
  WiFi power-save. ~1 W at idle. Only tunables that are safe across suspend.
- **Power profiles** (performance/balanced/saver): **no measurable charging
  behavior change**; platform profile on this EC is cosmetic for charging,
  mild CPU effect. Not worth automation here.
- `99-omarchy-audio-powersave.conf` (`system/modprobe/`): HDA codec power-save
  timeout — free, silent on this board (no hiss).

## Battery limit: negative result

The ZQC-P's EC charge-limit (write `70 90` to its sysfs offset) **does not
arm on M1010**. Our EC exposes different offsets — the write reads back but
charging continues to 100%. Offsets are in the M1010 repo's EC notes; mapping
them properly is parked (DSDT/SMBus RE, low value: 90% health battery is
already aging slowly).

## Charge behaviors worth knowing

- Charges at ~55 W (USB-C PD 65 W brick) to ~80%, then tapers; full at ~2.1 h.
- No USB-C "slow charger" notification mismatch: the EC negotiates properly
  with non-HONOR PD bricks; any 65 W+ works, 30 W bricks it down politely.

## Sleep (s2idle): measured, clean

Firmware is s2idle-only (`/sys/power/mem_sleep`, no S3) — Modern Standby,
the mechanism that *can* drain badly, so it was measured rather than
trusted:

- `suspend_stats` 6/6 success, zero failed steps, zero journal errors at
  resume; freeze time 0.06–0.11 s every cycle.
- Overnight lid suspend (01:58→09:43) ran **on AC**: charged to the cap
  while asleep — no drain event to measure there.
- The on-battery sample: 48 min lid suspend, 89%→88% — **~0.15 W,
  ~0.3 %/h**. Broken modern-standby machines do 3–5 %/h; this is good.
- No spurious wake cycles across the 7¾ h overnight window (no logind
  suspend/resume pairs, no kernel PM entries until the lid opened).
- One cosmetic: lid-switch bounce at resume (7 open/close events in 7 s)
  is absorbed by logind's post-resume holdoff — never triggers a suspend.
