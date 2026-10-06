# Fingerprint: FPC 10a5:a900, fully working

The reader is a Fast Devices (FPC) sensor inside the power button,
USB ID `10a5:a900`, firmware `22.26.2.43`. libfprint upstream does not know
it; `cityji/honor-magickbookpro-fingerprint-driver` does (libfprint 1.94.6 +
MR396 + board patches). This machine is that driver's second confirmed
FW-`22.26.2.43` data point (cityji issue #1).

## Install shape

- Driver built into `/opt/fpc-a900/` (out of tree, no distro package).
- `fprintd.service` drop-in adds `LD_LIBRARY_PATH=/opt/fpc-a900/lib` so
  fprintd finds the patched libfprint.
- Enroll once with `fprintd-enroll`; verify with `fprintd-verify`.
- Polkit rule (template in `system/polkit/40-fingerprint.rules.template`):
  named user, group `wheel`.

## PAM wiring

`/etc/pam.d/sudo` and `/etc/pam.d/polkit-1`:

    auth        sufficient  pam_exec.so /usr/local/bin/omarchy-hw-laptop-closed ...
    auth        sufficient  pam_fprintd.so

The `pam_exec` gate **skips** fingerprint auth when the lid is closed (clamshell
docking: external screen, lid shut, reader unreachable). Falls through to
password in that state. `/etc/pam.d/omarchy-lock-fingerprint` drives the
Hyprland lock screen.

**Password fallback stays first-class in every stack** — `sufficient`, never
`required`: any fingerprint failure (wet finger, docked, driver dead after
kernel update) degrades to password prompt, never lockout.

## Costs & gotchas

- Rebuild pain: none — the driver is user-space, kernel updates don't touch it.
  But it pins `libfprint`/`fprintd` versions: a distro fprintd upgrade that
  changes the library soname will silently bypass the drop-in. Check with
  `ls -l /proc/$(pidof fprintd)/fd | grep fpc-a900` after fprintd package updates.
- The sensor is ~0.5 s per auth (enroll ~12 presses). Reader works reliably
  at normal press pressure; very light touches fail.
