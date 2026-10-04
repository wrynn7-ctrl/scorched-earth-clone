#!/usr/bin/env python3
"""Unit tests for the sound generator (standard library unittest). Run: python3 tools/sfx/test_gen_sfx.py"""
import json
import os
import sys

sys.dont_write_bytecode = True  # do not leave __pycache__ folders in the repo
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sfx  # noqa: E402

with open(os.path.join(HERE, "presets.json"), "r", encoding="utf-8") as _f:
    PRESETS = json.load(_f)["sounds"]


class GeneratorTests(unittest.TestCase):
    def test_deterministic(self):
        for name in ("ui_tap", "fire_light", "love_fire"):
            a = gen_sfx.render_sound(PRESETS[name], name)
            b = gen_sfx.render_sound(PRESETS[name], name)
            self.assertEqual(a, b, name)

    def test_peak_is_at_the_requested_level_and_below_minus_one_db(self):
        for name in ("ui_tap", "explosion_small", "love_found"):
            s = gen_sfx.render_sound(PRESETS[name], name)
            peak_db = 20.0 * __import__("math").log10(max(abs(v) for v in s))
            self.assertAlmostEqual(peak_db, PRESETS[name].get("peak_db", gen_sfx.DEFAULT_PEAK_DB), places=1)
            self.assertLessEqual(peak_db, -1.0)

    def test_every_preset_peak_is_at_most_minus_one_db(self):
        for name, spec in PRESETS.items():
            self.assertLessEqual(spec.get("peak_db", gen_sfx.DEFAULT_PEAK_DB), -1.0, name)

    def test_loops_have_the_exact_loop_length(self):
        for name in ("well_hum", "fire_crackle"):
            s = gen_sfx.render_sound(PRESETS[name], name)
            self.assertEqual(len(s), PRESETS[name]["loop_samples"], name)

    def test_loops_use_only_memoryless_post_ops(self):
        for name, spec in PRESETS.items():
            if spec.get("loop"):
                for op in spec.get("post", []):
                    self.assertIn(op["op"], gen_sfx.STATELESS, name)

    def test_periodic_hum_partials_fit_the_loop(self):
        spec = PRESETS["well_hum"]
        seconds = spec["loop_samples"] / gen_sfx.SR
        for layer in spec["layers"]:
            if layer.get("periodic"):
                cycles = layer["freq"] * seconds
                self.assertAlmostEqual(cycles, round(cycles), places=3, msg=str(layer["freq"]))

    def test_old_sfxr_layers_still_render(self):
        spec = {"seed": 1, "layers": [{"wave": "square", "freq": 440, "sustain": 0.05, "decay": 0.05}]}
        s = gen_sfx.render_sound(spec, "legacy")
        self.assertGreater(len(s), 1000)

    def test_unknown_layer_or_op_is_an_error(self):
        with self.assertRaises(ValueError):
            gen_sfx.render_sound({"seed": 1, "layers": [{"type": "nope"}]}, "x")
        with self.assertRaises(ValueError):
            gen_sfx.render_sound({"seed": 1, "layers": [{"type": "kick"}], "post": [{"op": "nope"}]}, "x")


if __name__ == "__main__":
    unittest.main()
