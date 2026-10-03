#!/usr/bin/env python3
"""Deterministic sfxr/bfxr-style sound generator for Craterline.

Reads tools/sfx/presets.json and writes 16-bit mono 44.1 kHz WAV files into game/assets/sfx/.
Pure standard library (no numpy needed), so it runs anywhere Python 3.8+ does.

    python3 tools/sfx/gen_sfx.py                 # regenerate every sound
    python3 tools/sfx/gen_sfx.py fire_light ui_tap   # only these
    python3 tools/sfx/gen_sfx.py --list          # names and durations (no files written)
    python3 tools/sfx/gen_sfx.py --out /tmp/sfx  # write somewhere else

Determinism: every sound has a fixed integer `seed` (noise and crackle come from random.Random(seed + layer
index), whose stream is stable across Python versions) and the maths is plain IEEE double arithmetic, so
the same presets give the same WAVs on the same platform. The WAVs are committed anyway.

Preset format (see presets.json): a sound is {"seed": int, "loop": bool, "layers": [layer, ...]}.
A layer mixes into the sound at `delay` seconds. Layer parameters (all optional):

    wave        square | saw | sine | triangle | noise   (noise = sample-and-hold at `freq`, or white if freq is 0)
    freq        start frequency in Hz
    slide       frequency slide in octaves per second (negative = falling)
    slide_accel change of the slide in octaves per second^2
    min_freq    the frequency never falls below this (Hz)
    vib_rate, vib_depth      vibrato in Hz and as a fraction of the frequency
    duty, duty_sweep         square duty cycle (0..1) and its change per second
    attack, sustain, decay   envelope in seconds (decay shape: `curve` = 1 linear, 2 quadratic, ...)
    punch       extra loudness (0..1) at the start of the sustain, fading over 60 ms
    lp, lp_sweep             2-pole low-pass cut-off (Hz) and its change in octaves per second
    hp, hp_sweep             1-pole high-pass cut-off (Hz) and its change in octaves per second
    bits, crush              bit crusher: `bits` quantisation depth (0 = off), `crush` = hold every Nth sample
    am_rate, am_depth        tremolo
    crackle     random pops per second multiplying the layer (fire, debris), `crackle_decay` seconds each
    arp         {"semis": [0, 4, 7], "rate": 0.06}: cycle the pitch through these semitone offsets
    notes       [[midi_note, start_s, length_s], ...]: play the layer as a melody (ignores freq/slide); `length_s`
                is the sustain, the layer's `decay` is the release tail
    gain        layer volume (default 1)
    delay       start offset in seconds

Sound-level options: `drive` (tanh soft clip amount, 0 = off), `loop` (cross-fade the tail onto the head so
the file loops without a click; no trimming), `fade_out` (seconds, default 0.004).

Every file is trimmed (leading and trailing silence) and normalised to a -3 dBFS peak. How loud each sound
should be in the game is decided by the AudioDirector, not here.
"""
import argparse
import array
import json
import math
import os
import random
import sys
import wave

SR = 44100
PEAK = 10.0 ** (-3.0 / 20.0)  # -3 dBFS
TRIM_THRESHOLD = 0.004  # relative to the loudest sample
TAU = 2.0 * math.pi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_PRESETS = os.path.join(HERE, "presets.json")
DEFAULT_OUT = os.path.join(ROOT, "game", "assets", "sfx")


def midi_hz(note):
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


class Voice:
    """State of one oscillator run (one note of a layer)."""

    def __init__(self, params, rng):
        self.p = params
        self.rng = rng
        self.phase = 0.0
        self.held = 0.0  # sample-and-hold noise value
        self.lp1 = 0.0
        self.lp2 = 0.0
        self.hp_prev_in = 0.0
        self.hp_prev_out = 0.0


def osc(voice, wave_name, freq, duty):
    """One oscillator sample at the voice's phase, then advances the phase by `freq`."""
    ph = voice.phase
    if wave_name == "square":
        v = 1.0 if ph < duty else -1.0
    elif wave_name == "saw":
        v = 2.0 * ph - 1.0
    elif wave_name == "sine":
        v = math.sin(TAU * ph)
    elif wave_name == "triangle":
        v = 4.0 * abs(ph - 0.5) - 1.0
    elif wave_name == "noise":
        if freq <= 0.0:
            v = voice.rng.uniform(-1.0, 1.0)
        else:
            v = voice.held
    else:
        raise ValueError("unknown wave " + wave_name)
    if freq > 0.0:
        voice.phase += freq / SR
        if voice.phase >= 1.0:
            voice.phase -= math.floor(voice.phase)
            if wave_name == "noise":
                voice.held = voice.rng.uniform(-1.0, 1.0)
    return v


