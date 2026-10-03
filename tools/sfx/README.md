# Sound effects (generated, fully owned)

Every file in `game/assets/sfx/*.wav` is produced by `gen_sfx.py` from the parameters in `presets.json`.
There are no samples, recordings or third-party assets in there: the sounds are synthesised from
oscillators (square / saw / sine / triangle / noise), envelopes, pitch slides, vibrato, filters and a bit
crusher, in the style of sfxr/bfxr. We own all of it. The WAVs are committed so a normal build never has to run Python.

Output format: 16-bit mono 44.1 kHz, trimmed, normalised to a -3 dBFS peak. How loud each sound is in the game
is set in `game/show/audio/audio_director.gd` (`SOUNDS` table), not in the files.

## Regenerate

```bash
python3 tools/sfx/gen_sfx.py                   # everything (about 5 s, standard library only)
python3 tools/sfx/gen_sfx.py fire_light ui_tap  # just these
python3 tools/sfx/gen_sfx.py --list            # durations and sizes, writes nothing
python3 tools/sfx/gen_sfx.py --out /tmp/sfx    # somewhere else, to compare
```

Output is deterministic (fixed seeds), so regenerating without changing a preset gives identical files.

## Change or add a sound

1. Edit (or add) the entry in `presets.json`. The header of `gen_sfx.py` documents every layer parameter.
2. Run the generator for that name, then open the project once (or run `tools/run_tests.sh`) so Godot imports it.
3. New sound: register it in the `SOUNDS` table of `audio_director.gd` (file, volume, priority) and map it to an
   event in `on_event()` or call `AudioDirector.play_sfx("name")`. Commit the `.wav` and its `.wav.import`.

Loopable sounds (`fire_crackle`, `well_hum`) have `"loop": true`: the tail is cross-faded onto the head so the
file repeats without a click. The AudioDirector switches the loop on at load time.
