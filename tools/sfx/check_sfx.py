#!/usr/bin/env python3
"""Objective checks for the generated sound effects (docs/ARCHITECTURE.md section 33a). Standard library only.

    python3 tools/sfx/check_sfx.py                    # measure game/assets/sfx, assert the rules, print a table
    python3 tools/sfx/check_sfx.py --dir DIR          # another folder of WAVs
    python3 tools/sfx/check_sfx.py --write-baseline   # (re)write baseline_old.json from the current files
    python3 tools/sfx/check_sfx.py --no-table         # only the verdict (used by the GUT test)

For every WAV it measures: peak and RMS (dBFS), duration, the loudest 50 ms RMS ("loud", what you hear as the
punch), the share of energy below 150 Hz, in 40-80 Hz (sub), in 100-300 Hz (what a phone speaker can still play),
above 6 kHz, and the spectral flatness between 200 Hz and 10 kHz (1 = noise, 0 = a pure tone). Loops also get
a seam measure. `baseline_old.json` holds the same numbers for the sfxr-style files this redesign replaced, so
the table shows old versus new.

Exit code 0 = every rule holds, 1 = some rule failed (each is printed as FAIL).
"""
import argparse
import cmath
import json
import math
import os
import re
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_DIR = os.path.join(ROOT, "game", "assets", "sfx")
BASELINE = os.path.join(HERE, "baseline_old.json")
DIRECTOR = os.path.join(ROOT, "game", "show", "audio", "audio_director.gd")

FRAME = 4096
SR_EXPECTED = 44100

SHOTS = ["fire_light", "fire_medium", "fire_heavy"]
EXPLOSIONS = ["explosion_small", "explosion_medium", "explosion_large", "explosion_nuke"]
IMPACTS = EXPLOSIONS + ["tank_destroyed"]
# Battle thumps that must also be heard on a phone speaker (they only get the 100-300 Hz and sub checks).
THUMPS = ["dirt_thud", "terrain_crumble", "anchor_clank", "shield_break", "ui_locked", "well_hum"]
LOVE = ["love_fire", "heart_burst", "love_found", "love_win"]
LOOPS = ["well_hum", "fire_crackle"]
UI = ["ui_tap", "ui_back", "ui_purchase", "ui_locked", "turn_blip", "cpu_think_tick"]
BATTLE_LOUD = SHOTS + EXPLOSIONS + ["tank_destroyed", "beam_zap"]

# --- rule thresholds ----------------------------------------------------------------------------------------
MAX_PEAK_DB = -1.0
MAX_TOTAL_BYTES = 4 * 1024 * 1024
MIN_LOW150 = {"explosion_small": 0.45, "explosion_medium": 0.55, "explosion_large": 0.60, "explosion_nuke": 0.65,
              "tank_destroyed": 0.55, "fire_light": 0.30, "fire_medium": 0.40, "fire_heavy": 0.50}
MIN_BAND_100_300 = 0.12   # phone speakers: some of the weight must sit above the sub
MIN_SUB_40_80 = 0.10      # and there is a real sub
OLD_PUNCH_GAIN_DB = 3.0   # absolute 100-300 Hz energy at least this far above the old file's. The old sounds were
                          # short and kept their bass in a sine under 60 Hz, which a phone speaker cannot play
OLD_PUNCH_GAIN_EXCEPT = {"explosion_small": -1.0}  # the smallest bang was already mid-heavy, it just was 0.35 s long
LOVE_MAX_HF6K = 0.004
LOVE_MAX_FLATNESS = 0.20
LOOP_MAX_SEAM = 1.0       # |first - last| over the largest sample-to-sample step inside the file
UI_BELOW_BATTLE_DB = 6.0  # loud (short-term RMS) plus the director's dB: UI at least this far below the battle
DURATION = {  # name: (min_s, max_s)
    "explosion_small": (0.4, 1.2), "explosion_medium": (0.8, 1.8), "explosion_large": (1.5, 2.8),
    "explosion_nuke": (3.0, 4.2), "love_win": (3.0, 5.0), "match_win": (2.5, 5.0), "round_win": (1.2, 3.0),
    "tank_destroyed": (1.0, 2.4),
}


