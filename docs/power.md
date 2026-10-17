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

NOTE: The table above was measured before DSC was enabled (display doc);
the DSC engine's idle cost at 60 Hz is not yet re-measured — expect a
small addition, re-run the idle ladder when convenient.

Ladder reconciliation (2026-10-17): a mid-session idle window on the 61 %
pack measured **5.72 W** on the battery counter — consistent with the 5.3 W
screensaver floor, *not* with a screen-on idle. The window's display state
was not captured, so read it as a cross-check on the floor rather than a new
row. The meter-based rows above stand; see "Instrument caveat" below before
trusting any battery-counter figure.

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
  `drm.debug=0x04` — never leave that flag on; its measured cost is in
  display.md). monitors.lua now computes the mode from ADP1 at load
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
  mild CPU effect. Not worth automation here. The CPU half of that is now
  quantified under "CPU power envelope" below — saver is the energy-optimal
  end of the trade, and it is already the daily state.
- `99-omarchy-audio-powersave.conf` (`system/modprobe/`): HDA codec power-save
  timeout — free, silent on this board (no hiss).

## CPU power envelope: measured — nothing left to take (2026-10-16)

4 P + 8 E + 2 LP-E cores (LP-E = CPUs 16–17, 2.5 GHz ceiling). Method: fixed
workloads at pinned affinities, battery counter cross-checked against sampled
`current_now`; **relative comparisons only** — see the instrument caveat below.

| knob | value | on battery |
|---|---|---|
| PL1 / PL2 / peak | 41 / 43 / 83 W | **never binding** — peak system draw measured 26.7 W (power-saver), 35.6 W (balanced) |
| `energy_performance_preference` | `power` (power-saver) | P-cores cap at **~2.5 GHz** against a 4.5 GHz capability — three runs, p95 = 2500 MHz |
| same, `balance_power` (balanced) | | 4.58 GHz single-thread, 3.70 GHz p95 all-core |
| `no_turbo` / `max_perf_pct` | 0 / 100 | turbo is *available* and simply not chosen |

Energy per unit of work (identical loop, nJ per iteration):

| profile | 1 thread | 18 threads |
|---|---|---|
| power-saver | 27.5 | 7.19–8.08 |
| balanced | 29.1 | 8.60 |
| performance | 31.9 | 9.04 |

What follows from that:

- **Do not add a PL1/PL2 cap hook on battery.** 41 W is an AC-side number; the
  battery path never lets the CPU near it, so such a cap would be a no-op. A
  PL1/PL2 cap on battery is the obvious-looking suggestion and it looks free —
  this is the measurement that says it isn't: the envelope is already capped by
  the platform, well below the value you'd be writing.
- **Do not disable turbo.** `EPP=power` already does it in effect, on a
  hardware capability of 4.5 GHz.
- **Power-saver is the energy-optimal profile** — 6 % better per unit of work
  single-thread, ~15 % all-core — and it charges 44 % single-thread throughput
  for that. The trade is already in force; nothing to automate.
- **Parallelism beats clock.** The same work costs 30.4 nJ/unit run serially
  versus 7.2 nJ/unit at 18-way, because the ~6 W floor is paid either way.
  Throttling *down* to save energy is the wrong direction on this machine.

## Undervolting: unavailable — and it is firmware, not the kernel (2026-10-17)

The one lever that would cut power at *unchanged* frequency, and it is closed.
Two gates, only one of them real:

1. **Kernel `msr` driver — not the blocker.** `filter_write()` in
   `arch/x86/kernel/msr.c` permits writes in the default mode and merely warns
   and taints (`CPU_OUT_OF_SPEC`); `msr.allow_writes=on` silences it. Secure
   Boot is off and lockdown is `none`, so `LOCKDOWN_MSR` is out of the picture.
2. **Intel Undervolt Protection / CFG Lock — the wall.** The offset interface
   (MSR `0x150`, OC mailbox) *is* present on Meteor Lake — UnderVolter ships a
   `6,170,*` profile for it — but writes are gated behind a hidden firmware
   variable and HONOR BIOS 3.05 exposes no toggle. Non-HX mobile parts have
   been reported locked this way since 12th gen, with MSI and ASUS documenting
   the same gate on their own boards.

The two-minute test, **not yet run on this board** — the conclusion above is
from the documented behaviour of the gate, not a local measurement:

```sh
sudo pacman -S --needed intel-undervolt msr-tools
printf 'undervolt 0 "CPU" -50\nundervolt 1 "GPU" -50\nundervolt 2 "CPU Cache" -50\n' \
  | sudo tee /etc/intel-undervolt.conf
sudo intel-undervolt apply     # dmesg "Write to unrecognized MSR 0x150 ..." is expected and harmless
sudo intel-undervolt read      # 0.00 mV everywhere ⇒ firmware dropped the write
```

Deliberately not attempted: the pre-boot route (UnderVolter / OC-mailbox writes,
plus patching the hidden CFG-Lock variable in NVRAM). It needs NVRAM byte
patching and a modified Secure Boot chain to buy a few watts. Not worth it here.

