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

### Do not leave `drm.debug=0x04` on (measured cost)

The 2026-10-07 flicker diagnosis needed KMS debug output
(`/usr/local/bin/honor-drm-debug` → `echo 04 > /sys/module/drm/parameters/debug`).
It got wired into the **deployed** `honor-edp-dsc.service` as a second
`ExecStart=` and stayed there. The repo's copy of that unit is clean — the line
is local drift, so re-installing `system/systemd/honor-edp-dsc.service` removes
it.

Cost measured 2026-10-17, 23 h uptime, `xe` bound:

| metric | `drm.debug=0x04` | `drm.debug=0` |
|---|---|---|
| journal lines/s | 5,629 — **5,622 xe/drm (99.9 %)** | **2–7** |
| journal growth | 140 kB/s ≈ **12 GB/day** | ~0 |
| journal on disk | 3.1 GB | 481 MB (after `--vacuum-size=500M`) |
| `nvme0n1` writes | 743 kB/s | 480 kB/s — remainder is the user's apps |
| DC6 power-well cycles | **~1,120/s** | **~1/s** (cursor blink) |
| `PkgWatt` | 2.74 W | **2.58 W** |
| `SysWatt` (PSys) | 5.89 W | **5.78 W** |
| `GFX%rc6` | 89.92 % | 94.34 % |
| battery idle, screen on | 9.7–10.1 W | 9.6–10.0 W (inside the noise) |

The messages are `drm_dbg_kms`-level — `[drm:skl_enable_dc6 [xe]]` is
DRM_DEBUG's own output format — so with `drm.debug=0` they cost nothing.
journald's `RateLimit*` will not help: kernel messages arrive via `/dev/kmsg`,
not the syslog socket, and are not rate-limited. The flag has to go.

Knock-on — **confirmed, and it was the logging**: re-enabling `drm.debug=0x04`
for 10 s after the fix produced **51** `Setting DC state` lines (~1.0 cycle/s,
cursor-blink driven) against 2,247 lines/s before. The ~1 kHz thrash was
therefore a *symptom* of the synchronous `printk` inside the DC6 power-well
handshake, not a driver defect — nothing to file upstream. The watts moved only
a little (`PkgWatt` −0.16 W, `SysWatt` −0.11 W, battery-side unchanged inside
the noise); the value of this fix is I/O, journal size and ~5.6k wakeups/s, not
runtime. Don't oversell it in the power doc.

Fix:

```sh
sudo sed -i '/honor-drm-debug/d' /etc/systemd/system/honor-edp-dsc.service
sudo systemctl daemon-reload
echo 0 | sudo tee /sys/module/drm/parameters/debug
sudo journalctl --vacuum-size=500M     # the 3.1 GB backlog is mostly this
```

Keep `/usr/local/bin/honor-drm-debug` on disk — it is the right tool when a
display problem genuinely needs KMS traces. Just never wire it into a boot
unit, and remember it is per-boot state (`/proc/cmdline` has no `drm.debug`).

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

## External displays over USB-C: cold-boot yes, hotplug no (EC mux policy)

Chassis: two USB-C ports, both Type-C-subsystem backed (`00:07.0` root port,
`00:0d.0` TB xHCI + `00:0d.3` DMA1; host router `Gen14`, USB4), i915 TC
PHYs (TC#2/TC#3, tbt-alt, 4 lanes). Tested with a 32" 6K display (Kuycon
G32P, TB4-class) and a 10 Gbps SSD, same ports, same cables:

| Test | Result |
|---|---|
| SSD, runtime hotplug | **10 Gbps SuperSpeed** on the TB xHCI — SS lanes fine |
| Display, runtime hotplug (both ports) | 480 Mbps USB2 only; mux never flips to DP; no HPD |
| Display, **connected at power-on** | **DP-3 connected, native 6144×3456@60** over DP-alt |
| TB4 display on a MacBook | 6K works — display side healthy |

