class_name GemBoard
extends RefCounted
## One player's Gem Battle board: the grid plus the rules that are the same in
## every mode (gravity, matching, junk, chains, attack sizes). Plain data with
## no nodes, so Drop mode, Swap mode and the bots all share it, and the rules
## can be tested headlessly. Row 0 is the top; gravity pulls towards the bottom.

const WIDTH: int = 6
const HEIGHT: int = 12
const EMPTY: int = 0
## Gem colours are 1 to COLOURS.
const COLOURS: int = 5
## Grey stone: never matches, breaks when a match touches it.
const JUNK: int = 6
const MIN_GROUP: int = 3
const MAX_ATTACK: int = 24

## Row-major, index = y * WIDTH + x.
var cells: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	cells.resize(WIDTH * HEIGHT)


static func is_gem(value: int) -> bool:
	return value >= 1 and value <= COLOURS


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT


## Junk sent for a chain of this many steps: 1, 2, 4, 8, 16, then capped at MAX_ATTACK.
static func attack_for_chain(chain: int) -> int:
	if chain <= 0:
		return 0
	return mini(1 << mini(chain - 1, 30), MAX_ATTACK)


## Blocking: your attack first cancels junk that's on its way to you.
## Returns Vector2i(junk still incoming, junk to send to the opponent).
static func cancel_incoming(incoming: int, attack: int) -> Vector2i:
	var cancelled: int = mini(incoming, attack)
	return Vector2i(incoming - cancelled, attack - cancelled)


## Rebuilds a board from encode() output, e.g. from the opponent's snapshot.
## Returns null if the text isn't a valid board (it's untrusted input).
static func decode(text: String) -> GemBoard:
	if text.length() != WIDTH * HEIGHT:
		return null
	var board := GemBoard.new()
	for i: int in text.length():
		var value: int = text.unicode_at(i) - 48 # "0"
		if value < EMPTY or value > JUNK:
			return null
		board.cells[i] = value
	return board


func get_cell(x: int, y: int) -> int:
	return cells[y * WIDTH + x]


func set_cell(x: int, y: int, value: int) -> void:
	cells[y * WIDTH + x] = value


func copy() -> GemBoard:
	var board := GemBoard.new()
	board.cells = cells.duplicate()
	return board


## One character per cell ("0" empty, "1"-"5" gems, "6" junk), for snapshots.
func encode() -> String:
	return encode_cells(cells)


static func encode_cells(values: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return "".join(parts)


## Filled cells in a column. On a settled board that's the stack height.
func column_height(x: int) -> int:
	var count: int = 0
	for y: int in HEIGHT:
		if get_cell(x, y) != EMPTY:
			count += 1
	return count


## Drops every gem and junk straight down into the lowest gap, so there are no
## holes. Returns true if anything moved.
func apply_gravity() -> bool:
	var moved: bool = false
	for x: int in WIDTH:
		var write_y: int = HEIGHT - 1
		for y: int in range(HEIGHT - 1, -1, -1):
			var value: int = get_cell(x, y)
			if value == EMPTY:
				continue
			if y != write_y:
				set_cell(x, write_y, value)
				set_cell(x, y, EMPTY)
				moved = true
			write_y -= 1
	return moved


## Groups of MIN_GROUP or more touching gems of one colour (up, down, left and
## right; not diagonal). Each group is a list of cell indexes.
func find_groups() -> Array[PackedInt32Array]:
	var groups: Array[PackedInt32Array] = []
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(cells.size())
	for start: int in cells.size():
		if seen[start] == 1 or not is_gem(cells[start]):
			continue
		var colour: int = cells[start]
		var group: PackedInt32Array = PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var index: int = stack.pop_back()
			group.append(index)
			for next: int in _neighbours(index):
				if seen[next] == 0 and cells[next] == colour:
					seen[next] = 1
					stack.append(next)
		if group.size() >= MIN_GROUP:
			groups.append(group)
	return groups


## Removes the groups, plus any junk touching them. Returns how many gems
## (not junk) were cleared.
func clear_groups(groups: Array[PackedInt32Array]) -> int:
	var gems: int = 0
	for group: PackedInt32Array in groups:
		for index: int in group:
			for next: int in _neighbours(index):
				if cells[next] == JUNK:
					cells[next] = EMPTY
		for index: int in group:
			cells[index] = EMPTY
		gems += group.size()
	return gems


## One step of a chain: let everything fall, then clear whatever matches.
## Returns the number of gems cleared; 0 means the board has settled and any
## chain is over. Step by step so the game can animate each clear.
func resolve_step() -> int:
	apply_gravity()
	var groups: Array[PackedInt32Array] = find_groups()
	if groups.is_empty():
		return 0
	return clear_groups(groups)


## Resolves every chain step at once (for bots and tests). Returns the chain length.
func resolve() -> int:
	var chain: int = 0
	while resolve_step() > 0:
		chain += 1
	return chain


## Drop mode: junk falls onto the stacks from the top. Each full WIDTH of junk
## covers every column once; the rest go into different random columns. Returns
## how many didn't fit because their column was full. rng is this player's own
## (junk placement doesn't need to match the other side). Expects a settled board.
func drop_junk(count: int, rng: RandomNumberGenerator) -> int:
	var overflow: int = 0
	while count > 0:
		var columns: Array[int] = []
		for x: int in WIDTH:
			columns.append(x)
		if count < WIDTH:
			_shuffle(columns, rng)
			columns.resize(count)
		for x: int in columns:
			var height: int = column_height(x)
			if height >= HEIGHT:
				overflow += 1
			else:
				set_cell(x, HEIGHT - 1 - height, JUNK)
		count -= columns.size()
	return overflow


func _neighbours(index: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var x: int = index % WIDTH
	@warning_ignore("integer_division")
	var y: int = index / WIDTH
	if x > 0:
		result.append(index - 1)
	if x < WIDTH - 1:
		result.append(index + 1)
	if y > 0:
		result.append(index - WIDTH)
	if y < HEIGHT - 1:
		result.append(index + WIDTH)
	return result


## Fisher-Yates with the given RNG, so the order is reproducible from its seed.
static func _shuffle(items: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var held: int = items[i]
		items[i] = items[j]
		items[j] = held
