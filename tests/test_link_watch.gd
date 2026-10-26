extends "res://tests/test_case.gd"


func test_status_follows_silence() -> void:
	var watch := LinkWatch.new()
	watch.heard(1000)
	check_eq(watch.status(1000), LinkWatch.Status.OK, "just heard")
	check_eq(watch.status(1000 + LinkWatch.WARN_AFTER_MSEC - 1), LinkWatch.Status.OK, "just under warn")
	check_eq(watch.status(1000 + LinkWatch.WARN_AFTER_MSEC), LinkWatch.Status.WARN, "warn")
	check_eq(watch.status(1000 + LinkWatch.LOST_AFTER_MSEC - 1), LinkWatch.Status.WARN, "just under lost")
	check_eq(watch.status(1000 + LinkWatch.LOST_AFTER_MSEC), LinkWatch.Status.LOST, "lost")


func test_hearing_again_clears_the_warning() -> void:
	var watch := LinkWatch.new()
	watch.heard(0)
	check_eq(watch.status(5000), LinkWatch.Status.WARN, "warn after 5 s")
	watch.heard(5000)
	check_eq(watch.status(5500), LinkWatch.Status.OK, "ok once heard")


func test_heartbeat_message_round_trips() -> void:
	var msg: Dictionary = Messages.decode(Messages.encode(Messages.Type.HEARTBEAT))
	check_eq(msg.get("type"), Messages.Type.HEARTBEAT, "type")
	check_eq(msg.get("payload"), {}, "empty payload")