## Idle budget, layer by layer (`turbostat`, 2026-10-17)

`sudo turbostat sleep 10`, 60 Hz, screen on, `EPP=power`, 1.58 % CPU busy:

| counter | value |
|---|---|
| `PkgWatt` — CPU package | **2.74 W** |
| `CorWatt` / `GFXWatt` | 0.70 / 0.17 W |
| `C10%` — cores | 91.46 % |
| `GFX%rc6` — GPU | 89.92 % |
| `SAM%mc6` — memory controller | 99.52 % |
| `Pkg%pc10` | 6.31 % |
| `SYS%LPI` | 0.00 % |
| `SysWatt` — PSys, whole platform | 5.89 W |

`Pkg%pc10 ≈ 6 %` together with `SYS%LPI = 0` is **expected, not a fault**:
package C10 and S0ix both require the display pipeline to be idle, and a 3K
panel at 60 Hz never lets that happen. Cores, GPU and memory controller reach
their deep states regardless. The SoC is at its floor.

Conditions: taken with `drm.debug=0x04` still left on from the display flicker
diagnosis (display doc) — the driver was printing ~5.6k KMS lines/s and cycling
DC6 ~1.1k times/s at the time. Re-measured after removing it: `PkgWatt` 2.74 →
**2.58 W**, `SysWatt` 5.89 → **5.78 W**, `GFX%rc6` 89.92 → 94.34 %, and the
battery-side screen-on idle 9.7–10.1 → **9.6–10.0 W** (inside the noise). The
thrash was itself an artifact of the debug logging, so the corrected floor is
**~2.6 W package** — the fix was worth taking for I/O and wakeups, not watts.

The battery-side screen-on figure for the same conditions was 9.7–10.1 W.
Against PSys (5.89 W) that leaves ~4 W for panel + display engine + storage +
VRM losses — not software-addressable. **Screen-on idle runtime on this 56 Wh
pack is therefore ~5.5–6 h.** (That 9.7–10.1 W window sat inside the gauge's
unreliable regime; PSys is the trustworthy half. Re-measure with the meter when
convenient and replace this paragraph with a meter number.)

## Instrument caveat: the battery gauge lies above ~95 % SoC (2026-10-17)

Recorded because it produced two wrong conclusions in a single session. With
the pack at 100 %:

- `charge_now` **froze at 0** — zero µAh moved over 20 s at a reported 1.26 A.
- It then **over-reported 2×** against sampled `current_now` (2358 vs 1220 mA),
  recovered to agreement for one phase, and passed the gate again at 97 %.
- At 70 % SoC the same two estimators agreed to 2.6 %.

Rule: never take an absolute watt figure from `charge_now`/`current_now` above
~95 % SoC. Require the two estimators to agree within 20 % before believing a
phase, and prefer `turbostat` (package/PSys) or the USB-C meter for absolutes.
`charge_now` quantises at 1 mAh, so a 45 s window is ±10 % at best regardless.

## Battery charge limit: enforced, presets only

This board's EC **does** hold a charge ceiling, and it holds only for the
three pairs HONOR PC Manager offers — `40 70`, `70 90`, `95 100`. Any other
pair (upstream hwdb's catch-all `75 80`, a `60 80` of your own) is echoed
back through `/sys/devices/platform/huawei-wmi/charge_control_thresholds` and
silently ignored by the EC: sysfs reads back what you asked for and the pack
charges to 100% anyway.

The live pair on MRA-XXX is at EC RAM **0xE4/0xE5**, with the mode at
**0xE6**: reading `0x46 0x5A 0x02` = `70 90` = mode 2 = "Office 70–90 %" in
PC Manager. The pair is written through the mailbox `ECCC(0x82, start, stop)`
and the EC derives the mode from the **start byte alone** (40→1, 70→2, 95→3,
anything else→0 = unarmed). The ZQC-P offsets `0x80/0x81/0x85` that the
sibling repo documents are **battery telemetry here**, which is what made
this look like a negative result the first time round — resolved by live EC
reads on 2026-10-08, in `honor-m1010-linux`
`docs/hardware/mra-xxx-power.md`.

Measured behaviour, not inference: AC has been in since 2026-10-14 15:48 and
the pack has sat at 90 % with `status` reading `Not charging` the whole time —
every row of dh.power's 48 h state history is in the charging family, no
discharge, no excursion above the ceiling.

Operate it with `honor-charge-limit` (`system/bin/`, install to
`/usr/local/bin/`), and from the battery widget's **CHARGE LIMIT** button
(see [desktop-ux.md](desktop-ux.md)):

```sh
honor-charge-limit status    # the pair the EC holds, and its mode
honor-charge-limit full      # 95 100 — charges to 100 %
honor-charge-limit limit     # 70 90  — the everyday ceiling
```

It is a *charging* limit: with the ceiling restored while the pack sits above
it, the EC simply stops topping up and the level stays put until it falls
below the floor on its own.

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
