extends SceneTree
## Headless test runner. From the repo root:
##   godot_console --path . --headless -s tests/run_tests.gd
## Runs every test_* method in tests/test_*.gd (each extends test_case.gd).
## A test also fails if it logs an engine or script error (e.g. it crashed
## part way), and a test file that won't load counts as a failure.
## Exits with code 1 if any test fails.

const TESTS_DIR: String = "res://tests"


## Collects errors logged while a test runs. Godot keeps running the caller
## after a script error, so without this a crashed test would look like a pass.
class ErrorCatcher extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _errors: Array[String] = []

	# Loggers can be called from any thread, hence the mutex.
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text: String = rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("error: %s (%s:%d)" % [text, file, line])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var errors: Array[String] = _errors
		_errors = []
		_mutex.unlock()
		return errors


var _catcher: ErrorCatcher = ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	_run.call_deferred()


func _run() -> void:
	var total: int = 0
	var failed: int = 0
	for file: String in DirAccess.get_files_at(TESTS_DIR):
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		_catcher.take()
		var script: GDScript = load("%s/%s" % [TESTS_DIR, file]) as GDScript
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			var problems: Array[String] = ["couldn't load the test file"]
			problems.append_array(_catcher.take())
			_report(file, "(load)", problems)
			continue
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var test: Node = script.new()
			root.add_child(test)
			_catcher.take()
			await Callable(test, method_name).call()
			total += 1
			var failures: Array[String] = test.get("failures")
			failures.append_array(_catcher.take())
			if not failures.is_empty():
				failed += 1
			_report(file, method_name, failures)
			test.queue_free()
	OS.remove_logger(_catcher)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


func _report(file: String, method_name: String, failures: Array[String]) -> void:
	if failures.is_empty():
		print("  ok    %s  %s" % [file.get_basename(), method_name])
		return
	print("  FAIL  %s  %s" % [file.get_basename(), method_name])
	for line: String in failures:
		print("          " + line)
