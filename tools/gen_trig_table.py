#!/usr/bin/env python3
"""Generate game/core/trig_table.gd: quarter-wave sine table in Q16.16.

Entry i (0..900) = round-half-away-from-zero(sin(i / 10 degrees) * 65536).
Regenerate with:  python3 tools/gen_trig_table.py
The output is committed; the game never computes it at runtime.
"""
import math
import os

ENTRIES = 901
ONE = 65536


def q16(i: int) -> int:
    if i == 900:
        return ONE  # exact, avoid fp noise at the peak
    v = math.sin(math.radians(i / 10.0)) * ONE
    return int(math.floor(v + 0.5))  # v >= 0 here, so this is half-away-from-zero


def main() -> None:
    vals = [q16(i) for i in range(ENTRIES)]
    lines = []
    lines.append("# GENERATED FILE - do not edit by hand.")
    lines.append("# Regenerate with: python3 tools/gen_trig_table.py")
    lines.append("# Quarter-wave sine table: SIN_Q[i] = round(sin(i/10 degrees) * 65536), i = 0..900.")
    lines.append("class_name TrigTable")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append("const SIN_Q: PackedInt32Array = PackedInt32Array([")
    for start in range(0, ENTRIES, 10):
        chunk = vals[start:start + 10]
        tail = "," if start + 10 < ENTRIES else ""
        lines.append("\t" + ", ".join(str(v) for v in chunk) + tail)
    lines.append("])")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "core", "trig_table.gd")
    with open(os.path.normpath(out), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
