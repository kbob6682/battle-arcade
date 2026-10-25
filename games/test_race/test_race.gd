class_name TestRace
extends MiniGame
## Click Race: a dev-only test game for the lobby and networking. Click the
## targets; first to TARGET_COUNT wins. Both players get the same target
## positions from the shared seed.
##
## Finishing: each side sends DONE {t} (msec since its own start). A side that
## gets DONE before finishing concedes. If both finish before hearing from the
## other, both compare the same two times and agree (exact tie: host wins).

enum Kind { HIT = 1, DONE = 2, CONCEDE = 3 }

const TARGET_COUNT: int = 20
const TARGET_SIZE: Vector2 = Vector2(72, 72)

var _targets: Array[Vector2] = []
var _hits: int = 0
var _opponent_hits: int = 0
var _start_msec: int = 0
var _my_done_msec: int = -1

@onready var _play_area: Control = %PlayArea
@onready var _target: Panel = %Target
@onready var _my_name: Label = %MyName
@onready var _my_bar: ProgressBar = %MyBar
@onready var _their_name: Label = %TheirName
@onready var _their_bar: ProgressBar = %TheirBar
@onready var _status: Label = %Status


## Target positions as fractions (0..1) of the play area, so they match on any window size.
static func make_targets(source: RandomNumberGenerator, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i: int in count:
		result.append(Vector2(source.randf(), source.randf()))
	return result


## Who wins when both players finished, from one player's side.
static func race_winner(my_msec: int, their_msec: int, i_am_host: bool) -> Outcome:
	if my_msec < their_msec:
		return Outcome.WIN
	if my_msec > their_msec:
		return Outcome.LOSE
	return Outcome.WIN if i_am_host else Outcome.LOSE


func _start() -> void:
	_targets = make_targets(rng, TARGET_COUNT)
	_my_name.text = local_player.player_name
	_my_name.add_theme_color_override("font_color", local_player.get_colour())
	_their_name.text = opponent.info.player_name
	_their_name.add_theme_color_override("font_color", opponent.info.get_colour())
	for bar: ProgressBar in [_my_bar, _their_bar]:
		bar.max_value = TARGET_COUNT
		bar.value = 0
	_status.text = "Click the targets!"
	_target.size = TARGET_SIZE
	_target.gui_input.connect(_on_target_input)
	_start_msec = Time.get_ticks_msec()
	# Wait a frame so the play area has its final size.
	_show_target.call_deferred()


func _show_target() -> void:
	var room: Vector2 = (_play_area.size - TARGET_SIZE).max(Vector2.ZERO)
	_target.position = _targets[_hits] * room
	_target.show()


func _on_target_input(event: InputEvent) -> void:
	if is_finished() or _my_done_msec >= 0 or not event.is_action_pressed("primary_click"):
		return
	_target.accept_event()
	_hits += 1
	_my_bar.value = _hits
	send(Kind.HIT, {"n": _hits})
	if _hits < TARGET_COUNT:
		_show_target()
		return
	_target.hide()
	_my_done_msec = Time.get_ticks_msec() - _start_msec
	_status.text = "Done! Waiting for %s..." % opponent.info.player_name
	send(Kind.DONE, {"t": _my_done_msec})


func _on_opponent_message(kind: int, data: Dictionary) -> void:
	if is_finished():
		return
	match kind:
		Kind.HIT:
			var n: Variant = data.get("n")
			if typeof(n) == TYPE_INT:
				_opponent_hits = clampi(n, 0, TARGET_COUNT)
				_their_bar.value = _opponent_hits
		Kind.DONE:
			var t: Variant = data.get("t")
			if typeof(t) != TYPE_INT:
				return
			_their_bar.value = TARGET_COUNT
			if _my_done_msec < 0:
				send(Kind.CONCEDE)
				_end(Outcome.LOSE)
			else:
				_end(race_winner(_my_done_msec, t, is_host))
		Kind.CONCEDE:
			if _my_done_msec >= 0:
				_end(Outcome.WIN)


func _end(outcome: Outcome) -> void:
	_target.hide()
	_status.text = ""
	finish(outcome, {"hits": _hits})
