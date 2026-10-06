# Desktop UX: notifications, session shape, quality of life

Omarchy's shell (Quickshell) is configured under `~/.config/omarchy/`; Hyprland
under `~/.config/hypr/`. This repo keeps the full deltas in `user/`.

## Notification pills (`user/omarchy/plugins/dh.notifications`)

Cloned from Omarchy's stock plugin, then:

- 20 s duration, all urgencies (stock: shorter for low).
- Countdown **pauses while the session is locked** (polls
  `omarchy-shell lock isLocked`); no more "you had 3 notifications while
  you were away, they all just vanished".
- Pills stack in a horizontal-center column, corner radius = half height.
- `shell.json` keeps the plugin registered with stock plugins disabled
  (so omarchy updates don't double-render notifications).

## Session restore (`user/hypr/windows.lua` + `autostart.lua`)

True pixel-perfect window restore isn't a thing in a tiling WM (state is
layout, not geometry) — accepted consciously. Instead:

- Per-app home workspaces: brave → 1, ghostty/foot/obsidian → 2,
  Proton Pass → 3, brave-discord → 5 (with `persistent_size`).
- Autostart on login: browser, terminal, obsidian.
- Result: after reboot the workspace map and the app set are back; window
  arrangement within workspaces is manual, by design.

## Session lock + fingerprint

`omarchy-lock-fingerprint` PAM stack (see fingerprint doc) — fingerprint
unlocks the lock screen; password always available.

## Camera / privacy UX

Webcam plug/unplug notifications (hotkeys doc). The camera is a detachable
puck — when it's off the laptop, it's *off*, no tape needed.

## Autostart inventory (`user/autostart/`)

- `easyeffects-service.desktop` — headless `--service-mode` audio profile
  (see audio doc).

## Known trade-off, deliberately kept

`focus-freeze` (cgroup-freeze apps on blur to save idle power) worked and
measured well, but Electron apps (Brave, VS Code) pop "page unresponsive"
modals when unfrozen after a long freeze — Chromium's hang watchdog has no
"we were frozen, not hung" signal. Reverted; artifacts kept in
`user/local-bin/` + `user/systemd-user/` + `user/omarchy/focus-freeze.json`
for a future retry with per-app exclusions. Do not re-enable as-is.
