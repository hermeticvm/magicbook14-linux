#!/usr/bin/env python3
"""Speaker characterization suite for the HONOR MagicBook Art 14 (M1010).

Measures what each speaker-pair configuration actually emits, using the
laptop's own DMIC array as the instrument. No ears required for the data
collection; ears are the final judge afterwards.

Usage:
  speaker-suite.py gen          - write test signals to /tmp/speaker-suite/
  speaker-suite.py play NAME    - play one signal at a safe level
  speaker-suite.py measure CONFIG-NAME - play+record every signal for a config
  speaker-suite.py analyze RUN  - FFT the recordings of one run, print table
  speaker-suite.py ladder       - run configs D,C,B,A in order (module swaps)

Configs (set via alsa, no reboot):
  D  fixup active, all pairs on   (today's state)
  C  fixup active, 0x1a pair solo (mid+treble pairs muted)
  B  fixup active, 0x14 pair solo
  A  stock module, only 0x1b pair (module swap - see set-config.sh)

Safety: everything at -12 dBFS, sweeps <= 8 s, nothing below 40 Hz or above
10 kHz, pauses between configs. Amp power is capped regardless; these bounds
protect the panel from sustained vibration, not the drivers from watts.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import wave
import array

DIR = "/tmp/speaker-suite"
SR = 48000
LEVEL = 0.25  # -12 dBFS

# name -> (frequency or None for sweep/noise, duration_s)
STIMULI = {
    "b45": (45, 3), "b60": (60, 3), "b80": (80, 3), "b120": (120, 3), "b200": (200, 3),
    "m300": (300, 3), "m500": (500, 3), "m1k": (1000, 3), "m2k": (2000, 3),
    "t3k": (3000, 3), "t5k": (5000, 3), "t8k": (8000, 3),
    "sweep": ("sweep40-200", 8),
    "pink": ("pink", 6),
}

def sine(freq, dur):
    n = int(SR * dur)
    out = array.array("h")
    fade = int(SR * 0.05)
    for i in range(n):
        env = 1.0
        if i < fade: env = i / fade
        if i > n - fade: env = (n - i) / fade
        v = int(LEVEL * env * 32767 * math.sin(2 * math.pi * freq * i / SR))
        out.append(v)
    return out

def sweep(dur):
    import numpy as np
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 40 * (200 / 40) ** (t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    sig = LEVEL * 0.8 * np.sin(phase)
    fade = int(SR * 0.1)
    env = np.ones(n)
    env[:fade] = np.linspace(0, 1, fade)
    env[-fade:] = np.linspace(1, 0, fade)
    sig *= env
    return array.array("h", (int(v) for v in sig * 32767))

def pink(dur):
    import numpy as np
    n = int(SR * dur)
    white = np.random.default_rng(42).standard_normal(n)
    # Voss-ish 3-stage approximation is enough for a reference signal
    b0 = b1 = b2 = np.zeros(1)
    # use simple IIR pink filter
    out = np.zeros(n)
    for i in range(n):
        w = white[i]
        out[i] = 0.0499220 * w + 0.0499220
    # too slow; fall back to FFT shaping
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spec *= 1 / np.sqrt(np.maximum(freqs, 1))
    sig = np.fft.irfft(spec, n)
    sig /= np.max(np.abs(sig))
    fade = int(SR * 0.1)
    env = np.ones(n)
    env[:fade] = np.linspace(0, 1, fade)
    env[-fade:] = np.linspace(1, 0, fade)
    return array.array("h", (int(v) for v in (LEVEL * 0.7 * sig * env * 32767)))

def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(samples.tobytes())

def gen():
    os.makedirs(DIR, exist_ok=True)
    import numpy as np  # noqa: F401  (sweep/pink need it)
    for name, (f, dur) in STIMULI.items():
        if name == "sweep":
            s = sweep(dur)
        elif name == "pink":
            s = pink(dur)
        else:
            s = sine(f, dur)
        write_wav(f"{DIR}/{name}.wav", s)
    print(f"generated {len(STIMULI)} signals in {DIR}")

def rec_channels():
    out = subprocess.run(["pactl", "list", "sources"], capture_output=True, text=True).stdout
    # return the default source name
    r = subprocess.run(["pactl", "info"], capture_output=True, text=True).stdout
    for line in r.splitlines():
        if "Default Source" in line:
            return line.split(":", 1)[1].strip()
    return None

def measure(config):
    import numpy as np
    src = rec_channels()
    runs = {}
    for name in STIMULI:
        rec = f"{DIR}/{config}-{name}.wav"
        # capture via the raw SOF DMIC (hw:0,6) — PipeWire's mic route is muted
        proc = subprocess.Popen(["arecord", "-D", "hw:0,6", "-f", "S32_LE", "-r", str(SR),
                                 "-c", "4", "-d", "999", rec + ".raw"],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import time
        time.sleep(0.4)
        subprocess.run(["pw-play", f"{DIR}/{name}.wav"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.3)
        proc.terminate()
        proc.wait()
        import numpy as np
        raw = np.fromfile(rec + ".raw", dtype=np.int32).astype(np.float64) / 2147483648
        raw = raw[: len(raw) // 4 * 4].reshape(-1, 4).mean(axis=1)
        with wave.open(rec, "w") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((raw * 32767).astype(np.int16).tobytes())
        os.unlink(rec + ".raw")
        time.sleep(0.4)
    print(f"measured config {config}: {len(STIMULI)} recordings")

def analyze(run):
    import numpy as np
    print(f"{'stim':6} {'dB@freq':>18}   peak-dB")
    table = {}
    for name, (f, _) in STIMULI.items():
        path = f"{DIR}/{run}-{name}.wav"
        if not os.path.exists(path):
            continue
        with wave.open(path) as w:
            sr = w.getframerate()
            raw = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
        if len(raw) < sr:
            table[name] = ("silent", 0)
            continue
        seg = raw[sr // 4:]  # skip onset
        win = np.hanning(len(seg))
        spec = np.abs(np.fft.rfft(seg * win))
        freqs = np.fft.rfftfreq(len(seg), 1 / sr)
        db = 20 * np.log10(spec / (np.max(spec) + 1e-12))
        def db_at(target):
            idx = np.argmin(np.abs(freqs - target))
            window = slice(max(0, idx - 20), idx + 20)
            return float(np.max(spec[window]))
        ref = db_at(f if isinstance(f, int) else 100)
        table[name] = (float(20 * np.log10(ref + 1e-12)), float(20 * np.log10(np.max(spec) + 1e-12)))
        marker = f"@{f}Hz" if isinstance(f, int) else ""
        print(f"{name:6} {marker:>8} {table[name][0]:>7.1f} dB   peak {table[name][1]:>6.1f} dB")
    with open(f"{DIR}/{run}-table.json", "w") as fh:
        json.dump(table, fh, indent=1)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "gen"
    if cmd == "gen":
        gen()
    elif cmd == "play":
        subprocess.run(["pw-play", f"{DIR}/{sys.argv[2]}.wav"])
    elif cmd == "measure":
        measure(sys.argv[2])
    elif cmd == "analyze":
        analyze(sys.argv[2])
    else:
        print(__doc__)
