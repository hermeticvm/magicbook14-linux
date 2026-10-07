# MagicBook Art 14 Linux — 0 to 100

Everything from one machine, one weekend: a used **HONOR MagicBook Art 14 2024**
(MRA-XXX, board M1010, Core Ultra 5 125H, 32 GB, 1 TB, 3120×2080 OLED)
brought from a blank Omarchy (Arch + Hyprland) install to a fully working,
fully understood daily driver.

## The machine

| | |
|---|---|
| Model | HONOR MagicBook Art 14 2024, DMI `MRA-XXX`, board `M1010`, SKU `C233` |
| CPU / iGPU | Core Ultra 5 125H (Meteor Lake) / Intel Arc, `8086:7d55` on `i915` |
| Display | EDO OLED 3120×2080 3:2 120/60 Hz, touchscreen, rounded corners |
| Audio | Realtek ALC256 (`10ec:0256`, codec SSID `1ee7:2060`), 6 drivers, 3 amp channels |
| Fingerprint | FPC `10a5:a900` in the power button |
| Camera | Detachable magnetic FHD Camera, `3277:00a8`, USB port `3-4` |
| Battery | 62.5 Wh design / 56.2 Wh full (89.9% health at 128 cycles) |
| BIOS | 3.05 (2025-03-07) — latest HONOR offers |

## Status: everything works

| Feature | State | Where |
|---|---|---|
| 6-speaker audio + bass profile | ✅ working, measured | [audio doc](docs/audio.md) |
| Fingerprint (login, sudo, polkit, lock screen) | ✅ working | [fingerprint doc](docs/fingerprint.md) |
| Fn hotkeys incl. keyboard backlight | ✅ working | [hotkeys doc](docs/hotkeys.md) |
| Webcam hot-plug notifications | ✅ working | udev rule in `system/udev/` |
| Power/charging behavior | ✅ measured + tuned | [power doc](docs/power.md) |
| Display 10-bit over DSC | ✅ 10 bpc via runtime force, no kernel patch | [display doc](docs/display.md) |
| HDR10 per-content (OLED 1600 nits) | ✅ fullscreen-only: `mpv-hdr` + auto-flip for tagged apps | [display doc](docs/display.md) |
| Session restore, gestures, rounded-corner UI | ✅ | `user/hypr/`, `user/omarchy/` |
| Battery widget: rolling-average estimate + session graphs | ✅ `user/omarchy/plugins/dh.power` | [desktop-ux doc](docs/desktop-ux.md) |

## Layout

```
docs/       what was learned, with measurements and links
system/     root-owned files: hooks, udev rules, units, rebuild scripts
user/       home-directory config: Hyprland, Omarchy shell, EasyEffects
tools/      speaker measurement suite (play/record/FFT ladder)
```

## The three companion projects this machine depends on

- [`rs0x29a/Linux-on-HONOR-…-M1010`](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010) — fix repo where this board was
  verified ([PR #15](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/pull/15),
  [hardware dump #16](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010/issues/16)).
  Source of the keymap patch and the audio SSID quirk.
- [`cityji/honor-magickbookpro-fingerprint-driver`](https://github.com/cityji/honor-magickbookpro-fingerprint-driver) —
  the fingerprint driver; first FW-`22.26.2.43` data point
  ([issue #1](https://github.com/cityji/honor-magickbookpro-fingerprint-driver/issues/1)).
- HONOR's own driver portal ([downloads page](https://www.honor.com/my/support/downloads/),
  model "HONOR MagicBook Art 14 (MRA-561)") — source of the Windows audio package
  that explained the speaker system (see the audio doc).

## Install

This is a snapshot, not an installer: files are where they live on the machine,
paths intact. To reuse a piece, read its doc first — several items
(PAM wiring, the module overlay) have order-of-operations and safety notes.
`system/` maps to `/`, `user/` maps to `$HOME`.

Boot-path items (kernel modules, UKI) are **not** shipped here — they are built
from source by `system/bin/honor-modules-rebuild.sh` (runs automatically via
the pacman hook on every `linux-omarchy` update).

## Honest failure log

Things that were tried and did not work, kept because they cost real time:

1. **eDP DSC patch on i915/Meteor Lake** — the prefer-DSC patch black-screens
   at early KMS on this board (works on the ZQC-P's Panther Lake/`xe`),
   documented upstream. The goal it chased — 10 bpc on a link that can't
   carry it uncompressed — was instead achieved with zero kernel changes:
   `bitdepth=10` monitor rule + a boot unit writing i915's runtime debugfs
   force flags. The *patch* stays on the do-not-apply list; see the
   [display doc](docs/display.md) for the working stack.
2. **cgroup-freezer app freezing on blur** — worked perfectly, but Electron's
   hang watchdog shows "unresponsive" dialogs; reverted.
3. **The subwoofer** — does not exist. Six drivers, three channels, all pairs
   acoustically identical in the 40–200 Hz band. The Windows "subwoofer" is
   Awinic SKTune DSP software. Reproduced on Linux with EasyEffects instead.
4. **Battery EC preset pairs from the ZQC-P** — our EC maps charge state to
   different offsets; the limit reads back but the EC ignores it.

5. **Hyprland auto-HDR with mpv** — `render:cm_auto_hdr` keys on apps that
   tag their surfaces via the Wayland CM protocol. mpv's
   `--target-colorspace-hint` doesn't tag (verified: sRGB window during PQ
   playback), so the auto-flip never triggers for it. gamescope-tagged games
   should still auto-flip; mpv gets the `mpv-hdr` wrapper, which flips
   explicitly and restores on exit.

## License

Personal configuration and documentation; no warranty. Scripts borrowed from
the companion projects keep their upstream licenses.