def render_note(p, rng, start_freq, sustain, out, offset):
    """Renders one oscillator run into `out` (a list of floats) starting at sample `offset`."""
    attack = p.get("attack", 0.002)
    decay = p.get("decay", 0.1)
    curve = p.get("curve", 2.0)
    punch = p.get("punch", 0.0)
    total = attack + sustain + decay
    n = int(total * SR)
    if offset + n > len(out):
        out.extend([0.0] * (offset + n - len(out)))
    voice = Voice(p, rng)
    voice.held = rng.uniform(-1.0, 1.0)
    wave_name = p.get("wave", "square")
    freq = start_freq
    slide = p.get("slide", 0.0)
    accel = p.get("slide_accel", 0.0)
    min_freq = p.get("min_freq", 0.0)
    vib_rate = p.get("vib_rate", 0.0)
    vib_depth = p.get("vib_depth", 0.0)
    duty = p.get("duty", 0.5)
    duty_sweep = p.get("duty_sweep", 0.0)
    lp = p.get("lp", 0.0)
    lp_sweep = p.get("lp_sweep", 0.0)
    hp = p.get("hp", 0.0)
    hp_sweep = p.get("hp_sweep", 0.0)
    bits = p.get("bits", 0)
    crush = max(1, int(p.get("crush", 1)))
    am_rate = p.get("am_rate", 0.0)
    am_depth = p.get("am_depth", 0.0)
    crackle = p.get("crackle", 0.0)
    crackle_decay = p.get("crackle_decay", 0.004)
    arp = p.get("arp")
    lp_a = 1.0
    hp_a = 0.0
    held_sample = 0.0
    pop = 0.0
    pop_k = math.exp(-1.0 / (max(crackle_decay, 1e-4) * SR))
    pop_p = crackle / SR
    lp_hz = lp
    hp_hz = hp
    for i in range(n):
        t = i / SR
        # Frequency: slide, vibrato, arpeggio.
        if slide != 0.0 or accel != 0.0:
            slide += accel / SR
            freq *= 2.0 ** (slide / SR)
            if min_freq > 0.0 and freq < min_freq:
                freq = min_freq
        f = freq
        if vib_depth:
            f *= 1.0 + vib_depth * math.sin(TAU * vib_rate * t)
        if arp:
            step = int(t / arp["rate"]) % len(arp["semis"])
            f *= 2.0 ** (arp["semis"][step] / 12.0)
        duty += duty_sweep / SR
        d = min(0.95, max(0.05, duty))
        v = osc(voice, wave_name, f, d)
        # Filters (coefficients refreshed every 16 samples).
        if (lp or hp) and i % 16 == 0:
            if lp:
                lp_hz = max(30.0, min(SR * 0.45, lp * 2.0 ** (lp_sweep * t)))
                lp_a = 1.0 - math.exp(-TAU * lp_hz / SR)
            if hp:
                hp_hz = max(10.0, min(SR * 0.45, hp * 2.0 ** (hp_sweep * t)))
                hp_a = math.exp(-TAU * hp_hz / SR)
        if lp:
            voice.lp1 += lp_a * (v - voice.lp1)
            voice.lp2 += lp_a * (voice.lp1 - voice.lp2)
            v = voice.lp2
        if hp:
            out_hp = hp_a * (voice.hp_prev_out + v - voice.hp_prev_in)
            voice.hp_prev_in = v
            voice.hp_prev_out = out_hp
            v = out_hp
        # Bit crusher.
        if crush > 1:
            if i % crush == 0:
                held_sample = v
            v = held_sample
        if bits:
            levels = 2.0 ** (bits - 1)
            v = math.floor(v * levels + 0.5) / levels
        # Tremolo and crackle.
        if am_depth:
            v *= 1.0 - am_depth * 0.5 * (1.0 + math.sin(TAU * am_rate * t))
        if crackle:
            pop *= pop_k
            if rng.random() < pop_p:
                pop = max(pop, 0.35 + 0.65 * rng.random() ** 2)
            v *= pop
        # Envelope.
        if t < attack:
            e = t / max(attack, 1e-6)
        elif t < attack + sustain:
            e = 1.0
            if punch:
                e += punch * math.exp(-(t - attack) / 0.06)
        else:
            e = max(0.0, 1.0 - (t - attack - sustain) / max(decay, 1e-6)) ** curve
        out[offset + i] += v * e


