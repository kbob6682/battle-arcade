extends "res://tests/test_case.gd"
## Tug of War rules, stepped with fixed times.


func started(seed_value: int = 42) -> TugGame:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = seed_value
	var game := TugGame.new()
	game.start(pieces_rng)
	return game


## Ticks until the next piece appears (or the side tops out).
func settle(game: TugGame) -> void:
	for i: int in 200:
		if game.phase != TugGame.Phase.CLEARING:
			return
		game.tick(0.05)


## Fills a side's column completely except the given rows.
func fill_column(board: TugBoard, d: int, gaps: Array[int] = []) -> void:
	for r: int in TugBoard.ROWS:
		if not gaps.has(r):
			board.set_cell(d, r, 1)


func test_shapes_have_four_cells_in_every_rotation() -> void:
	for type: int in range(1, TugBoard.PIECE_TYPES + 1):
		for rotation: int in 4:
			var cells: Array[Vector2i] = TugBoard.piece_offsets(type, rotation)
			check_eq(cells.size(), 4, "type %d rotation %d" % [type, rotation])
			var box: int = TugBoard.BOX_SIZES[type - 1]
			for cell: Vector2i in cells:
				check(cell.x >= 0 and cell.x < box and cell.y >= 0 and cell.y < box, "inside its box")
		check_eq(TugBoard.piece_offsets(type, 4), TugBoard.piece_offsets(type, 0), "four turns come back round")


func test_same_seed_gives_same_pieces() -> void:
	var a: TugGame = started(7)
	var b: TugGame = started(7)
	for i: int in 6:
		check_eq(a.piece_type, b.piece_type, "piece %d" % i)
		check_eq(a.next_type, b.next_type, "next %d" % i)
		a.hard_drop()
		b.hard_drop()
		settle(a)
		settle(b)
	# Each bag of 7 has every piece once.
	var game: TugGame = started(3)
	var bag: Array[int] = [game.piece_type, game.next_type]
	for i: int in 5:
		bag.append(game._take_from_bag())
	bag.sort()
	check_eq(bag, [1, 2, 3, 4, 5, 6, 7] as Array[int], "first bag has all seven")


func test_piece_spawns_at_the_back_and_travels_to_the_line() -> void:
	var game: TugGame = started()
	var deepest: int = 0
	for cell: Vector2i in game.piece_cells():
		deepest = maxi(deepest, cell.x)
	check_eq(deepest, TugBoard.START_WIDTH - 1, "starts at the back edge")
	var start: Vector2i = game.pos
	game.tick(TugGame.BASE_STEP_SEC + 0.01)
	check_eq(game.pos, start + Vector2i(-1, 0), "one step towards the line")
	game.hard_drop()
	var nearest: int = 99
	for r: int in TugBoard.ROWS:
		for d: int in game.board.width:
			if game.board.get_cell(d, r) != TugBoard.EMPTY:
				nearest = mini(nearest, d)
	check_eq(nearest, 0, "lands against the line")


func test_moving_and_rotating() -> void:
	var game: TugGame = started()
	var start: Vector2i = game.pos
	check(game.move(-1), "moves up")
	check_eq(game.pos, start + Vector2i(0, -1), "one row up")
	check(game.move(1) and game.move(1), "moves down")
	for i: int in TugBoard.ROWS:
		game.move(1)
	for cell: Vector2i in game.piece_cells():
		check(cell.y < TugBoard.ROWS, "stays on the field")
	var before: int = game.rotation
	if game.piece_type != 2:
		check(game.rotate(1), "turns at the bottom edge (nudged if needed)")
		check_eq(game.rotation, posmod(before + 1, 4), "one turn")
	check(game.board.fits(game.piece_cells()), "still fits")


