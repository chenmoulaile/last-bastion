extends Node
## InputBuffer - real-time input capture that survives hitstop.
##
## The existing player controller already implements its own coyote/jump
## windows; this autoload records presses in real time so the game-feel layer
## can prove that a freeze never eats an input, expose buffered actions to new
## systems, and provide the shared reload-cancel/combo windows.
##
## It never consumes Input actions and never writes gameplay state.
##
## Autoload: InputBuffer

const COYOTE_WINDOW := 0.10
const JUMP_WINDOW := 0.12
const COMBO_WINDOW := 0.25
const RELOAD_CANCEL_FRACTION := 0.30
const POST_HITSTOP_WINDOW := 0.30

const TRACKED := [
	&"jump", &"fire", &"melee", &"reload", &"switch_weapon", &"throw",
	&"interact", &"skill", &"medkit", &"pills", &"crouch", &"move_left",
	&"move_right", &"cmd_follow", &"cmd_advance", &"cmd_hold", &"cmd_focus",
	&"cmd_formation",
]

var _times: Dictionary = {}
var _hitstop_presses: Dictionary = {}
var _in_hitstop: bool = false
var _hitstop_start_usec: int = 0
var _hitstop_end_usec: int = 0
var _press_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	for action in TRACKED:
		if event.is_action_pressed(action, false):
			note_press(action)


## Public for synthetic tests and future gameplay consumers.
func note_press(action: StringName) -> void:
	var now := Time.get_ticks_usec()
	_times[action] = now
	_press_count += 1
	if _in_hitstop:
		_hitstop_presses[action] = now


func is_buffered(action: StringName, window: float) -> bool:
	if not _times.has(action):
		return false
	var age := float(Time.get_ticks_usec() - int(_times[action])) / 1_000_000.0
	return age <= window


func consume(action: StringName, window: float) -> bool:
	if not is_buffered(action, window):
		return false
	_times.erase(action)
	return true


func pressed_during_hitstop(action: StringName) -> bool:
	if not _hitstop_presses.has(action):
		return false
	var age := float(Time.get_ticks_usec() - int(_hitstop_presses[action])) / 1_000_000.0
	return age <= POST_HITSTOP_WINDOW


func consume_after_hitstop(action: StringName) -> bool:
	if not pressed_during_hitstop(action):
		return false
	_hitstop_presses.erase(action)
	_times.erase(action)
	return true


func begin_hitstop() -> void:
	_in_hitstop = true
	_hitstop_start_usec = Time.get_ticks_usec()
	_hitstop_end_usec = 0
	_hitstop_presses.clear()


func end_hitstop() -> void:
	_in_hitstop = false
	_hitstop_end_usec = Time.get_ticks_usec()


func is_in_hitstop() -> bool:
	return _in_hitstop


func reload_cancel_open(reload_elapsed: float, reload_total: float) -> bool:
	if reload_total <= 0.001:
		return false
	return reload_elapsed >= reload_total * (1.0 - RELOAD_CANCEL_FRACTION)


func combo_open(last_attack_usec: int) -> bool:
	if last_attack_usec <= 0:
		return false
	return float(Time.get_ticks_usec() - last_attack_usec) / 1_000_000.0 <= COMBO_WINDOW


func coyote_open(time_since_grounded: float) -> bool:
	return time_since_grounded <= COYOTE_WINDOW


func jump_buffered(time_until_ground: float) -> bool:
	return time_until_ground <= JUMP_WINDOW and is_buffered(&"jump", JUMP_WINDOW)


func reset() -> void:
	_times.clear()
	_hitstop_presses.clear()
	_in_hitstop = false
	_hitstop_start_usec = 0
	_hitstop_end_usec = 0
	_press_count = 0


func total_presses() -> int:
	return _press_count


func windows() -> Dictionary:
	return {
		"coyote": COYOTE_WINDOW,
		"jump": JUMP_WINDOW,
		"combo": COMBO_WINDOW,
		"reload_cancel_fraction": RELOAD_CANCEL_FRACTION,
	}
