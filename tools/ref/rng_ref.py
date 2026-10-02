#!/usr/bin/env python3
"""Reference implementation of the Craterline RNG (docs/ARCHITECTURE.md section 3).

SplitMix32 seeding + xoshiro128** + fork + unbiased range_int. Prints the golden values that
game/tests/core/test_rng.gd and test_fixed_math.gd compare against.
Run: python3 tools/ref/rng_ref.py
"""
M32 = 0xFFFFFFFF


def mul32(a: int, b: int) -> int:
    return (a * b) & M32


def rotl32(x: int, k: int) -> int:
    x &= M32
    return ((x << k) | (x >> (32 - k))) & M32


class Rng:
    def __init__(self, seed: int):
        # GDScript ints are 64-bit; fold the seed into 32 bits the same way.
        seed &= (1 << 64) - 1
        x = (seed ^ (seed >> 32)) & M32
        words = []
        for _ in range(4):
            x = (x + 0x9E3779B9) & M32
            z = x
            z = mul32(z ^ (z >> 16), 0x21F0AAAD)
            z = mul32(z ^ (z >> 15), 0x735A2D97)
            z = z ^ (z >> 15)
            words.append(z)
        if all(w == 0 for w in words):
            words[0] = 1
        self.s = words

    def next_u32(self) -> int:
        s0, s1, s2, s3 = self.s
        result = mul32(rotl32(mul32(s1, 5), 7), 9)
        t = (s1 << 9) & M32
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = rotl32(s3, 11)
        self.s = [s0, s1, s2, s3]
        return result

    def range_int(self, lo: int, hi: int) -> int:
        n = hi - lo + 1
        if n <= 1:
            return lo
        limit = ((1 << 32) // n) * n
        while True:
            r = self.next_u32()
            if r < limit:
                return lo + r % n

    def chance(self, num: int, den: int) -> bool:
        if num <= 0 or den <= 0:
            return False
        if num >= den:
            return True
        return self.range_int(0, den - 1) < num

    def fork(self, tag: int) -> "Rng":
        hi = self.next_u32()
        return Rng(((hi << 32) | mul32(tag & M32, 0x9E3779B9)))


SEEDS = [0, 1, 42, (1 << 40) + 7]

if __name__ == "__main__":
    for seed in SEEDS:
        r = Rng(seed)
        print(f"seed {seed} u32:", [r.next_u32() for _ in range(10)])
    for seed, tag in [(42, 1000), (42, 2001), (0, 0)]:
        f = Rng(seed).fork(tag)
        print(f"seed {seed} fork({tag}) u32:", [f.next_u32() for _ in range(10)])
    for seed in [1, 42]:
        r = Rng(seed)
        print(f"seed {seed} range_int(-10, 10):", [r.range_int(-10, 10) for _ in range(10)])
        r = Rng(seed)
        print(f"seed {seed} range_int(0, 2999999999):", [r.range_int(0, 2999999999) for _ in range(10)])
    # mul32 goldens for large operands
    for a, b in [(0xFFFFFFFF, 0xFFFFFFFF), (0x9E3779B9, 0x21F0AAAD), (0xDEADBEEF, 0x12345678), (0x80000000, 3), (123456789, 987654321)]:
        print(f"mul32({a}, {b}) =", mul32(a, b))
    print("rotl32(0x80000001, 1) =", rotl32(0x80000001, 1), " rotl32(0x12345678, 11) =", rotl32(0x12345678, 11))