# --- FFT (iterative radix 2, two real frames per transform) --------------------------------------------------

def _make_tables(n):
    bits = n.bit_length() - 1
    rev = [0] * n
    for i in range(n):
        rev[i] = (rev[i >> 1] >> 1) | ((i & 1) << (bits - 1))
    tw = [cmath.exp(-2j * math.pi * k / n) for k in range(n // 2)]
    return rev, tw


_TABLES = _make_tables(FRAME)
_HANN = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / FRAME) for i in range(FRAME)]


def fft(vals):
    rev, tw = _TABLES
    n = len(vals)
    a = [vals[rev[i]] for i in range(n)]
    size = 2
    while size <= n:
        half = size // 2
        step = n // size
        for start in range(0, n, size):
            k = 0
            for j in range(start, start + half):
                t = a[j + half] * tw[k]
                u = a[j]
                a[j] = u + t
                a[j + half] = u - t
                k += step
        size *= 2
    return a


def power_spectrum(samples):
    """Sum of the Hann-windowed periodograms of consecutive 4096-sample frames (energy-true), bins 0..n/2."""
    frames = []
    pos = 0
    n = len(samples)
    while pos < n or not frames:
        chunk = samples[pos:pos + FRAME]
        if len(chunk) < FRAME:
            chunk = chunk + [0.0] * (FRAME - len(chunk))
        frames.append([chunk[i] * _HANN[i] for i in range(FRAME)])
        pos += FRAME
    total = [0.0] * (FRAME // 2 + 1)
    for i in range(0, len(frames), 2):
        a = frames[i]
        b = frames[i + 1] if i + 1 < len(frames) else [0.0] * FRAME
        z = fft([complex(a[k], b[k]) for k in range(FRAME)])
        for k in range(FRAME // 2 + 1):
            zk = z[k]
            zn = z[(-k) % FRAME].conjugate()
            xa = (zk + zn) * 0.5
            xb = (zk - zn) * -0.5j
            total[k] += xa.real * xa.real + xa.imag * xa.imag + xb.real * xb.real + xb.imag * xb.imag
    return total


# --- measurements ------------------------------------------------------------------------------------------------

def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, width, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    import array
    data = array.array("h")
    data.frombytes(raw)
    if sys.byteorder == "big":
        data.byteswap()
    return [v / 32768.0 for v in data], sr, ch, width


def db(x):
    return 20.0 * math.log10(max(x, 1e-9))


def measure(path):
    samples, sr, ch, width = read_wav(path)
    n = len(samples)
    peak = max(abs(v) for v in samples) if n else 0.0
    rms = math.sqrt(sum(v * v for v in samples) / max(n, 1))
    win = int(0.05 * sr)
    loud = 0.0
    for s in range(0, max(n - win, 1), win // 2):
        seg = samples[s:s + win]
        loud = max(loud, math.sqrt(sum(v * v for v in seg) / len(seg)))
    ps = power_spectrum(samples)
    hz = sr / FRAME

    def share(lo, hi):
        tot = sum(ps) or 1.0
        return sum(p for k, p in enumerate(ps) if lo <= k * hz < hi) / tot

    # Spectral flatness of the long-term spectrum, 200 Hz .. 10 kHz.
    band = [p + 1e-18 for k, p in enumerate(ps) if 200.0 <= k * hz <= 10000.0]
    flat = math.exp(sum(math.log(p) for p in band) / len(band)) / (sum(band) / len(band))
    clipped = 0
    run = 0
    for v in samples:
        if abs(v) >= 32700.0 / 32768.0:
            run += 1
            if run >= 3:
                clipped += 1
        else:
            run = 0
    steps = [samples[i + 1] - samples[i] for i in range(n - 1)]
    max_step = max((abs(d) for d in steps), default=0.0) or 1e-9
    # The step from the last sample back to the first, over the biggest step anywhere else in the file: a seam
    # that is as smooth as the signal itself is <= 1, a click is far above.
    seam = abs(samples[0] - samples[-1]) / max_step if n > 1 else 0.0
    energy = sum(v * v for v in samples)
    low = share(0.0, 150.0)

    def band_db(lo, hi):  # absolute energy in the band (a Hann window and 4096-frames: comparable, not calibrated)
        return round(10.0 * math.log10(max(energy * share(lo, hi), 1e-12)), 2)

    return {
        "peak_db": round(db(peak), 2), "rms_db": round(db(rms), 2), "loud_db": round(db(loud), 2),
        "dur": round(n / sr, 3), "low150": round(low, 4), "sub": round(share(40.0, 80.0), 4),
        "mid": round(share(100.0, 300.0), 4), "mid_db": band_db(100.0, 300.0), "bass_db": band_db(40.0, 300.0), "hf6k": round(share(6000.0, 1e9), 5), "flat": round(flat, 4),
        "low_db": round(10.0 * math.log10(max(energy * low, 1e-12)), 2),
        "clipped": clipped, "seam": round(seam, 3), "sr": sr, "channels": ch, "width": width,
        "bytes": os.path.getsize(path),
    }


def measure_dir(folder):
    out = {}
    for f in sorted(os.listdir(folder)):
        if f.endswith(".wav"):
            out[f[:-4]] = measure(os.path.join(folder, f))
    return out


def director_db():
    """name -> the AudioDirector's dB offset, parsed from its SOUNDS table."""
    table = {}
    if not os.path.exists(DIRECTOR):
        return table
    with open(DIRECTOR, "r", encoding="utf-8") as f:
        for m in re.finditer(r'"(\w+)": \{"s": preload\("[^"]+"\), "db": (-?[\d.]+)', f.read()):
            table[m.group(1)] = float(m.group(2))
    return table


# --- rules ---------------------------------------------------------------------------------------------------------

def check(new, old):
    fails = []

    def need(cond, msg):
        if not cond:
            fails.append(msg)

    total = sum(m["bytes"] for m in new.values())
    need(total <= MAX_TOTAL_BYTES, "total size %d bytes exceeds %d" % (total, MAX_TOTAL_BYTES))
    for name, m in new.items():
        need(m["sr"] == SR_EXPECTED and m["channels"] == 1 and m["width"] == 2, "%s: not 44.1 kHz mono 16-bit" % name)
        need(m["peak_db"] <= MAX_PEAK_DB, "%s: peak %.2f dBFS above %.1f" % (name, m["peak_db"], MAX_PEAK_DB))
        need(m["clipped"] == 0, "%s: %d clipped samples" % (name, m["clipped"]))
    for name in IMPACTS + SHOTS:
        m = new.get(name)
        if m is None:
            fails.append("%s: missing" % name)
            continue
        need(m["low150"] >= MIN_LOW150[name], "%s: low share %.2f below %.2f" % (name, m["low150"], MIN_LOW150[name]))
        need(m["mid"] >= MIN_BAND_100_300, "%s: 100-300 Hz share %.3f below %.2f" % (name, m["mid"], MIN_BAND_100_300))
        need(m["sub"] >= MIN_SUB_40_80, "%s: 40-80 Hz share %.3f below %.2f" % (name, m["sub"], MIN_SUB_40_80))
        o = old.get(name)
        if o is not None and "mid_db" in o:
            gain = OLD_PUNCH_GAIN_EXCEPT.get(name, OLD_PUNCH_GAIN_DB)
            need(m["mid_db"] >= o["mid_db"] + gain,
                 "%s: 100-300 Hz energy %.1f dB is not %.0f dB above the old %.1f dB" % (
                     name, m["mid_db"], gain, o["mid_db"]))
    for name in THUMPS:
        m = new.get(name)
        if m is not None:
            need(m["mid"] >= MIN_BAND_100_300, "%s: 100-300 Hz share %.3f below %.2f (silent on a phone speaker)" % (
                name, m["mid"], MIN_BAND_100_300))
    # Sizes are ordered in length, absolute low-end energy and short-term loudness.
    for a, b in zip(EXPLOSIONS, EXPLOSIONS[1:]):
        if a in new and b in new:
            for key, label in (("dur", "length"), ("low_db", "low-end energy"), ("loud_db", "loudness")):
                need(new[a][key] < new[b][key], "%s < %s fails for %s (%s vs %s)" % (a, b, label, new[a][key], new[b][key]))
    for name, (lo, hi) in DURATION.items():
        if name in new:
            need(lo <= new[name]["dur"] <= hi, "%s: duration %.2f s outside %.1f..%.1f" % (name, new[name]["dur"], lo, hi))
    for name in LOVE:
        m = new.get(name)
        if m is None:
            fails.append("%s: missing" % name)
            continue
        need(m["hf6k"] <= LOVE_MAX_HF6K, "%s: %.4f of the energy above 6 kHz (limit %.4f)" % (name, m["hf6k"], LOVE_MAX_HF6K))
        need(m["flat"] <= LOVE_MAX_FLATNESS, "%s: spectral flatness %.3f (limit %.2f): too noisy" % (name, m["flat"], LOVE_MAX_FLATNESS))
        need(m["low150"] < 0.5, "%s: too boomy for Love (low share %.2f)" % (name, m["low150"]))
    for name in LOOPS:
        m = new.get(name)
        if m is None:
            fails.append("%s: missing" % name)
            continue
        need(m["seam"] <= LOOP_MAX_SEAM, "%s: loop seam %.2f (limit %.1f)" % (name, m["seam"], LOOP_MAX_SEAM))
    dbs = director_db()
    if dbs:
        battle = [new[n]["loud_db"] + dbs.get(n, 0.0) for n in BATTLE_LOUD if n in new]
        ui = [new[n]["loud_db"] + dbs.get(n, 0.0) for n in UI if n in new]
        if battle and ui:
            need(min(battle) >= max(ui) + UI_BELOW_BATTLE_DB,
                 "battle sounds (quietest %.1f dB) are not %.0f dB above the UI sounds (loudest %.1f dB)" % (
                     min(battle), UI_BELOW_BATTLE_DB, max(ui)))
    return fails


# --- output ----------------------------------------------------------------------------------------------------------

def print_table(new, old):
    print("%-17s %5s | %6s %6s %6s | %5s %5s %5s %6s %5s | %s" % (
        "sound", "dur", "peak", "rms", "loud", "<150", "40-80", "100-300", ">6k", "flat", "punch dB (old)  loud (old)  dur (old)"))
    for name, m in new.items():
        o = old.get(name)
        oldtxt = "%6.1f (%6.1f) %6.1f (%6.1f) %5.2f (%5.2f)" % (
            m["mid_db"], o.get("mid_db", 0.0), m["loud_db"], o["loud_db"], m["dur"], o["dur"]) if o else "-"
        print("%-17s %5.2f | %6.1f %6.1f %6.1f | %5.2f %5.2f %5.2f %6.3f %5.2f | %s" % (
            name, m["dur"], m["peak_db"], m["rms_db"], m["loud_db"], m["low150"], m["sub"], m["mid"],
            m["hf6k"] * 100.0, m["flat"], oldtxt))
    total = sum(m["bytes"] for m in new.values())
    print("total %.2f MB in %d files  (>6k column is in percent)" % (total / 1048576.0, len(new)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--baseline", default=BASELINE)
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--no-table", action="store_true")
    args = ap.parse_args()
    new = measure_dir(args.dir)
    if args.write_baseline:
        with open(args.baseline, "w", encoding="utf-8") as f:
            json.dump(new, f, indent=1, sort_keys=True)
            f.write("\n")
        print("wrote", args.baseline)
        return 0
    old = {}
    if os.path.exists(args.baseline):
        with open(args.baseline, "r", encoding="utf-8") as f:
            old = json.load(f)
    if not args.no_table:
        print_table(new, old)
    fails = check(new, old)
    for f in fails:
        print("FAIL:", f)
    print("check_sfx: %s (%d files, %d problems)" % ("OK" if not fails else "FAILED", len(new), len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
