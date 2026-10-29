class_name TugOfWar
extends MiniGame
## Tug of War: pieces travel sideways towards a glowing middle line. Filling a
## whole column clears it and moves the line into the opponent's side, giving
## you more room and them less. Classic mode so far.
##
## Each player runs their own side (TugGame); on both screens your side is on
## the left. Messages (all small):
## - CLEAR {n}: I cleared n columns; the line moves n steps into your side.
##   Both sides apply every clear once, so their widths always add up.
## - BOARD {b, w}: snapshot of my side (TugBoard.encode_cells) and its width,
##   up to SNAPSHOTS_PER_SEC, only when something changed.
## - TOPPED {t}: I topped out, t = msec since my match started.
## - TOPPED_ACK: I was still playing when your TOPPED arrived, so I win.
## Finishing works like Gem Battle's: a player still playing when TOPPED
## arrives wins and acks; if both topped before hearing, both compare times.

enum Kind { TOPPED = 1, TOPPED_ACK = 2, CLEAR = 3, BOARD = 4 }

## Holding up or down: first repeat after this long, then this often.
const MOVE_REPEAT_DELAY_SEC: float = 0.17
const MOVE_REPEAT_SEC: float = 0.05
const SNAPSHOT_INTERVAL_SEC: float = 0.25
## Most columns one piece can clear (it's 4 cells long at most).
const MAX_CLEAR: int = 4
const HELP: String = "Up/Down or W/S: move. Left/A, X or right click: rotate (Z or left click the other way). Right/D: push towards the line. Space: drop."
const CLEAR_WORDS: Array[String] = ["", "Push!", "Double push!", "Triple push!", "MEGA PUSH!"]

var _game: TugGame = null
var _move_dir: int = 0
var _move_timer: float = 0.0
var _start_msec: int = 0
var _my_topped_msec: int = -1
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0
var _sudden_death_shown: bool = false
## Columns each side has cleared. Theirs is counted from the CLEARs that
## arrive, so both screens show the same numbers.
var _my_cleared: int = 0
var _their_cleared: int = 0

@onready var _field: TugFieldView = %Field
@onready var _next_view: TugPieceView = %NextView
@onready var _my_name: Label = %MyName
@onready var _their_name: Label = %TheirName
@onready var _line_label: Label = %LineLabel
@onready var _my_cleared_label: Label = %MyCleared
@onready var _their_cleared_label: Label = %TheirCleared
@onready var _status: Label = %Status
@onready var _sudden_death_label: Label = %SuddenDeathLabel


## Who won when both players topped out, from one player's side: whoever
## topped out first loses. Both sides compare the same two numbers.
static func topped_result(my_msec: int, their_msec: int) -> Outcome:
	if my_msec < their_msec:
		return Outcome.LOSE
	if my_msec > their_msec:
		return Outcome.WIN
	return Outcome.DRAW


func _start() -> void:
	_my_name.text = local_player.player_name
	_my_name.add_theme_color_override("font_color", local_player.get_colour())
	_their_name.text = opponent.info.player_name
	_their_name.add_theme_color_override("font_color", opponent.info.get_colour())
	_status.text = HELP
	_sudden_death_label.hide()
	_game = TugGame.new()
	_game.changed.connect(_redraw)
	_game.columns_cleared.connect(_on_columns_cleared)
	_game.line_moved.connect(func(_width: int) -> void: _show_line())
	_game.topped_out.connect(_on_topped_out)
	_start_msec = Time.get_ticks_msec()
	# rng is seeded with the shared match seed, so both players get the same pieces.
	_game.start(rng)
	_field.show_theirs(TugBoard.TOTAL_WIDTH - _game.board.width, PackedInt32Array())
	_show_line()


func _process(delta: float) -> void:
	if _game == null or is_finished():
		return
	_handle_input(delta)
	_game.tick(delta)
	if _game.is_sudden_death() and not _sudden_death_shown:
		_sudden_death_shown = true
		_sudden_death_label.show()
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		send(Kind.BOARD, {"b": TugBoard.encode_cells(_game.cells_with_piece()), "w": _game.board.width})