def render_layer(layer, rng):
    out = []
    gain = layer.get("gain", 1.0)
    delay = int(layer.get("delay", 0.0) * SR)
    if "notes" in layer:
        for note, start, length in layer["notes"]:
            render_note(layer, rng, midi_hz(note), length, out, delay + int(start * SR))
    else:
        render_note(layer, rng, layer.get("freq", 440.0), layer.get("sustain", 0.1), out, delay)
    return [v * gain for v in out]


def render_sound(spec, name):
    seed = int(spec.get("seed", 1))
    mix = []
    for idx, layer in enumerate(spec["layers"]):
        rng = random.Random(seed * 1000 + idx)
        buf = render_layer(layer, rng)
        if len(buf) > len(mix):
            mix.extend([0.0] * (len(buf) - len(mix)))
        for i, v in enumerate(buf):
            mix[i] += v
    drive = spec.get("drive", 0.0)
    if drive:
        peak = max(abs(v) for v in mix) or 1.0
        mix = [math.tanh(v / peak * (1.0 + drive * 3.0)) for v in mix]
    if spec.get("loop"):
        mix = make_loop(mix, int(spec.get("loop_samples", 0)) or None)
    else:
        mix = trim(mix)
        fade = int(spec.get("fade_out", 0.004) * SR)
        fade = min(fade, len(mix))
        for i in range(fade):
            mix[len(mix) - 1 - i] *= i / max(fade, 1)
        for i in range(min(24, len(mix))):  # 0.5 ms fade-in: no click at the start
            mix[i] *= i / 24.0
    # Remove DC and normalise to -3 dBFS.
    mean = sum(mix) / max(len(mix), 1)
    mix = [v - mean for v in mix]
    peak = max(abs(v) for v in mix) or 1.0
    k = PEAK / peak
    return [v * k for v in mix]


def trim(buf):
    peak = max(abs(v) for v in buf) or 1.0
    limit = peak * TRIM_THRESHOLD
    start = 0
    while start < len(buf) - 1 and abs(buf[start]) < limit:
        start += 1
    end = len(buf)
    while end > start + 1 and abs(buf[end - 1]) < limit:
        end -= 1
    return buf[start:end]


def make_loop(buf, length=None):
    """Cross-fades the part past `length` onto the start so the end flows into the beginning."""
    length = length or int(len(buf) * 0.8)
    xf = len(buf) - length
    if xf < 64:
        return buf
    out = buf[:length]
    for i in range(xf):
        a = i / xf  # 0 = tail only, 1 = head only
        out[i] = buf[i] * a + buf[length + i] * (1.0 - a)
    return out


def write_wav(path, samples):
    data = array.array("h", (max(-32768, min(32767, int(round(v * 32767.0)))) for v in samples))
    if sys.byteorder == "big":
        data.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("names", nargs="*", help="sounds to generate (default: all)")
    ap.add_argument("--presets", default=DEFAULT_PRESETS)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--list", action="store_true", help="render and print stats, write nothing")
    args = ap.parse_args()

    with open(args.presets, "r", encoding="utf-8") as f:
        presets = json.load(f)["sounds"]
    names = args.names or sorted(presets.keys())
    for n in names:
        if n not in presets:
            sys.exit("unknown sound: " + n)
    if not args.list:
        os.makedirs(args.out, exist_ok=True)
    total_bytes = 0
    for n in names:
        samples = render_sound(presets[n], n)
        size = 44 + 2 * len(samples)
        total_bytes += size
        print("%-18s %5.2f s  %7d bytes  peak %.1f dBFS" % (
            n, len(samples) / SR, size, 20.0 * math.log10(max(abs(v) for v in samples))))
        if not args.list:
            write_wav(os.path.join(args.out, n + ".wav"), samples)
    print("total %.2f MB" % (total_bytes / 1048576.0))


if __name__ == "__main__":
    main()
