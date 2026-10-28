class_name GameFeelShellEject
extends Node2D
## Pooled brass shells drawn with a shared rectangle and draw_set_transform.
## _draw() performs no allocations. 30 shells maximum on screen.

const POOL_SIZE := 30
const RECT := 2.0
const GRAVITY := 620.0
const LIFE := 2.0
const FADE := 0.35
const COLOR := Color(0.86, 0.68, 0.30, 1.0)

var _active: PackedByteArray = PackedByteArray()
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _rot: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _rect: PackedVector2Array = PackedVector2Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 4
	z_as_relative = true
	_rng.randomize()
	_active.resize(POOL_SIZE)
	_pos.resize(POOL_SIZE)
	_vel.resize(POOL_SIZE)
	_rot.resize(POOL_SIZE)
	_spin.resize(POOL_SIZE)
	_age.resize(POOL_SIZE)
	_rect.resize(4)
	_rect[0] = Vector2(-RECT, -RECT * 0.5)
	_rect[1] = Vector2(RECT, -RECT * 0.5)
	_rect[2] = Vector2(RECT, RECT * 0.5)
	_rect[3] = Vector2(-RECT, RECT * 0.5)


func _process(delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"shell_eject"):
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
		_vel[i].y += GRAVITY * delta
		_pos[i] += _vel[i] * delta
		_rot[i] += _spin[i] * delta
		# A single cheap ground bounce keeps shells from falling forever.
		var floor_y := _pos[i].y
		if floor_y > 310.0 and _vel[i].y > 0.0:
			_vel[i].y *= -0.28
			_vel[i].x *= 0.55
			_spin[i] *= 0.5
			_pos[i].y = 310.0
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
		draw_set_transform(_pos[i], _rot[i], Vector2.ONE)
		draw_colored_polygon(_rect, Color(COLOR.r, COLOR.g, COLOR.b, COLOR.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func eject(world_position: Vector2, direction: Vector2, count: int = 1) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"shell_eject"):
		return
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var right := Vector2(-dir.y, dir.x)
	if right.y > 0.0:
		right = -right
	for i in count:
		var slot := _free_slot()
		_active[slot] = 1
		_pos[slot] = world_position + Vector2(0, -2)
		_vel[slot] = right * _rng.randf_range(55.0, 95.0) + Vector2(dir.x * -18.0, -_rng.randf_range(70.0, 130.0))
		_rot[slot] = _rng.randf_range(0.0, TAU)
		_spin[slot] = _rng.randf_range(-14.0, 14.0)
		_age[slot] = 0.0
	queue_redraw()


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
