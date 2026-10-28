class_name GameFeelMuzzleFlash
extends Node2D
## Procedural star-shaped muzzle flash. All geometry is pre-computed once and
## drawn with draw_set_transform + draw_colored_polygon, so _draw() performs no
## allocations. Pool: 12 flashes.

const POOL_SIZE := 12
const STAR_POINTS := 9

const COLORS := {
	&"m9": Color(1.0, 0.94, 0.62, 0.95),
	&"smg": Color(1.0, 0.93, 0.58, 0.95),
	&"ar15": Color(1.0, 0.90, 0.50, 0.95),
	&"shotgun": Color(1.0, 0.62, 0.24, 0.95),
	&"lmg": Color(0.72, 0.86, 1.0, 0.95),
	&"sniper": Color(0.86, 0.78, 1.0, 0.95),
	&"default": Color(1.0, 0.86, 0.48, 0.95),
}

var _visible_flash: PackedByteArray = PackedByteArray()
var _pos: PackedVector2Array = PackedVector2Array()
var _rotation: PackedFloat32Array = PackedFloat32Array()
var _scale: PackedFloat32Array = PackedFloat32Array()
var _until: PackedInt64Array = PackedInt64Array()
var _started: PackedInt64Array = PackedInt64Array()
var _color: Array[Color] = []
var _points: PackedVector2Array = PackedVector2Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 6
	z_as_relative = true
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	self.material = material
	_rng.randomize()
	_build_star()
	_visible_flash.resize(POOL_SIZE)
	_pos.resize(POOL_SIZE)
	_rotation.resize(POOL_SIZE)
	_scale.resize(POOL_SIZE)
	_until.resize(POOL_SIZE)
	_started.resize(POOL_SIZE)
	for i in POOL_SIZE:
		_color.append(COLORS[&"default"])


func _process(_delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"muzzle_flash"):
		if _any_visible():
			for i in POOL_SIZE:
				_visible_flash[i] = 0
			queue_redraw()
		return
	var now := Time.get_ticks_usec()
	var changed := false
	for i in POOL_SIZE:
		if _visible_flash[i] == 0:
			continue
		if now >= _until[i]:
			_visible_flash[i] = 0
			changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		return
	var now := Time.get_ticks_usec()
	for i in POOL_SIZE:
		if _visible_flash[i] == 0:
			continue
		var duration := maxf(1.0, float(_until[i] - _started[i]))
		var remaining := clampf(float(_until[i] - now) / duration, 0.0, 1.0)
		if remaining <= 0.0:
			continue
		var color: Color = _color[i]
		color.a = clampf(color.a * remaining, 0.0, 1.0)
		draw_set_transform(_pos[i], _rotation[i], Vector2(_scale[i], _scale[i]))
		draw_colored_polygon(_points, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func flash(world_pos: Vector2, direction: Vector2, weapon_id: StringName, heavy: bool = false) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"muzzle_flash"):
		return
	if GameFeelConfig.flash_multiplier() <= 0.01:
		return
	var slot := _free_slot()
	var now := Time.get_ticks_usec()
	var duration := 0.055 if heavy else 0.035
	var base_color: Color = COLORS.get(weapon_id, COLORS[&"default"])
	base_color.a *= GameFeelConfig.flash_multiplier()
	_visible_flash[slot] = 1
	_pos[slot] = world_pos
	_rotation[slot] = direction.angle()
	_scale[slot] = _rng.randf_range(0.85, 1.25) * (1.35 if heavy else 1.0)
	_started[slot] = now
	_until[slot] = now + int(duration * 1_000_000.0)
	_color[slot] = base_color
	queue_redraw()


func clear() -> void:
	for i in POOL_SIZE:
		_visible_flash[i] = 0
	queue_redraw()


func active_count() -> int:
	var count := 0
	for i in POOL_SIZE:
		if _visible_flash[i] == 1:
			count += 1
	return count


func pool_size() -> int:
	return POOL_SIZE


func _free_slot() -> int:
	var now := Time.get_ticks_usec()
	for i in POOL_SIZE:
		if _visible_flash[i] == 0:
			return i
	# Recycle the flash closest to expiring.
	var best := 0
	var best_until := _until[0]
	for i in POOL_SIZE:
		if _until[i] < best_until:
			best = i
			best_until = _until[i]
	if best_until < now:
		return best
	return best


func _any_visible() -> bool:
	for i in POOL_SIZE:
		if _visible_flash[i] == 1:
			return true
	return false


func _build_star() -> void:
	_points.resize(STAR_POINTS * 2)
	for i in STAR_POINTS * 2:
		var angle := TAU * float(i) / float(STAR_POINTS * 2)
		var radius := 14.0 if i % 2 == 0 else 4.0
		_points[i] = Vector2(cos(angle), sin(angle)) * radius
