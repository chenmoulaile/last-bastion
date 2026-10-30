extends Node2D
## CinematicCamera - 电影化镜头与演�.
##
## Autoload singleton; all modules reference it directly.
## As Autoload 挂载，全场景可通过 CinematicCamera 访问。

const LETTERBOX_HEIGHT := 44.0
const LETTERBOX_FADE_SPEED := 4.0

var _letterbox_top: ColorRect = null
var _letterbox_bottom: ColorRect = null
var _letterbox_target_alpha: float = 0.0
var _letterbox_current_alpha: float = 0.0

var _shake: TraumaShake = null
var _base_zoom: float = 1.0
var _target_zoom: float = 1.0
var _zoom_lerp_speed: float = 8.0

var camera_2d: Camera2D = null
var _player_ref: Node2D = null
var _follow_offset: Vector2 = Vector2(0, -80)

var _killcam_active: bool = false
var _killcam_target: Node2D = null
var _killcam_timer: float = 0.0
var _killcam_duration: float = 1.2
var _killcam_zoom: float = 0.45
var _killcam_speed_lines: Node2D = null
var _chromatic_amount: float = 0.0
var _radial_blur_amount: float = 0.0

var _cutscene_active: bool = false
var _cutscene_path: Array[Vector2] = []
var _cutscene_index: int = 0
var _cutscene_timer: float = 0.0
var _cutscene_duration: float = 0.0
var _cutscene_on_complete: Callable = Callable()

var _target_node: Node2D = null
var _camera_offset: Vector2 = Vector2.ZERO
var _lerp_speed: float = 5.0

var _dialogue_zoom_active: bool = false
var _dialogue_target_pos: Vector2 = Vector2.ZERO
var _dialogue_target_zoom: float = 1.0

var _combo_kill_count: int = 0
var _combo_timer: float = 0.0
var _combo_target: Node2D = null

signal killcam_started(target_position: Vector2)
signal killcam_ended
signal cutscene_started
signal cutscene_ended
signal letterbox_changed(visible: bool, immediate: bool)


func _ready() -> void:
	_build_letterbox()
	_shake = TraumaShake.new()
	set_process(true)

	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.hitstop.connect(_on_hitstop)
	EventBus.return_to_menu_requested.connect(_on_return_to_menu)
	EventBus.start_level_requested.connect(_on_level_start)

	set_letterbox(false, true)
	_bind_camera.call_deferred()


func _process(delta: float) -> void:
	_update_zoom(delta)
	_update_shake(delta)
	_update_killcam(delta)
	_update_cutscene(delta)
	_update_dialogue_zoom(delta)
	_update_combo(delta)
	_apply_camera(delta)
	_apply_letterbox(delta)


## ------------------------------------------------------------- letterbox ----

func _build_letterbox() -> void:
	_letterbox_top = ColorRect.new()
	_letterbox_top.name = "LetterboxTop"
	_letterbox_top.color = Color(0, 0, 0, 0)
	_letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# PRESET_TOP_WIDE pins top/bottom to the same edge, so a direct .size write
	# is silently reverted by Control::_set_size ("opposite anchors"). Use
	# set_deferred so the height survives layout, and grow downward from top.
	_letterbox_top.offset_bottom = LETTERBOX_HEIGHT
	_letterbox_top.custom_minimum_size = Vector2(0, LETTERBOX_HEIGHT)
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_top)

	_letterbox_bottom = ColorRect.new()
	_letterbox_bottom.name = "LetterboxBottom"
	_letterbox_bottom.color = Color(0, 0, 0, 0)
	_letterbox_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Same anchor trap as the top bar: offset_top is negative because the
	# bottom-wide preset anchors to offset_bottom == 0.
	_letterbox_bottom.offset_top = -LETTERBOX_HEIGHT
	_letterbox_bottom.custom_minimum_size = Vector2(0, LETTERBOX_HEIGHT)
	_letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_letterbox_bottom)


