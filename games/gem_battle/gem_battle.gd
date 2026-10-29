class_name GemBattle
extends MiniGame
## Gem Battle: each player matches gems on their own board, and chains send
## junk to the opponent. Two modes with the same messages: Drop (DropGame)
## and Swap (SwapGame); both are GemModeGames, so most of this is shared.
##
## Messages (all small; each game is in charge of its own board):
## - ATTACK {n}: junk sent after blocking. Lands after the receiver's next
##   landing (Drop) or next rising row (Swap).
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
const SWAP_MODE: String = "Swap"
## Size of one cell in the Swap mode next-row preview.
const ROW_PREVIEW_CELL: float = 24.0
const DROP_HELP: String = "Arrows or WASD: move, Up/W rotate, Down/S soft drop. Z/X or left/right click rotate either way. Space hard drop."
const SWAP_HELP: String = "Drag a gem onto a neighbour to swap (right click cancels). Only swaps that make a match work. Keys: arrows/WASD move, hold Space + arrow to swap."

var _game: GemModeGame = null
## Swap mode: the selected cell (mouse) or keyboard cursor.
var _cursor: Vector2i = Vector2i(2, GemBoard.HEIGHT - 3)
## Swap mode: a gem was clicked, so clicking a neighbour next swaps them.
var _picked: bool = false
## Swap mode: the mouse button is held after picking a gem.
var _dragging: bool = false
## Swap mode: the outline is showing (hidden after a cancel until the next
## click or key).
var _cursor_shown: bool = true
var _move_dir: int = 0
var _move_timer: float = 0.0
var _start_msec: int = 0
var _my_topped_msec: int = -1
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0
var _sudden_death_shown: bool = false
## Junk each side has sent, after blocking. Theirs is counted from the ATTACKs
## that arrive, so both screens show the same numbers.
var _my_sent: int = 0
var _their_sent: int = 0

@onready var _board_view: GemGridView = %BoardView
@onready var _effects: GemEffects = %Effects
@onready var _my_sent_label: Label = %MySent
@onready var _their_sent_label: Label = %TheirSent
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
	_chain_label.text = ""
	_sudden_death_label.hide()
	_show_incoming(0)
	_their_incoming.text = ""
	_effects.grid = _board_view
	if mode == SWAP_MODE:
		_start_swap()
	else:
		_status.text = DROP_HELP
		_game = DropGame.new()
	_game.changed.connect(_redraw)
	_game.chain_step.connect(_on_chain_step)
	_game.chain_finished.connect(func(_chain: int) -> void: _chain_label.text = "")
	_game.attack_sent.connect(_on_attack_sent)
	_game.junk_dropped.connect(func(_amount: int) -> void: _board_view.shake(4.0))
	_game.incoming_changed.connect(_on_incoming_changed)
	_game.topped_out.connect(_on_topped_out)
	_start_msec = Time.get_ticks_msec()
	# rng is seeded with the shared match seed, so both players get the same gems.
	_game.start(rng)


func _start_swap() -> void:
	_status.text = SWAP_HELP
	var swap_game := SwapGame.new()
	swap_game.swap_rejected.connect(func(_a: Vector2i, _b: Vector2i) -> void: _board_view.shake(3.0))
	_game = swap_game
	# The side panel previews the next row instead of the next pair.
	var preview: Vector2i = swap_game.preview_size()
	_next_view.columns = preview.x
	_next_view.rows = preview.y
	_next_view.custom_minimum_size = Vector2(preview) * ROW_PREVIEW_CELL
	($UI/Margin/Column/Boards/Side/NextTitle as Label).text = "Next row"
	_board_view.gui_input.connect(_on_board_input)


func _process(delta: float) -> void:
	if _game == null or is_finished():
		return
	if _game is SwapGame:
		_handle_swap_keys()
	else:
		_handle_input(delta)
	_game.tick(delta)
	if _game is SwapGame:
		var swap_game: SwapGame = _game as SwapGame
		_board_view.progress = swap_game.rise_progress()
		_board_view.danger = swap_game.is_in_danger()
	if _game.is_sudden_death() and not _sudden_death_shown:
		_sudden_death_shown = true
		_sudden_death_label.show()
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		send(Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_for_view()), "i": _game.incoming})


