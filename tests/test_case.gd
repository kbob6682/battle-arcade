extends Node
## Base for test files. Checks record failures instead of stopping the test.

var failures: Array[String] = []


func check(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)


func check_eq(actual: Variant, expected: Variant, what: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [what, var_to_str(expected), var_to_str(actual)])


## Waits up to timeout_sec for condition to become true. Returns whether it did.
func wait_until(condition: Callable, timeout_sec: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true