func _handle_input(delta: float) -> void:
	if Input.is_action_just_pressed("tug_rotate_cw"):
		_game.rotate(1)
	if Input.is_action_just_pressed("tug_rotate_ccw"):
		_game.rotate(-1)
	if Input.is_action_just_pressed("tug_hard_drop"):
		_game.hard_drop()
	_game.soft_drop = Input.is_action_pressed("tug_soft_drop")
	var dir: int = int(Input.is_action_pressed("tug_down")) - int(Input.is_action_pressed("tug_up"))
	if dir == 0:
		_move_dir = 0
	elif dir != _move_dir:
		_move_dir = dir
		_move_timer = MOVE_REPEAT_DELAY_SEC
		_game.move(dir)
	else:
		_move_timer -= delta
		if _move_timer <= 0.0:
			_move_timer = MOVE_REPEAT_SEC
			_game.move(dir)


func _redraw() -> void:
	_board_dirty = true
	var ghost: Array[Vector2i] = []
	if _game.phase == TugGame.Phase.FALLING:
		ghost = _game.landing_cells()
	_field.show_mine(_game.board.width, _game.cells_with_piece(), ghost)
	_next_view.show_piece(_game.next_type)


func _on_columns_cleared(count: int, depths: Array[int]) -> void:
	send(Kind.CLEAR, {"n": count})
	_my_cleared += count
	_my_cleared_label.text = "Columns: %d" % _my_cleared
	_field.flash_mine(depths)
	_field.shake(2.0 + 2.0 * count)
	_popup(CLEAR_WORDS[mini(count, CLEAR_WORDS.size() - 1)] + "  >>", Color(1, 0.9, 0.4))


## Where the line is: how many steps it has moved your way or theirs.
func _show_line() -> void:
	var ahead: int = _game.board.width - TugBoard.START_WIDTH
	if ahead > 0:
		_line_label.text = "You're winning by %d" % ahead
	elif ahead < 0:
		_line_label.text = "%s is winning by %d" % [opponent.info.player_name, -ahead]
	else:
		_line_label.text = "Even"


func _on_topped_out() -> void:
	_my_topped_msec = Time.get_ticks_msec() - _start_msec
	send(Kind.TOPPED, {"t": _my_topped_msec})
	_status.text = "Out of room! Waiting for %s..." % opponent.info.player_name


func _on_opponent_message(kind: int, data: Dictionary) -> void:
	if is_finished():
		return
	match kind:
		Kind.CLEAR:
			var n: Variant = data.get("n")
			if typeof(n) != TYPE_INT or n < 1 or n > MAX_CLEAR:
				return
			_their_cleared += n
			_their_cleared_label.text = "Columns: %d" % _their_cleared
			if _my_topped_msec < 0:
				_game.push_line(n)
				_field.shake(3.0)
				_popup("Pushed back!", Color(1, 0.45, 0.4))
		Kind.BOARD:
			var width: Variant = data.get("w")
			if typeof(width) != TYPE_INT:
				return
			var their_board: TugBoard = TugBoard.decode(str(data.get("b", "")), width)
			if their_board != null:
				_field.show_theirs(their_board.width, their_board.cells)
		Kind.TOPPED:
			var t: Variant = data.get("t")
			if typeof(t) != TYPE_INT:
				return
			if _my_topped_msec < 0:
				send(Kind.TOPPED_ACK)
				finish(Outcome.WIN)
			else:
				finish(topped_result(_my_topped_msec, t))
		Kind.TOPPED_ACK:
			if _my_topped_msec >= 0:
				finish(Outcome.LOSE)


## A word that pops up at the middle line, rises and fades.
func _popup(text: String, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	_field.add_child(label)
	label.reset_size()
	label.position = _field.line_centre() - label.size / 2.0
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 60.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)
