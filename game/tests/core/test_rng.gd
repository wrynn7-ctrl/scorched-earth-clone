extends GutTest

# Golden values printed by tools/ref/rng_ref.py.


func _draw(r: Rng, n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(n):
		out.append(r.next_u32())
	return out


func test_seed_0_golden() -> void:
	assert_eq(_draw(Rng.new(0), 10), [1789933344, 44971166, 2521387044, 3848737593, 1138324114, 749234105, 1899511038, 1995189375, 3629653958, 19166872] as Array[int])


func test_seed_1_golden() -> void:
	assert_eq(_draw(Rng.new(1), 10), [393288148, 2174103013, 3814759091, 2092745082, 1865176206, 2179171167, 3207394750, 2858353069, 559075315, 3395495274] as Array[int])


func test_seed_42_golden() -> void:
	assert_eq(_draw(Rng.new(42), 10), [660444221, 3652823732, 77672526, 910233633, 2297337756, 3786072677, 3123505064, 1891482476, 2460634111, 3466307039] as Array[int])


func test_seed_large_golden() -> void:
	assert_eq(_draw(Rng.new((1 << 40) + 7), 10), [1814506324, 3221904288, 3467598780, 969496532, 288042106, 2376382169, 2724495446, 4176963748, 1981659261, 3642794894] as Array[int])


func test_fork_golden() -> void:
	assert_eq(_draw(Rng.new(42).fork(1000), 10), [2468156239, 1512538898, 1598783193, 1004492116, 2739527900, 538272998, 305011093, 2960116662, 2308457564, 868957843] as Array[int])
	assert_eq(_draw(Rng.new(42).fork(2001), 10), [1167261998, 3100914887, 597363200, 4086299249, 502590043, 2035681181, 2282219048, 3852952261, 3779648614, 1355237849] as Array[int])
	assert_eq(_draw(Rng.new(0).fork(0), 10), [3083583030, 1027413330, 1169104932, 3361557431, 3010606060, 271651250, 1592152639, 2298026253, 1717385881, 658998210] as Array[int])


func test_derive_equals_new_fork() -> void:
	assert_eq(_draw(Rng.derive(42, 1000), 5), _draw(Rng.new(42).fork(1000), 5))


func test_fork_streams_differ_by_tag() -> void:
	assert_ne(_draw(Rng.derive(5, 1000), 4), _draw(Rng.derive(5, 1001), 4))


func test_range_int_golden() -> void:
	var r := Rng.new(42)
	var got: Array[int] = []
	for i: int in range(10):
		got.append(r.range_int(-10, 10))
	assert_eq(got, [7, -5, 5, 5, -10, -8, -2, -8, 9, 10] as Array[int])
	# Rejection sampling: range larger than 2^31 skips draws that fall in the biased tail.
	var r2 := Rng.new(1)
	var got2: Array[int] = []
	for i: int in range(10):
		got2.append(r2.range_int(0, 2999999999))
	assert_eq(got2, [393288148, 2174103013, 2092745082, 1865176206, 2179171167, 2858353069, 559075315, 1929427096, 498941776, 2789075627] as Array[int])


func test_range_int_bounds_and_ends() -> void:
	var r := Rng.new(99)
	var seen_lo: bool = false
	var seen_hi: bool = false
	for i: int in range(10000):
		var v: int = r.range_int(-5, 5)
		assert_true(v >= -5 and v <= 5, "in bounds")
		seen_lo = seen_lo or v == -5
		seen_hi = seen_hi or v == 5
	assert_true(seen_lo, "hits lower end")
	assert_true(seen_hi, "hits upper end")


func test_range_int_degenerate() -> void:
	var r := Rng.new(3)
	var before: PackedInt64Array = r.get_state()
	assert_eq(r.range_int(7, 7), 7)
	assert_eq(r.range_int(7, 3), 7)
	assert_eq(r.get_state(), before, "no draw consumed")


func test_range_int_roughly_uniform() -> void:
	var r := Rng.new(2024)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	for i: int in range(6000):
		counts[r.range_int(0, 5)] += 1
	for c: int in counts:
		assert_true(c > 800 and c < 1200, "bucket %d" % c)


func test_same_seed_same_sequence() -> void:
	assert_eq(_draw(Rng.new(777), 50), _draw(Rng.new(777), 50))
	assert_ne(_draw(Rng.new(777), 5), _draw(Rng.new(778), 5))


func test_chance() -> void:
	var r := Rng.new(5)
	assert_false(r.chance(0, 10))
	assert_true(r.chance(10, 10))
	assert_false(r.chance(1, 0))
	var hits: int = 0
	for i: int in range(4000):
		if r.chance(1, 4):
			hits += 1
	assert_true(hits > 800 and hits < 1200, "about 25%%: %d" % hits)


func test_state_roundtrip() -> void:
	var a := Rng.new(11)
	_draw(a, 7)
	var b: Rng = Rng.from_state(a.get_state())
	assert_eq(_draw(a, 10), _draw(b, 10))


func test_never_all_zero_state() -> void:
	# The generator must be usable for every seed we try.
	for s: int in range(-3, 40):
		var st: PackedInt64Array = Rng.new(s).get_state()
		assert_true(st[0] != 0 or st[1] != 0 or st[2] != 0 or st[3] != 0)
