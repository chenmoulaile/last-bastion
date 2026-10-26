class_name Pickup
extends Area2D
## Auto-collected supply / score pickup. Weapon pickups swap the player's
## primary weapon; everything else feeds the player's inventory.

var kind: String = "ammo"
var amount: int = 1
var weapon_id: String = ""
var level: Node = null
var sprite: Sprite2D
var base_y: float = 0.0
var time: float = 0.0
var collected: bool = false


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 64
	collision_mask = 2
	monitoring = true
	monitorable = false
	sprite = Sprite2D.new()
	sprite.texture = _texture_for_kind()
	sprite.z_index = 4
	if kind == "weapon":
		sprite.scale = Vector2(1.6, 1.6)
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 13.0 if kind == "weapon" else 10.0
	shape.shape = circle
	add_child(shape)
	base_y = position.y
	body_entered.connect(_on_body_entered)
	# Gentle glow to make supplies readable against dark floors.
	var glow := Sprite2D.new()
	glow.texture = SpriteLibrary.ui_texture("crosshair")
	glow.modulate = Color(1.0, 0.9, 0.45, 0.25)
	glow.scale = Vector2(2.4, 2.4)
	glow.z_index = 3
	add_child(glow)


func _texture_for_kind() -> Texture2D:
	match kind:
		"ammo":
			return SpriteLibrary.prop_texture("pickup_ammo")
		"medkit":
			return SpriteLibrary.prop_texture("pickup_medkit")
		"pills":
			return SpriteLibrary.prop_texture("pickup_pills")
		"grenade":
			return SpriteLibrary.prop_texture("pickup_grenade")
		"molotov":
			return SpriteLibrary.prop_texture("pickup_molotov")
		"bile":
			return SpriteLibrary.prop_texture("pickup_bile")
		"gold":
			return SpriteLibrary.prop_texture("pickup_gold")
		"weapon":
			return SpriteLibrary.weapon_texture(weapon_id)
		_:
			return SpriteLibrary.prop_texture("pickup_ammo")


func _process(delta: float) -> void:
	time += delta
	position.y = base_y + sin(time * 3.0) * 2.0


func _on_body_entered(body: Node) -> void:
	if collected or not body.is_in_group("player"):
		return
	collected = true
	set_deferred("monitoring", false)
	_apply(body)
	EventBus.pickup_collected.emit(StringName(kind), amount)
	AudioManager.play_sfx(&"pickup")
	queue_free()


func _apply(player: Node) -> void:
	match kind:
		"ammo":
			if player.has_method("add_ammo"):
				player.add_ammo(amount if amount > 1 else 90)
			EventBus.notify.emit("拾取弹药")
		"medkit":
			if player.has_method("add_medkit"):
				player.add_medkit(amount)
			EventBus.notify.emit("拾取医疗包")
		"pills":
			if player.has_method("add_pills"):
				player.add_pills(amount)
			EventBus.notify.emit("拾取药丸")
		"grenade", "molotov", "bile":
			if player.has_method("add_throwable"):
				player.add_throwable(kind, amount)
			EventBus.notify.emit("拾取 " + {"grenade": "手雷", "molotov": "燃烧瓶", "bile": "胆汁瓶"}[kind])
		"gold":
			if level:
				level.add_score(amount)
			EventBus.notify.emit("+%d 分" % amount)
		"health":
			if player.has_method("heal"):
				player.heal(amount)
			EventBus.notify.emit("恢复生命")
		"weapon":
			if player.has_method("give_weapon") and weapon_id != "":
				player.give_weapon(StringName(weapon_id))
		_:
			if player.has_method("add_ammo"):
				player.add_ammo(60)
