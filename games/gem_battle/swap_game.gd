class_name SwapGame
extends GemModeGame
## Swap mode for one board: swapping neighbouring gems to make matches,
## chains, rows rising from the bottom, junk rows, and the speed-up. Shared
## signals and fields are in GemModeGame.
##
## Swaps: two neighbouring gems of different colours, and only if the swap
## makes a match; otherwise nothing moves (swap_rejected). No swapping while a
## chain is clearing.
##
## Rising: a new row pushes in from the bottom every rise_interval() seconds,
## paused while a chain clears. The start board and every new row come from
## the shared seed, so both players get the same ones. A row that has to push
## a gem out of the top row tops the board out.
##
## Junk: attacks wait in `incoming` until the next row rises. A chain first
## cancels incoming junk (blocking). Then up to MAX_JUNK_ROWS rows of stone
## push in under the board (a partial row is stone mixed with gems), with the
## new row below them.
##
## Attacks: a plain 3-match sends nothing (matches are easy in Swap); bigger
## groups send 1 per extra gem; chains use GemBoard.attack_for. Matches made
## by a rising row clear but never attack.

## Two gems were swapped and made a match.
signal swapped(a: Vector2i, b: Vector2i)
signal swap_rejected(a: Vector2i, b: Vector2i)
## A row pushed in from the bottom (rows includes any junk rows).
signal rows_risen(rows: int)

enum Phase { NOT_STARTED, READY, RESOLVING, TOPPED }

## Filled rows at the start.
const START_ROWS: int = 6
## Seconds per new row. Steps up every SPEEDUP_EVERY_SEC by the same factor,
## reaching the sudden-death speed after SPEEDUP_STEPS steps (3:00):
## 6.0, 4.6, 3.5, 2.6, then 2.0.
const BASE_RISE_SEC: float = 6.0
const SPEEDUP_EVERY_SEC: float = 45.0
const SPEEDUP_STEPS: int = 4
const SUDDEN_DEATH_SEC: float = SPEEDUP_EVERY_SEC * SPEEDUP_STEPS
const SUDDEN_DEATH_RISE_SEC: float = 2.0
## Most junk rows that push in at once; the rest waits for the next rise.
const MAX_JUNK_ROWS: int = 3
## Pauses so players can see what happened: after a swap, between chain
## steps, and after junk rows push in.
const SWAP_PAUSE_SEC: float = 0.12
const CHAIN_STEP_SEC: float = 0.4
const JUNK_PAUSE_SEC: float = 0.3

var phase: Phase = Phase.NOT_STARTED
## The row that pushes in next, shown under the board.
var next_row: PackedInt32Array = PackedInt32Array()

## Seeded with the shared match seed: the start board and the rising rows.
var _rows_rng: RandomNumberGenerator
## Junk rows' stone positions and gems. This player's own.
var _junk_rng: RandomNumberGenerator
var _rise_timer: float = 0.0
var _step_timer: float = 0.0
var _chain: int = 0
var _chain_extra_gems: int = 0
## The chain was started by a swap, so it can attack (not by a rising row).
var _player_chain: bool = false


## Junk sent for a Swap chain: nothing for plain 3-matches, 1 per gem beyond
## 3 in a single clear, and GemBoard.attack_for from a 2-chain up.
static func attack_for(chain: int, extra_gems: int) -> int:
	if chain <= 0:
		return 0
	if chain == 1:
		return mini(extra_gems, GemBoard.MAX_ATTACK)
	return GemBoard.attack_for(chain, extra_gems)


## Whether swapping cells a and b is allowed and makes a match. Used by the
## game and the bots. Leaves the board as it was.
static func is_matching_swap(b: GemBoard, a: Vector2i, c: Vector2i) -> bool:
	if not GemBoard.in_bounds(a.x, a.y) or not GemBoard.in_bounds(c.x, c.y):
		return false
	if absi(a.x - c.x) + absi(a.y - c.y) != 1:
		return false
	var first: int = b.get_cell(a.x, a.y)
	var second: int = b.get_cell(c.x, c.y)
	if not GemBoard.is_gem(first) or not GemBoard.is_gem(second) or first == second:
		return false
	b.set_cell(a.x, a.y, second)
	b.set_cell(c.x, c.y, first)
	var matched: bool = b.has_group_at(a) or b.has_group_at(c)
	b.set_cell(a.x, a.y, first)
	b.set_cell(c.x, c.y, second)
	return matched


func start(shared_rng: RandomNumberGenerator, junk_rng: RandomNumberGenerator = null) -> void:
	_rows_rng = shared_rng
	_junk_rng = _own_rng(junk_rng)
	_fill_start_board()
	next_row = _make_row()
	phase = Phase.READY
	changed.emit()


func tick(delta: float) -> void:
	if phase == Phase.NOT_STARTED or phase == Phase.TOPPED:
		return
	elapsed += delta
	match phase:
		Phase.READY:
			_rise_timer += delta
			if _rise_timer >= rise_interval():
				_rise_timer = 0.0
				_rise()
		Phase.RESOLVING:
			_step_timer -= delta
			if _step_timer <= 0.0:
				_resolve_next()


func rise_interval() -> float:
	var level: int = mini(int(elapsed / SPEEDUP_EVERY_SEC), SPEEDUP_STEPS)
	return BASE_RISE_SEC * pow(SUDDEN_DEATH_RISE_SEC / BASE_RISE_SEC, float(level) / SPEEDUP_STEPS)


