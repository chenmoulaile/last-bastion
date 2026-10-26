extends Node
## Full campaign integration pass: instantiates all 11 levels, exercises every
## weapon/skill/throwable, spawns every special and finishes the mission.
## Run: Godot --headless --path . res://tests/campaign.tscn

var _failures: Array[String] = []
var _checks: int = 0
var _characters: Array[StringName] = [&"assault", &"heavy", &"medic", &"scout", &"ninja", &"officer"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	for i in 11:
		var id := "l%02d" % (i + 1)
		var character: StringName = _characters[i % _characters.size()]
		await _test_level(id, character, i)
	print("[CAMPAIGN] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[CAMPAIGN] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[CAMPAIGN] FAIL: " + failure)
		print("[CAMPAIGN] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _test_level(id: String, character: StringName, index: int) -> void:
	var level := GameManager.get_level(StringName(id))
	if level == null:
		_check(false, "level data missing: " + id)
		return
	GameManager.selected_character = character
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	var mode := GameManager.default_mode_for(level)
	GameManager.start_level(StringName(id), mode, &"NORMAL")
	var path := "res://scenes/levels/%s.tscn" % id
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await get_tree().create_timer(0.85, true, false, true).timeout

	_check(scene.get("data") != null, "level data bound: " + id)
	_check(scene.get_player() != null, "player spawned: " + id)
	var expected := 3
	if mode == &"COMMAND":
		expected = mini(8, level.commander_squad.size()) if level.commander_squad.size() > 0 else 6
	_check(scene.get_allies().size() == expected, "ally count %d: %s" % [expected, id])
	_check(scene.ground_segments.size() > 0, "terrain built: " + id)
	_check(scene.get("hud") != null, "hud built: " + id)
	_check(GameManager.current_mode == mode, "mode bound: " + id)

	var player: Node2D = scene.get_player()
	# Spawn each special in turn so the same-screen special cap (4) is respected.
	var spawned: Array = []
	var collector := func(kind: StringName) -> void:
		spawned.append(kind)
	EventBus.special_spawned.connect(collector)
	for kind in [&"hunter", &"smoker", &"boomer", &"charger", &"spitter", &"jockey", &"witch"]:
		spawned.clear()
		scene.spawn_special(kind)
		await get_tree().create_timer(0.12, true, false, true).timeout
		_check(kind in spawned, "special spawned: %s %s" % [String(kind), id])
		for zombie in get_tree().get_nodes_in_group("zombies"):
			if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
				continue
			var zd: ZombieData = zombie.get("data")
			if zd != null and zd.is_special:
				zombie.apply_damage(99999, Vector2.RIGHT, true, &"player", &"bullet")
		await get_tree().create_timer(0.12, true, false, true).timeout
	EventBus.special_spawned.disconnect(collector)
	scene.spawn_boss(&"tank")
	await get_tree().create_timer(0.12, true, false, true).timeout
	var tank_found := false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
			continue
		var zd: ZombieData = zombie.get("data")
		if zd != null and zd.id == &"tank":
			tank_found = true
			break
	_check(tank_found, "tank spawned: " + id)
	await get_tree().create_timer(0.25, true, false, true).timeout
	await get_tree().create_timer(0.5, true, false, true).timeout
	# Melee shove + skill + damage/heal before clearing the field.
	Input.action_press("melee")
	await get_tree().create_timer(0.1, true, false, true).timeout
	Input.action_release("melee")
	player.call("_use_skill")
	await get_tree().create_timer(0.15, true, false, true).timeout
	player.take_damage(12, Vector2.RIGHT, &"zombie", &"melee")
	player.heal(30)
	_check(int(player.get("hp")) > 0, "player survives damage: " + id)

	# Every gun and melee weapon.
	for weapon in GameManager.weapons.values():
		var category := StringName(weapon.category)
		if category != &"primary" and category != &"melee":
			continue
		player.give_weapon(weapon.id)
		await get_tree().create_timer(0.04, true, false, true).timeout
		Input.action_press("fire")
		await get_tree().create_timer(0.12, true, false, true).timeout
		Input.action_release("fire")
		await get_tree().create_timer(0.04, true, false, true).timeout
	# Every throwable.
	for kind in ["grenade", "molotov", "bile"]:
		player.add_throwable(kind, 1)
		player.call("_throw_current")
		await get_tree().create_timer(0.45, true, false, true).timeout
	# Reload, pills and medkit bindings.
	Input.action_press("reload")
	await get_tree().create_timer(0.1, true, false, true).timeout
	Input.action_release("reload")
	Input.action_press("pills")
	await get_tree().create_timer(0.1, true, false, true).timeout
	Input.action_release("pills")
	Input.action_press("medkit")
	await get_tree().create_timer(0.1, true, false, true).timeout
	Input.action_release("medkit")
	await get_tree().create_timer(0.35, true, false, true).timeout

	# Clear the field and finish through the normal mission path.
	for _i in 2:
		for zombie in get_tree().get_nodes_in_group("zombies"):
			if is_instance_valid(zombie) and not bool(zombie.get("dead")):
				zombie.apply_damage(99999, Vector2.RIGHT, true, &"player", &"bullet")
		await get_tree().create_timer(0.3, true, false, true).timeout
	var alive := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if is_instance_valid(zombie) and not bool(zombie.get("dead")):
			alive += 1
	print("[CAMPAIGN] field after clear: %d alive (director waves allowed)" % alive)

	scene.call("_finish_level")
	await get_tree().create_timer(1.65, true, false, true).timeout
	_check(GameManager.state == GameManager.State.RESULT, "result state: " + id)
	_check(String(GameManager.last_result.get("level_id", "")) == id, "result level id: " + id)
	_check(int(GameManager.last_result.get("score", -1)) >= 0, "result score: " + id)
	_check(String(GameManager.last_result.get("rank", "")) != "", "result rank: " + id)

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.change_state(GameManager.State.MENU)
	print("[CAMPAIGN] level ok: %s (%s, %s)" % [id, String(mode), String(character)])
