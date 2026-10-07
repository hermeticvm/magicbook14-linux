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

## Battery widget (`user/omarchy/plugins/dh.power`)

Stock `omarchy.power` panel, cloned, then:

- "Time left" is a **10-min rolling average** of the discharge draw, not
  upower's instant `time-to-empty`. Real load swings 6–14 W on this
  machine, which used to bounce the estimate between ~3 h and ~8 h;
  only sustained load moves it now. The "Discharging" watts stay live.
- A 30 s background sampler keeps the average warm while the panel is
  closed; the open-panel refresh stays stock's 5 s. Sampler overhead is
  ~180 ms of CPU per 30 s — a few mW, not worth a second thought.
- "Screen on": accumulated screen-on time of the current discharge
  session, reset by charging. Screen counts as off for the omarchy
  screensaver window, a locked session, or all-monitors-DPMS-off;
  gaps >120 s (suspend) never count.
- "LAST 8H ON BATTERY": two graphs on one time axis — mean W and
  screen-on minutes per 5-min bucket, last 8 h of the discharge session.
- Histories live in `~/.local/state/dh.power/`: `rate.tsv` (10 min of
  draw, for the estimate) and `long.tsv` (48 h of
  `ts · W · state · screen_on`, feeds session stats + graphs). Honest
  limit: a charge that happens entirely while the shell is down can't
  split a session — the next *sampled* charge resets it.

## Display widget (`user/omarchy/plugins/dh.monitor`)

Stock panel, cloned, then:

- **REFRESH RATE pills** — SCALE-style toggle over the rates hyprctl
  reports at the current resolution (60/120 Hz here): click, or h/l and
  Enter; the live rate is filled.
- Applying a choice persists into `~/.config/hypr/monitors.lua`
  (`mode = "WxH@rate"`) and runs `hyprctl reload` — deliberately not a
  runtime-only eval: that file carries `bitdepth = 10`, the DisplayID
  cm/HDR overrides and scale, which a bare eval would silently drop
  (same rule as `edp-refresh`). Displays absent from monitors.lua fall
  back to runtime eval, session-only, like the scale pills.
- Interplay with the udev policy: `edp-refresh` wins on AC/battery
  events, the pill wins on click (and rewrites the file's default).

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