## How far the next row is towards rising, 0 to 1.
func rise_progress() -> float:
	return clampf(_rise_timer / rise_interval(), 0.0, 1.0)


func is_sudden_death() -> bool:
	return elapsed >= SUDDEN_DEATH_SEC


func is_topped() -> bool:
	return phase == Phase.TOPPED


## Gems near the top: the next rows could top the board out.
func is_in_danger() -> bool:
	for x: int in GemBoard.WIDTH:
		if board.get_cell(x, 1) != GemBoard.EMPTY:
			return true
	return false


func can_swap() -> bool:
	return phase == Phase.READY


## Swaps two neighbouring gems if that makes a match. Returns whether it did.
func try_swap(a: Vector2i, b: Vector2i) -> bool:
	if phase != Phase.READY:
		return false
	if not is_matching_swap(board, a, b):
		swap_rejected.emit(a, b)
		return false
	var first: int = board.get_cell(a.x, a.y)
	board.set_cell(a.x, a.y, board.get_cell(b.x, b.y))
	board.set_cell(b.x, b.y, first)
	_begin_resolving(true, SWAP_PAUSE_SEC)
	changed.emit()
	swapped.emit(a, b)
	return true


func preview_cells() -> PackedInt32Array:
	return next_row


func preview_size() -> Vector2i:
	return Vector2i(GemBoard.WIDTH, 1)


func _begin_resolving(by_player: bool, pause: float) -> void:
	phase = Phase.RESOLVING
	_player_chain = by_player
	_chain = 0
	_chain_extra_gems = 0
	_step_timer = pause


func _resolve_next() -> void:
	board.apply_gravity()
	var groups: Array[PackedInt32Array] = board.find_groups()
	if not groups.is_empty():
		var colours: Array[int] = []
		for group: PackedInt32Array in groups:
			colours.append(board.cells[group[0]])
		board.clear_groups(groups)
		_chain += 1
		_chain_extra_gems += GemBoard.extra_gems(groups)
		_step_timer = CHAIN_STEP_SEC
		changed.emit()
		chain_step.emit(_chain, groups, colours)
		return
	phase = Phase.READY
	if _chain > 0:
		var chain: int = _chain
		_chain = 0
		chain_finished.emit(chain)
		if _player_chain:
			_block_and_attack(attack_for(chain, _chain_extra_gems))
	_chain_extra_gems = 0
	changed.emit()


## Pushes in any waiting junk rows, then the next row. Tops out if a row has
## to push a gem out of the top.
func _rise() -> void:
	var junk: int = mini(incoming, MAX_JUNK_ROWS * GemBoard.WIDTH)
	var rows: Array[PackedInt32Array] = _junk_rows(junk)
	rows.append(next_row)
	if junk > 0:
		incoming -= junk
		incoming_changed.emit(incoming)
	for row: PackedInt32Array in rows:
		if not board.push_row(row):
			phase = Phase.TOPPED
			changed.emit()
			topped_out.emit()
			return
	next_row = _make_row()
	if junk > 0:
		junk_dropped.emit(junk)
	rows_risen.emit(rows.size())
	# A new row can line up with the gems above it; that clears but doesn't attack.
	if junk > 0 or not board.find_groups().is_empty():
		_begin_resolving(false, JUNK_PAUSE_SEC if junk > 0 else SWAP_PAUSE_SEC)
	changed.emit()


## Rows of stone for this much junk: a partial row (stone mixed with gems)
## first so it ends up highest, then full rows.
func _junk_rows(junk: int) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	@warning_ignore("integer_division")
	var full: int = junk / GemBoard.WIDTH
	var partial: int = junk % GemBoard.WIDTH
	if partial > 0:
		var columns: Array[int] = []
		for x: int in GemBoard.WIDTH:
			columns.append(x)
		GemBoard.shuffle(columns, _junk_rng)
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(GemBoard.WIDTH)
		for x: int in GemBoard.WIDTH:
			row[x] = _junk_rng.randi_range(1, GemBoard.COLOURS)
		for i: int in partial:
			row[columns[i]] = GemBoard.JUNK
		rows.append(row)
	for i: int in full:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(GemBoard.WIDTH)
		row.fill(GemBoard.JUNK)
		rows.append(row)
	return rows


## The bottom START_ROWS rows, with no matches already made.
func _fill_start_board() -> void:
	for y: int in range(GemBoard.HEIGHT - START_ROWS, GemBoard.HEIGHT):
		for x: int in GemBoard.WIDTH:
			var colour: int = _rows_rng.randi_range(1, GemBoard.COLOURS)
			for attempt: int in GemBoard.COLOURS:
				board.set_cell(x, y, colour)
				if not board.has_group_at(Vector2i(x, y)):
					break
				colour = colour % GemBoard.COLOURS + 1


## A new row with no three of a colour in a line.
func _make_row() -> PackedInt32Array:
	var row: PackedInt32Array = PackedInt32Array()
	row.resize(GemBoard.WIDTH)
	for x: int in GemBoard.WIDTH:
		var colour: int = _rows_rng.randi_range(1, GemBoard.COLOURS)
		if x >= 2 and row[x - 1] == colour and row[x - 2] == colour:
			colour = colour % GemBoard.COLOURS + 1
		row[x] = colour
	return row
