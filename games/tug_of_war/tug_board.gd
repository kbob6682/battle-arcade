class_name TugBoard
extends RefCounted
## One player's side of the Tug of War field: the blocks between their back
## edge and the middle line, plus the piece shapes. Plain data with no nodes,
## so the game, the bots and the tests share it.
##
## Cells are addressed by depth d (0 is next to the middle line, width - 1 is
## the back edge) and row r (0 is the top). Pieces travel towards the line,
## so "falling" means d getting smaller. Each side's width changes as the line
## moves; the two widths always add up to TOTAL_WIDTH.

const ROWS: int = 10
const TOTAL_WIDTH: int = 20
const START_WIDTH: int = 10
const EMPTY: int = 0
## Piece types are 1 to PIECE_TYPES (I, O, T, S, Z, J, L).
const PIECE_TYPES: int = 7

## Each piece's cells in its own box, x towards the line and y down, as it
## would sit on screen for the player on the left. The box size is used for
## rotating.
const SHAPES: Array[Array] = [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], # O
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], # Z
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # J
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], # L
]
const BOX_SIZES: Array[int] = [4, 2, 3, 3, 3, 3, 3]

var width: int = START_WIDTH
## Depth-major: index = d * ROWS + r.
var cells: PackedInt32Array = PackedInt32Array()


func _init(start_width: int = START_WIDTH) -> void:
	width = start_width
	cells.resize(width * ROWS)


## A piece's cells in its box after turning it clockwise `rotation` times
## (0 to 3).
static func piece_offsets(type: int, rotation: int) -> Array[Vector2i]:
	var box: int = BOX_SIZES[type - 1]
	var result: Array[Vector2i] = []
	for cell: Vector2i in SHAPES[type - 1]:
		var turned: Vector2i = cell
		for i: int in posmod(rotation, 4):
			turned = Vector2i(box - 1 - turned.y, turned.x)
		result.append(turned)
	return result


## Board cells covered by a piece whose box sits at pos (d, r of the box's
## corner nearest the back edge and top). x in the box points towards the line.
static func piece_cells(type: int, rotation: int, pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in piece_offsets(type, rotation):
		result.append(Vector2i(pos.x - offset.x, pos.y + offset.y))
	return result


## Rebuilds a side from encode() output (the opponent's snapshot). Returns
## null if it isn't valid (it's untrusted input).
static func decode(text: String, side_width: int) -> TugBoard:
	if side_width < 0 or side_width > TOTAL_WIDTH or text.length() != side_width * ROWS:
		return null
	var board := TugBoard.new(side_width)
	for i: int in text.length():
		var value: int = text.unicode_at(i) - 48 # "0"
		if value < EMPTY or value > PIECE_TYPES:
			return null
		board.cells[i] = value
	return board


static func encode_cells(values: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return "".join(parts)


func in_bounds(d: int, r: int) -> bool:
	return d >= 0 and d < width and r >= 0 and r < ROWS


func get_cell(d: int, r: int) -> int:
	return cells[d * ROWS + r]


func set_cell(d: int, r: int, value: int) -> void:
	cells[d * ROWS + r] = value


func is_free(cell: Vector2i) -> bool:
	return in_bounds(cell.x, cell.y) and get_cell(cell.x, cell.y) == EMPTY


func fits(cells_to_check: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells_to_check:
		if not is_free(cell):
			return false
	return true


func copy() -> TugBoard:
	var board := TugBoard.new(width)
	board.cells = cells.duplicate()
	return board


## Depths whose column is full from top to bottom, nearest the line first.
func full_columns() -> Array[int]:
	var result: Array[int] = []
	for d: int in width:
		var full: bool = true
		for r: int in ROWS:
			if get_cell(d, r) == EMPTY:
				full = false
				break
		if full:
			result.append(d)
	return result


## Removes the columns at these depths; everything behind them moves up
## towards the line, and empty columns fill in at the back.
func clear_columns(depths: Array[int]) -> void:
	var sorted: Array[int] = depths.duplicate()
	sorted.sort()
	sorted.reverse()
	for d: int in sorted:
		cells = cells.slice(0, d * ROWS) + cells.slice((d + 1) * ROWS)
	var empty: PackedInt32Array = PackedInt32Array()
	empty.resize(sorted.size() * ROWS)
	cells.append_array(empty)


## The line moved away: n more empty columns at the back (never past the
## whole field).
func grow(n: int) -> void:
	var added: int = clampi(n, 0, TOTAL_WIDTH - width)
	width += added
	cells.resize(width * ROWS)


## The line moved into this side by n: the back n columns go. Returns false
## if any of them had blocks in (pushed off the back: this side has lost).
func shrink(n: int) -> bool:
	var removed: int = clampi(n, 0, width)
	var ok: bool = removed == n
	for i: int in range((width - removed) * ROWS, width * ROWS):
		if cells[i] != EMPTY:
			ok = false
	width -= removed
	cells.resize(width * ROWS)
	return ok


## How far the stack in row r reaches from the line (0 if the row is empty).
func row_depth(r: int) -> int:
	for d: int in range(width - 1, -1, -1):
		if get_cell(d, r) != EMPTY:
			return d + 1
	return 0
