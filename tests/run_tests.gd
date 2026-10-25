extends SceneTree
## Headless test runner. From the repo root:
##   godot_console --path . --headless -s tests/run_tests.gd
## Runs every test_* method in tests/test_*.gd (each extends test_case.gd).
## Exits with code 1 if any test fails.

const TESTS_DIR: String = "res://tests"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var total: int = 0
	var failed: int = 0
	for file: String in DirAccess.get_files_at(TESTS_DIR):
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		var script: GDScript = load("%s/%s" % [TESTS_DIR, file])
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var test: Node = script.new()
			root.add_child(test)
			await Callable(test, method_name).call()
			total += 1
			var failures: Array[String] = test.get("failures")
			if failures.is_empty():
				print("  ok    %s  %s" % [file.get_basename(), method_name])
			else:
				failed += 1
				print("  FAIL  %s  %s" % [file.get_basename(), method_name])
				for line: String in failures:
					print("          " + line)
			test.queue_free()
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
