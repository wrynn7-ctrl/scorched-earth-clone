extends GutTest
## SimTestUtil.perf_scale: the PERF_BUDGET_SCALE multiplier for wall-clock budgets in tests.

const VAR: String = "PERF_BUDGET_SCALE"


func _with(value: String) -> float:
	OS.set_environment(VAR, value)
	return SimTestUtil.perf_scale()


func test_scale_parsing_and_clamping() -> void:
	var saved: String = OS.get_environment(VAR)
	assert_eq(_with(""), 1.0, "unset means 1")
	assert_eq(_with("3"), 3.0)
	assert_eq(_with("2.5"), 2.5)
	assert_eq(_with(" 4 "), 4.0, "whitespace is ignored")
	assert_eq(_with("0.2"), 1.0, "never below 1")
	assert_eq(_with("0"), 1.0)
	assert_eq(_with("-5"), 1.0)
	assert_eq(_with("fast"), 1.0, "garbage means 1")
	OS.set_environment(VAR, "3")
	assert_eq(SimTestUtil.perf_budget(100), 300)
	assert_eq(SimTestUtil.perf_budget_f(40.0), 120.0)
	OS.set_environment(VAR, "1.5")
	assert_eq(SimTestUtil.perf_budget(5), 8, "rounded up")
	if saved == "":
		OS.unset_environment(VAR)
	else:
		OS.set_environment(VAR, saved)
