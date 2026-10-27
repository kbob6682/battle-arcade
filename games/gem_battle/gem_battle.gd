class_name GemBattle
extends MiniGame
## Gem Battle: each player matches gems on their own board. Drop mode only so
## far, and no attacks yet: whoever tops out first loses.
##
## Finishing (simple for now; Step 3 makes both sides always agree): a player
## who tops out sends TOPPED and loses; a player who receives TOPPED wins.

enum Kind { TOPPED = 1 }

## Holding left or right: first repeat after this long, then this often.
const MOVE_REPEAT_DELAY_SEC: float = 0.17
const MOVE_REPEAT_SEC: float = 0.05

var _game: DropGame = null
var _move_dir: int = 0
var _move_timer: float = 0.0

@onready var _board_view: GemGridView = %BoardView
@onready var _next_view: GemGridView = %NextView
@onready var _my_name: Label = %MyName
@onready var _their_name: Label = %TheirName
@onready var _status: Label = %Status
@onready var _chain_label: Label = %ChainLabel


func _start() -> void:
	_my_name.text = local_player.player_name
	_my_name.add_theme_color_override("font_color", local_player.get_colour())
	_their_name.text = "vs %s" % opponent.info.player_name
	_their_name.add_theme_color_override("font_color", opponent.info.get_colour())
	_status.text = "Left/Right move, Z/X rotate, Down soft drop, Space hard drop"
	_chain_label.text = ""
	_game = DropGame.new()
	_game.changed.connect(_redraw)
	_game.chain_step.connect(_on_chain_step)
	_game.chain_finished.connect(func(_chain: int) -> void: _chain_label.text = "")
	_game.topped_out.connect(_on_topped_out)
	# rng is seeded with the shared match seed, so both players get the same pairs.
	_game.start(rng)


func _process(delta: float) -> void:
	if _game == null or is_finished():
		return
	_handle_input(delta)
	_game.tick(delta)


func _handle_input(delta: float) -> void:
	if Input.is_action_just_pressed("gem_rotate_cw"):
		_game.rotate(1)
	if Input.is_action_just_pressed("gem_rotate_ccw"):
		_game.rotate(-1)
	if Input.is_action_just_pressed("gem_hard_drop"):
		_game.hard_drop()
	_game.soft_drop = Input.is_action_pressed("gem_soft_drop")
	var dir: int = int(Input.is_action_pressed("gem_right")) - int(Input.is_action_pressed("gem_left"))
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
	_board_view.show_cells(_game.cells_with_piece())
	# The preview shows the pair as it appears: second gem on top.
	_next_view.show_cells(PackedInt32Array([_game.next_colours[1], _game.next_colours[0]]))


func _on_chain_step(chain: int, _cleared: int) -> void:
	_chain_label.text = "%d chain!" % chain if chain > 1 else ""


func _on_topped_out() -> void:
	send(Kind.TOPPED)
	finish(Outcome.LOSE)


func _on_opponent_message(kind: int, _data: Dictionary) -> void:
	if is_finished():
		return
	if kind == Kind.TOPPED:
		finish(Outcome.WIN)
