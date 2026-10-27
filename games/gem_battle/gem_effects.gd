class_name GemEffects
extends Control
## Clear effects over a GemGridView: cleared gems flash and burst into
## pieces, words pop up for each clear ("Nice!", "Great! +1"), big chain text,
## and a callout when junk is sent. Purely visual; the game works without it.
## Sits on top of the board and ignores the mouse.

const BURST_SEC: float = 0.35
const PIECES_PER_GEM: int = 6
const PIECE_SPEED: float = 220.0
const PIECE_GRAVITY: float = 600.0
const POPUP_SEC: float = 0.8
const POPUP_RISE: float = 50.0
## Chain text colours: 2-chain, 3, 4, 5 and up.
const CHAIN_COLOURS: Array[Color] = [
	Color(1, 0.88, 0.3), Color(1, 0.6, 0.2), Color(1, 0.3, 0.3), Color(0.8, 0.45, 1),
]

## The board the effects line up with.
var grid: GemGridView = null

## Burst pieces: [position, velocity, colour, age].
var _pieces: Array[Array] = []
## Flashes on cleared cells: [position, age].
var _flashes: Array[Array] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


## Words for a clear of this many gems; the +N is the bonus junk.
static func clear_word(gems: int) -> String:
	var bonus: int = gems - GemBoard.MIN_GROUP
	match bonus:
		0:
			return "Nice!"
		1:
			return "Great! +1"
		2:
			return "Awesome! +2"
	return "Amazing! +%d" % bonus


## One chain step: flash and burst every cleared gem, a word at each group,
## and from a 2-chain up the big chain text (plus a shake from 3).
func show_clear(chain: int, groups: Array[PackedInt32Array], colours: Array[int]) -> void:
	if grid == null:
		return
	var cell: float = grid.cell_size()
	for g: int in groups.size():
		var colour: Color = GemGridView.GEM_COLOURS[colours[g] - 1]
		var centre := Vector2.ZERO
		for index: int in groups[g]:
			var at: Vector2 = grid.cell_centre(index)
			centre += at
			_flashes.append([at, 0.0])
			for k: int in PIECES_PER_GEM:
				var velocity: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * PIECE_SPEED * _rng.randf_range(0.5, 1.0)
				_pieces.append([at, velocity + Vector2(0, -80), colour, 0.0])
		centre /= groups[g].size()
		_popup(clear_word(groups[g].size()), centre, colour.lightened(0.4), int(cell * 0.45))
	if chain >= 2:
		var chain_colour: Color = CHAIN_COLOURS[mini(chain - 2, CHAIN_COLOURS.size() - 1)]
		_chain_text("%d CHAIN!" % chain, chain_colour, int(cell * 0.7) + 8 * (chain - 2))
	if chain >= 3:
		grid.shake(2.0 + 2.0 * chain)


## Junk sent: a callout that shoots off to the right, towards the opponent.
func show_attack(amount: int) -> void:
	var label: Label = _make_label("%d junk >>" % amount, Color(1, 0.55, 0.3), 26)
	label.position = Vector2(size.x * 0.55, size.y * 0.35)
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:x", size.x + 40.0, POPUP_SEC).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_SEC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _process(delta: float) -> void:
	if _pieces.is_empty() and _flashes.is_empty():
		return
	for piece: Array in _pieces:
		piece[1] += Vector2(0, PIECE_GRAVITY * delta)
		piece[0] += piece[1] * delta
		piece[3] += delta
	for flash: Array in _flashes:
		flash[1] += delta
	_pieces = _pieces.filter(func(piece: Array) -> bool: return piece[3] < BURST_SEC)
	_flashes = _flashes.filter(func(flash: Array) -> bool: return flash[1] < BURST_SEC)
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	var cell: float = grid.cell_size()
	for flash: Array in _flashes:
		var t: float = flash[1] / BURST_SEC
		draw_circle(flash[0], cell * (0.45 + 0.3 * t), Color(1, 1, 1, 0.8 * (1.0 - t)))
	for piece: Array in _pieces:
		var t: float = piece[3] / BURST_SEC
		var colour: Color = piece[2]
		colour.a = 1.0 - t
		var half: float = cell * 0.09 * (1.0 - 0.5 * t)
		draw_rect(Rect2(piece[0] - Vector2(half, half), Vector2(half, half) * 2.0), colour)


func _popup(text: String, at: Vector2, colour: Color, font_size: int) -> void:
	var label: Label = _make_label(text, colour, font_size)
	label.position = at - label.size / 2.0
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_SEC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_SEC * 0.5).set_delay(POPUP_SEC * 0.5)
	tween.chain().tween_callback(label.queue_free)


## Big text in the middle of the board that pops in, holds, then fades.
func _chain_text(text: String, colour: Color, font_size: int) -> void:
	var label: Label = _make_label(text, colour, font_size)
	label.position = (size - label.size) / 2.0
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.4, 0.4)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.1)
	tween.tween_interval(0.35)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(label.queue_free)


func _make_label(text: String, colour: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(int(font_size / 6.0), 4))
	add_child(label)
	# Size the label to its text now, so it can be centred straight away.
	label.reset_size()
	return label