func set_letterbox(enable: bool, immediate: bool = false) -> void:
	_letterbox_target_alpha = 1.0 if enable else 0.0
	if immediate:
		_letterbox_current_alpha = _letterbox_target_alpha
		_letterbox_top.color.a = _letterbox_current_alpha
		_letterbox_bottom.color.a = _letterbox_current_alpha
		_letterbox_top.visible = _letterbox_current_alpha > 0.0
		_letterbox_bottom.visible = _letterbox_current_alpha > 0.0
	else:
		var tween := create_tween()
		tween.set_pass_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_callback(func() -> void:
			_letterbox_top.visible = _letterbox_target_alpha > 0.01
			_letterbox_bottom.visible = _letterbox_target_alpha > 0.01
		)
	letterbox_changed.emit(enable, immediate)


func _apply_letterbox(delta: float) -> void:
	if absf(_letterbox_target_alpha - _letterbox_current_alpha) < 0.001 and _letterbox_target_alpha == _letterbox_current_alpha:
		return
	_letterbox_current_alpha = lerpf(_letterbox_current_alpha, _letterbox_target_alpha, LETTERBOX_FADE_SPEED * delta)
	_letterbox_top.color.a = _letterbox_current_alpha
	_letterbox_bottom.color.a = _letterbox_current_alpha
	_letterbox_top.visible = _letterbox_current_alpha > 0.005
	_letterbox_bottom.visible = _letterbox_current_alpha > 0.005


## ------------------------------------------------------------- shake -------

func _update_shake(delta: float) -> void:
	# TraumaShake needs real delta to advance its internal time
	if _shake != null:
		_shake.update(delta)


func add_trauma(amount: float) -> void:
	if _shake != null:
		_shake.add_trauma(amount)


func add_trauma_directional(amount: float, direction: Vector2) -> void:
	if _shake != null:
		_shake.add_trauma_directional(amount, direction)


## ------------------------------------------------------------- kill cam ---

func trigger_killcam(target: Node2D, duration: float = 1.2, zoom: float = 0.45) -> void:
	if _killcam_active or target == null or not is_instance_valid(target):
		return
	_killcam_active = true
	_killcam_target = target
	_killcam_timer = 0.0
	_killcam_duration = duration
	_killcam_zoom = clampf(zoom, 0.2, 1.0)
	_target_zoom = _killcam_zoom
	_chromatic_amount = 0.38
	_radial_blur_amount = 0.85

	if _killcam_speed_lines == null:
		_build_speed_lines()
	_killcam_speed_lines.visible = true
	_killcam_speed_lines.position = target.global_position

	# Radial blur + CA on the post-process layer
	if PostProcess != null:
		PostProcess.set_chromatic_aberration(_chromatic_amount)
		PostProcess.set_radial_blur(_radial_blur_amount)

	killcam_started.emit(target.global_position)

	# Strong directional shake
	add_trauma_directional(1.0, (target.global_position - get_viewport().get_camera_2d().global_position).normalized())

	# Slow-mo for cinematic impact
	if not GameFeelConfig.reduced_motion:
		Engine.time_scale = 0.15
		create_tween().tween_callback(func() -> void:
			if Engine.time_scale < 1.0:
				Engine.time_scale = 1.0
		).set_delay(0.35).set_loops(1)


func _build_speed_lines() -> void:
	_killcam_speed_lines = Node2D.new()
	_killcam_speed_lines.name = "KillcamSpeedLines"
	_killcam_speed_lines.visible = false
	_killcam_speed_lines.z_index = 100
	add_child(_killcam_speed_lines)

	for i in 8:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.35)
		line.size = Vector2(2, 80)
		line.position = Vector2(-1, -40)
		line.rotation = TAU * float(i) / 8.0
		_killcam_speed_lines.add_child(line)


func _update_killcam(delta: float) -> void:
	if not _killcam_active:
		return

	_killcam_timer += delta
	var progress := clampf(_killcam_timer / _killcam_duration, 0.0, 1.0)

	if _killcam_target != null and is_instance_valid(_killcam_target):
		_target_node = _killcam_target

	_chromatic_amount = lerpf(0.38, 0.0, progress)
	_radial_blur_amount = lerpf(0.85, 0.0, progress * progress)

	if PostProcess != null:
		PostProcess.set_chromatic_aberration(_chromatic_amount)
		PostProcess.set_radial_blur(_radial_blur_amount)

	if _killcam_speed_lines != null:
		_killcam_speed_lines.rotation += delta * 5.0
		var alpha := 1.0 - progress * progress
		_killcam_speed_lines.modulate = Color(1, 1, 1, alpha * 0.4)

	if progress >= 1.0:
		_end_killcam()


