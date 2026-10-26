class_name HazardZone
extends Area2D
## Acid pool / molotov fire. Damages survivors and infected standing inside.
## Player-owned fire credits zombie kills to the player for scoring.

var kind: String = "acid"
var radius: float = 60.0
var duration: float = 4.0
var dps: float = 18.0
var source: StringName = &"fire"
var player_owned: bool = false
var level: Node = null
var sprite: Sprite2D
var tick_timer: float = 0.0
var life: float = 0.0
var fire_fx_timer: float = 0.0


func _ready() -> void:
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 2 | 4 | 8 | 16
	monitoring = true
	monitorable = false
	life = duration
	sprite = Sprite2D.new()
	if kind == "fire":
		sprite.texture = SpriteLibrary.prop_texture("fire_zone")
		sprite.scale = Vector2(radius / 16.0, radius / 18.0)
		sprite.modulate = Color(1.0, 0.9, 0.7, 0.95)
	else:
		sprite.texture = SpriteLibrary.prop_texture("acid_pool")
		sprite.scale = Vector2(radius / 22.0, radius / 16.0)
		sprite.modulate = Color(0.8, 1.0, 0.45, 0.9)
	sprite.z_index = 1
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	z_index = 1


func _process(delta: float) -> void:
	life -= delta
	tick_timer -= delta
	fire_fx_timer -= delta
	if kind == "fire":
		sprite.modulate.a = 0.75 + sin(life * 14.0) * 0.15
		if fire_fx_timer <= 0.0 and level:
			fire_fx_timer = 0.22
			Fx.fire(level.fx_layer, global_position + Vector2(randf_range(-radius * 0.55, radius * 0.55), -4), randf_range(0.6, 1.1))
	else:
		sprite.modulate.a = 0.7 + sin(life * 5.0) * 0.12
	if life <= 0.0:
		queue_free()
		return
	if tick_timer > 0.0:
		return
	tick_timer = 0.38
	_damage_tick()


func _damage_tick() -> void:
	var hit_source: StringName = &"player" if player_owned else source
	var dtype: StringName = &"fire" if kind == "fire" else &"acid"
	for body in get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue
		if body.is_in_group("zombies"):
			if body.has_method("apply_damage"):
				body.apply_damage(int(dps * 0.42), Vector2.ZERO, false, hit_source, dtype)
			if kind == "acid":
				body.slow_timer = maxf(float(body.get("slow_timer")), 0.8)
			elif kind == "fire":
				body.burn_timer = maxf(float(body.get("burn_timer")), 1.2)
				body.burn_dps = 7.0
		elif body.is_in_group("player"):
			if body.has_method("take_damage"):
				body.take_damage(int(dps * 0.32), Vector2.ZERO, &"fire" if kind == "fire" else &"acid", dtype)
				if kind == "fire" and body.has_method("apply_burn"):
					body.apply_burn(4.0, 1.0)
		elif body.is_in_group("allies"):
			if body.has_method("take_damage"):
				body.take_damage(int(dps * 0.28), Vector2.ZERO, &"fire" if kind == "fire" else &"acid", dtype)
