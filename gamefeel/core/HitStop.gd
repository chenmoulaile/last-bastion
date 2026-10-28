extends Node
## HitStop - real-time-scaled hit freeze.
##
## Design notes:
##   * Time is scaled globally (Engine.time_scale), which Godot applies to
##     physics delta but not to input polling. Input is therefore never eaten;
##     InputBuffer additionally records every press during the freeze.
##   * Restore is driven by Time.get_ticks_usec(), so a frozen frame cannot
##     keep the game in slow motion.
##   * A per-target cooldown of 150 ms prevents automatic fire from turning
##     into a stutter loop.
##   * The legacy GameManager.hitstop connection is taken over by
##     GameFeelBridge while the layer is enabled, preserving all existing
##     EventBus.hitstop calls but giving them proper per-event profiles.
##
## Autoload: HitStop

signal hitstop_started(kind: StringName, duration: float, scale: float)
signal hitstop_finished

const TARGET_COOLDOWN_USEC := 150_000
const PROFILES := {
	&"normal": {"duration": 0.04, "scale": 0.10},
	&"crit": {"duration": 0.08, "scale": 0.05},
	&"execution": {"duration": 0.12, "scale": 0.0},
	&"kill": {"duration": 0.06, "scale": 0.10},
	&"boss": {"duration": 0.03, "scale": 0.30},
}

var _active: bool = false
var _end_usec: int = 0
var _base_scale: float = 1.0
var _active_scale: float = 1.0
var _last_target_usec: Dictionary = {}
var _frozen: Dictionary = {} # instance_id -> {"node": Node, "until": int, "physics": bool, "idle": bool}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 2000


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_restore_frozen(now)
	if _active and now >= _end_usec:
		_finish()


## Public request. `kind` is one of PROFILES. `target` is only used for the
## duplicate-hit cooldown (and local freezing where supported).
func request(kind: StringName, target: Node = null, duration_multiplier: float = 1.0) -> bool:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"hitstop"):
		return false
	if GameFeelConfig.hitstop_scale <= 0.0:
		return false
	var profile: Dictionary = PROFILES.get(kind, PROFILES[&"normal"])
	var now := Time.get_ticks_usec()
	if target != null and is_instance_valid(target):
		var key := target.get_instance_id()
		if now - int(_last_target_usec.get(key, -TARGET_COOLDOWN_USEC)) < TARGET_COOLDOWN_USEC:
			return false
		_last_target_usec[key] = now
	var duration := float(profile["duration"]) * GameFeelConfig.hitstop_scale * duration_multiplier
	if duration <= 0.001:
		return false
	var scale_value := clampf(float(profile["scale"]), 0.0, 1.0)
	_begin(duration, scale_value, kind)
	if target != null and is_instance_valid(target) and kind in [&"crit", &"execution"]:
		freeze(target, duration)
	return true


## Used by GameFeelBridge for legacy EventBus.hitstop(duration) calls.
func request_legacy(duration: float) -> void:
	var kind := &"normal"
	if duration <= 0.032:
		kind = &"crit"
	elif duration >= 0.055:
		kind = &"kill"
	request(kind, null)


func request_shot(weapon_heavy: bool) -> void:
	request(&"normal" if not weapon_heavy else &"crit", null, 0.5 if not weapon_heavy else 1.0)


func freeze(node: Node, duration: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var key := node.get_instance_id()
	var now := Time.get_ticks_usec()
	if _frozen.has(key):
		var entry: Dictionary = _frozen[key]
		entry["until"] = maxi(int(entry["until"]), now + int(duration * 1_000_000.0))
		return
	var entry := {
		"node": node,
		"until": now + int(duration * 1_000_000.0),
		"physics": node.is_physics_processing(),
		"idle": node.is_processing(),
	}
	_frozen[key] = entry
	node.set_physics_process(false)


func is_active() -> bool:
	return _active


func remaining() -> float:
	if not _active:
		return 0.0
	return maxf(0.0, float(_end_usec - Time.get_ticks_usec()) / 1_000_000.0)


func cancel_all() -> void:
	_restore_all_frozen()
	if _active:
		Engine.time_scale = _base_scale
		_active = false
		_active_scale = 1.0
		InputBuffer.end_hitstop()
		hitstop_finished.emit()


func _begin(duration: float, scale_value: float, kind: StringName) -> void:
	var now := Time.get_ticks_usec()
	if not _active:
		_base_scale = Engine.time_scale
		if _base_scale <= 0.001:
			_base_scale = 1.0
		_active_scale = scale_value
		_active = true
		InputBuffer.begin_hitstop()
	else:
		_active_scale = minf(_active_scale, scale_value)
	_end_usec = maxi(_end_usec, now + int(duration * 1_000_000.0))
	Engine.time_scale = maxf(0.0, _base_scale * _active_scale)
	hitstop_started.emit(kind, duration, _active_scale)


func _finish() -> void:
	Engine.time_scale = _base_scale
	_active = false
	_active_scale = 1.0
	InputBuffer.end_hitstop()
	hitstop_finished.emit()


func _restore_frozen(now: int) -> void:
	if _frozen.is_empty():
		return
	var expired: Array[int] = []
	for key in _frozen.keys():
		var entry: Dictionary = _frozen[key]
		if now >= int(entry["until"]):
			expired.append(int(key))
	for key in expired:
		var entry: Dictionary = _frozen[key]
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.set_physics_process(bool(entry["physics"]))
		_frozen.erase(key)


func _restore_all_frozen() -> void:
	for key in _frozen.keys():
		var entry: Dictionary = _frozen[key]
		var node: Node = entry["node"]
		if node != null and is_instance_valid(node):
			node.set_physics_process(bool(entry["physics"]))
	_frozen.clear()
