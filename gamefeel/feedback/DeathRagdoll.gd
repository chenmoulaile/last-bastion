class_name GameFeelDeathRagdoll
extends Node2D
## Pooled pixel limbs. Only normal infected and human enemies spawn limbs;
## bosses and specials keep their existing death effects. Max 12 limbs.
## In reduced-motion mode limbs fade in place instead of being thrown.

const POOL_SIZE := 12
const GRAVITY := 900.0
const LIFE := 1.5
const FADE := 0.45

var _active: PackedByteArray = PackedByteArray()
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _rot: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _size: Array[Vector2] = []
var _color: Array[Color] = []
var _unit: PackedVector2Array = PackedVector2Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 3
	z_as_relative = true
	_rng.randomize()
	_active.resize(POOL_SIZE)
	_pos.resize(POOL_SIZE)
	_vel.resize(POOL_SIZE)
	_rot.resize(POOL_SIZE)
	_spin.resize(POOL_SIZE)
	_age.resize(POOL_SIZE)
	_unit.resize(4)
	_unit[0] = Vector2(-1, -1)
	_unit[1] = Vector2(1, -1)
	_unit[2] = Vector2(1, 1)
	_unit[3] = Vector2(-1, 1)
	for i in POOL_SIZE:
		_size.append(Vector2(2, 1))
		_color.append(Color(0.5, 0.1, 0.1, 1.0))


func _process(delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"death_ragdoll"):
		if _any_active():
			clear()
		return
	var any := false
	for i in POOL_SIZE:
		if _active[i] == 0:
			continue
		_age[i] += delta
		if _age[i] >= LIFE + FADE:
			_active[i] = 0
			continue
		any = true
		if not GameFeelConfig.reduced_motion:
			_vel[i].y += GRAVITY * delta
			_pos[i] += _vel[i] * delta
			_rot[i] += _spin[i] * delta
			if _pos[i].y > 314.0:
				_pos[i].y = 314.0
				_vel[i] = Vector2.ZERO
				_spin[i] = 0.0
	if any:
		queue_redraw()


func _draw() -> void:
	for i in POOL_SIZE:
		if _active[i] == 0:
			continue
		var age := _age[i]
		var alpha := 1.0
		if age > LIFE:
			alpha = clampf(1.0 - (age - LIFE) / FADE, 0.0, 1.0)
		if alpha <= 0.001:
			continue
		var color: Color = _color[i]
		draw_set_transform(_pos[i], _rot[i], _size[i])
		draw_colored_polygon(_unit, Color(color.r * 0.75, color.g * 0.55, color.b * 0.55, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Returns the number of limbs actually spawned.
func spawn(world_position: Vector2, direction: Vector2, color: Color,
		is_boss: bool = false, is_special: bool = false, _human: bool = false) -> int:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"death_ragdoll"):
		return 0
	if is_boss or is_special:
		return 0
	var density := GameFeelConfig.effective_particle_density()
	if density <= 0.02:
		return 0
	var count := 2 + (1 if _rng.randf() < 0.55 * density else 0)
	count = maxi(1, int(round(float(count) * maxf(0.4, density))))
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	for i in count:
		var slot := _free_slot()
		_active[slot] = 1
		_age[slot] = 0.0
		_pos[slot] = world_position + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-18.0, -6.0))
		_rot[slot] = _rng.randf_range(0.0, TAU)
		_size[slot] = Vector2(_rng.randf_range(1.5, 3.2), _rng.randf_range(1.0, 2.4))
		_color[slot] = color
		if GameFeelConfig.reduced_motion:
			_vel[slot] = Vector2.ZERO
			_spin[slot] = 0.0
		else:
			_vel[slot] = Vector2(
				dir.x * _rng.randf_range(70.0, 190.0) + _rng.randf_range(-35.0, 35.0),
				_brng(-240.0, -90.0)
			)
			_spin[slot] = _rng.randf_range(-9.0, 9.0)
	queue_redraw()
	return count


func clear() -> void:
	for i in POOL_SIZE:
		_active[i] = 0
	queue_redraw()


func active_count() -> int:
	var count := 0
	for i in POOL_SIZE:
		if _active[i] == 1:
			count += 1
	return count


func pool_size() -> int:
	return POOL_SIZE


func _free_slot() -> int:
	for i in POOL_SIZE:
		if _active[i] == 0:
			return i
	var oldest := 0
	var oldest_age := _age[0]
	for i in POOL_SIZE:
		if _age[i] > oldest_age:
			oldest_age = _age[i]
			oldest = i
	_active[oldest] = 0
	return oldest


func _any_active() -> bool:
	for i in POOL_SIZE:
		if _active[i] == 1:
			return true
	return false


func _brng(min_value: float, max_value: float) -> float:
	return _rng.randf_range(min_value, max_value)
