extends Node
## ScreenShake - trauma-based directional camera shake.
##
## It replaces the legacy ShakeCamera update while the game-feel layer is on.
## The legacy node stays alive: when GameFeelConfig is disabled, its processing
## is restored so the v1.0 behaviour remains available as a fallback.
##
## Autoload: ScreenShake

const DEFAULT_DECAY := 1.9
const DEFAULT_PEAK := 2.0

var trauma: float = 0.0
var max_offset: float = DEFAULT_PEAK
var trauma_decay: float = DEFAULT_DECAY

var _dir: Vector2 = Vector2.ZERO
var _dir_weight: float = 0.0
var _sustain_until: int = 0
var _sustain_floor: float = 0.0
var _time: float = 0.0
var _last_usec: int = 0
var _camera: Camera2D = null
var _camera_disabled: Dictionary = {} # instance_id -> {"node": Camera2D, "idle": bool, "physics": bool}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1500
	_rng.randomize()
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.25)
	_last_usec = now
	_time += real_delta

	if not GameFeelConfig.enabled:
		_restore_legacy_camera()
		trauma = 0.0
		return

	_acquire_camera()
	if _camera == null or not is_instance_valid(_camera):
		return

	if now < _sustain_until:
		trauma = maxf(trauma, _sustain_floor)
	else:
		trauma = maxf(0.0, trauma - trauma_decay * real_delta)
	_sustain_floor = maxf(0.0, _sustain_floor - real_delta * 0.8)
	max_offset = move_toward(max_offset, DEFAULT_PEAK, 5.0 * real_delta)
	_dir_weight = maxf(0.0, _dir_weight - real_delta * 1.8)

	var motion := GameFeelConfig.motion_scale()
	var scale_value := GameFeelConfig.screenshake_scale
	var amount := pow(trauma, 2.0) * max_offset * scale_value * motion
	if amount < 0.01:
		amount = 0.0
	var noise := Vector2(
		sin(_time * 37.0 + 0.7) * 0.62 + sin(_time * 71.0) * 0.28 + _rng.randf_range(-0.10, 0.10),
		sin(_time * 43.0 + 2.1) * 0.62 + sin(_time * 89.0) * 0.28 + _rng.randf_range(-0.10, 0.10)
	)
	var directional := _dir.normalized() * amount * 0.42 * _dir_weight
	var punch := Vector2.ZERO
	if GameFeelConfig.is_module_enabled(&"camera_punch"):
		punch = CameraPunch.punch_offset
	var look := Vector2.ZERO
	if _camera.has_method("set_look_ahead"):
		look = Vector2(float(_camera.get("look_ahead")), 0.0)
	_camera.offset = look + noise * amount + directional + punch


func add_trauma(amount: float, peak: float = DEFAULT_PEAK, direction: Vector2 = Vector2.ZERO,
		sustain: float = 0.0) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"screenshake"):
		return
	var motion := GameFeelConfig.motion_scale()
	trauma = clampf(trauma + amount * GameFeelConfig.screenshake_scale * motion, 0.0, 1.0)
	max_offset = maxf(max_offset, peak * GameFeelConfig.screenshake_scale * motion)
	if direction.length_squared() > 0.001:
		_dir = direction.normalized()
		_dir_weight = clampf(_dir_weight + 0.35 + amount, 0.0, 1.0)
	else:
		_dir_weight = maxf(0.0, _dir_weight - 0.25)
	if sustain > 0.0:
		_sustain_until = maxi(_sustain_until, Time.get_ticks_usec() + int(sustain * 1_000_000.0))
		_sustain_floor = maxf(_sustain_floor, minf(1.0, trauma))


func add_shot(heavy: bool, direction: Vector2 = Vector2.ZERO) -> void:
	if heavy:
		add_trauma(0.18, 4.0, direction)
	else:
		add_trauma(0.08, 2.0, direction)


func add_player_hit(damage_direction: Vector2) -> void:
	add_trauma(0.35, 6.0, -damage_direction)


func add_explosion(direction: Vector2 = Vector2.ZERO) -> void:
	add_trauma(0.6, 10.0, direction)


func add_boss_death() -> void:
	add_trauma(1.0, 14.0, Vector2.ZERO, 0.8)
	_sustain_floor = 0.9


func reset() -> void:
	trauma = 0.0
	max_offset = DEFAULT_PEAK
	_dir = Vector2.ZERO
	_dir_weight = 0.0
	_sustain_until = 0
	_sustain_floor = 0.0


func _acquire_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		_disable_legacy(_camera)
		return
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node is Node and is_instance_valid(node):
			var cam: Variant = node.get("camera")
			if cam is Camera2D:
				_camera = cam as Camera2D
				_disable_legacy(_camera)
				return
	_camera = get_viewport().get_camera_2d()
	if _camera != null:
		_disable_legacy(_camera)


func _disable_legacy(camera: Camera2D) -> void:
	var key := camera.get_instance_id()
	if _camera_disabled.has(key):
		return
	# Only touch cameras that actually own the legacy shake script.
	if not camera.has_method("add_trauma"):
		return
	_camera_disabled[key] = {
		"node": camera,
		"idle": camera.is_processing(),
		"physics": camera.is_physics_processing(),
	}
	camera.set_process(false)
	camera.set_physics_process(false)


func _restore_legacy_camera() -> void:
	if _camera_disabled.is_empty():
		if _camera != null and is_instance_valid(_camera):
			_camera.offset = Vector2.ZERO
		return
	for key in _camera_disabled.keys():
		var entry: Dictionary = _camera_disabled[key]
		var camera: Camera2D = entry["node"]
		if camera != null and is_instance_valid(camera):
			camera.set_process(bool(entry["idle"]))
			camera.set_physics_process(bool(entry["physics"]))
			camera.offset = Vector2.ZERO
	_camera_disabled.clear()
	_camera = null
	reset()
