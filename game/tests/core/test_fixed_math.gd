extends GutTest

const ONE: int = 65536


func _near(got: int, want: int, msg: String) -> void:
	assert_true(absi(got - want) <= 1, "%s: got %d want %d" % [msg, got, want])


func test_sin10_known_values() -> void:
	_near(FixedMath.sin10(0), 0, "sin 0")
	_near(FixedMath.sin10(300), 32768, "sin 30")
	_near(FixedMath.sin10(450), 46341, "sin 45")
	_near(FixedMath.sin10(900), ONE, "sin 90")
	_near(FixedMath.sin10(1350), 46341, "sin 135")
	_near(FixedMath.sin10(1800), 0, "sin 180")
	_near(FixedMath.sin10(2700), -ONE, "sin 270")
	_near(FixedMath.sin10(-900), -ONE, "sin -90")
	_near(FixedMath.sin10(3600 + 450), 46341, "sin 405")


func test_cos10_known_values() -> void:
	_near(FixedMath.cos10(0), ONE, "cos 0")
	_near(FixedMath.cos10(300), 56756, "cos 30")
	_near(FixedMath.cos10(450), 46341, "cos 45")
	_near(FixedMath.cos10(900), 0, "cos 90")
	_near(FixedMath.cos10(1350), -46341, "cos 135")
	_near(FixedMath.cos10(1800), -ONE, "cos 180")
	_near(FixedMath.cos10(2700), 0, "cos 270")
	_near(FixedMath.cos10(-900), 0, "cos -90")
	_near(FixedMath.cos10(3600 + 450), 46341, "cos 405")


func test_sin_cos_symmetry_and_range() -> void:
	for a: int in range(-3700, 3700, 7):
		assert_eq(FixedMath.sin10(a), FixedMath.sin10(a + 3600), "periodic %d" % a)
		assert_eq(FixedMath.sin10(-a), -FixedMath.sin10(a), "odd %d" % a)
		var s: int = FixedMath.sin10(a)
		var c: int = FixedMath.cos10(a)
		assert_true(absi(s) <= ONE and absi(c) <= ONE)
		# s^2 + c^2 ~ ONE^2 within rounding
		var sum: int = s * s + c * c
		assert_true(absi(sum - ONE * ONE) < 4 * ONE, "unit circle %d" % a)


func test_trig_table_shape() -> void:
	assert_eq(TrigTable.SIN_Q.size(), 901)
	assert_eq(TrigTable.SIN_Q[0], 0)
	assert_eq(TrigTable.SIN_Q[900], ONE)
	for i: int in range(1, 901):
		assert_true(TrigTable.SIN_Q[i] >= TrigTable.SIN_Q[i - 1], "monotonic %d" % i)


func test_isqrt_exact_values() -> void:
	assert_eq(FixedMath.isqrt(0), 0)
	assert_eq(FixedMath.isqrt(1), 1)
	assert_eq(FixedMath.isqrt(2), 1)
	assert_eq(FixedMath.isqrt(3), 1)
	assert_eq(FixedMath.isqrt(4), 2)
	assert_eq(FixedMath.isqrt(15), 3)
	assert_eq(FixedMath.isqrt(16), 4)
	assert_eq(FixedMath.isqrt(1_000_000_000_000), 1_000_000)
	assert_eq(FixedMath.isqrt(1 << 61), 1518500249)
	assert_eq(FixedMath.isqrt(-5), 0)


func test_isqrt_floor_property() -> void:
	var samples: Array[int] = [5, 99, 100, 101, 65535, 65536, 65537, 999999, 123456789, 4611686014132420609]
	for n: int in samples:
		var r: int = FixedMath.isqrt(n)
		assert_true(r * r <= n, "r^2 <= n for %d" % n)
		assert_true((r + 1) * (r + 1) > n or r >= 2147483647, "(r+1)^2 > n for %d" % n)
	for n: int in range(0, 3000):
		var r: int = FixedMath.isqrt(n)
		assert_true(r * r <= n and (r + 1) * (r + 1) > n, "small %d" % n)


func test_mul_signs() -> void:
	assert_eq(FixedMath.mul(3 * ONE, 2 * ONE), 6 * ONE)
	assert_eq(FixedMath.mul(-3 * ONE, 2 * ONE), -6 * ONE)
	assert_eq(FixedMath.mul(-3 * ONE, -2 * ONE), 6 * ONE)
	assert_eq(FixedMath.mul(ONE / 2, ONE / 2), ONE / 4)
	assert_eq(FixedMath.mul(0, 12345), 0)
	# arithmetic shift floors toward negative infinity
	assert_eq(FixedMath.mul(-1, 1), -1)
	assert_eq(FixedMath.mul(1, 1), 0)


func test_div_signs() -> void:
	assert_eq(FixedMath.div(ONE, 2 * ONE), ONE / 2)
	assert_eq(FixedMath.div(-ONE, 2 * ONE), -ONE / 2)
	assert_eq(FixedMath.div(ONE, -2 * ONE), -ONE / 2)
	assert_eq(FixedMath.div(-ONE, -2 * ONE), ONE / 2)
	assert_eq(FixedMath.div(6 * ONE, 3 * ONE), 2 * ONE)
	# truncates toward zero
	assert_eq(FixedMath.div(1, 3 * ONE), 0)
	assert_eq(FixedMath.div(-1, 3 * ONE), 0)
	assert_eq(FixedMath.div(ONE, 3 * ONE), 21845)
	assert_eq(FixedMath.div(-ONE, 3 * ONE), -21845)


func test_cell_conversion() -> void:
	assert_eq(FixedMath.to_cell(5 * ONE), 5)
	assert_eq(FixedMath.to_cell(5 * ONE + 65535), 5)
	assert_eq(FixedMath.to_cell(-1), -1)
	assert_eq(FixedMath.to_cell(-ONE), -1)
	assert_eq(FixedMath.to_cell(-ONE - 1), -2)
	assert_eq(FixedMath.from_cell(7), 7 * ONE)
	assert_eq(FixedMath.from_cell(-3), -3 * ONE)


# Golden values from tools/ref/rng_ref.py ((a * b) & 0xFFFFFFFF in Python).
func test_mul32_golden() -> void:
	assert_eq(FixedMath.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
	assert_eq(FixedMath.mul32(0x9E3779B9, 0x21F0AAAD), 3099728901)
	assert_eq(FixedMath.mul32(0xDEADBEEF, 0x12345678), 1445054984)
	assert_eq(FixedMath.mul32(0x80000000, 3), 2147483648)
	assert_eq(FixedMath.mul32(123456789, 987654321), 4227814277)
	assert_eq(FixedMath.mul32(0, 0xFFFFFFFF), 0)
	assert_eq(FixedMath.mul32(1, 0xFFFFFFFF), 0xFFFFFFFF)


func test_rotl32_golden() -> void:
	assert_eq(FixedMath.rotl32(0x80000001, 1), 3)
	assert_eq(FixedMath.rotl32(0x12345678, 11), 2729689233)
	assert_eq(FixedMath.rotl32(0xABCDEF01, 0), 0xABCDEF01)
	assert_eq(FixedMath.rotl32(1, 31), 0x80000000)
