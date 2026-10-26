class_name ShakeCamera
extends Camera2D
## Camera2D with a decaying trauma shake and forward look-ahead.

var trauma: float = 0.0
var trauma_decay: float = 1.8
var look_ahead: float = 0.0
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func _ready() -> void:
	_rng.randomize()
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	EventBus.screen_shake.connect(add_trauma)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func set_look_ahead(value: float) -> void:
	look_ahead = lerpf(look_ahead, value, 0.15)


func _process(delta: float) -> void:
	_time += delta
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	var strength := ConfigManager.screenshake_strength()
	var amount := trauma * trauma * 9.0 * strength
	offset = Vector2(
		_rng.randf_range(-amount, amount),
		_rng.randf_range(-amount, amount)
	) + Vector2(look_ahead, 0.0)
	if trauma <= 0.001:
		offset = offset.lerp(Vector2(look_ahead, 0.0), 0.4)