**Cold boot works**: HONOR's EC arms DP-alt mode (mux → 4 DP lanes +
USB2 sideband, pin assignment D) during POST, and Linux inherits an
already-negotiated link — HPD asserted, DP-3 connected, native 6K@60 at
8 bpc over HBR3 (1344.65 MHz × 24 bpp = 32.3 Gbps vs 32.4 budget — a
0.3% fit; 10 bpc would need DSC, stock policy won't). The monitor's USB
hub stays at USB2 speeds even in this state — 4-lane DP leaves only the
sideband; no USB4 tunneling ever establishes (no partner on domain0).

**Hotplug doesn't**: at runtime attach, DP-alt entry needs a PD
`Enter Mode` host command, and this machine exposes no path to issue one
(`INTC1043` UCSI absent, `/sys/class/typec` never exists, HONOR EC
dialect-locks the PD controller behind its `TbtTypeC` SSDT). USB3 data
works at hotplug because SS training is PHY-autonomous (SSD proof);
the mux just stays in USB orientation forever. Not an i915 bug — the
fix lives in EC firmware (UCSI) or EC RE, not in any kernel patch.

Practical rule: **attach the 6K before power-on; don't hotplug it.**
Runtime unplug/replug parks DP-3 until the next cold boot. (Untested:
whether suspend/resume re-runs the EC arm routine — if yes, suspend
becomes the hotplug workaround. Worth one test.)

### Why the monitor charges the laptop (documented, not bizarre)

The G32P delivers **up to 100 W upstream PD** through its USB-C input —
a documented feature. Power contracts are sink-autonomous PD messages
(every charger proves it); only alt-mode entry is host-issued. Hence the
port's split personality: charger ✓, USB2 hub ✓, USB3 ✓ (SSD), USB4/DP
✗ at hotplug, DP ✓ at cold boot.

### HDMI path (fallback, and FRL backport verdict)

The display also takes HDMI 2.1. On 7.2.5 i915 that path is TMDS-class:
4K@60, 8 bpc, no 6K (1371 MHz pixel clock vs 600 MHz TMDS cap). Intel's
"Enable HDMI FRL for MTL+" 44-patch series (Aug 2026, LWN 1087803) would
lift this — **but it's moot now**: native 6K over USB-C cold-boot covers
the need, the series doesn't touch the hotplug/mux gap (EC-side), and a
WIP 44-patch backport buys only a redundant HDMI backup path at real
boot risk. Verdict: **skip; it arrives free if/when merged upstream.**
The HDMI rule stays in `monitors.lua` as the plain-display fallback.

### hyprmoncfg: unmanaged (its poll re-application fights the power policy)

`hyprmoncfgd` (user service) generates `~/.config/hypr/hyprmoncfg-monitors.lua`,
patches `hyprland.lua` to load it **last**, and runs an "automatic
reconciliation" every ~70 s that **re-applies its saved profile**. That
profile is a snapshot of capture time — on a battery boot it captures
60 Hz, and then stomps every runtime change back to 60 Hz once a minute,
including the edp-refresh AC policy (120 on power). Symptoms it produced:
flicker every reconciliation cycle, and AC plug-in flipping to 120 and
being dragged back within a minute. Two modes cannot share one output.

Fix: the tool's own `hyprmoncfg unmanage` — stops the switching and removes
its include, so `monitors.lua` + `edp-refresh` own everything again;
`systemctl --user disable --now hyprmoncfgd.service` keeps it from
re-arming at login. Profiles stay saved on disk; `hyprmoncfg manage`
restores it (and the conflict — don't re-manage while edp-refresh runs,
or re-save the profile at the target refresh first).

`edp-refresh` hardened to match: skips the rule eval when the current
mode already equals the target (power_supply udev events fire often —
battery capacity polls — and each needless eval is a needless modeset),
and logs to the journal (`logger -t edp-refresh`) because udev RUN
output is otherwise discarded. Verified: 60→120 on AC, second run skips,
both logged.

### Chassis EMI note (keyboard)

While the 6K was connected, the internal PS/2 keyboard (i8042/atkbd — not
USB, no shared data path) showed doubled and dropped keys. Unplug → clean,
replug → jank, A/B verified; an SSD on the same port → no jank. This board
already needed an atkbd phantom-scancode hwdb patch on day one — its
keyboard lines are noise-sensitive. With a TB4 display + PSU + cable into
the chassis: break the ground/EMI path (monitor PSU on a different outlet,
ferrite on the cable, or a powered hub in between) and the jank goes.
Not a Linux bug; electrical.

## Panel self-refresh: PSR1 on, and it is the ceiling (2026-10-17)

`sudo cat /sys/kernel/debug/dri/0000:00:02.0/i915_edp_psr_status` — the file
keeps its `i915_` name because it belongs to the shared Intel display code, not
to the `i915` driver (see the driver note at the end):

```
Sink support: PSR = yes [0x03], Panel Replay = no, Panel Replay Selective Update = no, Panel Replay DSC support = not supported
PSR mode: PSR1 enabled
Source PSR/PanelReplay ctl: enabled [0x81f006e6]
Source PSR/PanelReplay status: IDLE [0x04010003]
Busy frontbuffer bits: 0x00000000
Performance counter: 5
```

and at every modeset, the crtc state dump:
`psr: enabled, selective update: disabled, panel replay: disabled, selective fetch: disabled`.

Read together, the position is unambiguous: **PSR1 is on** — the base panel
self-refresh, which is most of the win — and the deeper states are ruled out by
the *sink*, not by us. This panel declares no Panel Replay, no Panel Replay
Selective Update and no Panel Replay DSC at all, so no module parameter,
debugfs knob or kernel patch can conjure them. The live confirmation, from
`turbostat` at idle with the panel running: 90 % GPU RC6 residency (power doc).

The `xe` parameters are all at driver default, so none of this is a config we
disabled:

| parameter | value |
|---|---|
| `enable_psr` | `-1` (auto → enabled) |
| `enable_psr2_sel_fetch` | `Y` |
| `enable_panel_replay` | `-1` (auto) |
| `enable_dc`, `enable_fbc` | `-1` (auto) |
| `enable_sagv` | `Y` |

Note `enable_psr2_sel_fetch = Y` while the crtc state says
`selective fetch: disabled`: the driver declining a sink that can't take it,
not a setting we got wrong. Escape hatch if it ever needs forcing for an
experiment: `i915_edp_psr_debug` (0644, currently `0`).

## xe driver note

`8086:7d55` is present in `xe`'s alias table, and **`xe` is the driver actually
bound to this machine's iGPU**, forced by the kernel command line
(`i915.force_probe=!7d55 xe.force_probe=7d55`): `/sys/class/drm/card0/device/driver`
→ `/sys/bus/pci/drivers/xe`, with zero devices under `i915`. Upstream's default
policy would give Meteor Lake to i915, but that is not what runs here.

This is worth stating explicitly because it is easy to misread: the `i915_*`
debugfs names used throughout this doc (the DSC knobs, `i915_edp_psr_status`)
come from the **shared Intel display code**, which kept its `i915_` prefix when
`xe` took over the display side. They are not evidence about which driver is
bound — check the symlink above.

Not chased: whether i915 would serve this panel better, since the runtime DSC
stack makes the question moot for this machine.
