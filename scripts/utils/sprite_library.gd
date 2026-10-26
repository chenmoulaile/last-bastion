class_name SpriteLibrary
extends RefCounted
## Builds SpriteFrames from the generated horizontal animation strips and caches
## them. Keeping this in one place makes every actor share the same naming rules.

static var _cache: Dictionary = {}

const CHAR_ANIMS := {
	"idle": [4, 6.0, true],
	"run": [6, 11.0, true],
	"shoot": [3, 14.0, false],
	"melee": [3, 14.0, false],
	"hurt": [2, 8.0, false],
	"die": [6, 7.0, false],
	"crouch": [2, 4.0, true],
	"slide": [2, 8.0, false],
	"jump": [2, 5.0, true],
}

const ZOMBIE_ANIMS := {
	"idle": [4, 4.0, true],
	"run": [6, 8.5, true],
	"attack": [4, 9.0, false],
	"hurt": [2, 8.0, false],
	"die": [6, 6.0, false],
	"inflate": [3, 4.0, false],
	"charge": [4, 9.0, false],
	"punch": [3, 8.0, false],
	"pounce": [3, 10.0, false],
	"pin": [2, 5.0, true],
	"leap": [3, 10.0, false],
	"ride": [2, 6.0, true],
	"spit": [3, 10.0, false],
	"scream": [2, 6.0, false],
	"chase": [6, 12.0, true],
	"throw": [3, 8.0, false],
}


static func character_frames(visual_id: String) -> SpriteFrames:
	var key := "char_" + visual_id
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in CHAR_ANIMS.keys():
		var spec: Array = CHAR_ANIMS[anim]
		var count := int(spec[0])
		var path := "res://assets/sprites/characters/%s_%s.png" % [visual_id, anim]
		var tex := _texture(path)
		if tex == null:
			continue
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, bool(spec[2]))
		frames.set_animation_speed(anim, float(spec[1]))
		_add_strip(frames, anim, tex, count)
	_cache[key] = frames
	return frames


static func zombie_frames(prefix: String, frame_size: Vector2i) -> SpriteFrames:
	var key := "zombie_%s_%dx%d" % [prefix, frame_size.x, frame_size.y]
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ZOMBIE_ANIMS.keys():
		var spec: Array = ZOMBIE_ANIMS[anim]
		var path := "res://assets/sprites/zombies/%s_%s.png" % [prefix, anim]
		var tex := _texture(path)
		if tex == null:
			continue
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, bool(spec[2]))
		frames.set_animation_speed(anim, float(spec[1]))
		# Every strip is generated at the frame width, so derive the frame count
		# from the texture instead of duplicating the table in two places.
		var count := maxi(1, tex.get_width() / frame_size.x)
		_add_strip(frames, anim, tex, count)
	_cache[key] = frames
	return frames


static func _add_strip(frames: SpriteFrames, anim: String, tex: Texture2D, count: int) -> void:
	var frame_w := tex.get_width() / count
	var frame_h := tex.get_height()
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		atlas.filter_clip = true
		frames.add_frame(anim, atlas, 1.0)


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func portrait(visual_id: String) -> Texture2D:
	return _texture("res://assets/sprites/characters/%s_portrait.png" % visual_id)


static func weapon_texture(sprite: String) -> Texture2D:
	return _texture("res://assets/sprites/weapons/%s.png" % sprite)


static func prop_texture(name: String) -> Texture2D:
	return _texture("res://assets/sprites/environment/%s.png" % name)


static func ui_texture(name: String) -> Texture2D:
	return _texture("res://assets/sprites/ui/%s.png" % name)


static func achievement_texture(icon: String) -> Texture2D:
	return _texture("res://assets/sprites/ui/%s.png" % icon)


static func clear_cache() -> void:
	_cache.clear()
