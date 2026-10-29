class_name LevelDoor
extends StaticBody2D
## Breakable barricade door. Kicking it stuns nearby infected; zombies can also
## claw it down. Doors block both survivors and infected until destroyed.

var level: Node = null
var kind: String = "wood"
var health: int = 60
var max_health: int = 60
var kick_cd: float = 0.0
var scratch_cd: float = 0.0
var broken: bool = false
var sprite: Sprite2D
var collision: CollisionShape2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("melee_targets")
	add_to_group("doors")
	collision_layer = 64
	collision_mask = 0
	match kind:
		"metal":
			max_health = 95
		"glass":
			max_health = 42
		_:
			max_health = 62
	health = max_health
	sprite = Sprite2D.new()
	sprite.texture = SpriteLibrary.prop_texture("door_" + kind)
	sprite.position = Vector2(0, -24)
	sprite.z_index = 2
	add_child(sprite)
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(22, 46)
	collision.shape = shape
	collision.position = Vector2(0, -23)
	add_child(collision)


func _process(delta: float) -> void:
	kick_cd = maxf(0.0, kick_cd - delta)
	scratch_cd = maxf(0.0, scratch_cd - delta)


func get_prompt() -> String:
	return "E 踹门  [%d%%]" % int(100.0 * float(health) / float(max_health))


func interact(player: Node) -> void:
	if broken or kick_cd > 0.0:
		return
	kick_cd = 0.38
	health -= 36
	EventBus.door_kicked.emit(global_position)
	# 战术破门: 0.08秒极限慢动作，震晕门后敌人。
	EventBus.hitstop.emit(0.08)
	EventBus.shake(3.5)
	AudioManager.play_sfx_2d(&"door_kick", global_position, 800.0)
	if level:
		Fx.spark(level.fx_layer, global_position + Vector2(0, -22))
		level.stun_zombies_near(global_position, 78.0, 1.2)
	if health <= 0:
		_break()
	else:
		EventBus.notify.emit("门松动了，再踹一脚")
		if player and player.has_method("shake_camera"):
			player.shake_camera(2.0)


func hit(amount: int, source: StringName = &"player") -> void:
	if broken:
		return
	health -= amount
	AudioManager.play_sfx_2d(&"door_hit", global_position, 600.0)
	if level:
		Fx.spark(level.fx_layer, global_position + Vector2(0, -24))
	if health <= 0:
		_break()


func zombie_scratch(zombie: Node) -> void:
	if broken or scratch_cd > 0.0:
		return
	scratch_cd = 0.75
	health -= 9
	if level:
		Fx.spark(level.fx_layer, global_position + Vector2(0, -18))
	if health <= 0:
		_break()
	elif zombie and zombie.has_method("apply_stagger"):
		zombie.apply_stagger(0.1)


func _break() -> void:
	if broken:
		return
	broken = true
	EventBus.door_broken.emit(global_position)
	AudioManager.play_sfx_2d(&"door_break", global_position, 900.0)
	EventBus.shake(3.0)
	if level:
		Fx.smoke(level.fx_layer, global_position + Vector2(0, -22), 1.2)
		Fx.spark(level.fx_layer, global_position + Vector2(-6, -30))
		Fx.spark(level.fx_layer, global_position + Vector2(8, -14))
	collision_layer = 0
	collision_mask = 0
	remove_from_group("interactables")
	remove_from_group("melee_targets")
	remove_from_group("doors")
	sprite.visible = false
	if collision:
		collision.set_deferred("disabled", true)
	queue_free()
