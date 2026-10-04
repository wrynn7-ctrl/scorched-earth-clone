#!/usr/bin/env python3
"""Deterministic heavy sci-fi sound generator for Craterline (docs/ARCHITECTURE.md section 33a).

Reads tools/sfx/presets.json and writes 16-bit mono 44.1 kHz WAV files into game/assets/sfx/.
Pure standard library (no numpy), so it runs anywhere Python 3.8+ does.

    python3 tools/sfx/gen_sfx.py                      # regenerate every sound
    python3 tools/sfx/gen_sfx.py fire_light ui_tap    # only these
    python3 tools/sfx/gen_sfx.py --list               # durations and sizes, writes nothing
    python3 tools/sfx/gen_sfx.py --out DIR            # write somewhere else, to compare

Determinism: every sound has a fixed integer `seed` (noise comes from random.Random(seed * 1000 + layer index),
whose stream is stable across Python versions) and the maths is plain IEEE double arithmetic, so the same presets
give the same WAVs on the same platform. The WAVs are committed anyway.

A sound is {"seed": int, "peak_db": -1.5, "loop": bool, "layers": [layer, ...], "post": [op, ...]}.
Layers are synthesised separately, mixed at their `delay`, scaled to a peak of 1, and then the `post` chain runs
over the mix (it is the "mastering" of one sound): saturation, filters, compressor, reverb, echo. The result is
trimmed, faded out and scaled to `peak_db` (default -1.5 dBFS, so every file peaks at or below -1 dBFS).

Heavy sound design in short: transient (a sharp crack) -> body (a pitched thump plus a swept noise burst) ->
tail (sub rumble, debris, reverb). The weight must survive a phone speaker, which plays almost nothing below
100 Hz, so the sub (40-80 Hz) is saturated: tanh adds odd harmonics at 3x the sub frequency (120-240 Hz).

LAYER TYPES (`"type"`; a layer without one is the old sfxr-style oscillator, documented at `render_note`)

  kick     a sine with an exponential pitch drop: f0 -> f1 with time constant `tau`. Sub drops and thumps.
           f0, f1, tau, sat (tanh drive, adds 3rd/5th harmonics), bias (adds even harmonics), plus the envelope.
  noise    coloured noise through a resonant state-variable filter whose cut-off falls from f0 to f1 (time
           constant `tau`). color white|pink|brown, mode lp|bp|hp, q, crackle (pops per second multiplying the
           noise), crackle_decay, am_rate/am_depth, sat. Bodies, debris, rumble, air.
  fm       two-operator FM: carrier at `freq` (or `notes`), modulator at carrier * `ratio`, modulation index
           `index` falling with time constant `index_tau`. Bells, chimes, metallic clanks, soft synth blips.
  pluck    Karplus-Strong string from a triangular pluck (no noise burst): notes, `damp` (0 = bright, 1 = dull),
           `pos` (pluck position), decay = ring time to -60 dB. Harp-like.
  pad      detuned voices per note (`wave` saw|triangle|sine, `detune` in cents, `lp` Hz with `lp_env`: the
           cut-off starts at lp * lp_env and falls to lp with time constant `lp_tau`), attack / hold / decay.
           Warm pads and the triumphant synth stabs.
  bubbles  random rising sine blips (sludge): rate (per s), f_lo, f_hi, len, span (seconds covered).

Envelope of the new layer types: linear `attack`, constant `hold`, then an exponential `decay` that reaches
-60 dB after `decay` seconds. Every layer also takes `gain` and `delay` (seconds). `notes` is
[[midi_note, start_s, hold_s], ...] for fm / pluck / pad. A layer marked "periodic": true in a loop sound must
repeat exactly every loop length (all its frequencies are multiples of 1 / loop length).

POST OPS (applied in order; each is {"op": name, ...})

  drive    {"amount": 0.4}               tanh soft clip of the peak-normalised mix (1 + 3 * amount of gain)
  sat      {"k": 2.0}                    plain tanh(k x) / tanh(k): thickens without re-normalising
  hp / lp  {"hz": 28, "order": 2}        Butterworth-style biquad(s)
  comp     {"thresh_db": -14, "ratio": 4, "attack": 0.003, "release": 0.12, "makeup_db": 6}
  reverb   {"mix": 0.2, "size": 1.0, "fb": 0.8, "damp": 0.4, "pre_ms": 8, "tail": 0.6}  Schroeder, 4 combs + 2 allpasses
  echo     {"time_ms": 380, "fb": 0.45, "lp_hz": 1800, "mix": 0.3, "tail": 1.5}  feedback delay with a dull loop
  limit    {"ceil_db": -8, "knee": 0.6}  soft clipper: peaks are bent down to the ceiling, then the final normalise
                                         lifts everything (lower crest factor = louder), see op_limit

Sound-level options: `drive` (legacy, runs first), `peak_db`, `loop` with `loop_samples` and `xfade` (seconds; the
tail of every non-periodic layer is cross-faded onto its head, so the file repeats without a click; a loop
allows only memoryless post ops), `fade_out` (seconds, default 0.01), `trim_db` (default -54).
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
DEFAULT_PEAK_DB = -1.5
TAU = 2.0 * math.pi
LN1000 = math.log(1000.0)  # an exponential decay of `d` seconds reaches -60 dB: exp(-LN1000 * t / d)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_PRESETS = os.path.join(HERE, "presets.json")
DEFAULT_OUT = os.path.join(ROOT, "game", "assets", "sfx")


def midi_hz(note):
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


# ======================================================================================
# The original sfxr-style oscillator layer (layers without a "type"). Parameters, all optional:
#   wave        square | saw | sine | triangle | noise   (noise = sample-and-hold at `freq`, or white if freq is 0)
#   freq        start frequency in Hz;  slide / slide_accel  octaves per second (and per second^2)
#   min_freq    the frequency never falls below this (Hz);  vib_rate, vib_depth  vibrato (Hz, fraction)
#   duty, duty_sweep         square duty cycle and its change per second
#   attack, sustain, decay   envelope in seconds (decay shape: `curve` = 1 linear, 2 quadratic, ...)
#   punch       extra loudness (0..1) at the start of the sustain, fading over 60 ms
#   lp, lp_sweep             2-pole low-pass cut-off (Hz) and its change in octaves per second
#   hp, hp_sweep             1-pole high-pass cut-off (Hz) and its change in octaves per second
#   bits, crush              bit crusher;  am_rate, am_depth  tremolo
#   crackle, crackle_decay   random pops per second multiplying the layer (fire, debris)
#   arp         {"semis": [0, 4, 7], "rate": 0.06}   cycle the pitch through these semitone offsets
#   notes       [[midi_note, start_s, length_s], ...]  play the layer as a melody (`length_s` = sustain)
# ======================================================================================

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



# ======================================================================================
# Heavy sound design: new layer types
# ======================================================================================

def make_env(attack, hold, decay):
    """Linear attack, flat hold, then an exponential fall that is -60 dB after `decay` seconds."""
    attack = max(attack, 1e-4)
    decay = max(decay, 1e-3)
    na = max(int(attack * SR), 1)
    nh = int(hold * SR)
    nd = int(decay * SR)
    env = [i / na for i in range(na)]
    env.extend([1.0] * nh)
    k = math.exp(-LN1000 / (decay * SR))
    e = 1.0
    for _ in range(nd):
        env.append(e)
        e *= k
    return env


def _env_of(p, default_decay=0.2):
    return make_env(p.get("attack", 0.001), p.get("hold", 0.0), p.get("decay", default_decay))


def layer_kick(p, rng):
    """A sine with an exponential pitch drop (sub drops, cannon thumps), optionally saturated."""
    env = _env_of(p)
    n = len(env)
    f0 = p.get("f0", 120.0)
    f1 = p.get("f1", 50.0)
    tau = max(p.get("tau", 0.03), 1e-4)
    sat = p.get("sat", 0.0)
    bias = p.get("bias", 0.0)
    k = math.exp(-1.0 / (tau * SR))
    norm = math.tanh(sat) if sat else 1.0
    tb = math.tanh(bias)
    d = f0 - f1
    ph = 0.0
    out = [0.0] * n
    for i in range(n):
        ph += (f1 + d) / SR
        d *= k
        s = math.sin(TAU * ph)
        e = env[i]
        if sat:
            out[i] = (math.tanh(sat * e * s + bias) - tb) / norm
        else:
            out[i] = s * e
    return out


def layer_noise(p, rng):
    """Coloured noise through a resonant state-variable filter with a falling cut-off."""
    env = _env_of(p)
    n = len(env)
    color = p.get("color", "white")
    mode = p.get("mode", "lp")
    f0 = p.get("f0", 0.0)
    f1 = p.get("f1", f0)
    tau = max(p.get("tau", 0.1), 1e-4)
    q = p.get("q", 0.7)
    kq = 1.0 / q
    sat = p.get("sat", 0.0)
    am_rate = p.get("am_rate", 0.0)
    am_depth = p.get("am_depth", 0.0)
    crackle = p.get("crackle", 0.0)
    pop_k = math.exp(-1.0 / (max(p.get("crackle_decay", 0.004), 1e-4) * SR))
    pop_p = crackle / SR
    pop = 0.0
    b0 = b1 = b2 = 0.0
    brown = 0.0
    ic1 = ic2 = 0.0
    a1 = a2 = a3 = 0.0
    k_t = math.exp(-1.0 / (tau * SR))
    sweep = f0 - f1
    norm = math.tanh(sat) if sat else 1.0
    out = [0.0] * n
    for i in range(n):
        w = rng.uniform(-1.0, 1.0)
        if color == "pink":
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            x = (b0 + b1 + b2 + w * 0.1848) * 0.35
        elif color == "brown":
            brown = (brown + 0.04 * w) / 1.02
            x = brown * 7.0
        else:
            x = w
        if f0 > 0.0:
            if i % 4 == 0:
                fc = f1 + sweep
                g = math.tan(math.pi * min(max(fc, 20.0), SR * 0.45) / SR)
                a1 = 1.0 / (1.0 + g * (g + kq))
                a2 = g * a1
                a3 = g * a2
            sweep *= k_t
            v3 = x - ic2
            v1 = a1 * ic1 + a2 * v3
            v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2.0 * v1 - ic1
            ic2 = 2.0 * v2 - ic2
            if mode == "lp":
                x = v2
            elif mode == "bp":
                x = kq * v1
            else:
                x = x - kq * v1 - v2
        if am_depth:
            x *= 1.0 - am_depth * 0.5 * (1.0 + math.sin(TAU * am_rate * i / SR))
        if crackle:
            pop *= pop_k
            if rng.random() < pop_p:
                pop = max(pop, 0.35 + 0.65 * rng.random() ** 2)
            x *= pop
        e = env[i]
        if sat:
            out[i] = math.tanh(sat * x * e) / norm
        else:
            out[i] = x * e
    return out


def _notes_of(p):
    """[(freq_hz, start_s, hold_s, velocity)] from `notes`, or one note at `freq`."""
    if "notes" in p:
        return [(midi_hz(nt[0]), nt[1], nt[2], nt[3] if len(nt) > 3 else 1.0) for nt in p["notes"]]
    return [(p.get("freq", 440.0), 0.0, p.get("hold", 0.0), 1.0)]


def _mix_into(out, buf, offset):
    if offset + len(buf) > len(out):
        out.extend([0.0] * (offset + len(buf) - len(out)))
    for i, v in enumerate(buf):
        out[offset + i] += v


def note_fm(p, freq, hold, vel):
    env = make_env(p.get("attack", 0.002), hold, p.get("decay", 0.8))
    n = len(env)
    ratio = p.get("ratio", 2.0)
    index = p.get("index", 2.0)
    itau = max(p.get("index_tau", p.get("decay", 0.8) * 0.4), 1e-3)
    ik = math.exp(-1.0 / (itau * SR))
    fb = p.get("fb", 0.0)
    ph_c = ph_m = 0.0
    inc_c = freq / SR
    inc_m = freq * ratio / SR
    out = [0.0] * n
    idx = index
    last = 0.0
    for i in range(n):
        m = math.sin(TAU * ph_m + fb * last)
        last = m
        out[i] = math.sin(TAU * ph_c + idx * m) * env[i] * vel
        idx *= ik
        ph_c += inc_c
        ph_m += inc_m
    return out


def note_pluck(p, freq, hold, vel):
    """Karplus-Strong with a triangular (noise-free) pluck and a tuned fractional delay."""
    decay = p.get("decay", 1.2)
    s = p.get("damp", 0.4) * 0.5  # 0 = bright, 0.5 = very dull
    period = SR / freq
    length = max(int(period - s - 0.0), 4)
    frac = period - s - length
    c = (1.0 - frac) / (1.0 + frac)
    g = 10.0 ** (-3.0 / (freq * max(decay, 0.05)))
    pos = p.get("pos", 0.18)
    peak_i = max(int(pos * length), 1)
    line = [(i / peak_i) if i < peak_i else ((length - i) / (length - peak_i)) for i in range(length)]
    mean = sum(line) / length
    line = [v - mean for v in line]
    n = int((p.get("attack", 0.0) + hold + decay) * SR)
    out = [0.0] * n
    idx = 0
    prev = 0.0
    ap_x = ap_y = 0.0
    fade = int(0.04 * SR)
    for i in range(n):
        x0 = line[idx]
        out[i] = x0 * vel
        y = g * ((1.0 - s) * x0 + s * prev)
        prev = x0
        z = c * y + ap_x - c * ap_y
        ap_x = y
        ap_y = z
        line[idx] = z
        idx += 1
        if idx == length:
            idx = 0
    for i in range(min(fade, n)):
        out[n - 1 - i] *= i / fade
    return out


def _polyblep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def note_pad(p, freq, hold, vel):
    env = make_env(p.get("attack", 0.4), hold, p.get("decay", 1.0))
    n = len(env)
    wave_name = p.get("wave", "saw")
    detune = p.get("detune", [-8.0, 0.0, 8.0])
    incs = [freq * 2.0 ** (c / 1200.0) / SR for c in detune]
    phs = [(i * 0.37) % 1.0 for i in range(len(incs))]  # spread the start phases (no summed click)
    lp = p.get("lp", 1800.0)
    lp_env = p.get("lp_env", 1.0)
    lp_tau = max(p.get("lp_tau", 0.3), 1e-3)
    sub = p.get("sub", 0.0)
    sub_inc = freq * 0.5 / SR
    sub_ph = 0.0
    lp1 = lp2 = 0.0
    a = 0.0
    inv = vel / len(incs)
    out = [0.0] * n
    for i in range(n):
        v = 0.0
        for j in range(len(incs)):
            ph = phs[j]
            if wave_name == "saw":
                v += 2.0 * ph - 1.0 - _polyblep(ph, incs[j])
            elif wave_name == "triangle":
                v += 4.0 * abs(ph - 0.5) - 1.0
            else:
                v += math.sin(TAU * ph)
            ph += incs[j]
            if ph >= 1.0:
                ph -= 1.0
            phs[j] = ph
        v *= inv
        if sub:
            v += sub * math.sin(TAU * sub_ph) * vel
            sub_ph += sub_inc
        if i % 16 == 0:
            cut = lp * (1.0 + (lp_env - 1.0) * math.exp(-(i / SR) / lp_tau))
            a = 1.0 - math.exp(-TAU * min(cut, SR * 0.45) / SR)
        lp1 += a * (v - lp1)
        lp2 += a * (lp1 - lp2)
        out[i] = lp2 * env[i]
    return out


def layer_bubbles(p, rng):
    span = p.get("span", 1.0)
    rate = p.get("rate", 12.0)
    f_lo = p.get("f_lo", 110.0)
    f_hi = p.get("f_hi", 320.0)
    blen = p.get("len", 0.07)
    env = _env_of(p, 0.3)
    n = len(env)
    out = [0.0] * n
    for _ in range(int(span * rate)):
        t0 = int(rng.uniform(0.0, span) * SR)
        f = f_lo + (f_hi - f_lo) * rng.random() ** 1.5
        ln = int(blen * rng.uniform(0.6, 1.5) * SR)
        vol = 0.3 + 0.7 * rng.random()
        ph = 0.0
        for i in range(ln):
            if t0 + i >= n:
                break
            u = i / ln
            ph += f * (1.0 + 1.1 * u) / SR
            out[t0 + i] += math.sin(TAU * ph) * vol * math.exp(-5.0 * u) * min(1.0, i / 60.0)
    return [v * e for v, e in zip(out, env)]


def layer_notes(p, rng, note_fn):
    out = []
    for freq, start, hold, vel in _notes_of(p):
        _mix_into(out, note_fn(p, freq, hold, vel), int(start * SR))
    return out


def render_layer(layer, rng):
    kind = layer.get("type", "osc")
    if kind == "kick":
        buf = layer_kick(layer, rng)
    elif kind == "noise":
        buf = layer_noise(layer, rng)
    elif kind == "fm":
        buf = layer_notes(layer, rng, note_fm)
    elif kind == "pluck":
        buf = layer_notes(layer, rng, note_pluck)
    elif kind == "pad":
        buf = layer_notes(layer, rng, note_pad)
    elif kind == "bubbles":
        buf = layer_bubbles(layer, rng)
    elif kind == "osc":
        buf = render_osc(layer, rng)
    else:
        raise ValueError("unknown layer type " + kind)
    gain = layer.get("gain", 1.0)
    delay = int(layer.get("delay", 0.0) * SR)
    return [0.0] * delay + [v * gain for v in buf] if delay else [v * gain for v in buf]


def render_osc(layer, rng):
    out = []
    if "notes" in layer:
        for note, start, length in layer["notes"]:
            render_note(layer, rng, midi_hz(note), length, out, int(start * SR))
    else:
        render_note(layer, rng, layer.get("freq", 440.0), layer.get("sustain", 0.1), out, 0)
    return out


# ======================================================================================
# Post chain
# ======================================================================================

def peak_of(buf):
    return max((abs(v) for v in buf), default=0.0) or 1.0


def normalise(buf, peak=1.0):
    k = peak / peak_of(buf)
    return [v * k for v in buf]


def biquad(buf, kind, hz, q):
    w0 = TAU * hz / SR
    cw = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * q)
    if kind == "lp":
        b0 = (1.0 - cw) * 0.5
        b1 = 1.0 - cw
        b2 = b0
    else:
        b0 = (1.0 + cw) * 0.5
        b1 = -(1.0 + cw)
        b2 = b0
    a0 = 1.0 + alpha
    a1 = -2.0 * cw / a0
    a2 = (1.0 - alpha) / a0
    b0 /= a0
    b1 /= a0
    b2 /= a0
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(buf)
    for i, x in enumerate(buf):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        out[i] = y
    return out


def op_filter(buf, kind, hz, order):
    qs = (0.7071,) if order <= 2 else (0.5412, 1.3066)
    for q in qs:
        buf = biquad(buf, kind, hz, q)
    return buf


def op_comp(buf, thresh_db, ratio, attack, release, makeup_db):
    thr = 10.0 ** (thresh_db / 20.0)
    ka = math.exp(-1.0 / (max(attack, 1e-4) * SR))
    kr = math.exp(-1.0 / (max(release, 1e-3) * SR))
    slope = 1.0 - 1.0 / ratio
    mk = 10.0 ** (makeup_db / 20.0)
    env = 0.0
    out = [0.0] * len(buf)
    for i, x in enumerate(buf):
        ax = abs(x)
        if ax > env:
            env = ax + ka * (env - ax)
        else:
            env = ax + kr * (env - ax)
        g = (thr / env) ** slope if env > thr else 1.0
        out[i] = x * g * mk
    return out


def _rms(buf):
    return math.sqrt(sum(v * v for v in buf) / max(len(buf), 1)) or 1e-9


def _blend_wet(dry, wet, mix):
    """Adds `wet` so that its RMS is `mix` times the dry RMS (an intuitive, scale-free mix control)."""
    k = mix * _rms(dry) / _rms(wet)
    return [d + w * k for d, w in zip(dry, wet)]


COMB_DELAYS = (1116, 1188, 1277, 1356)
ALLPASS_DELAYS = (556, 441)


def op_reverb(buf, mix, size, fb, damp, pre_ms, tail):
    n = len(buf) + int(tail * SR)
    pre = int(pre_ms * SR / 1000.0)
    dry = buf + [0.0] * (n - len(buf))
    x = [0.0] * pre + dry[:n - pre]
    wet = [0.0] * n
    for d0 in COMB_DELAYS:
        d = max(int(d0 * size), 8)
        line = [0.0] * d
        idx = 0
        lp = 0.0
        for i in range(n):
            y = line[idx]
            lp = y + damp * (lp - y)
            line[idx] = x[i] + lp * fb
            idx += 1
            if idx == d:
                idx = 0
            wet[i] += y
    for d0 in ALLPASS_DELAYS:
        d = max(int(d0 * size), 8)
        line = [0.0] * d
        idx = 0
        for i in range(n):
            y = line[idx]
            v = wet[i]
            line[idx] = v + y * 0.5
            wet[i] = y - v * 0.5
            idx += 1
            if idx == d:
                idx = 0
    return _blend_wet(dry, wet, mix)


def op_echo(buf, time_ms, fb, lp_hz, mix, tail):
    n = len(buf) + int(tail * SR)
    dry = buf + [0.0] * (n - len(buf))
    d = max(int(time_ms * SR / 1000.0), 8)
    a = 1.0 - math.exp(-TAU * lp_hz / SR)
    line = [0.0] * d
    idx = 0
    lp = 0.0
    wet = [0.0] * n
    for i in range(n):
        y = line[idx]
        lp += a * (y - lp)
        line[idx] = dry[i] + lp * fb
        idx += 1
        if idx == d:
            idx = 0
        wet[i] = y
    return _blend_wet(dry, wet, mix)


def op_limit(buf, ceil_db, knee=0.6):
    """Soft clipper: the mix was normalised to a peak of 1, everything above `ceil_db` is bent towards the
    ceiling (the loudest peaks end up at it), then the final normalise lifts the body by the same amount.
    That is what makes a sound loud: the crest factor drops while the transient stays."""
    c = 10.0 ** (ceil_db / 20.0)
    k = c * knee
    span = max(c - k, 1e-3)
    out = []
    for x in buf:
        ax = abs(x)
        if ax <= k:
            out.append(x)
        else:
            y = k + span * math.tanh((ax - k) / span)
            out.append(y if x > 0 else -y)
    return out


STATELESS = ("drive", "sat", "limit")


def apply_post(mix, post, looping):
    for op in post:
        name = op["op"]
        if looping and name not in STATELESS:
            raise ValueError("a loop may only use memoryless post ops, not " + name)
        mix = normalise(mix)
        if name == "drive":
            amount = op.get("amount", 0.3)
            mix = [math.tanh(v * (1.0 + amount * 3.0)) for v in mix]
        elif name == "sat":
            k = op.get("k", 2.0)
            norm = math.tanh(k)
            mix = [math.tanh(v * k) / norm for v in mix]
        elif name in ("hp", "lp"):
            mix = op_filter(mix, name, op["hz"], op.get("order", 2))
        elif name == "comp":
            mix = op_comp(mix, op.get("thresh_db", -14.0), op.get("ratio", 4.0), op.get("attack", 0.003),
                          op.get("release", 0.12), op.get("makeup_db", 0.0))
        elif name == "reverb":
            mix = op_reverb(mix, op.get("mix", 0.2), op.get("size", 1.0), op.get("fb", 0.8), op.get("damp", 0.4),
                            op.get("pre_ms", 8.0), op.get("tail", 0.5))
        elif name == "echo":
            mix = op_echo(mix, op.get("time_ms", 300.0), op.get("fb", 0.4), op.get("lp_hz", 1800.0),
                          op.get("mix", 0.3), op.get("tail", 1.0))
        elif name == "limit":
            mix = op_limit(mix, op.get("ceil_db", -8.0), op.get("knee", 0.6))
        else:
            raise ValueError("unknown post op " + name)
    return normalise(mix)


# ======================================================================================
# Sound assembly
# ======================================================================================

def render_sound(spec, name):
    seed = int(spec.get("seed", 1))
    looping = bool(spec.get("loop"))
    loop_n = int(spec.get("loop_samples", 0))
    xf = int(spec.get("xfade", 0.12) * SR)
    mix = []
    for idx, layer in enumerate(spec["layers"]):
        rng = random.Random(seed * 1000 + idx)
        buf = render_layer(layer, rng)
        if looping:
            buf = loop_layer(buf, loop_n, xf, bool(layer.get("periodic")))
        if len(buf) > len(mix):
            mix.extend([0.0] * (len(buf) - len(mix)))
        for i, v in enumerate(buf):
            mix[i] += v
    post = list(spec.get("post", []))
    if spec.get("drive"):
        post.insert(0, {"op": "drive", "amount": spec["drive"]})
    mix = apply_post(mix, post, looping)
    if not looping:
        mix = trim(mix, 10.0 ** (spec.get("trim_db", -54.0) / 20.0))
        fade = min(int(spec.get("fade_out", 0.01) * SR), len(mix))
        for i in range(fade):
            mix[len(mix) - 1 - i] *= math.sin(0.5 * math.pi * i / max(fade, 1)) ** 2
        for i in range(min(24, len(mix))):  # 0.5 ms fade-in: no click at the start
            mix[i] *= i / 24.0
        mean = sum(mix) / max(len(mix), 1)
        mix = [v - mean for v in mix]
    return normalise(mix, 10.0 ** (spec.get("peak_db", DEFAULT_PEAK_DB) / 20.0))


def loop_layer(buf, length, xf, periodic):
    """Exactly `length` samples that repeat without a seam. A periodic layer is simply cut; any other layer
    (noise, slow drift) cross-fades its tail past `length` onto its head with equal power."""
    if len(buf) < length + (0 if periodic else xf):
        buf = buf + [0.0] * (length + (0 if periodic else xf) - len(buf))
    out = buf[:length]
    if periodic or xf < 16:
        return out
    for i in range(xf):
        a = 0.5 * math.pi * i / xf  # 0 = tail only ... pi/2 = head only
        out[i] = buf[i] * math.sin(a) + buf[length + i] * math.cos(a)
    return out


def trim(buf, rel_limit):
    peak = peak_of(buf)
    limit = peak * rel_limit
    start = 0
    while start < len(buf) - 1 and abs(buf[start]) < limit:
        start += 1
    end = len(buf)
    while end > start + 1 and abs(buf[end - 1]) < limit:
        end -= 1
    return buf[start:end]


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
