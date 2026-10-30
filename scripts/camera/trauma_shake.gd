class_name TraumaShake
extends RefCounted
## TraumaShake - 基于 Perlin 噪声的屏幕震动系统。
##
## 不再是简单的随机抖动，而是基于 Trauma 值的弹性回正震动。
## 震动幅度 = trauma^2，频率由 Perlin 噪声驱动，具有自然的衰减与回正。
## 震动幅度、频率与回正弹性完全可配置。
##
## 使用方式：
##   trauma = TraumaShake.new()
##   trauma.add_trauma(0.6)   # 0~1，轻微到剧烈
##   var offset = trauma.get_offset(delta)   # 返回 Vector2 偏移量

var trauma: float = 0.0
var decay_rate: float = 4.5   # 每秒衰减率 (Perlin-based, smoother decay)
var max_shake: float = 14.0   # 最大像素偏移
var noise_scale: float = 4.0  # 噪声频率
var _noise: FastNoiseLite = null
var _time: float = 0.0

# Directional bias: when set, shake is pulled toward this direction
var _dir: Vector2 = Vector2.ZERO
var _dir_weight: float = 0.0
# Sustained trauma floor (for boss death, etc.)
var _sustain_until: int = 0
var _sustain_floor: float = 0.0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = noise_scale
	_noise.seed = randi()
	_rng.randomize()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_trauma_directional(amount: float, direction: Vector2) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)
	if direction.length_squared() > 0.01:
		_dir = direction.normalized()
		_dir_weight = clampf(_dir_weight + 0.5 + amount * 0.5, 0.0, 1.0)
	else:
		_dir_weight = maxf(0.0, _dir_weight - 0.3)


func sustain_floor(floor_value: float, seconds: float) -> void:
	_sustain_until = Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	_sustain_floor = maxf(_sustain_floor, floor_value)


## 更新并返回本帧的屏幕偏移量。
func update(delta: float) -> Vector2:
	return get_offset(delta)


func get_offset(delta: float) -> Vector2:
	if trauma <= 0.001 and _dir_weight <= 0.001:
		_time += delta
		return Vector2.ZERO

	var now := Time.get_ticks_usec()
	if now >= _sustain_until:
		_sustain_floor = maxf(0.0, _sustain_floor - delta * 0.7)
	else:
		trauma = maxf(trauma, _sustain_floor)

	# 衰减
	trauma = clampf(trauma - decay_rate * delta, 0.0, 1.0)
	_dir_weight = maxf(0.0, _dir_weight - delta * 1.6)

	_time += delta

	# 震动幅度 = trauma^2（强化轻微创伤，抑制剧烈创伤的线性感）
	var intensity := trauma * trauma
	var amp := intensity * max_shake * _rng.randf_range(0.9, 1.1)

	# Perlin 噪声驱动方向，产生自然的不规则抖动
	var nx := _noise.get_noise_2d(_time * 2.5, 0.0)
	var ny := _noise.get_noise_2d(0.0, _time * 2.5)
	var nz := _noise.get_noise_2d(_time * 1.7, _time * 1.9)

	var offset_x := nx * amp
	var offset_y := ny * amp

	# 弹性回正：创伤越高，回正力越强，产生“被拉回”的感觉
	var snap_x := -_time * 0.3 * trauma * 2.0
	var snap_y := nz * trauma * 1.5

	# Directional bias pull
	var dir_contribution := _dir * amp * 0.35 * _dir_weight

	return Vector2(offset_x + snap_x + dir_contribution.x, offset_y + snap_y + dir_contribution.y)


func reset() -> void:
	trauma = 0.0
	_time = 0.0
	_dir = Vector2.ZERO
	_dir_weight = 0.0
	_sustain_until = 0
	_sustain_floor = 0.0
