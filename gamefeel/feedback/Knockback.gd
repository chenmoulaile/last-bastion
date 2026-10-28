class_name GameFeelKnockback
extends Node
## Visual-only knockback: the sprite slides along an exponentially decaying
## displacement curve while the body, collision shape and AI position stay
## untouched. This preserves every combat value and keeps netcode deterministic.

const DECAY_K := 12.0
const MAX_ACTIVE := 64

const PROFILES := {
	&"m9": {"v0": 60.0, "duration": 0.08},
	&"smg": {"v0": 40.0, "duration": 0.05},
	&"ar15": {"v0": 55.0, "duration": 0.06},
	&"shotgun": {"v0": 220.0, "duration": 0.15},
	&"lmg": {"v0": 70.0, "duration": 0.07},
	&"sniper": {"v0": 140.0, "duration": 0.10},
	&"katana": {"v0": 300.0, "duration": 0.18},
	&"axe": {"v0": 300.0, "duration": 0.18},
	&"chainsaw": {"v0": 120.0, "duration": 0.10},
	&"melee": {"v0": 300.0, "duration": 0.18},
	&"explosion": {"v0": 400.0, "duration": 0.25},
	&"bullet": {"v0": 60.0, "duration": 0.08},
}

var _active: Dictionary = {}


func _process(_delta: float) -> void:
	if _active.is_empty():
		return
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"knockback"):
		clear()
		return
	var now := Time.get_ticks_usec()
	var expired: Array[int] = []
	for key in _active.keys():
		var entry: Dictionary = _active[key]
		var target: Node2D = entry.get("target", null)
		var sprite: Node2D = entry.get("sprite", null)
		if target == null or not is_instance_valid(target) or sprite == null or not is_instance_valid(sprite):
			expired.append(int(key))
			continue
		var start := int(entry.get("start", now))
		var duration := float(entry.get("duration", 0.1))
		var elapsed := float(now - start) / 1_000_000.0
		if elapsed >= duration:
			sprite.position = Vector2(entry.get("base", Vector2.ZERO))
			expired.append(int(key))
			continue
		var v0 := float(entry.get("v0", 0.0))
		var direction: Vector2 = entry.get("direction", Vector2.ZERO)
		var distance := (v0 / DECAY_K) * (1.0 - exp(-DECAY_K * elapsed))
		sprite.position = Vector2(entry.get("base", Vector2.ZERO)) + direction * distance
	for key in expired:
		_active.erase(key)


## Returns the peak visual displacement in pixels (0 when suppressed).
func apply(target: Node, direction: Vector2, weapon_id: StringName, is_boss: bool = false,
		armored: bool = false) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"knockback"):
		return 0.0
	if is_boss:
		return 0.0
	var sprite: Node2D = target.get("sprite") as Node2D
	if sprite == null or not is_instance_valid(sprite):
		return 0.0
	if target.is_in_group("player"):
		return 0.0
	var profile: Dictionary = PROFILES.get(weapon_id, PROFILES[&"bullet"])
	var v0 := float(profile.get("v0", 60.0))
	if armored:
		v0 *= 0.3
	if GameFeelConfig.reduced_motion:
		v0 *= 0.5
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	if _active.size() >= MAX_ACTIVE:
		var first_key: Variant = _active.keys()[0]
		var first: Dictionary = _active[first_key]
		var old_sprite: Node2D = first.get("sprite", null)
		if old_sprite != null and is_instance_valid(old_sprite):
			old_sprite.position = Vector2(first.get("base", Vector2.ZERO))
		_active.erase(first_key)
	var key := target.get_instance_id()
	var base := Vector2.ZERO
	var existing: Variant = _active.get(key, null)
	if existing is Dictionary:
		base = (existing as Dictionary).get("base", Vector2.ZERO)
	else:
		base = sprite.position
	_active[key] = {
		"target": target,
		"sprite": sprite,
		"base": base,
		"direction": dir,
		"v0": v0,
		"duration": float(profile.get("duration", 0.1)),
		"start": Time.get_ticks_usec(),
	}
	return v0 / DECAY_K


func clear() -> void:
	for key in _active.keys():
		var entry: Dictionary = _active[key]
		var sprite: Node2D = entry.get("sprite", null)
		if sprite != null and is_instance_valid(sprite):
			sprite.position = Vector2(entry.get("base", Vector2.ZERO))
	_active.clear()


func active_count() -> int:
	return _active.size()
