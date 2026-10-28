class_name GameFeelHitFlash
extends Node2D
## Additive sprite overlay flash. The overlay is separate from the target's
## sprite, so the zombie's own white hit tint, character palette tint and
## animation frames are never clobbered.
##
## Pool: 32 overlays, pre-allocated. No node is created at runtime.

const MAX_FLASHES := 32

var _overlays: Array[Sprite2D] = []
var _active: Array[Dictionary] = []
var _material: CanvasItemMaterial = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 1
	z_as_relative = true
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_rng.randomize()
	for i in MAX_FLASHES:
		var overlay := Sprite2D.new()
		overlay.centered = true
		overlay.visible = false
		overlay.z_index = 2
		overlay.material = _material
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(overlay)
		_overlays.append(overlay)


func _process(_delta: float) -> void:
	if _active.is_empty():
		return
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"hit_flash"):
		clear()
		return
	var now := Time.get_ticks_usec()
	var expired: Array[int] = []
	for index in _active.size():
		var entry: Dictionary = _active[index]
		var target: Node = entry.get("target", null)
		var overlay: Sprite2D = entry.get("overlay", null)
		if overlay == null or not is_instance_valid(overlay):
			expired.append(index)
			continue
		if target == null or not is_instance_valid(target):
			overlay.visible = false
			expired.append(index)
			continue
		var sprite: AnimatedSprite2D = target.get("sprite") as AnimatedSprite2D
		if sprite == null or not is_instance_valid(sprite):
			overlay.visible = false
			expired.append(index)
			continue
		var until := int(entry.get("until", 0))
		var duration := maxf(0.001, float(entry.get("duration", 0.06)))
		var remaining := float(until - now) / 1_000_000.0
		if remaining <= 0.0:
			overlay.visible = false
			expired.append(index)
			continue
		overlay.global_position = sprite.global_position
		overlay.offset = sprite.offset
		overlay.flip_h = sprite.flip_h
		overlay.flip_v = sprite.flip_v
		overlay.scale = sprite.scale
		var alpha := clampf(remaining / duration, 0.0, 1.0)
		var color: Color = entry.get("color", Color.WHITE)
		overlay.modulate = Color(color.r, color.g, color.b, color.a * alpha)
		overlay.visible = true
	for index in range(expired.size() - 1, -1, -1):
		var remove_at := expired[index]
		if remove_at >= 0 and remove_at < _active.size():
			var entry: Dictionary = _active[remove_at]
			var overlay: Sprite2D = entry.get("overlay", null)
			if overlay != null and is_instance_valid(overlay):
				overlay.visible = false
			_active.remove_at(remove_at)


func flash(target: Node, kind: StringName) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"hit_flash"):
		return
	if GameFeelConfig.flash_multiplier() <= 0.01:
		return
	var sprite: AnimatedSprite2D = target.get("sprite") as AnimatedSprite2D
	if sprite == null or not is_instance_valid(sprite) or sprite.sprite_frames == null:
		return
	var color := Color(1.0, 1.0, 1.0, 0.62)
	var duration := 0.06
	if kind == &"crit":
		color = Color(1.0, 0.90, 0.30, 0.80)
		duration = 0.10
	elif kind == &"player":
		color = Color(1.0, 0.20, 0.20, 0.50)
		duration = 0.15
	color.a *= GameFeelConfig.flash_multiplier()
	if color.a <= 0.01:
		return
	var now := Time.get_ticks_usec()
	var target_id := target.get_instance_id()
	for entry in _active:
		if int(entry.get("id", 0)) == target_id:
			entry["until"] = maxi(int(entry.get("until", 0)), now + int(duration * 1_000_000.0))
			entry["color"] = color
			entry["duration"] = duration
			return
	var overlay := _take_overlay(now)
	if overlay == null:
		return
	var frames: SpriteFrames = sprite.sprite_frames
	if not frames.has_animation(sprite.animation):
		return
	overlay.texture = frames.get_frame_texture(sprite.animation, sprite.frame)
	if overlay.texture == null:
		return
	overlay.centered = sprite.centered
	overlay.global_position = sprite.global_position
	overlay.offset = sprite.offset
	overlay.flip_h = sprite.flip_h
	overlay.flip_v = sprite.flip_v
	overlay.scale = sprite.scale
	overlay.modulate = color
	overlay.visible = true
	_active.append({
		"id": target_id,
		"target": target,
		"overlay": overlay,
		"until": now + int(duration * 1_000_000.0),
		"duration": duration,
		"color": color,
		"used": now,
	})


func flash_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	flash(player, &"player")


func clear() -> void:
	for entry in _active:
		var overlay: Sprite2D = entry.get("overlay", null)
		if overlay != null and is_instance_valid(overlay):
			overlay.visible = false
	_active.clear()


func active_count() -> int:
	return _active.size()


func pool_size() -> int:
	return _overlays.size()


func _take_overlay(now: int) -> Sprite2D:
	for overlay in _overlays:
		var used := false
		for entry in _active:
			if entry.get("overlay", null) == overlay:
				used = true
				break
		if not used:
			return overlay
	# All overlays busy: recycle the oldest entry.
	if not _active.is_empty():
		var oldest_index := 0
		var oldest_used := int(_active[0].get("used", now))
		for index in _active.size():
			var used_at := int(_active[index].get("used", now))
			if used_at < oldest_used:
				oldest_used = used_at
				oldest_index = index
		var recycled: Dictionary = _active[oldest_index]
		var overlay: Sprite2D = recycled.get("overlay", null)
		_active.remove_at(oldest_index)
		if overlay != null and is_instance_valid(overlay):
			overlay.visible = false
			return overlay
	return null
