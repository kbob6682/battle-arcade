class_name LinkWatch
extends RefCounted
## Tracks when we last heard from the other player and decides whether the
## link looks fine, shaky or gone. Times are passed in (msec, e.g.
## Time.get_ticks_msec()) so tests can use fake ones.

enum Status { OK, WARN, LOST }

## Silence before "Waiting for X..." shows.
const WARN_AFTER_MSEC: int = 4000
## Silence before giving up. Long enough that briefly switching browser tabs
## (which pauses the game in that tab) doesn't end the session.
const LOST_AFTER_MSEC: int = 20000

var _last_heard_msec: int = 0


## Something arrived from the other player (or the link just came up).
func heard(now_msec: int) -> void:
	_last_heard_msec = now_msec


func status(now_msec: int) -> Status:
	var silent_msec: int = now_msec - _last_heard_msec
	if silent_msec >= LOST_AFTER_MSEC:
		return Status.LOST
	if silent_msec >= WARN_AFTER_MSEC:
		return Status.WARN
	return Status.OK
