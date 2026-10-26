class_name BreakableCrate
extends StaticBody2D
## Wooden supply crate. Breaking it drops ammo, pills, throwables or gold.

var level: Node = null
var health: int = 18
var broken: bool = false
var sprite: Sprite2D
var collision: CollisionShape2D


func _ready() -> void:
	add_to_group("melee_targets")
	collision_layer = 64
	collision_mask = 0
	sprite = Sprite2D.new()
	sprite.texture = SpriteLibrary.prop_texture("crate")
	sprite.position = Vector2(0, -10)
	sprite.z_index = 2
	add_child(sprite)
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(18, 18)
	collision.shape = shape
	collision.position = Vector2(0, -9)
	add_child(collision)


func hit(amount: int, _source: StringName = &"player") -> void:
	if broken:
		return
	health -= amount
	AudioManager.play_sfx_2d(&"wood_hit", global_position, 600.0)
	if level:
		Fx.spark(level.fx_layer, global_position + Vector2(0, -10))
	if health <= 0:
		_break()


func _break() -> void:
	if broken:
		return
	broken = true
	collision_layer = 0
	collision_mask = 0
	if collision:
		collision.set_deferred("disabled", true)
	sprite.visible = false
	if level:
		Fx.smoke(level.fx_layer, global_position + Vector2(0, -10), 0.8)
		level.drop_random_pickup(global_position + Vector2(0, -10))
	AudioManager.play_sfx_2d(&"crate_break", global_position, 800.0)
	queue_free()
