class_name Fx
extends RefCounted
## Lightweight, pool-friendly combat FX. All effects are AnimatedSprite2D nodes
## that free themselves; blood decals are capped at 64 as required by the spec.

static var _frames_cache: Dictionary = {}
static var _decals: Array[Sprite2D] = []

const SHEETS := {
	"blood": ["res://assets/sprites/fx/blood_burst.png", 32, 32, 6, 18.0, false],
	"muzzle": ["res://assets/sprites/fx/muzzle_flash.png", 16, 12, 2, 30.0, false],
	"explosion": ["res://assets/sprites/fx/explosion.png", 64, 64, 6, 18.0, false],
	"smoke": ["res://assets/sprites/fx/smoke.png", 48, 48, 6, 8.0, false],
	"spark": ["res://assets/sprites/fx/spark.png", 12, 12, 3, 18.0, false],
	"fire": ["res://assets/sprites/fx/fire.png", 32, 32, 6, 10.0, true],
	"acid": ["res://assets/sprites/fx/acid_splash.png", 32, 24, 4, 14.0, false],
	"bile": ["res://assets/sprites/fx/bile_splash.png", 32, 24, 4, 14.0, false],
}


static func _get_frames(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var spec: Array = SHEETS[key]
	var path: String = spec[0]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var fw: int = spec[1]
	var fh: int = spec[2]
	var count: int = spec[3]
	var fps: float = spec[4]
	var loop: bool = spec[5]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("fx")
	frames.set_animation_speed("fx", fps)
	frames.set_animation_loop("fx", loop)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame("fx", atlas, 1.0)
	_frames_cache[key] = frames
	return frames


static func _spawn(parent: Node, key: String, pos: Vector2, scale_value: float = 1.0,
		rotation_value: float = 0.0, flip: bool = false, z: int = 20) -> AnimatedSprite2D:
	if parent == null or not is_instance_valid(parent):
		return null
	var frames := _get_frames(key)
	if frames == null:
		return null
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.position = pos
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.rotation = rotation_value
	sprite.flip_h = flip
	sprite.z_index = z
	sprite.animation = "fx"
	parent.add_child(sprite)
	sprite.play("fx")
	var spec: Array = SHEETS[key]
	if not bool(spec[5]):
		sprite.animation_finished.connect(sprite.queue_free)
	else:
		sprite.get_tree().create_timer(1.6, true, false, true).timeout.connect(sprite.queue_free)
	return sprite


static func blood(parent: Node, pos: Vector2, direction: Vector2 = Vector2.ZERO, scale_value: float = 1.0) -> void:
	_spawn(parent, "blood", pos, scale_value, 0.0, direction.x < 0.0, 21)


static func muzzle(parent: Node, pos: Vector2, angle: float) -> void:
	_spawn(parent, "muzzle", pos, 1.0, angle, false, 30)


static func tracer(parent: Node, from: Vector2, to: Vector2, color: Color = Color(1.0, 0.92, 0.62, 0.9)) -> void:
	if parent == null:
		return
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = color
	line.points = PackedVector2Array([from, to])
	line.z_index = 29
	parent.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.07)
	tween.tween_callback(line.queue_free)


static func shell(parent: Node, pos: Vector2, direction: float) -> void:
	if parent == null:
		return
	var tex: Texture2D = load("res://assets/sprites/fx/shell.png")
	if tex == null:
		return
	var shell := Sprite2D.new()
	shell.texture = tex
	shell.position = pos
	shell.z_index = 22
	parent.add_child(shell)
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "position", pos + Vector2(direction * 22.0, 4.0), 0.32)
	tween.tween_property(shell, "rotation", direction * 3.0, 0.32)
	tween.tween_property(shell, "modulate:a", 0.0, 0.18).set_delay(0.14)
	tween.chain().tween_callback(shell.queue_free)


static func explosion(parent: Node, pos: Vector2, scale_value: float = 1.0) -> void:
	_spawn(parent, "explosion", pos, scale_value, 0.0, false, 25)


static func smoke(parent: Node, pos: Vector2, scale_value: float = 1.0) -> void:
	_spawn(parent, "smoke", pos, scale_value, 0.0, false, 18)


static func spark(parent: Node, pos: Vector2) -> void:
	_spawn(parent, "spark", pos, 1.0, 0.0, false, 24)


static func fire(parent: Node, pos: Vector2, scale_value: float = 1.0) -> AnimatedSprite2D:
	return _spawn(parent, "fire", pos, scale_value, 0.0, false, 8)


static func acid(parent: Node, pos: Vector2) -> void:
	_spawn(parent, "acid", pos, 1.0, 0.0, false, 12)


static func bile(parent: Node, pos: Vector2, scale_value: float = 1.0) -> void:
	_spawn(parent, "bile", pos, scale_value, 0.0, false, 12)


static func blood_decal(parent: Node, pos: Vector2) -> void:
	if parent == null:
		return
	if _decals.size() >= 64:
		var oldest: Sprite2D = _decals.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var tex: Texture2D = load("res://assets/sprites/environment/blood_decal_%d.png" % randi_range(0, 2))
	if tex == null:
		return
	var decal := Sprite2D.new()
	decal.texture = tex
	decal.position = pos
	decal.z_index = -2
	decal.flip_h = randf() < 0.5
	parent.add_child(decal)
	_decals.append(decal)
	var tween := decal.create_tween()
	tween.tween_property(decal, "modulate:a", 0.0, 2.0).set_delay(8.0)
	tween.tween_callback(decal.queue_free)


static func reset() -> void:
	for decal in _decals:
		if is_instance_valid(decal):
			decal.queue_free()
	_decals.clear()
