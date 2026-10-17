# MagicBook Art 14 Linux: 0 to 100

A used **HONOR MagicBook Art 14 2024** (DMI product `MRA-XXX`, board `M1010`,
Core Ultra 5 125H, 32 GB, 1 TB, 3120×2080 OLED panel), brought from a blank
Omarchy (Arch + Hyprland) install to a fully working daily driver.

Two weeks of intermittent tuning around real work, not a weekend sprint.

## The machine

| | |
|---|---|
| Model | HONOR MagicBook Art 14 2024, DMI `MRA-XXX`, board `M1010`, SKU `C233` |
| CPU / iGPU | Core Ultra 5 125H (Meteor Lake) / Intel Arc, `8086:7d55` on `xe` (forced via command line; recommended for this device class) |
| Display | EDO OLED (organic light-emitting diode) 3120×2080 3:2 120/60 Hz, touchscreen, rounded corners |
| Audio | Realtek ALC256 (`10ec:0256`, codec SSID `1ee7:2060`), 6 drivers, 3 amp channels, **no subwoofer** (see below) |
| Fingerprint | FPC `10a5:a900` in the power button |
| Camera | Detachable magnetic FHD Camera, `3277:00a8`, USB port `3-4` |
| Battery | 62.5 Wh design / 56.2 Wh full (89.9% health at 128 cycles) |
| BIOS | 3.05 (2025-03-07) - latest HONOR offers |

## Status: everything works

| Feature | State | Where |
|---|---|---|
| 6-speaker audio + bass profile, no physical subwoofer | ✅ working, measured | [audio doc](docs/audio.md) |
| Fingerprint (login, sudo, polkit, lock screen) | ✅ working | [fingerprint doc](docs/fingerprint.md) |
| Fn hotkeys incl. keyboard backlight | ✅ working | [hotkeys doc](docs/hotkeys.md) |
| Webcam hot-plug notifications | ✅ working | udev rule in `system/udev/` |
| Power/charging behavior | ✅ measured + tuned | [power doc](docs/power.md) |
| CPU power envelope: power limits (PL1/PL2), energy performance preference (EPP), turbo, undervolt | ✅ measured: PL1 never binds, `EPP=power` already optimal, undervolt firmware-locked | [power doc](docs/power.md) |
| Idle power budget (system-on-chip floor) | ✅ measured: 2.58 W package, 5.78 W platform, 94 % GPU RC6 residency | [power doc](docs/power.md) |
| Display 10-bit over DSC (Display Stream Compression) | ✅ 10 bpc via runtime force, no kernel patch | [display doc](docs/display.md) |
| HDR10 (high dynamic range) per content, 1600 nits | ✅ fullscreen-only: `mpv-hdr` + auto-flip for tagged apps | [display doc](docs/display.md) |
| Session restore, gestures, rounded-corner UI | ✅ | `user/hypr/`, `user/omarchy/` |
| Battery charge limit + "charge to full" button | ✅ enforced at 70–90 %, EC (embedded controller) arms its 3 presets only | [power doc](docs/power.md) |
| External 6K over USB-C | ✅ 6K@60 confirmed on one USB-C port (cold boot); hotplug still dead. HDMI falls back to 4K until HDMI 2.1 FRL lands | [display doc](docs/display.md) |

## Layout

```
docs/       what was learned, with measurements and links
system/     root-owned files: hooks, udev rules, units, rebuild scripts
user/       home-directory config: Hyprland, Omarchy shell, EasyEffects
tools/      speaker measurement suite (play/record/FFT ladder)
```

## The three companion projects this machine depends on

- [`rs0x29a/Linux-on-HONOR-…-M1010`](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010) - fix repo where this board was
  verified ([PR #15](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/pull/15),
  [hardware dump #16](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/16)).
  It covers the sibling HONOR MagicBook 14 Pro 2026 AI, board code `ZQC-P`;
  this machine is the Art 14 (`MRA-XXX`/`M1010`). Source of the keymap patch
  and the audio SSID quirk.
- [`cityji/honor-magickbookpro-fingerprint-driver`](https://github.com/cityji/honor-magickbookpro-fingerprint-driver) -
  the fingerprint driver; first FW-`22.26.2.43` data point
  ([issue #1](https://github.com/cityji/honor-magickbookpro-fingerprint-driver/issues/1)).
- HONOR's own driver portal ([downloads page](https://www.honor.com/my/support/downloads/),
  model "HONOR MagicBook Art 14 (MRA-561)") - source of the Windows audio package
  that explained the speaker system (see the audio doc).

## Install

This is a snapshot, not an installer: files are where they live on the machine,
paths intact. To reuse a piece, read its doc first - several items
(PAM wiring, the module overlay) have order-of-operations and safety notes.
`system/` maps to `/`, `user/` maps to `$HOME`.

Boot-path items (kernel modules, UKI) are **not** shipped here - they are built
from source by `system/bin/honor-modules-rebuild.sh` (runs automatically via
the pacman hook on every `linux-omarchy` update).

## Honest failure log

Things that were tried and did not work, kept because they cost real time:

1. **eDP DSC patch on i915/Meteor Lake** - the prefer-DSC patch black-screens
   at early KMS on this board (it works on the sibling Panther Lake board),
   documented upstream. This machine now runs the `xe` driver instead, which
   is the recommendation for this device class (see the display doc), so the
   i915 verdict is historical - but do not assume the patch is safe here. The
   goal it chased (10 bpc on a link that can't carry it uncompressed) was
   achieved with zero kernel changes: a `bitdepth=10` monitor rule plus a boot
   unit writing the driver's runtime debugfs force flags. See the
   [display doc](docs/display.md) for the working stack.

2. **The subwoofer** - does not exist. Reviews and the Windows marketing
   describe a "6-speaker system with subwoofer"; the hardware is six drivers
   on three amp channels, and all driver pairs are acoustically identical in
   the 40–200 Hz band. The bass on Windows is Awinic SKTune digital signal
   processor (DSP) software, not a driver, and the same effect is reproduced
   on Linux with EasyEffects.

3. **Battery charge-limit presets copied from the sibling board** - the
   offsets that board documents are battery telemetry here; this embedded
   controller (EC) maps charge state to different addresses, so the limit read
   back as written while the EC ignored it.

4. **Hyprland auto-HDR with mpv** - `render:cm_auto_hdr` keys on apps that
   tag their surfaces via the Wayland color-management protocol. mpv's
   `--target-colorspace-hint` doesn't tag (verified: sRGB window during PQ
   playback), so the auto-flip never triggers for it. gamescope-tagged games
   should still auto-flip; mpv gets the `mpv-hdr` wrapper, which flips
   explicitly and restores on exit.

5. **6K display hotplug over USB-C** - dead at runtime. Thunderbolt 4 (TB4)
   class displays wait for USB4 host negotiation, which needs host USB Power
   Delivery (PD) `Enter Mode` commands this machine can't issue: there is no
   USB Type-C Connector System Software Interface (UCSI) here, no
   `/sys/class/typec`, and the HONOR EC dialect-locks the mux. Cold boot with
   the display attached does work: 6K@60 is confirmed on one of the two ports,
   with the EC arming DisplayPort alternate mode (DP-alt) at POST and Linux
   inheriting the link. The hotplug half was measured in one session and not
   re-verified since the switch to `xe` - treat that half as a lead. Attach
   before power-on; don't hotplug. HDMI is not an alternative for 6K: it falls
   back to 4K until HDMI 2.1 FRL support lands.

## License

Personal configuration and documentation; no warranty. Scripts borrowed from
the companion projects keep their upstream licenses.
