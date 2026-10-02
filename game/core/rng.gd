@warning_ignore_start("integer_division")
class_name Rng
extends RefCounted
## xoshiro128** seeded with SplitMix32. Reference: tools/ref/rng_ref.py.

const M32: int = 0xFFFFFFFF

var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0


func _init(seed_value: int = 0) -> void:
	var x: int = (seed_value ^ (seed_value >> 32)) & M32
	var w: Array[int] = [0, 0, 0, 0]
	for i: int in range(4):
		x = (x + 0x9E3779B9) & M32
		var z: int = x
		z = FixedMath.mul32(z ^ (z >> 16), 0x21F0AAAD)
		z = FixedMath.mul32(z ^ (z >> 15), 0x735A2D97)
		z = z ^ (z >> 15)
		w[i] = z
	if w[0] == 0 and w[1] == 0 and w[2] == 0 and w[3] == 0:
		w[0] = 1
	_s0 = w[0]
	_s1 = w[1]
	_s2 = w[2]
	_s3 = w[3]


## Convenience: the independent stream `tag` of the root seed `seed`.
static func derive(seed_value: int, tag: int) -> Rng:
	return Rng.new(seed_value).fork(tag)


func next_u32() -> int:
	var result: int = FixedMath.mul32(FixedMath.rotl32(FixedMath.mul32(_s1, 5), 7), 9)
	var t: int = (_s1 << 9) & M32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = FixedMath.rotl32(_s3, 11)
	return result


## Uniform integer in [lo, hi] (inclusive), unbiased via rejection sampling.
## If hi <= lo, returns lo without consuming a draw. Range is limited to 2^32 values.
func range_int(lo: int, hi: int) -> int:
	var n: int = hi - lo + 1
	if n <= 1:
		return lo
	var limit: int = ((1 << 32) / n) * n
	while true:
		var r: int = next_u32()
		if r < limit:
			return lo + r % n
	return lo  # unreachable, keeps the typed-return checker happy


## True with probability num/den. No draw is consumed when the answer is certain.
func chance(num: int, den: int) -> bool:
	if num <= 0 or den <= 0:
		return false
	if num >= den:
		return true
	return range_int(0, den - 1) < num


## Independent child stream (consumes one draw from this stream).
func fork(tag: int) -> Rng:
	return Rng.new((next_u32() << 32) | FixedMath.mul32(tag, 0x9E3779B9))


func get_state() -> PackedInt64Array:
	return PackedInt64Array([_s0, _s1, _s2, _s3])


static func from_state(st: PackedInt64Array) -> Rng:
	var r := Rng.new(0)
	r._s0 = st[0]
	r._s1 = st[1]
	r._s2 = st[2]
	r._s3 = st[3]
	return r
