extends Node
## CameraPunch - directional kick and zoom pulse for the local camera.
##
## Offsets are accumulated in `punch_offset` and composited by ScreenShake, so
## there is only ever one writer of Camera2D.offset. Zoom is applied directly.
## Every tween is killed before a new one starts, preventing runaway stacking.
##
## Autoload: CameraPunch

signal punched(strength: float)

const WEAPON_KICK := {
	&"m9": 1.0,
	&"smg": 1.1,
	&"ar15": 1.4,
	&"shotgun": 2.6,
	&"lmg": 1.8,
	&"sniper": 3.0,
	&"katana": 1.2,
	&"axe": 1.4,
	&"chainsaw": 1.2,
}

var punch_offset: Vector2 = Vector2.ZERO
var zoom_factor: float = 1.0

var _offset_tween: Tween = null
var _zoom_tween: Tween = null
var _camera: Camera2D = null
var _base_zoom: Vector2 = Vector2.ONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1600


func _process(_delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"camera_punch"):
		if punch_offset != Vector2.ZERO:
			punch_offset = Vector2.ZERO
		if zoom_factor != 1.0:
			zoom_factor = 1.0
		_apply_zoom()
		return
	_acquire_camera()
	_apply_zoom()


func punch(direction: Vector2, weapon_id: StringName = &"m9", crit: bool = false) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"camera_punch"):
		return
	var motion := GameFeelConfig.motion_scale()
	if motion <= 0.0:
		return
	var kick := float(WEAPON_KICK.get(weapon_id, 1.2)) * GameFeelConfig.camera_punch_scale * motion
	if crit:
		kick += 1.2
	var offset := -direction.normalized() * minf(3.0, 1.0 + kick * 0.55)
	if _offset_tween != null and _offset_tween.is_valid():
		_offset_tween.kill()
	_offset_tween = create_tween()
	_offset_tween.set_ignore_time_scale(true)
	_offset_tween.tween_property(self, "punch_offset", offset, 0.02)
	_offset_tween.tween_property(self, "punch_offset", Vector2.ZERO, 0.06)

	var heavy := weapon_id in [&"shotgun", &"lmg", &"sniper"]
	if heavy:
		_zoom_to(0.98, 0.10)
	if crit:
		_zoom_to(1.03, 0.12)
	punched.emit(kick)


func headshot_kill(direction: Vector2 = Vector2.ZERO) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"camera_punch"):
		return
	if not GameFeelConfig.reduced_motion:
		_zoom_to(1.03, 0.12)
	var motion := GameFeelConfig.motion_scale()
	var offset := Vector2(0.0, -2.0) - direction.normalized() * 1.2 * motion
	if _offset_tween != null and _offset_tween.is_valid():
		_offset_tween.kill()
	_offset_tween = create_tween()
	_offset_tween.set_ignore_time_scale(true)
	_offset_tween.tween_property(self, "punch_offset", offset, 0.04)
	_offset_tween.tween_property(self, "punch_offset", Vector2.ZERO, 0.10)


func boss_death() -> void:
	if not GameFeelConfig.enabled or GameFeelConfig.reduced_motion:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	_zoom_tween.tween_property(self, "zoom_factor", 1.05, 0.18)
	_zoom_tween.tween_interval(0.30)
	_zoom_tween.tween_property(self, "zoom_factor", 1.0, 0.28)


func reset() -> void:
	if _offset_tween != null and _offset_tween.is_valid():
		_offset_tween.kill()
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	punch_offset = Vector2.ZERO
	zoom_factor = 1.0
	_apply_zoom()


func _zoom_to(value: float, duration: float, delay: float = 0.0) -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_ignore_time_scale(true)
	if delay > 0.0:
		_zoom_tween.tween_interval(delay)
	_zoom_tween.tween_property(self, "zoom_factor", value, duration * 0.45)
	_zoom_tween.tween_property(self, "zoom_factor", 1.0, duration * 0.55)


func _acquire_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	_camera = get_viewport().get_camera_2d()
	if _camera == null:
		var players := get_tree().get_nodes_in_group("player")
		for node in players:
			var cam: Variant = node.get("camera")
			if cam is Camera2D:
				_camera = cam as Camera2D
				break
	if _camera != null:
		_base_zoom = _camera.zoom


func _apply_zoom() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.zoom = _base_zoom * zoom_factor