## Drop mode keys.
func _handle_input(delta: float) -> void:
	var drop: DropGame = _game as DropGame
	if Input.is_action_just_pressed("gem_rotate_cw"):
		drop.rotate(1)
	if Input.is_action_just_pressed("gem_rotate_ccw"):
		drop.rotate(-1)
	if Input.is_action_just_pressed("gem_hard_drop"):
		drop.hard_drop()
	drop.soft_drop = Input.is_action_pressed("gem_soft_drop")
	var dir: int = int(Input.is_action_pressed("gem_right")) - int(Input.is_action_pressed("gem_left"))
	if dir == 0:
		_move_dir = 0
	elif dir != _move_dir:
		_move_dir = dir
		_move_timer = MOVE_REPEAT_DELAY_SEC
		drop.move(dir)
	else:
		_move_timer -= delta
		if _move_timer <= 0.0:
			_move_timer = MOVE_REPEAT_SEC
			drop.move(dir)


## Swap mode keys: a direction moves the cursor, or swaps that way while
## gem_swap is held (the cursor follows the gem). gem_cancel (right click)
## drops a picked gem and hides the outline.
func _handle_swap_keys() -> void:
	if Input.is_action_just_pressed("gem_cancel"):
		_picked = false
		_dragging = false
		_cursor_shown = false
		_board_view.highlight = -1
	var dir := Vector2i.ZERO
	if Input.is_action_just_pressed("gem_left"):
		dir = Vector2i.LEFT
	elif Input.is_action_just_pressed("gem_right"):
		dir = Vector2i.RIGHT
	elif Input.is_action_just_pressed("gem_up"):
		dir = Vector2i.UP
	elif Input.is_action_just_pressed("gem_down"):
		dir = Vector2i.DOWN
	if dir == Vector2i.ZERO:
		return
	_picked = false
	if Input.is_action_pressed("gem_swap"):
		_swap_cursor(dir)
	else:
		_cursor = (_cursor + dir).clamp(Vector2i.ZERO, Vector2i(GemBoard.WIDTH - 1, GemBoard.HEIGHT - 1))
		_show_cursor()


## Swap mode mouse and touch: press on a gem to pick it, then drag onto a
## neighbour, or let go and click the neighbour.
func _on_board_input(event: InputEvent) -> void:
	if is_finished():
		return
	if event.is_action_pressed("primary_click"):
		var cell: Vector2i = _cell_at((event as InputEventMouse).position)
		if cell.x < 0:
			return
		var offset: Vector2i = cell - _cursor
		if _picked and absi(offset.x) + absi(offset.y) == 1:
			_swap_cursor(offset)
			return
		_cursor = cell
		_picked = true
		_dragging = true
		_show_cursor()
	elif event.is_action_released("primary_click"):
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var cell: Vector2i = _cell_at((event as InputEventMouse).position)
		if cell.x < 0 or cell == _cursor:
			return
		var offset: Vector2i = cell - _cursor
		# Dragged into another cell: swap one step that way, along the longer axis.
		var dir: Vector2i = Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y) else Vector2i(0, signi(offset.y))
		_dragging = false
		_swap_cursor(dir)


func _swap_cursor(dir: Vector2i) -> void:
	_picked = false
	var target: Vector2i = _cursor + dir
	if (_game as SwapGame).try_swap(_cursor, target):
		_cursor = target
	_show_cursor()


func _cell_at(local: Vector2) -> Vector2i:
	var index: int = _board_view.cell_at(local)
	if index < 0:
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	return Vector2i(index % GemBoard.WIDTH, index / GemBoard.WIDTH)


func _show_cursor() -> void:
	_cursor_shown = true
	_board_view.highlight = _cursor.y * GemBoard.WIDTH + _cursor.x


func _redraw() -> void:
	_board_dirty = true
	_board_view.show_cells(_game.cells_for_view())
	_next_view.show_cells(_game.preview_cells())
	if _game is SwapGame and _cursor_shown:
		_show_cursor()


func _on_chain_step(chain: int, groups: Array[PackedInt32Array], colours: Array[int]) -> void:
	_chain_label.text = "%d chain!" % chain if chain > 1 else ""
	_effects.show_clear(chain, groups, colours)


func _on_attack_sent(amount: int) -> void:
	send(Kind.ATTACK, {"n": amount})
	_my_sent += amount
	_my_sent_label.text = "Junk sent: %d" % _my_sent
	_effects.show_attack(amount)


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
			if typeof(amount) != TYPE_INT:
				return
			var junk: int = clampi(amount, 0, GemBoard.MAX_ATTACK)
			_their_sent += junk
			_their_sent_label.text = "Junk sent: %d" % _their_sent
			if _my_topped_msec < 0:
				_game.add_incoming(junk)
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