func _end_killcam() -> void:
	_killcam_active = false
	_killcam_target = null
	_target_zoom = _base_zoom
	_chromatic_amount = 0.0
	_radial_blur_amount = 0.0
	if PostProcess != null:
		PostProcess.set_chromatic_aberration(0.0)
		PostProcess.set_radial_blur(0.0)
	if _killcam_speed_lines != null:
		_killcam_speed_lines.visible = false
	killcam_ended.emit()


## ------------------------------------------------------------- cutscene ----

func play_cutscene(path: Array[Vector2], duration: float, on_complete: Callable = Callable()) -> void:
	if path.is_empty():
		return
	_cutscene_active = true
	_cutscene_path = path.duplicate()
	_cutscene_index = 0
	_cutscene_timer = 0.0
	_cutscene_duration = duration
	_cutscene_on_complete = on_complete
	set_letterbox(true)
	cutscene_started.emit()

	if _cutscene_path.size() > 0:
		_target_node = null
		_camera_offset = _cutscene_path[0]


func _update_cutscene(delta: float) -> void:
	if not _cutscene_active:
		return

	_cutscene_timer += delta
	var progress := clampf(_cutscene_timer / _cutscene_duration, 0.0, 1.0)
	var t := smoothstep(0.0, 1.0, progress)

	if _cutscene_path.size() >= 2:
		var seg := float(_cutscene_path.size() - 1) * t
		var idx := int(floorf(seg))
		idx = clampi(idx, 0, _cutscene_path.size() - 1)
		var next_idx := mini(idx + 1, _cutscene_path.size() - 1)
		var local_t := seg - float(idx)
		_camera_offset = lerp(_cutscene_path[idx], _cutscene_path[next_idx], local_t)

	if progress >= 1.0:
		_end_cutscene()


func _end_cutscene() -> void:
	_cutscene_active = false
	_cutscene_index = 0
	set_letterbox(false)
	if _cutscene_on_complete != Callable():
		var cb := _cutscene_on_complete
		_cutscene_on_complete = Callable()
		cb.call()
	cutscene_ended.emit()


## --------------------------------------------------------- dialogue zoom ----

func start_dialogue_zoom(target_pos: Vector2, zoom: float = 0.82, duration: float = 0.6) -> void:
	if _cutscene_active or _killcam_active:
		return
	_dialogue_zoom_active = true
	_dialogue_target_pos = target_pos
	_dialogue_target_zoom = zoom
	_target_zoom = zoom
	if PostProcess != null:
		PostProcess.set_radial_blur(0.15)


func end_dialogue_zoom(duration: float = 0.4) -> void:
	_dialogue_zoom_active = false
	_target_zoom = _base_zoom
	if PostProcess != null:
		var tween_time := duration
		PostProcess.fade_radial_blur(tween_time)


func _update_dialogue_zoom(delta: float) -> void:
	if not _dialogue_zoom_active:
		return
	# Smoothly follow the target position during dialogue
	if _target_node == null or not is_instance_valid(_target_node):
		return


## ------------------------------------------------------------- zoom --------

func _update_zoom(delta: float) -> void:
	var diff := _target_zoom - _base_zoom
	if abs(diff) > 0.001:
		_base_zoom += diff * _zoom_lerp_speed * delta
	else:
		_base_zoom = _target_zoom


## ------------------------------------------------------------- apply -------

func _apply_camera(delta: float) -> void:
	if camera_2d == null:
		_bind_camera()
		if camera_2d == null:
			return

	var target := _target_node
	if target == null or not is_instance_valid(target):
		target = _player_ref if _player_ref != null and is_instance_valid(_player_ref) else null
	if target == null and not _cutscene_active:
		# No owner yet (menus, or between levels): leave the camera alone
		# instead of snapping it to the world origin.
		return

	var pos := Vector2.ZERO
	if _cutscene_active:
		pos = _camera_offset
	elif target != null:
		pos = target.global_position + _follow_offset

	var shake_offset := Vector2.ZERO
	if _shake != null:
		shake_offset = _shake.get_offset(delta)

	var combined := pos + shake_offset

	if _killcam_active and target != null:
		var target_pos := target.global_position
		combined = target_pos.lerp(combined, 0.5)

	camera_2d.global_position = combined

	var effective_zoom := _base_zoom
	if _killcam_active:
		effective_zoom = lerpf(_base_zoom, _killcam_zoom, 0.65)
	camera_2d.zoom = Vector2(effective_zoom, effective_zoom)

	EventBus.camera_zoom_changed.emit(effective_zoom)


