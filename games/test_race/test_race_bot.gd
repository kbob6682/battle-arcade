class_name TestRaceBot
extends BotOpponent
## Click Race bot: "clicks" a target every so often, faster on harder levels.

const SECONDS_PER_TARGET: Array[float] = [1.2, 0.8, 0.5] # Easy, Medium, Hard
const JITTER: float = 0.3

var _hits: int = 0
var _playing: bool = false
var _start_msec: int = 0
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer)


func start_match(_match_seed: int, _mode: String) -> void:
	_hits = 0
	_playing = true
	_start_msec = Time.get_ticks_msec()
	_schedule()


func stop_match() -> void:
	_playing = false
	if _timer != null:
		_timer.stop()


func _schedule() -> void:
	var seconds: float = SECONDS_PER_TARGET[difficulty] * rng.randf_range(1.0 - JITTER, 1.0 + JITTER)
	_timer.start(seconds)


func _on_timer() -> void:
	if not _playing:
		return
	_hits += 1
	reply(TestRace.Kind.HIT, {"n": _hits})
	if _hits < TestRace.TARGET_COUNT:
		_schedule()
		return
	_playing = false
	reply(TestRace.Kind.DONE, {"t": Time.get_ticks_msec() - _start_msec})


func _on_player_message(kind: int, _data: Dictionary) -> void:
	match kind:
		TestRace.Kind.DONE:
			if _playing:
				stop_match()
				reply(TestRace.Kind.CONCEDE)
		TestRace.Kind.CONCEDE:
			stop_match()
