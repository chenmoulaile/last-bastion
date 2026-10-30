extends Node
## Headless integration smoke test. Run:
##   Godot --headless --path . res://tests/smoke.tscn
## It instantiates every menu and two playable levels, exercises core combat
## APIs and fails loudly if required nodes are missing.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("[SMOKE] data: levels=%d weapons=%d characters=%d zombies=%d" % [
		GameManager.levels.size(), GameManager.weapons.size(),
		GameManager.characters.size(), GameManager.zombies.size()])
	_check(GameManager.levels.size() == 11, "11 levels loaded")
	_check(GameManager.weapons.size() >= 12, "12+ weapons loaded")
	_check(GameManager.characters.size() >= 10, "10+ characters loaded")
	_check(GameManager.zombies.size() >= 15, "15+ zombie entries loaded")

	await _test_screens()
	await _test_level("res://scenes/levels/l01.tscn", &"SQUAD", 3)
	await _test_level("res://scenes/levels/l07.tscn", &"COMMAND", 6)
	await _test_screens_after()

	print("[SMOKE] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[SMOKE] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[SMOKE] FAIL: " + failure)
		print("[SMOKE] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _test_screens() -> void:
	var screens := [
		["res://scenes/ui/main_menu.tscn", {}],
		["res://scenes/ui/level_select.tscn", {"level_id": "l01"}],
		["res://scenes/ui/briefing.tscn", {"level_id": "l01", "mode": "SQUAD", "difficulty": "NORMAL"}],
		["res://scenes/ui/character_select.tscn", {"from": "levels"}],
		["res://scenes/ui/settings.tscn", {}],
		["res://scenes/ui/achievements.tscn", {}],
		["res://scenes/ui/codex.tscn", {}],
		["res://scenes/ui/credits.tscn", {}],
	]
	for row in screens:
		var path: String = row[0]
		var inst = load(path).instantiate()
		if inst.has_method("setup"):
			inst.setup(row[1])
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(is_instance_valid(inst), "screen instantiates: " + path)
		inst.queue_free()
		await get_tree().process_frame
	print("[SMOKE] menus instantiated")


func _test_screens_after() -> void:
	GameManager.last_result = {
		"failed": false, "score": 180000, "rank": "S", "time": 211.0,
		"kills": 120, "headshots": 33, "specials": 7, "rescues": 2,
		"max_combo": 31, "squad_alive": 4, "soldiers_start": 0, "soldiers_lost": 0,
		"doors_kicked": 5, "hunter_interrupts": 1, "witch_crowns": 0,
		"barrel_kills": 4, "molotov_kills": 3, "tanks_killed": 1,
		"witch_woken": false, "hidden_rooms": ["l01_hidden"], "codex": ["hunter"],
		"level_id": "l01", "level_title": "街道突破口", "mode": "SQUAD",
		"difficulty": "NORMAL", "new_achievements": ["first_blood"],
	}
	var result = load("res://scenes/ui/result.tscn").instantiate()
	add_child(result)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(result), "result screen instantiates")
	result.queue_free()
	await get_tree().process_frame


func _test_level(path: String, mode: StringName, expected_allies: int) -> void:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(StringName(path.get_file().get_basename()), mode, &"NORMAL")
	_check(GameManager.state == GameManager.State.PLAYING, "state PLAYING for " + path)
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await get_tree().create_timer(0.9, true, false, true).timeout
	_check(scene.get("data") != null, "level data bound: " + path)
	_check(scene.get_player() != null, "player spawned: " + path)
	_check(scene.get_allies().size() == expected_allies, "ally count %d: %s" % [expected_allies, path])
	_check(scene.get("hud") != null, "hud built: " + path)
	_check(scene.ground_segments.size() > 0, "terrain built: " + path)

	var player: Node2D = scene.get_player()
	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	await get_tree().create_timer(0.45, true, false, true).timeout
	Input.action_release("move_right")
	_check(player.global_position.x > start_x + 10.0, "player moves: " + path)

	Input.action_press("fire")
	await get_tree().create_timer(0.22, true, false, true).timeout
	Input.action_release("fire")
	Input.action_press("jump")
	await get_tree().create_timer(0.12, true, false, true).timeout
	Input.action_release("jump")
	Input.action_press("melee")
	await get_tree().create_timer(0.12, true, false, true).timeout
	Input.action_release("melee")

	scene.spawn_horde_at(player.global_position, 12, true)
	scene.spawn_special(&"hunter")
	scene.spawn_boss(&"tank")
	scene.start_defense(4.0, 1, 4)
	await get_tree().create_timer(0.7, true, false, true).timeout
	_check(get_tree().get_nodes_in_group("zombies").size() >= 5, "zombies spawned: " + path)
	_check(get_tree().get_nodes_in_group("player").size() == 1, "single player group: " + path)

	if mode == &"COMMAND":
		EventBus.command_issued.emit(&"hold")
		await get_tree().create_timer(0.15, true, false, true).timeout
		_check(scene.get_allies().size() == expected_allies, "command squad intact: " + path)

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.change_state(GameManager.State.MENU)
	print("[SMOKE] level ok: %s" % path)
