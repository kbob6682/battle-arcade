class_name TugOfWar
extends MiniGame
## Tug of War: three modes around a glowing middle line.
## - Classic: pieces fall down from your side (on top) to the line. Full rows
##   clear and push the line into the opponent's side, below.
## - Cannon: your side is on the left; aim a cannon on your back edge, turn
##   the piece and fire it at the line. Full columns push the line.
## - Rope: ten lanes, each a rope with a knot; every block you fire into a lane
##   pulls its knot your way. After two minutes, most lanes leaning your way wins.
## Classic and Cannon run the same rules (TugGame); Rope runs RopeGame.
##
## Messages (all small):
## - CLEAR {n}: I cleared n lines; the line moves n steps into your side.
##   Both sides apply every clear once, so their widths always add up.
## - BOARD {b, w}: snapshot of my side (TugBoard.encode_cells) and its width,
##   up to SNAPSHOTS_PER_SEC, only when something changed.
## - TOPPED {t} / TOPPED_ACK: as in Gem Battle; t = msec since my match started.
## - PULL {p}: Rope: my shot's pulls, one digit per lane.
## - AIM {p, o, r}: Rope: my cannon's piece, rotation and lane, for drawing.
## - DONE: Rope: my clock ran out; no more PULLs from me. Once both are done,
##   both have every shot and work out the same result.

enum Kind { TOPPED = 1, TOPPED_ACK = 2, CLEAR = 3, BOARD = 4, PULL = 5, AIM = 6, DONE = 7 }

const CLASSIC_MODE: String = "Classic"
const CANNON_MODE: String = "Cannon"
const ROPE_MODE: String = "Rope"
## Holding a move key: first repeat after this long, then this often.
const MOVE_REPEAT_DELAY_SEC: float = 0.17
const MOVE_REPEAT_SEC: float = 0.05
const SNAPSHOT_INTERVAL_SEC: float = 0.25
## Most lines one piece can clear (it's 4 cells long at most).
const MAX_CLEAR: int = 4
## Most blocks one shot can put in a lane, and in total.
const MAX_PULL: int = 4
const CLASSIC_HELP: String = "Left/Right or A/D: move. Up/W, X or right click: turn (Z or left click the other way). Down/S: faster. Space: drop."
const CANNON_HELP: String = "Aim: Up/Down, W/S or the mouse. Turn: Left/A, X or right click (Z the other way). Fire: Space, Right/D or left click. The fuse fires for you!"
const ROPE_HELP: String = "Aim: Up/Down, W/S or the mouse. Turn: Left/A, X or right click (Z the other way). Fire: Space, Right/D or left click. Flat pieces pull one lane hard, tall ones pull several."
const CLEAR_WORDS: Array[String] = ["", "Push!", "Double push!", "Triple push!", "MEGA PUSH!"]

var _game: TugGame = null
var _rope: RopeGame = null
var _rope_view: RopeView = null
var _move_dir: int = 0
var _move_timer: float = 0.0
var _start_msec: int = 0
var _my_topped_msec: int = -1
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0
var _sudden_death_shown: bool = false
## Lines each side has cleared. Theirs is counted from the CLEARs that
## arrive, so both screens show the same numbers.
var _my_cleared: int = 0
var _their_cleared: int = 0
## Rope: who has run out of time.
var _my_done: bool = false
var _their_done: bool = false

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


## Rope: a shot's pulls from a PULL message, or an empty array if it isn't
## valid (it's untrusted input): one digit per lane, 1 to MAX_PULL in total.
static func decode_pulls(text: String) -> PackedInt32Array:
	var pulls: PackedInt32Array = PackedInt32Array()
	if text.length() != RopeGame.LANES:
		return pulls
	var total: int = 0
	for i: int in text.length():
		var value: int = text.unicode_at(i) - 48 # "0"
		if value < 0 or value > MAX_PULL:
			return PackedInt32Array()
		pulls.append(value)
		total += value
	if total < 1 or total > MAX_PULL:
		return PackedInt32Array()
	return pulls


func _start() -> void:
	_my_name.text = local_player.player_name
	_my_name.add_theme_color_override("font_color", local_player.get_colour())
	_their_name.text = opponent.info.player_name
	_their_name.add_theme_color_override("font_color", opponent.info.get_colour())
	_sudden_death_label.hide()
	_start_msec = Time.get_ticks_msec()
	if mode == ROPE_MODE:
		_start_rope()
		return
	_game = TugGame.new()
	_game.cannon = mode == CANNON_MODE
	_field.upright = mode != CANNON_MODE
	_next_view.upright = _field.upright
	_status.text = CANNON_HELP if _game.cannon else CLASSIC_HELP
	if _game.cannon:
		_field.gui_input.connect(_on_aim_input)
	_game.changed.connect(_redraw)
	_game.columns_cleared.connect(_on_columns_cleared)
	_game.line_moved.connect(func(_width: int) -> void: _show_line())
	_game.topped_out.connect(_on_topped_out)
	# rng is seeded with the shared match seed, so both players get the same pieces.
	_game.start(rng)
	_field.rows = _game.board.rows
	_field.total_width = _game.board.total_width
	_field.show_theirs(_game.board.total_width - _game.board.width, PackedInt32Array())
	_show_line()


