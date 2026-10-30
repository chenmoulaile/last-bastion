extends Node
## Short scripted combat used with --write-movie for frame-accurate evidence.
## Run:
##   Godot --path . --write-movie out/gold_audit.avi --fixed-fps 60 \
##       res://tests/movie_demo.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.selected_character = &"assault"
	var empty_squad: Array[StringName] = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL", &"assault", empty_squad)
	var level: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(level)
	await get_tree().create_timer(1.0, true, false, true).timeout
	var player: Node2D = level.get_player()
	player.set("iframes", 9999.0)
	var px := player.global_position.x
	for i in 10:
		var x := px + 60.0 + float(i) * 18.0
		level.call("_spawn_zombie", &"common", Vector2(x, level.call("get_ground_y", x)), true)
	level.call("spawn_special", &"hunter")
	await get_tree().create_timer(0.5, true, false, true).timeout
	Input.action_press("fire")
	await get_tree().create_timer(1.5, true, false, true).timeout
	var barrels: Array = get_tree().get_nodes_in_group("barrels")
	if not barrels.is_empty():
		barrels[0].global_position = player.global_position + Vector2(84.0, 0.0)
		await get_tree().create_timer(0.2, true, false, true).timeout
		barrels[0].call("hit", 999)
	await get_tree().create_timer(1.5, true, false, true).timeout
	Input.action_release("fire")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit()
