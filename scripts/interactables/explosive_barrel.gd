class_name ExplosiveBarrel
extends StaticBody2D
## Red fuel barrel. Any bullet, melee hit or another explosion can set it off.

var level: Node = null
var health: int = 28
var exploded: bool = false
var sprite: Sprite2D
var collision: CollisionShape2D


func _ready() -> void:
	add_to_group("barrels")
	add_to_group("melee_targets")
	collision_layer = 64
	collision_mask = 0
	sprite = Sprite2D.new()
	sprite.texture = SpriteLibrary.prop_texture("barrel_explosive")
	sprite.position = Vector2(0, -12)
	sprite.z_index = 2
	add_child(sprite)
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(13, 22)
	collision.shape = shape
	collision.position = Vector2(0, -11)
	add_child(collision)


func hit(amount: int, _source: StringName = &"player") -> void:
	if exploded:
		return
	health -= amount
	AudioManager.play_sfx_2d(&"metal_hit", global_position, 600.0)
	if level:
		Fx.spark(level.fx_layer, global_position + Vector2(0, -12))
	if health <= 0:
		explode()


func explode() -> void:
	if exploded:
		return
	exploded = true
	collision_layer = 0
	collision_mask = 0
	if collision:
		collision.set_deferred("disabled", true)
	if sprite:
		sprite.visible = false
	if level:
		level.barrel_exploded(self, global_position + Vector2(0, -10), 105.0, 190)
	queue_free()