func _start_rope() -> void:
	_status.text = ROPE_HELP
	_my_cleared_label.text = ""
	_their_cleared_label.text = ""
	# The rope view takes the field's place.
	_rope_view = RopeView.new()
	_rope_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rope_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rope_view.custom_minimum_size = _field.custom_minimum_size
	_rope_view.my_colour = local_player.get_colour()
	_rope_view.their_colour = opponent.info.get_colour()
	_field.add_sibling(_rope_view)
	_field.get_parent().move_child(_rope_view, _field.get_index())
	_field.hide()
	_rope_view.gui_input.connect(_on_aim_input)
	_rope = RopeGame.new()
	_rope.changed.connect(_redraw_rope)
	_rope.fired.connect(_on_rope_fired)
	_rope.time_up.connect(_on_rope_time_up)
	_rope.start(rng)


func _process(delta: float) -> void:
	if is_finished():
		return
	if _rope != null:
		_process_rope(delta)
		return
	if _game == null:
		return
	if _game.cannon:
		_handle_cannon_keys(_game)
	else:
		_handle_classic_keys(delta)
	_game.tick(delta)
	_field.fuse = _game.fuse_left() if _game.cannon else -1.0
	if _game.is_sudden_death() and not _sudden_death_shown:
		_sudden_death_shown = true
		_sudden_death_label.show()
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		send(Kind.BOARD, {"b": TugBoard.encode_cells(_game.cells_with_piece()), "w": _game.board.width})


func _process_rope(delta: float) -> void:
	if not _rope.is_done():
		_handle_cannon_keys(_rope)
	_rope.tick(delta)
	_rope_view.reload = _rope.reload_progress()
	if _rope.is_final_stretch() and not _sudden_death_shown:
		_sudden_death_shown = true
		_sudden_death_label.text = "FINAL PULL!"
		_sudden_death_label.show()
	_show_rope_score()
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		send(Kind.AIM, {"p": _rope.piece_type, "o": _rope.rotation, "r": _rope.row})


## Classic keys. The field is drawn upright, which mirrors the pieces, so a
## clockwise turn on screen is an anticlockwise turn in TugGame.
func _handle_classic_keys(delta: float) -> void:
	if Input.is_action_just_pressed("tug_rotate"):
		_game.rotate(-1)
	if Input.is_action_just_pressed("tug_rotate_back"):
		_game.rotate(1)
	if Input.is_action_just_pressed("tug_drop"):
		_game.hard_drop()
	_game.soft_drop = Input.is_action_pressed("tug_soft_drop")
	var dir: int = int(Input.is_action_pressed("tug_right")) - int(Input.is_action_pressed("tug_left"))
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


## Cannon and Rope keys: aim up and down (one lane per press), turn, fire.
## cannon is a TugGame or a RopeGame; both have move, rotate and fire.
func _handle_cannon_keys(cannon: Object) -> void:
	if Input.is_action_just_pressed("tug_aim_up"):
		cannon.call("move", -1)
	if Input.is_action_just_pressed("tug_aim_down"):
		cannon.call("move", 1)
	if Input.is_action_just_pressed("tug_turn"):
		cannon.call("rotate", 1)
	if Input.is_action_just_pressed("tug_turn_back"):
		cannon.call("rotate", -1)
	if Input.is_action_just_pressed("tug_fire"):
		cannon.call("fire")


## Cannon and Rope: the cannon follows the mouse up and down.
func _on_aim_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or is_finished():
		return
	var position: Vector2 = (event as InputEventMouseMotion).position
	if _rope != null:
		var lane: int = _rope_view.lane_at(position)
		if lane >= 0 and not _rope.is_done():
			_rope.aim_at(lane - _middle_offset(_rope.piece_type, _rope.rotation))
	elif _game.phase == TugGame.Phase.FALLING:
		var row: int = _field.row_at(position)
		if row >= 0:
			_game.aim_at(row - _middle_offset(_game.piece_type, _game.rotation))


