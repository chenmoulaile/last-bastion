class_name GameFeelImpactParticles
extends Node2D
## Pooled CPUParticles2D impact bursts. 20 emitters are pre-allocated; a burst
## only reconfigures and restarts one of them. Density follows
## GameFeelConfig.particle_density, so low-end machines can halve the load.

const POOL_SIZE := 20
const MAX_PARTICLES := 48

const PROFILES := {
	&"blood": {
		"count": 7, "velocity_min": 80.0, "velocity_max": 160.0, "gravity": 200.0,
		"life_min": 0.30, "life_max": 0.50, "color": Color(0.52, 0.06, 0.07, 1.0),
		"scale_min": 1.4, "scale_max": 2.6, "spread": 70.0,
	},
	&"spore": {
		"count": 10, "velocity_min": 70.0, "velocity_max": 150.0, "gravity": 90.0,
		"life_min": 0.35, "life_max": 0.60, "color": Color(1.0, 0.52, 0.16, 1.0),
		"scale_min": 1.6, "scale_max": 3.0, "spread": 180.0,
	},
	&"human": {
		"count": 5, "velocity_min": 70.0, "velocity_max": 140.0, "gravity": 220.0,
		"life_min": 0.25, "life_max": 0.45, "color": Color(0.70, 0.08, 0.08, 1.0),
		"scale_min": 1.3, "scale_max": 2.4, "spread": 80.0,
	},
	&"armor": {
		"count": 8, "velocity_min": 140.0, "velocity_max": 260.0, "gravity": 60.0,
		"life_min": 0.15, "life_max": 0.25, "color": Color(1.0, 0.90, 0.54, 1.0),
		"scale_min": 1.0, "scale_max": 1.8, "spread": 120.0,
	},
	&"debris": {
		"count": 5, "velocity_min": 60.0, "velocity_max": 130.0, "gravity": 320.0,
		"life_min": 0.20, "life_max": 0.40, "color": Color(0.62, 0.60, 0.55, 1.0),
		"scale_min": 1.0, "scale_max": 2.0, "spread": 100.0,
	},
	&"blood_burst": {
		"count": 15, "velocity_min": 200.0, "velocity_max": 300.0, "gravity": 260.0,
		"life_min": 0.45, "life_max": 0.60, "color": Color(0.62, 0.04, 0.05, 1.0),
		"scale_min": 1.6, "scale_max": 3.2, "spread": 180.0,
	},
}

var _emitters: Array[CPUParticles2D] = []
var _used_at: PackedInt64Array = PackedInt64Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 5
	z_as_relative = true
	_rng.randomize()
	_used_at.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var particles := CPUParticles2D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.amount = 1
		particles.lifetime = 0.3
		particles.local_coords = false
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = Vector2(3, 3)
		particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		particles.z_index = 5
		add_child(particles)
		_emitters.append(particles)


func _process(_delta: float) -> void:
	if GameFeelConfig.enabled and GameFeelConfig.is_module_enabled(&"impact_particles"):
		return
	for particles in _emitters:
		if particles.emitting:
			particles.emitting = false


func burst(kind: StringName, world_position: Vector2, direction: Vector2,
		crit: bool = false, density: float = -1.0) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"impact_particles"):
		return
	var effective_density := GameFeelConfig.effective_particle_density() if density < 0.0 else clampf(density, 0.0, 1.0)
	if effective_density <= 0.01:
		return
	var profile: Dictionary = PROFILES.get(kind, PROFILES[&"blood"])
	var emitter := _take_emitter()
	if emitter == null:
		return
	var amount := int(round(float(profile.get("count", 6)) * effective_density))
	if crit:
		amount = int(round(amount * 1.4))
	amount = clampi(amount, 1, MAX_PARTICLES)
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.UP
	emitter.global_position = world_position
	emitter.amount = amount
	emitter.lifetime = _rng.randf_range(float(profile.get("life_min", 0.2)), float(profile.get("life_max", 0.4)))
	emitter.lifetime_randomness = 0.35
	emitter.direction = dir
	emitter.spread = float(profile.get("spread", 80.0))
	emitter.gravity = Vector2(0.0, float(profile.get("gravity", 200.0)))
	emitter.initial_velocity_min = float(profile.get("velocity_min", 60.0))
	emitter.initial_velocity_max = float(profile.get("velocity_max", 140.0))
	emitter.scale_amount_min = float(profile.get("scale_min", 1.0))
	emitter.scale_amount_max = float(profile.get("scale_max", 2.0))
	emitter.angular_velocity_min = -360.0
	emitter.angular_velocity_max = 360.0
	emitter.angle_min = 0.0
	emitter.angle_max = 360.0
	emitter.color = profile.get("color", Color.WHITE)
	emitter.modulate = Color.WHITE
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = true


func active_count() -> int:
	var count := 0
	for particles in _emitters:
		if particles.emitting:
			count += 1
	return count


func pool_size() -> int:
	return _emitters.size()


func clear() -> void:
	for particles in _emitters:
		particles.emitting = false


func _take_emitter() -> CPUParticles2D:
	var now := Time.get_ticks_usec()
	for i in _emitters.size():
		if not _emitters[i].emitting:
			_used_at[i] = now
			return _emitters[i]
	var oldest := 0
	var oldest_time := _used_at[0]
	for i in _emitters.size():
		if _used_at[i] < oldest_time:
			oldest_time = _used_at[i]
			oldest = i
	_emitters[oldest].emitting = false
	_used_at[oldest] = now
	return _emitters[oldest]
