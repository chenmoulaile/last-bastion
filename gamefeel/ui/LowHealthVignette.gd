class_name GameFeelLowHealth
extends CanvasLayer
## Low-health vignette. Deliberately subtle: the HUD already owns a low-health
## overlay, so this layer only adds depth and a 1.2 Hz heartbeat pulse below 15%.
##
## No combat values are read or written beyond the player's public hp/max_hp.

const THRESHOLD := 0.30
const CRITICAL := 0.15
const MAX_ALPHA := 0.34
const FADE_SPEED := 2.0

var _root: Control = null
var _vignette: TextureRect = null
var _player: Node = null
var _alpha: float = 0.0
var _beat_phase: float = 0.0
var _retry_usec: int = 0


func _ready() -> void:
	layer = 64
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "LowHealthRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = _build_texture()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0)
	_root.add_child(_vignette)


func _process(delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"low_health"):
		_alpha = move_toward(_alpha, 0.0, FADE_SPEED * delta)
		_vignette.modulate.a = _alpha
		return
	_acquire()
	if _player == null or not is_instance_valid(_player):
		_alpha = move_toward(_alpha, 0.0, FADE_SPEED * delta)
		_vignette.modulate.a = _alpha
		return
	var max_hp := maxi(1, int(_player.get("max_hp")))
	var hp := clampi(int(_player.get("hp")), 0, max_hp)
	if bool(_player.get("is_dead")) or bool(_player.get("is_downed")):
		hp = mini(hp, 1)
	var ratio := float(hp) / float(max_hp)
	var target := alpha_for_ratio(ratio, GameFeelConfig.reduced_motion)
	if ratio < CRITICAL and not GameFeelConfig.reduced_motion:
		_beat_phase += delta * 1.2
		if _beat_phase >= 1.0:
			_beat_phase -= 1.0
			AudioLayerManager.play_heartbeat(1.0 - ratio / CRITICAL)
	else:
		_beat_phase = 0.0
	var speed := FADE_SPEED if target < _alpha else 1.1
	_alpha = move_toward(_alpha, target, speed * delta)
	_vignette.modulate.a = clampf(_alpha, 0.0, MAX_ALPHA)


static func alpha_for_ratio(ratio: float, reduced_motion: bool) -> float:
	if ratio >= THRESHOLD:
		return 0.0
	var depth := clampf((THRESHOLD - ratio) / THRESHOLD, 0.0, 1.0)
	var alpha := 0.08 + depth * 0.22
	if reduced_motion:
		alpha = 0.08 + depth * 0.12
	return clampf(alpha, 0.0, MAX_ALPHA)


func current_alpha() -> float:
	return _alpha


func clear() -> void:
	_alpha = 0.0
	_beat_phase = 0.0
	if _vignette != null:
		_vignette.modulate.a = 0.0


func _acquire() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var now := Time.get_ticks_usec()
	if now - _retry_usec < 500_000:
		return
	_retry_usec = now
	_player = null
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node is Node and is_instance_valid(node):
			_player = node
			return


func _build_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.50, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.35, 0.01, 0.01, 0.0),
		Color(0.38, 0.01, 0.01, 0.0),
		Color(0.48, 0.02, 0.02, 0.55),
		Color(0.62, 0.02, 0.02, 1.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 144
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture
