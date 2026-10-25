extends Control
## Match screen: a 3-2-1 countdown, then the mini game, then the results panel
## (Rematch, Pick Another Game, Leave).

const COUNTDOWN_FROM: int = 3

var _game: MiniGame = null
var _count: int = COUNTDOWN_FROM

@onready var _game_holder: Node = %GameHolder
@onready var _countdown_label: Label = %CountdownLabel
@onready var _countdown_timer: Timer = %CountdownTimer
@onready var _results_panel: PanelContainer = %ResultsPanel
@onready var _result_label: Label = %ResultLabel
@onready var _rematch_status: Label = %RematchStatus
@onready var _rematch_button: Button = %RematchButton
@onready var _lobby_button: Button = %LobbyButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	_results_panel.hide()
	_rematch_button.pressed.connect(Session.request_rematch)
	_lobby_button.pressed.connect(Session.to_lobby)
	_leave_button.pressed.connect(Session.leave)
	Session.rematch_changed.connect(_refresh_rematch)
	_countdown_timer.timeout.connect(_on_countdown_tick)
	_countdown_label.text = str(_count)
	_countdown_timer.start(1.0)


func _on_countdown_tick() -> void:
	_count -= 1
	if _count > 0:
		_countdown_label.text = str(_count)
	elif _count == 0:
		_countdown_label.text = "Go!"
		_start_game()
	else:
		_countdown_timer.stop()
		_countdown_label.hide()


func _start_game() -> void:
	var info: GameInfo = Session.current_game()
	if info == null or Session.opponent == null:
		Session.to_lobby()
		return
	_game = info.scene.instantiate() as MiniGame
	_game_holder.add_child(_game)
	_game.finished.connect(_on_game_finished)
	_game.start_game(Session.match_seed, Session.opponent, Session.game_mode, Session.is_host, Net.local_player)
	if Session.opponent is BotOpponent:
		(Session.opponent as BotOpponent).start_match(Session.match_seed, Session.game_mode)


func _on_game_finished(outcome: MiniGame.Outcome, _stats: Dictionary) -> void:
	Session.record_result(outcome)
	match outcome:
		MiniGame.Outcome.WIN:
			_result_label.text = "You win!"
		MiniGame.Outcome.LOSE:
			_result_label.text = "You lose!"
		_:
			_result_label.text = "Draw!"
	_results_panel.show()
	_refresh_rematch()


func _refresh_rematch() -> void:
	_rematch_button.disabled = Session.local_rematch
	var them: String = Session.opponent_name()
	if Session.local_rematch:
		_rematch_status.text = "Waiting for %s..." % them
	elif Session.opponent_rematch:
		_rematch_status.text = "%s wants a rematch!" % them
	else:
		_rematch_status.text = ""
