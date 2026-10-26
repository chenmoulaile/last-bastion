class_name ThrowableProjectile
extends Node2D
## Arcing grenade / molotov / bile jar. Hits the first floor it touches.

var kind: String = "grenade"
var level: Node = null
var velocity: Vector2 = Vector2.ZERO
var age: float = 0.0
var detonated: bool = false
var sprite: Sprite2D
var trail_timer: float = 0.0


func _ready() -> void:
	z_index = 24
	sprite = Sprite2D.new()
	sprite.texture = SpriteLibrary.weapon_texture(kind)
	sprite.z_index = 24
	add_child(sprite)
	rotation = velocity.angle()


func _physics_process(delta: float) -> void:
	if detonated:
		return
	age += delta
	velocity.y += 900.0 * delta
	position += velocity * delta
	rotation += delta * 7.0
	trail_timer -= delta
	if trail_timer <= 0.0 and level:
		trail_timer = 0.08
		Fx.smoke(level.fx_layer, global_position, 0.3)
	var ground: float = level.get_ground_y(global_position.x) if level else -1.0
	if (age > 0.14 and ground > 0.0 and global_position.y >= ground - 2.0) or global_position.y > 450.0:
		_detonate()


func _detonate() -> void:
	if detonated:
		return
	detonated = true
	var pos := global_position
	if level:
		match kind:
			"molotov":
				level.spawn_fire_zone(pos, 64.0, 6.5, true)
				Fx.explosion(level.fx_layer, pos, 0.8)
				AudioManager.play_sfx_2d(&"firebomb", pos, 900.0)
			"bile":
				level.bile_explosion(pos, true)
				Fx.bile(level.fx_layer, pos, 1.8)
				AudioManager.play_sfx_2d(&"bile_splash", pos, 900.0)
			_:
				level.explode_at(pos, 105.0, 175, &"player", true)
				Fx.explosion(level.fx_layer, pos, 1.4)
				AudioManager.play_sfx_2d(&"explosion", pos, 1100.0)
	queue_free()
