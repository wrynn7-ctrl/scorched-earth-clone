class_name FixedMath
extends RefCounted
## Q16.16 fixed-point helpers, integer square root and 32-bit hashing helpers.
## Everything here is pure integer math so results are identical on every device.

const ONE: int = 65536
const M32: int = 0xFFFFFFFF


## Q16.16 multiply. Operands must satisfy |a|, |b| < 2^31.
static func mul(a: int, b: int) -> int:
	return (a * b) >> 16


## Q16.16 divide (truncates toward zero). Caller ensures b != 0.
static func div(a: int, b: int) -> int:
	return (a << 16) / b


static func to_cell(fp: int) -> int:
	return fp >> 16


static func from_cell(c: int) -> int:
	return c << 16


## Sine of an angle in tenths of a degree (any integer), as Q16.16.
static func sin10(a: int) -> int:
	var n: int = posmod(a, 3600)
	if n <= 900:
		return TrigTable.SIN_Q[n]
	if n <= 1800:
		return TrigTable.SIN_Q[1800 - n]
	if n <= 2700:
		return -TrigTable.SIN_Q[n - 1800]
	return -TrigTable.SIN_Q[3600 - n]


static func cos10(a: int) -> int:
	return sin10(a + 900)


## Floor integer square root for n >= 0 (bitwise method).
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var rem: int = n
	var res: int = 0
	var bit: int = 1 << 62
	while bit > rem:
		bit >>= 2
	while bit != 0:
		if rem >= res + bit:
			rem -= res + bit
			res = (res >> 1) + bit
		else:
			res >>= 1
		bit >>= 2
	return res


## (a * b) mod 2^32 using 16-bit halves so no intermediate exceeds 2^48.
static func mul32(a: int, b: int) -> int:
	var x: int = a & M32
	var y: int = b & M32
	var lo: int = (x & 0xFFFF) * y
	var hi: int = ((x >> 16) * y) & 0xFFFF
	return (lo + (hi << 16)) & M32


static func rotl32(x: int, k: int) -> int:
	var v: int = x & M32
	var s: int = k & 31
	if s == 0:
		return v
	return ((v << s) | (v >> (32 - s))) & M32
