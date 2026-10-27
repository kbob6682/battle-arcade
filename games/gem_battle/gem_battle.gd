class_name GemBattle
extends MiniGame
## Gem Battle: each player matches gems on their own board, and chains send
## junk to the opponent. Drop mode so far.
##
## Messages (all small; each game is in charge of its own board):
## - ATTACK {n}: junk sent after blocking. Drops after the receiver's next landing.
## - BOARD {b, i}: board snapshot (GemBoard.encode_cells) and incoming junk,
##   up to SNAPSHOTS_PER_SEC, only when something changed. For the mini board.
## - TOPPED {t}: I topped out, t = msec since my match started.
## - TOPPED_ACK: I was still playing when your TOPPED arrived, so I win.
## Finishing: a player still playing when TOPPED arrives wins and acks; the
## topped player loses on the ack. If both topped before hearing from each
## other, both compare the same two times (topped_result), so they agree.

enum Kind { TOPPED = 1, TOPPED_ACK = 2, ATTACK = 3, BOARD = 4 }

## Holding left or right: first repeat after this long, then this often.
const MOVE_REPEAT_DELAY_SEC: float = 0.17
const MOVE_REPEAT_SEC: float = 0.05
const SNAPSHOT_INTERVAL_SEC: float = 0.25

var _game: DropGame = null
var _move_dir: int = 0
var _move_timer: float = 0.0
var _start_msec: int = 0
var _my_topped_msec: int = -1
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0
var _sudden_death_shown: bool = false

@onready var _board_view: GemGridView = %BoardView
@onready var _next_view: GemGridView = %NextView
@onready var _incoming_view: GemGridView = %IncomingView
@onready var _incoming_label: Label = %IncomingLabel
@onready var _their_board: GemGridView = %TheirBoard
@onready var _their_incoming: Label = %TheirIncoming
@onready var _my_name: Label = %MyName
@onready var _their_name: Label = %TheirName
@onready var _status: Label = %Status
@onready var _chain_label: Label = %ChainLabel
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
	_status.text = "Arrows or WASD: move, Up/W rotate, Down/S soft drop. Z/X rotate either way. Space hard drop."
	_chain_label.text = ""
	_sudden_death_label.hide()
	_show_incoming(0)
	_their_incoming.text = ""
	_game = DropGame.new()
	_game.changed.connect(_redraw)
	_game.chain_step.connect(_on_chain_step)
	_game.chain_finished.connect(func(_chain: int) -> void: _chain_label.text = "")
	_game.attack_sent.connect(func(amount: int) -> void: send(Kind.ATTACK, {"n": amount}))
	_game.incoming_changed.connect(_on_incoming_changed)
	_game.topped_out.connect(_on_topped_out)
	_start_msec = Time.get_ticks_msec()
	# rng is seeded with the shared match seed, so both players get the same pairs.
	_game.start(rng)


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
		send(Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_with_piece()), "i": _game.incoming})


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
	_board_dirty = true
	_board_view.show_cells(_game.cells_with_piece())
	# The preview shows the pair as it appears: second gem on top.
	_next_view.show_cells(PackedInt32Array([_game.next_colours[1], _game.next_colours[0]]))


func _on_chain_step(chain: int, _cleared: int) -> void:
	_chain_label.text = "%d chain!" % chain if chain > 1 else ""


func _on_incoming_changed(amount: int) -> void:
	_board_dirty = true
	_show_incoming(amount)


## A row of little stones (one per junk, up to a row) and a count.
func _show_incoming(amount: int) -> void:
	var stones: PackedInt32Array = PackedInt32Array()
	stones.resize(GemBoard.WIDTH)
	for i: int in mini(amount, GemBoard.WIDTH):
		stones[i] = GemBoard.JUNK
	_incoming_view.show_cells(stones)
	_incoming_label.text = "%d junk incoming!" % amount if amount > 0 else ""


func _on_topped_out() -> void:
	_my_topped_msec = Time.get_ticks_msec() - _start_msec
	send(Kind.TOPPED, {"t": _my_topped_msec})
	_status.text = "Topped out! Waiting for %s..." % opponent.info.player_name


func _on_opponent_message(kind: int, data: Dictionary) -> void:
	if is_finished():
		return
	match kind:
		Kind.ATTACK:
			var amount: Variant = data.get("n")
			if typeof(amount) == TYPE_INT and _my_topped_msec < 0:
				_game.add_incoming(clampi(amount, 0, GemBoard.MAX_ATTACK))
		Kind.BOARD:
			var their_board: GemBoard = GemBoard.decode(str(data.get("b", "")))
			if their_board != null:
				_their_board.show_cells(their_board.cells)
			var their_incoming: Variant = data.get("i")
			if typeof(their_incoming) == TYPE_INT:
				_their_incoming.text = "%d junk incoming" % their_incoming if their_incoming > 0 else ""
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