## How far below its box's top a piece's middle lane is, so the mouse aims
## the middle of the piece.
static func _middle_offset(type: int, turned: int) -> int:
	var low: int = 99
	var high: int = -99
	for offset: Vector2i in TugBoard.piece_offsets(type, turned):
		low = mini(low, offset.y)
		high = maxi(high, offset.y)
	@warning_ignore("integer_division")
	return (low + high) / 2


func _redraw() -> void:
	_board_dirty = true
	var ghost: Array[Vector2i] = []
	if _game.phase == TugGame.Phase.FALLING:
		ghost = _game.landing_cells()
	_field.show_mine(_game.board.width, _game.cells_with_piece(), ghost)
	_next_view.show_piece(_game.next_type)


func _redraw_rope() -> void:
	_board_dirty = true
	_rope_view.show_knots(_rope.knots)
	if _rope.is_done():
		_rope_view.show_my_cannon(0, 0, 0)
	else:
		_rope_view.show_my_cannon(_rope.piece_type, _rope.rotation, _rope.row)
	_next_view.show_piece(_rope.next_type)


func _on_columns_cleared(count: int, depths: Array[int]) -> void:
	send(Kind.CLEAR, {"n": count})
	_my_cleared += count
	_my_cleared_label.text = "Lines: %d" % _my_cleared
	_field.flash_mine(depths)
	_field.shake(2.0 + 2.0 * count)
	_popup(CLEAR_WORDS[mini(count, CLEAR_WORDS.size() - 1)], Color(1, 0.9, 0.4))


func _on_rope_fired(pulls: PackedInt32Array) -> void:
	send(Kind.PULL, {"p": TugBoard.encode_cells(pulls)})
	_rope_view.shoot(pulls, true)


func _on_rope_time_up() -> void:
	_my_done = true
	send(Kind.DONE)
	_status.text = "Time! Waiting for %s's last shots..." % opponent.info.player_name
	_finish_rope_if_both_done()


func _finish_rope_if_both_done() -> void:
	if _my_done and _their_done:
		_show_rope_score()
		finish(RopeGame.result_for(_rope.knots))


## Where the line is: how many steps it has moved your way or theirs.
func _show_line() -> void:
	var ahead: int = _game.board.width - _game.board.start_width()
	if ahead > 0:
		_line_label.text = "You're winning by %d" % ahead
	elif ahead < 0:
		_line_label.text = "%s is winning by %d" % [opponent.info.player_name, -ahead]
	else:
		_line_label.text = "Even"


func _show_rope_score() -> void:
	var left: int = ceili(_rope.time_left())
	@warning_ignore("integer_division")
	_line_label.text = "%d:%02d   Lanes: you %d, %s %d" % [left / 60, left % 60, _rope.lanes_mine(), opponent.info.player_name, _rope.lanes_theirs()]


func _on_topped_out() -> void:
	_my_topped_msec = Time.get_ticks_msec() - _start_msec
	send(Kind.TOPPED, {"t": _my_topped_msec})
	_status.text = "Out of room! Waiting for %s..." % opponent.info.player_name


func _on_opponent_message(kind: int, data: Dictionary) -> void:
	if is_finished():
		return
	if _rope != null:
		_on_rope_message(kind, data)
		return
	match kind:
		Kind.CLEAR:
			var n: Variant = data.get("n")
			if typeof(n) != TYPE_INT or n < 1 or n > MAX_CLEAR:
				return
			_their_cleared += n
			_their_cleared_label.text = "Lines: %d" % _their_cleared
			if _my_topped_msec < 0:
				_game.push_line(n)
				_field.shake(3.0)
				_popup("Pushed back!", Color(1, 0.45, 0.4))
		Kind.BOARD:
			var width: Variant = data.get("w")
			if typeof(width) != TYPE_INT:
				return
			var their_board: TugBoard = TugBoard.decode(str(data.get("b", "")), width, _game.board.rows, _game.board.total_width)
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


func _on_rope_message(kind: int, data: Dictionary) -> void:
	match kind:
		Kind.PULL:
			if _their_done:
				return
			var pulls: PackedInt32Array = decode_pulls(str(data.get("p", "")))
			if pulls.is_empty():
				return
			_rope.apply_their_pulls(pulls)
			_rope_view.shoot(pulls, false)
		Kind.AIM:
			var type: Variant = data.get("p")
			var turned: Variant = data.get("o")
			var top: Variant = data.get("r")
			if typeof(type) == TYPE_INT and typeof(turned) == TYPE_INT and typeof(top) == TYPE_INT \
					and type >= 1 and type <= TugBoard.PIECE_TYPES and RopeGame.fits(type, turned, top):
				_rope_view.show_their_cannon(type, turned, top)
		Kind.DONE:
			_their_done = true
			_rope_view.show_their_cannon(0, 0, 0)
			_finish_rope_if_both_done()


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
