class_name WindowRappel
extends Node2D
## A window frame on an upper platform. Press E next to it to rappel down to
## the street below; the descent is fast, gives brief invulnerability and
## leaves a rope behind for a moment. This is the side-scrolling version of
## the spec's window rappel traversal.

var level: Node = null
var sprite: Sprite2D
var cooldown: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("windows")
	sprite = Sprite2D.new()
	sprite.texture = SpriteLibrary.prop_texture("window_frame")
	sprite.centered = false
	sprite.position = Vector2(-16, -48)
	sprite.z_index = 2
	add_child(sprite)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)


func get_prompt() -> String:
	if cooldown > 0.0 or level == null:
		return ""
	var player: Node2D = level.get_player()
	if player == null or not is_instance_valid(player):
		return ""
	if bool(player.get("is_dead")) or bool(player.get("is_downed")):
		return ""
	return "E 绳降"


func interact(player: Node) -> void:
	if cooldown > 0.0 or level == null:
		return
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("start_rappel"):
		return
	var ground_y: float = level.get_ground_y(global_position.x)
	if ground_y < 0.0:
		return
	if not bool(player.start_rappel(ground_y)):
		return
	cooldown = 1.2
	_spawn_rope(ground_y)


func _spawn_rope(ground_y: float) -> void:
	if level == null or not is_instance_valid(level.fx_layer):
		return
	var rope := Line2D.new()
	rope.width = 1.0
	rope.default_color = Color(0.62, 0.48, 0.28, 0.9)
	rope.z_index = 17
	rope.add_point(global_position + Vector2(0, -40))
	rope.add_point(Vector2(global_position.x, ground_y))
	level.fx_layer.add_child(rope)
	var tween := rope.create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(rope, "modulate:a", 0.0, 0.45)
	tween.finished.connect(rope.queue_free)
