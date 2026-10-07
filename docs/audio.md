# Audio: six speakers, no subwoofer, one psychoacoustic profile

The machine is advertised with a "6-speaker system with subwoofer". Reality on
this board (codec SSID `1ee7:2060`, PCI audio `1ee7:2059`):

- Six drivers, three amp channels, all working under Linux — but the pin
  configuration in the stock `snd-hda-codec-alc269` leaves two pairs asleep.
- **No pair reproduces low bass better than any other.** Measured, repeatedly.
- The "subwoofer" in the Windows marketing is **software**: a psychoacoustic
  bass-synthesis APO stack (Awinic SKTune). There is no smart-amp IC.

## What was measured

Measurement instrument: speaker-ladder suite (`tools/`), plays calibrated
stimuli (−12 dBFS sine bursts 45 Hz–8 kHz + sweep + pink) and records on the
raw DMIC array (`arecord -D hw:0,6 -f S32_LE -c 4`, PipeWire's Mic route is
dead on this board), then FFTs per-stimulus band level.

Results (config D = all three pin pairs woken; dB at stimulus freq):

| Stimulus | Level | vs 1 kHz |
|---|---|---|
| 45 Hz | 18.5 dB | −47 |
| 60 Hz | 22.5 dB | −42.7 |
| 80 Hz | 29.8 dB | −35.4 |
| 120 Hz | 38.9 dB | −26.3 |
| 200 Hz | 49.3 dB | −15.9 |
| 500 Hz | 66.4 dB | +8.4 |
| 8 kHz | 70.3 dB | +12.3 |

Key comparisons (all within ±0.5 dB — no pair is a woofer):

- Pin 0x14 alone ≈ pin 0x1b alone ≈ all pairs, **every band**.
- Pin 0x1a alone: best 300–500 Hz, rolls off >2 kHz → mid/treble pair.
- Adding any "second pair" adds zero low-frequency output.

So: two mid/treble-tuned pairs and one pair identical to them. Roll-off
below 200 Hz is steep and physical — no routing or pin trick recovers it.

## The Windows reference (why no hardware bass exists)

The 492 MB HONOR "Audio" Windows package, unpacked:

- Awinic stack = **pure software**: `SWC\AWDZAPO` virtual device, AwinicSKTuneAPO
  PRE/POST/MEC audio-processors, 9 config `.bin`s — psychoacoustic bass
  synthesis + excursion protection. No Awinic silicon on any bus.
- DTS:X Ultra handles only HP/BT/USB routes (per-SSID SQLite tuning DB
  `dts_apo4_oem_offline_hptuning_1EE72060.db`).
- DSDT: Realtek `10EC1308` on `INT34C2` exists but the I2S-codec ACPI branches
  are status=0 (not present). No hidden amp.

## The Linux stack that matches it

1. **Kernel**: patched `snd-hda-codec-alc269` overlay quirk
   `SND_PCI_QUIRK(0x1ee7, 0x2060, "HONOR MRA-XXX M1010", ALC256_FIXUP_HONOR_MRB_XXX_M1020_AUDIO)`
   — wakes the sleeping pin pairs. Rebuilt automatically on kernel updates
   (`system/hooks/95-honor-modules.hook` → `system/bin/honor-modules-rebuild.sh`).
   Upstream in the M1010 fix repo (PR #15).
2. **EasyEffects** (`user/easyeffects/`): the psychoacoustic layer Windows ships,
   reproduced: **bass_enhancer** (LSP harmonic synth, amount 7, scope 120 Hz)
   → **10-band EQ** (+10 dB @64 Hz, +6 @125, +2 @250; −1/−1.5/−2 treble)
   → **limiter** (Herm Thin, −3 dB, 5 ms lookahead) → speakers.
   Profile `art14-bass`, auto-applied via autoload keyed to the
   `HiFi__Speaker__sink`/`Speaker` route; app runs headless via
   `--service-mode` from `user/autostart/`.

   **8.2.9 flag regression (found live):** `--service-mode` sets the
   service-mode config but never emits the hide-window signal, so the UI
   shows at every boot; the *deprecated* `--gapplication-service` does
   both (src/command_line_parser.cpp:97–104). Fix without touching
   deprecated flags: `noWindowAfterStarting=true` in the `[Window]` group
   of `~/.config/easyeffects/db/easyeffectsrc` — "never show our window
   after initialization **when running in service mode**" (label of the
   kcfg key). Plain GUI launches are unaffected. Verified: service
   restart → zero EE windows, chain intact, preset reload via
   `easyeffects -l art14-bass`.

Measured effect of the profile (EQ-only round, same instrument): +4–6 dB
low-end lift at 60–200 Hz relative to 1 kHz, treble −1 dB, as designed.
Live-music capture with enhancer active shows 80–160 Hz energy tracking the
40–80 Hz band — the harmonic-synthesis signature.

## Capture path (the debugging breakthrough)

PipeWire's ALSA "Mic" route on this SOF stack records silence (route muted in
firmware topology). The raw SOF DMIC device works: `hw:0,6`, 4ch S32_LE,
average channels in post. The measurement suite does exactly this.

## What did NOT work

- Expecting pins 0x14/0x1a to be a woofer pair — refuted by measurement.
- Any idea that a different pin config could yield bass — three configs,
  one verdict.

The panel of "who has bass" is closed: **physics roll-off + synthesis** is
the only architecture this hardware supports. The profile is the answer.
