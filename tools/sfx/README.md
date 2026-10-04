# Sound effects (generated, fully owned)

Every file in `game/assets/sfx/*.wav` is produced by `gen_sfx.py` from the parameters in `presets.json`.
There are no samples, recordings or third-party assets in there: the sounds are synthesised from sine
pitch drops, coloured noise through resonant filters, FM bells, Karplus-Strong plucks and detuned pads, then
"mastered" per sound with saturation, a compressor, a soft clipper, a Schroeder reverb and a feedback echo.
We own all of it. The WAVs are committed so a normal build never has to run Python.

The character (docs/ARCHITECTURE.md section 33a) is **heavy sci-fi**: every impact is a sharp crack, then a
body (a saturated thump plus a swept noise burst), then a rumble or reverb tail. The weight has to survive a
phone speaker, which plays almost nothing under 100 Hz, so each thump is saturated: tanh adds harmonics at 3x
the 40-80 Hz sub, which land at 120-240 Hz. Size scales small < medium < large < nuke in length, low end and
loudness (nuke about 3.8 s). The **Love Edition** sounds are the opposite: soft FM chimes, harp-like plucks and
warm pads with a reverb, no noise at all; `love_win` is a 4.8 s arpeggio over a pad.

Output format: 16-bit mono 44.1 kHz, trimmed, faded out, scaled to the sound's `peak_db` (default -1.5 dBFS, UI
sounds are quieter, nothing above -1 dBFS). How loud each sound is in the game is set in
`game/show/audio/audio_director.gd` (`SOUNDS` table); the Master bus has a hard limiter.

## Regenerate and check

```bash
python3 tools/sfx/gen_sfx.py                   # everything (about 12 s, standard library only)
python3 tools/sfx/gen_sfx.py fire_light ui_tap # just these
python3 tools/sfx/gen_sfx.py --list            # durations and sizes, writes nothing
python3 tools/sfx/gen_sfx.py --out DIR         # somewhere else, to compare
python3 tools/sfx/check_sfx.py                 # measure every WAV, print the old-vs-new table, assert the rules
python3 tools/sfx/test_gen_sfx.py              # generator unit tests
```

`check_sfx.py` and `test_gen_sfx.py` also run from GUT (`game/tests/show/test_sfx_metrics.gd`, part of
`tools/run_tests.sh --suite show`; skipped if python3 is missing). The checks per file: peak, RMS, duration,
share of energy below 150 Hz, in 40-80 Hz and in 100-300 Hz, above 6 kHz, spectral flatness, loop seam.
Rules: nothing clips and every peak is at or below -1 dBFS; shots and impacts have a sub and real 100-300 Hz
energy (and more of it than the old sfxr files in `baseline_old.json`); explosion sizes are ordered in length,
low-end energy and loudness; the Love sounds have almost no energy above 6 kHz and a tonal (low flatness)
spectrum; the two loops are seamless; battle sounds sit at least 6 dB above UI sounds after the director's dB;
the total stays under 4 MB.

Output is deterministic (fixed seeds), so regenerating without changing a preset gives identical files.

## Change or add a sound

1. Edit (or add) the entry in `presets.json`. The header of `gen_sfx.py` documents every layer type and post op.
2. Run the generator for that name and `check_sfx.py`, then open the project once (or run `tools/run_tests.sh`)
   so Godot imports it.
3. New sound: register it in the `SOUNDS` table of `audio_director.gd` (file, volume, priority) and map it to an
   event in `sound_for_event()` or call `AudioDirector.play_sfx("name")`; add it to `HapticMapper.PATTERNS` or
   `NO_VIBRATION` (a test insists on a decision). Commit the `.wav` and its `.wav.import`.

Loopable sounds (`fire_crackle`, `well_hum`) have `"loop": true` and an exact `loop_samples`. Layers marked
`"periodic": true` (the hum's sines) repeat exactly in that length; noise layers cross-fade their tail onto
their head with equal power. A loop may only use memoryless post ops. The AudioDirector switches the loop on
at load time.
