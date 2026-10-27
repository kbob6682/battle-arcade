extends Control
## Lobby: the host picks the game and mode (the guest sees it update live),
## then both press Ready. In bot mode the player also picks the bot's level.

const BANNER_FONT_SIZE: int = 56
const BANNER_FLASHES: int = 3

var _games: Array[GameInfo] = []

@onready var _vs_label: RichTextLabel = %VsLabel
@onready var _game_option: OptionButton = %GameOption
@onready var _mode_option: OptionButton = %ModeOption
@onready var _description: Label = %Description
@onready var _difficulty_row: HBoxContainer = %DifficultyRow
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _ready_button: Button = %ReadyButton
@onready var _opponent_status: Label = %OpponentStatus
@onready var _hint: Label = %HintLabel
@onready var _ping_button: Button = %PingButton
@onready var _ping_label: Label = %PingLabel
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	_games = GameRegistry.visible_games()
	for game: GameInfo in _games:
		_game_option.add_item(game.display_name)
	for value: int in BotOpponent.Difficulty.values():
		_difficulty_option.add_item(BotOpponent.difficulty_name(value))

	_game_option.item_selected.connect(_on_game_selected)
	_mode_option.item_selected.connect(_on_mode_selected)
	_difficulty_option.item_selected.connect(func(index: int) -> void: Session.set_bot_difficulty(index as BotOpponent.Difficulty))
	_ready_button.toggled.connect(Session.set_ready)
	_ping_button.pressed.connect(Net.ping)
	_leave_button.pressed.connect(Session.leave)
	Session.lobby_changed.connect(_refresh)
	Net.ping_result.connect(func(rtt_msec: int) -> void: _ping_label.text = "%d ms" % rtt_msec)
	_refresh()
	if Session.take_back_from_match():
		_show_back_banner()


## "Back to the Lobby" pops in, flashes a few times, then fades. Built in code
## so the lobby layout doesn't change; it ignores the mouse.
func _show_back_banner() -> void:
	var label := Label.new()
	label.text = "Back to the Lobby"
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 0.88, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 10)
	# A full-screen CenterContainer keeps it centred whatever the window size.
	var centre := CenterContainer.new()
	centre.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(centre)
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	centre.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.3, 0.3)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.1)
	for i: int in BANNER_FLASHES:
		tween.tween_property(label, "modulate:a", 0.25, 0.15)
		tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_interval(0.3)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(centre.queue_free)


func _on_game_selected(index: int) -> void:
	var game: GameInfo = _games[index]
	Session.pick(game.id, game.modes[0])


func _on_mode_selected(index: int) -> void:
	var game: GameInfo = Session.current_game()
	if game != null:
		Session.pick(game.id, game.modes[index])


func _refresh() -> void:
	var online: bool = Session.kind == Session.Kind.ONLINE
	var me: PlayerInfo = Net.local_player
	var them_colour: Color = Color.LIGHT_GRAY
	if online and Session.opponent != null:
		them_colour = Session.opponent.info.get_colour()
	_vs_label.clear()
	_vs_label.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_vs_label.push_color(me.get_colour())
	_vs_label.add_text(me.player_name)
	_vs_label.pop()
	_vs_label.add_text("  vs  ")
	_vs_label.push_color(them_colour)
	_vs_label.add_text(Session.opponent_name())
	_vs_label.pop_all()

	var game: GameInfo = Session.current_game()
	_game_option.select(_games.find(game) if game != null else -1)
	_mode_option.clear()
	if game != null:
		for mode: String in game.modes:
			_mode_option.add_item(mode)
		_mode_option.select(game.modes.find(Session.game_mode))
	_description.text = game.description if game != null else ""

	_game_option.disabled = not Session.is_host
	_mode_option.disabled = not Session.is_host
	_difficulty_row.visible = not online
	_difficulty_option.select(Session.bot_difficulty)

	_ready_button.disabled = game == null
	_ready_button.set_pressed_no_signal(Session.local_ready)
	_ready_button.text = "Ready!" if Session.local_ready else "Ready"

	if online:
		var them: String = Session.opponent_name()
		_opponent_status.text = ("%s is ready" if Session.opponent_ready else "%s isn't ready yet") % them
		if Session.is_host:
			_hint.text = "You pick the game."
		elif game == null:
			_hint.text = "Waiting for %s to pick a game..." % them
		else:
			_hint.text = "%s picks the game." % them
	else:
		_opponent_status.text = ""
		_hint.text = "Press Ready to start." if game != null else "No games available."
	_ping_button.visible = online
	_ping_label.visible = online