## ------------------------------------------------------------- binding ----

func _bind_camera() -> void:
	if camera_2d != null and is_instance_valid(camera_2d):
		return
	if _player_ref != null and is_instance_valid(_player_ref):
		var bound: Variant = _player_ref.get("camera")
		if bound is Camera2D:
			camera_2d = bound as Camera2D
			_follow_offset = camera_2d.position
			if _target_node == null:
				_target_node = _player_ref
			return
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node is Node2D and is_instance_valid(node):
			if node.has_method("get"):
				var cam: Variant = node.get("camera")
				if cam is Camera2D:
					camera_2d = cam as Camera2D
					_player_ref = node
					_follow_offset = camera_2d.position
					if _target_node == null:
						_target_node = node
					return
	camera_2d = get_viewport().get_camera_2d()
	if camera_2d != null:
		_follow_offset = camera_2d.position
		var parent := camera_2d.get_parent()
		if parent is Node2D and parent.is_in_group("player"):
			_player_ref = parent
			if _target_node == null:
				_target_node = parent


## ------------------------------------------------------------- public API ---

func set_target(target: Node2D) -> void:
	_target_node = target
	_player_ref = target


func set_lerp(speed: float) -> void:
	_lerp_speed = clampf(speed, 0.1, 20.0)


func is_killcam_active() -> bool:
	return _killcam_active


func is_cutscene_active() -> bool:
	return _cutscene_active


func is_dialogue_zoom_active() -> bool:
	return _dialogue_zoom_active


func get_current_zoom() -> float:
	return _base_zoom


func set_base_zoom(zoom: float) -> void:
	_base_zoom = clampf(zoom, 0.2, 2.0)
	_target_zoom = _base_zoom


func get_shake() -> TraumaShake:
	return _shake


## ------------------------------------------------------------- events ------

func _on_enemy_killed(kind: StringName, source: StringName, pos: Vector2) -> void:
	if source == &"player" and kind != &"common" and not _killcam_active and not _cutscene_active:
		_combo_target = _get_nearest_enemy_to(pos)
		if _combo_target != null:
			_combo_kill_count += 1
			_combo_timer = 2.0
			if _combo_kill_count >= 3 and _combo_kill_count % 3 == 0:
				trigger_killcam(_combo_target, 1.0, 0.48)


func _on_boss_killed(kind: StringName) -> void:
	add_trauma_directional(1.2, Vector2.UP)
	set_letterbox(true)
	var target_pos := _boss_position()
	if target_pos != Vector2.ZERO:
		_trigger_boss_killcam(target_pos)
	create_tween().tween_callback(set_letterbox.bind(false, true)).set_delay(2.5)


func _on_hitstop(duration: float) -> void:
	add_trauma(clampf(duration * 0.4, 0.0, 1.0))


func _on_level_start() -> void:
	_reset_runtime()


func _on_return_to_menu() -> void:
	_reset_runtime()


func _get_nearest_enemy_to(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := 9999.0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
			continue
		var d := pos.distance_to(zombie.global_position)
		if d < best_dist:
			best = zombie
			best_dist = d
	return best if best_dist < 400.0 else null


func _boss_position() -> Vector2:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie):
			continue
		var data: Variant = zombie.get("data")
		if data != null and data.get("is_boss"):
			return zombie.global_position
	return Vector2.ZERO


func _trigger_boss_killcam(target_pos: Vector2) -> void:
	_killcam_active = true
	_killcam_target = null
	_killcam_timer = 0.0
	_killcam_duration = 2.0
	_target_zoom = 0.38
	_chromatic_amount = 0.5
	_radial_blur_amount = 1.0
	if PostProcess != null:
		PostProcess.set_chromatic_aberration(_chromatic_amount)
		PostProcess.set_radial_blur(_radial_blur_amount)


func _update_combo(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_kill_count = 0
			_combo_target = null


func _reset_runtime() -> void:
	set_letterbox(false, true)
	if _killcam_active:
		_end_killcam()
	if _cutscene_active:
		_end_cutscene()
	Engine.time_scale = 1.0
