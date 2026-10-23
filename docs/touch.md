# Touchscreen: FocalTech FTSC1000, and the phantom microphone mute

| | |
|---|---|
| Part | FocalTech **FTSC1000**, ACPI `FTSC1000:00`, I²C HID `2808:5662` |
| Bus | i2c-designware `i2c-0` on `0000:00:15.0`, interrupt 169 (intel-gpio) |
| Driver | `hid-multitouch`, class `MT_CLS_WIN_8`, 5 contacts, Type B |
| Ranges | X 0–3120, Y 0–2080 - the panel's native pixels, no calibration to do |

Touch maps to `eDP-1` at transform 0 through plain libinput, and the ranges
already match the 3120×2080 panel one to one, so there is nothing to configure
on the compositor side: Hyprland 0.56 has no touchscreen variables at all
(`input:touchdevice` and friends do not exist in the Lua era, `hyprctl devices`
lists the touch device under `touch`, and `gestures:` are touchpad-only).
The `ftsc1000` UNKNOWN node below was the only thing this screen exported
that needed fixing.

## The phantom KEY_MICMUTE device

The report descriptor ends with a vendor-defined collection (measured here,
`od /sys/.../0018:2808:5662.0001/report_descriptor`):

```
Usage Page (0xff01)
Usage (0x01)
Collection (Application)
    Report ID (0x10)
    Report Size (8)
    Report Count (12)        12 bytes of raw data
    Usage (0x01)
    Input (Data,Var,Abs)
End Collection
```

Usage page `0xff01` is `HID_UP_HPVENDOR2` in `include/linux/hid.h`, the page HP
uses for hotkey buttons. `drivers/hid/hid-input.c` maps it with no vendor check:

```c
	case HID_UP_HPVENDOR2:
		set_bit(EV_REP, input->evbit);
		switch (usage->hid & HID_USAGE) {
		case 0x001: map_key_clear(KEY_MICMUTE);		break;
```

Three things compound from there:

| Step | Effect |
|---|---|
| Device matches `MT_CLS_WIN_8`, which sets `export_all_inputs` | `hid-multitouch` does not filter the collection out |
| `HID_QUIRK_INPUT_PER_APP` | the collection gets its own input device, `FTSC1000:00 2808:5662 UNKNOWN`, whose only key is `KEY_MICMUTE` |
| All 12 bytes carry the same usage, 8 bits wide, and the same code path sets `EV_REP` | any non-zero byte is a key press, and one report leaves the key held down and auto-repeating |

Measured on this machine:

```
$ grep -B1 -A4 UNKNOWN /proc/bus/input/devices
N: Name="FTSC1000:00 2808:5662 UNKNOWN"
H: Handlers=kbd event6
B: EV=100013          EV_SYN + EV_KEY + EV_MSC + EV_REP
B: KEY=100000000000000 0 0 0     bit 248 only = KEY_MICMUTE
```

and Omarchy consumes it:
`/usr/share/omarchy/default/hypr/bindings/media.lua` binds
`XF86AudioMicMute` → `omarchy-audio-input-mute`, so every press/release edge
of the phantom key toggles the real microphone and pops the OSD.

## Measured here vs the sibling board

The sibling
[`rs0x29a/…ZQC-P_M1010`](https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010),
`patch/micmute/`, measured the same chip (59-byte variant of the same
collection) **streaming at idle: 29 `KEY_MICMUTE` autorepeat events per
second**, 8.5 h into an uptime, with nobody touching the machine - the
microphone mutes and unmutes on its own there.

This unit does not stream: 341 interrupts on IRQ 169 across five days of
uptime, zero in a 20 s idle window. The vendor report rides along with touch
activity here, so the phantom mutes would land while the screen is being used.
The edge has not been caught in the act locally (the event node is root-only),
and the fix does not need it to be: the descriptor above is the same
declaration the sibling measured firing, and the fixup is inert when no vendor
report arrives.

## Fix: HID-BPF report-descriptor fixup

`/usr/local/src/honor-ftsc1000-micmute.bpf.c` (repo `system/src/`) walks the
report descriptor before the kernel parses it and applies one rule:

> A hotkey is either a single bit of a button bitmap or an entry of a usage
> array, never a multi-bit variable data field.

That is the same test `hid-input` uses in its own `unknown:` fallback. Where a
wide variable field is found on page `0xff01`, the usage page item is rewritten
`0xff01 → 0xff00` (`HID_UP_MSVENDOR`), which `hid-input` ignores outright, so
no input node is created for the collection. The digitizer collections carry
their own usage pages and are untouched.

Build, install and apply:

```sh
sudo /usr/local/bin/honor-hid-bpf-rebuild.sh        # deps, build, install, apply now
```

which installs:

```
/etc/udev-hid-bpf/honor-ftsc1000-micmute.bpf.o
/etc/udev/rules.d/99-hid-bpf-honor-ftsc1000-micmute.rules   (written by udev-hid-bpf)
/etc/systemd/system/honor-hid-bpf-reapply.service           (repo system/systemd/)
```

The udev rule matches `hid:b0018g0004v00002808p00005662` and attaches on
device add; the reapply service re-attaches once the device has settled
because the boot attach races the `hid-generic` → `hid-multitouch` handover
(the kernel only recomputes a BPF-fixed descriptor when the program is
registered on a device that has not been reprobed yet, and the handover sets
`HID_STAT_REPROBED` first). The service is a no-op when the attach won.

The object is CO-RE: kernel updates need no rebuild, so unlike
`system/bin/honor-modules-rebuild.sh` there is no pacman hook for this one.

### Verified after installing

| Check | Result |
|---|---|
| `… UNKNOWN` input device | gone |
| Touchscreen `event5` (multitouch + `BTN_TOUCH`) | works |
| `KEY_MICMUTE` events from HID | none |
| Real Fn+F7 (WMI `0x287` → keycode 248, `huawei-wmi`) | unaffected |

## Ruled out

| Approach | Why it fails |
|---|---|
| udev hwdb `KEYBOARD_KEY_ff010001=reserved` | `hidinput_setkeycode()` remaps only the first usage matching the scancode, then re-sets the capability bit because the other 11 still map to 248. Tested live on the sibling, no change |
| `LIBINPUT_IGNORE_DEVICE` udev rule | hides it from libinput consumers only; the kernel still creates the node, holds the key down and burns ~30 timer wakeups per second while a report streams |
| Rebuilt `hid-multitouch.ko` refusing vendor collections | works, wrong layer, and has to be rebuilt after every kernel update |
| Patching `hid-input.c` directly | the guard belongs in `hid.ko`, which `linux-omarchy` builds `CONFIG_HID=y` (built-in, verified), so it cannot be overlaid as a module; a full kernel rebuild per update for one if-statement is the wrong trade |

The upstream shape of this program is `drivers/hid/bpf/progs/` in mainline
(thirty vendor programs, none for HONOR); if it is ever submitted there, the
source note in `system/src/honor-ftsc1000-micmute.bpf.c` is the provenance.