# Hotkeys, backlight, webcam

## The 15-key map (huawei-wmi overlay)

Stock `huawei-wmi` knows none of this board's WMI codes; every Fn combination
was silent until the keymap overlay. Patch adds to the driver's keymap:

| WMI code | Key |
|---|---|
| `0x2b1`–`0x2b4` | keyboard backlight off/low/mid/high |
| `0x283` / `0x2a3` | touchpad disable/enable |
| `0x288` / `0x2e0` / `0x2e1` | camera off/on/privacy |
| `0x2a1` | performance mode |
| `0x2a7` | display refresh toggle |

`system/bin/honor-modules-rebuild.sh` builds `huawei-wmi.ko` +
`snd-hda-codec-alc269.ko` against the running kernel and drops them in
`/usr/lib/modules/$KVER/updates/`. Triggered by pacman hook
`95-honor-modules.hook` (deferred 60 s via systemd-run so it never races an
in-flight kernel install). Source tarball cached in `/var/tmp/honor-modules/`.

## hwdb: silencing atkbd noise

The FN-row also emits raw `0xf7` scancodes via atkbd on some presses —
`/etc/udev/hwdb.d/61-honor-keyboard.hwdb` (not shipped here; trivial):

    keyboard:dmi:bvnHONOR:*:svnHONOR:pnMRA-XXX:pvrM1010*
     KEYBOARD_KEY_f7=unknown

## Webcam: magnetic, hot-pluggable, notifying

The FHD camera is a detachable magnetic puck (USB `3277:00a8`, fixed port
`3-4`). `system/udev/95-magicbook-webcam.rules` fires on add/remove →
`system/bin/magicbook-webcam-notify` → desktop notification. Verified
single-fire per plug event.

No driver needed — uvcvideo handles it; the rule exists purely for UX
(attached/detached feedback).