func test_a_full_column_clears_and_moves_the_line() -> void:
	var game: TugGame = started()
	# Column 0 full except where the piece will land.
	var cleared: Array[int] = []
	var widths: Array[int] = []
	game.columns_cleared.connect(func(count: int, _depths: Array[int]) -> void: cleared.append(count))
	game.line_moved.connect(func(width: int) -> void: widths.append(width))
	var landing: Array[Vector2i] = game.landing_cells()
	var gaps: Array[int] = []
	for cell: Vector2i in landing:
		if cell.x == 0:
			gaps.append(cell.y)
	fill_column(game.board, 0, gaps)
	game.board.set_cell(1, 0, 3)
	game.hard_drop()
	check_eq(cleared, [1] as Array[int], "one column cleared")
	check_eq(game.board.width, TugBoard.START_WIDTH + 1, "the line moved one step away")
	check_eq(widths, [TugBoard.START_WIDTH + 1], "reported")
	check_eq(game.board.get_cell(0, 0), 3, "the block behind moved up to the line")


func test_being_pushed_shrinks_the_side() -> void:
	var game: TugGame = started()
	game.board.set_cell(2, 5, 4)
	game.push_line(2)
	check_eq(game.board.width, TugBoard.START_WIDTH - 2, "two columns narrower")
	check_eq(game.board.get_cell(2, 5), 4, "the stack keeps its place by the line")
	check(not game.is_topped(), "still playing")
	check(game.board.fits(game.piece_cells()), "the piece was moved to fit")


func test_pushed_off_the_back_tops_out() -> void:
	var game: TugGame = started()
	var topped: Array[bool] = [false]
	game.topped_out.connect(func() -> void: topped[0] = true)
	game.board.set_cell(TugBoard.START_WIDTH - 1, 0, 2)
	game.push_line(1)
	check(topped[0] and game.is_topped(), "a block pushed off the back loses")


func test_tops_out_when_a_new_piece_has_no_room() -> void:
	var game: TugGame = started()
	for d: int in range(1, game.board.width):
		for r: int in TugBoard.ROWS:
			if r != 0:
				game.board.set_cell(d, r, 5)
	var topped: Array[bool] = [false]
	game.topped_out.connect(func() -> void: topped[0] = true)
	for i: int in 5:
		game.hard_drop()
		settle(game)
	check(topped[0], "topped out")


func test_widths_always_add_up() -> void:
	# Two sides clearing at the same time still agree on where the line is.
	var a := TugBoard.new()
	var b := TugBoard.new()
	a.grow(2)
	b.shrink(2)
	b.grow(1)
	a.shrink(1)
	check_eq(a.width + b.width, TugBoard.TOTAL_WIDTH, "same total")
	a.grow(50)
	check_eq(a.width, TugBoard.TOTAL_WIDTH, "never wider than the field")


func test_speeds_up_until_sudden_death() -> void:
	var game: TugGame = started()
	check(is_equal_approx(game.step_interval(), TugGame.BASE_STEP_SEC), "starts slow")
	game.elapsed = TugGame.SPEEDUP_EVERY_SEC
	check(game.step_interval() < TugGame.BASE_STEP_SEC, "faster after 45 s")
	game.elapsed = TugGame.SUDDEN_DEATH_SEC + 60.0
	check(game.is_sudden_death(), "sudden death")
	check(is_equal_approx(game.step_interval(), TugGame.SUDDEN_DEATH_STEP_SEC), "capped")


func test_snapshots_round_trip_and_reject_junk() -> void:
	var game: TugGame = started()
	game.board.set_cell(0, 3, 6)
	var text: String = TugBoard.encode_cells(game.board.cells)
	var back: TugBoard = TugBoard.decode(text, game.board.width)
	check(back != null and back.get_cell(0, 3) == 6, "round trip")
	check(TugBoard.decode(text, game.board.width + 1) == null, "wrong width")
	check(TugBoard.decode(text.substr(1) + "9", game.board.width) == null, "bad value")
	check(TugBoard.decode("", -1) == null, "negative width")
