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

- **60 Hz on eDP** (`user/hypr/monitors.lua`): the single biggest idle win on
  the OLED panel — 120 Hz idle is measurably worse. User keeps 60 on battery;
  profile-switch on plug-in is available but not wired (deliberate: the
  OLED's 120 Hz mode is panel-clock-bound and visibly less efficient).
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
- Overnight suspend drain test and 5× suspend/resume cycle: still parked.
