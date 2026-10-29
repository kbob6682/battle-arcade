class_name GemModeGame
extends RefCounted
## What every Gem Battle mode (Drop, Swap) has in common, so GemBattle and the
## bot can drive either one the same way: a board, incoming junk, a clock for
## the speed-up, and the same signals for chains, attacks and topping out.
## Each mode is plain logic driven by tick(), so the player's game and the
## bots run exactly the same rules, and tests can step it with fixed times.

signal changed
## A chain step cleared some gems. chain counts from 1; groups are the cell
## indexes cleared (now empty) and colours each group's colour, for effects.
signal chain_step(chain: int, groups: Array[PackedInt32Array], colours: Array[int])
## Incoming junk just landed on the board.
signal junk_dropped(amount: int)
## The chain is over.
signal chain_finished(chain: int)
## Junk to send to the opponent, after blocking.
signal attack_sent(amount: int)
signal incoming_changed(amount: int)
signal topped_out

var board: GemBoard = GemBoard.new()
## Seconds since start; drives the speed-up.
var elapsed: float = 0.0
## Junk the opponent has sent that hasn't landed yet.
var incoming: int = 0


## Starts the match. shared_rng is seeded with the match seed, so both
## players (and a bot) get the same gems. junk_rng is this player's own.
func start(_shared_rng: RandomNumberGenerator, _junk_rng: RandomNumberGenerator = null) -> void:
	pass


func tick(_delta: float) -> void:
	pass


func is_topped() -> bool:
	return false


func is_sudden_death() -> bool:
	return false


## The opponent attacked. When the junk lands depends on the mode.
func add_incoming(amount: int) -> void:
	if amount <= 0 or is_topped():
		return
	incoming += amount
	incoming_changed.emit(incoming)


## The board as it should be drawn and sent in snapshots.
func cells_for_view() -> PackedInt32Array:
	return board.cells


## What the side panel previews (the next pair, or the next row), and its size.
func preview_cells() -> PackedInt32Array:
	return PackedInt32Array()


func preview_size() -> Vector2i:
	return Vector2i(1, 2)


## Blocking: a finished chain first cancels incoming junk, and the rest is
## sent as an attack.
func _block_and_attack(attack: int) -> void:
	var result: Vector2i = GemBoard.cancel_incoming(incoming, attack)
	if result.x != incoming:
		incoming = result.x
		incoming_changed.emit(incoming)
	if result.y > 0:
		attack_sent.emit(result.y)


## Own RNG for junk placement when the caller doesn't pass one.
static func _own_rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	var fresh := RandomNumberGenerator.new()
	fresh.randomize()
	return fresh
