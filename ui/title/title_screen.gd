extends Control
## Title screen: pick a name and colour, then host or join a room.
## For now it also shows the connection log and a ping test once connected.

const LOG_MAX_LINES: int = 200
const SWATCH_SIZE: Vector2 = Vector2(36, 36)

var _player: PlayerInfo
var _swatch_group: ButtonGroup = ButtonGroup.new()

@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_hint: Label = %NameHint
@onready var _colour_row: HBoxContainer = %ColourRow
@onready var _host_button: Button = %HostButton
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _join_button: Button = %JoinButton
@onready var _bot_button: Button = %BotButton
@onready var _room_code_label: Label = %RoomCodeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _connected_row: HBoxContainer = %ConnectedRow
@onready var _ping_button: Button = %PingButton
@onready var _leave_button: Button = %LeaveButton
@onready var _log_view: RichTextLabel = %LogView


func _ready() -> void:
	_player = PlayerInfo.load_saved()
	_name_edit.max_length = PlayerInfo.NAME_MAX
	_name_edit.text = _player.player_name
	_build_swatches()

	_name_edit.text_changed.connect(_on_name_changed)
	_code_edit.text_changed.connect(_on_code_changed)
	_code_edit.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_ping_button.pressed.connect(Net.ping)
	_leave_button.pressed.connect(_on_leave_pressed)

	Net.state_changed.connect(_on_net_state_changed)
	Net.room_code_ready.connect(_on_room_code_ready)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.ping_result.connect(_on_ping_result)
	Net.log_line.connect(_append_log)

	_status_label.text = ""
	_room_code_label.text = ""
	_refresh()


func _build_swatches() -> void:
	for i: int in PlayerInfo.COLOURS.size():
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = _swatch_group
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = "Colour %d" % (i + 1)
		var colour: Color = PlayerInfo.COLOURS[i]
		swatch.add_theme_stylebox_override("normal", _swatch_style(colour, false))
		swatch.add_theme_stylebox_override("hover", _swatch_style(colour.lightened(0.15), false))
		swatch.add_theme_stylebox_override("pressed", _swatch_style(colour, true))
		swatch.add_theme_stylebox_override("hover_pressed", _swatch_style(colour, true))
		swatch.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		swatch.button_pressed = i == _player.colour_index
		swatch.pressed.connect(func() -> void: _player.colour_index = i)
		_colour_row.add_child(swatch)


func _swatch_style(colour: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(6)
	if selected:
		style.set_border_width_all(4)
		style.border_color = Color.WHITE
	return style


func _on_name_changed(_text: String) -> void:
	_refresh()


func _on_code_changed(text: String) -> void:
	var caret: int = _code_edit.caret_column
	_code_edit.text = text.to_upper()
	_code_edit.caret_column = caret
	_refresh()


func _on_host_pressed() -> void:
	if not _save_player():
		return
	_log_view.clear()
	_status_label.text = "Creating a room..."
	Net.host_game()


func _on_join_pressed() -> void:
	if _join_button.disabled or not _save_player():
		return
	_log_view.clear()
	_status_label.text = "Joining %s..." % _code_edit.text
	Net.join_game(_code_edit.text)


func _on_leave_pressed() -> void:
	Net.leave()
	_status_label.text = ""
	_room_code_label.text = ""


func _save_player() -> bool:
	var player_name: String = _name_edit.text.strip_edges()
	if not PlayerInfo.is_valid_name(player_name):
		return false
	_player.player_name = player_name
	_player.save()
	Net.local_player = _player
	return true


func _on_room_code_ready(code: String) -> void:
	_room_code_label.text = code


func _on_net_state_changed(state: int) -> void:
	match state:
		Net.State.WAITING:
			_status_label.text = "Tell the other player this code. Waiting for them to join..."
		Net.State.CONNECTING:
			_status_label.text = "Connecting..."
		Net.State.CONNECTED:
			_status_label.text = "Connected! Saying hello..."
	_refresh()


func _on_connected(opponent: PlayerInfo) -> void:
	_status_label.text = "Connected to %s!" % opponent.player_name
	_status_label.add_theme_color_override("font_color", opponent.get_colour())


func _on_connection_failed(reason: String) -> void:
	_show_problem(Net.describe(reason))


func _on_disconnected(reason: String) -> void:
	_show_problem(Net.describe(reason))


func _show_problem(text: String) -> void:
	_status_label.remove_theme_color_override("font_color")
	_status_label.text = text
	_room_code_label.text = ""


func _on_ping_result(rtt_msec: int) -> void:
	_append_log("Ping: %d ms round trip" % rtt_msec)
	_status_label.text = "Connected to %s! Ping %d ms" % [Net.opponent.player_name if Net.opponent else "?", rtt_msec]


func _append_log(text: String) -> void:
	if _log_view.get_paragraph_count() > LOG_MAX_LINES:
		_log_view.clear()
	_log_view.add_text(text + "\n")


func _refresh() -> void:
	var idle: bool = Net.state == Net.State.IDLE
	var name_ok: bool = PlayerInfo.is_valid_name(_name_edit.text.strip_edges())
	var code_ok: bool = _code_edit.text.strip_edges().length() == 5
	_name_hint.text = "" if name_ok else PlayerInfo.NAME_RULE
	_name_edit.editable = idle
	_code_edit.editable = idle
	for swatch: BaseButton in _swatch_group.get_buttons():
		swatch.disabled = not idle
		# Keep the colour visible (dimmed) while locked, with the pick still outlined.
		var colour: Color = PlayerInfo.COLOURS[swatch.get_index()]
		swatch.add_theme_stylebox_override("disabled", _swatch_style(colour.darkened(0.35), swatch.button_pressed))
	_host_button.disabled = not (idle and name_ok)
	_join_button.disabled = not (idle and name_ok and code_ok)
	_bot_button.disabled = true # Comes with the lobby flow (step 4).
	_connected_row.visible = not idle
	_ping_button.visible = Net.state == Net.State.CONNECTED
	if idle:
		_status_label.remove_theme_color_override("font_color")
