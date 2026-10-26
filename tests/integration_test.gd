extends Node
## Focused integration pass for the systems that the campaign test does not
## exercise directly: doors/barrels/crates/pickups, checkpoint respawn,
## defense/extraction completion, save persistence, achievements and the
## adaptive audio layer switcher.
## Run: Godot --headless --path . res://tests/integration.tscn

var _failures: Array[String] = []
var _checks: int = 0
var _original_save: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_original_save = SaveSystem.data.duplicate(true)
	await _test_interactables()
	await _test_checkpoint_respawn()
	await _test_downed_flow()
	await _test_control_immunity()
	await _test_defense()
	await _test_spawn_caps()
	await _test_debug_tools()
	await _test_command_mode()
	await _test_window_rappel()
	await _test_scoring()
	await _test_audio_layers()
	await _test_save_persistence()
	await _test_extraction()
	# Never leave test progress behind in the player's real save.
	SaveSystem.data = _original_save
	SaveSystem.save()
	print("[INTEGRATION] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[INTEGRATION] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[INTEGRATION] FAIL: " + failure)
		print("[INTEGRATION] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _open_level(id: StringName, mode: StringName = &"SQUAD") -> Node:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(id, mode, &"NORMAL")
	var path := "res://scenes/levels/%s.tscn" % String(id)
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await _wait(0.9)
	return scene


func _close_level(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await _frames(2)
	GameManager.change_state(GameManager.State.MENU)


func _test_interactables() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	_check(player != null, "interactables: player exists")

	# --- Door: two kicks must break it and count both kicks. ---
	var doors := get_tree().get_nodes_in_group("doors")
	_check(doors.size() >= 1, "door spawned")
	if doors.size() >= 1:
		var door = doors[0]
		var kicks_before := int(scene.get("_doors_kicked"))
		door.kick_cd = 0.0
		door.interact(player)
		_check(int(door.health) < int(door.max_health), "door damaged by kick")
		door.kick_cd = 0.0
		door.interact(player)
		_check(bool(door.broken), "door breaks after two kicks")
		_check(int(scene.get("_doors_kicked")) >= kicks_before + 2, "door kicks counted")

	# --- Barrel: explosion must kill a nearby common infected. ---
	var barrels := get_tree().get_nodes_in_group("barrels")
	_check(barrels.size() >= 1, "explosive barrel spawned")
	if barrels.size() >= 1:
		var barrel = barrels[0]
		var victim = scene.call("_spawn_zombie", &"common",
			barrel.global_position + Vector2(10, 0), false)
		_check(victim != null, "barrel victim spawned")
		barrel.hit(999)
		_check(bool(barrel.exploded), "barrel explodes when shot")
		await _wait(0.35)
		var victim_dead: bool = not is_instance_valid(victim) or bool(victim.get("dead"))
		_check(victim_dead, "barrel explosion kills nearby infected")

	# --- Crate: breaking it must drop loot. ---
	var crates := get_tree().get_nodes_in_group("melee_targets").filter(
		func(node: Node) -> bool: return node is BreakableCrate)
	_check(crates.size() >= 1, "breakable crate spawned")
	if crates.size() >= 1:
		var crate = crates[0]
		var pickups_before := get_tree().get_nodes_in_group("pickups").size()
		crate.hit(999)
		_check(bool(crate.broken), "crate breaks when hit")
		await _wait(0.25)
		_check(get_tree().get_nodes_in_group("pickups").size() > pickups_before,
			"crate drops a pickup")

	# --- Pickup: walking over gold must add score and consume the pickup. ---
	var score_before := int(scene.get("_score"))
	var gold := Pickup.new()
	gold.kind = "gold"
	gold.amount = 1234
	gold.level = scene
	gold.position = player.global_position
	var pickup_root: Node = scene.get("pickups")
	if pickup_root == null:
		pickup_root = scene
	pickup_root.add_child(gold)
	await _wait(0.4)
	_check(int(scene.get("_score")) >= score_before + 1234, "gold pickup adds score")
	_check(not is_instance_valid(gold) or bool(gold.get("collected")), "gold pickup consumed")

	await _close_level(scene)
	print("[INTEGRATION] interactables ok")


func _test_checkpoint_respawn() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var checkpoint := player.global_position
	scene.call("_on_checkpoint_trigger", player)
	_check(bool(scene.get("_checkpoint_active")), "checkpoint activates")
	var respawn: Vector2 = scene.get("_respawn_pos")
	_check(respawn.distance_to(checkpoint) < 2.0, "checkpoint records respawn position")

	player.call("die")
	_check(bool(player.get("is_dead")), "player enters dead state")
	await _wait(2.9)
	_check(not bool(player.get("is_dead")), "checkpoint respawns player")
	_check(int(player.get("hp")) > 0, "checkpoint respawn restores health")
	_check(player.global_position.distance_to(respawn) < 80.0,
		"checkpoint respawn returns player to checkpoint")
	await _close_level(scene)
	print("[INTEGRATION] checkpoint ok")


func _test_downed_flow() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	player.call("heal_full")
	player.set("iframes", 0.0)
	player.take_damage(999, Vector2.RIGHT, &"zombie", &"melee")
	_check(bool(player.get("is_downed")), "downed: lethal damage downs player")
	_check(int(player.get("hp")) == 0, "downed: hp reaches zero")
	player.revive(player)
	_check(not bool(player.get("is_downed")), "downed: revive restores control")
	_check(int(player.get("temp_hp")) == 30, "downed: revive grants 30 temp hp")
	player.set("iframes", 0.0)
	player.take_damage(999, Vector2.RIGHT, &"zombie", &"melee")
	player.revive(player)
	_check(bool(player.get("black_white")), "downed: second revive enters black-and-white")
	_check(int(player.get("max_hp")) == 1, "downed: black-and-white caps max hp")
	player.call("_finish_medkit")
	_check(not bool(player.get("black_white")), "downed: medkit clears black-and-white")
	_check(int(player.get("max_hp")) > 1, "downed: medkit restores max hp")
	var temp_before := int(player.get("temp_hp"))
	player.call("_use_pills")
	_check(int(player.get("temp_hp")) == mini(100, temp_before + 50), "downed: pills grant 50 temp hp")
	await _close_level(scene)
	print("[INTEGRATION] downed flow ok")


func _test_control_immunity() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	player.call("heal_full")
	player.call("enter_control", &"hunter", player)
	_check(bool(player.get("is_controlled")), "control: hunter pin applies")
	player.call("release_control")
	_check(not bool(player.get("is_controlled")), "control: release clears state")
	_check(is_equal_approx(float(player.get("control_immune")), 3.0),
		"control: release grants 3s immunity")
	player.call("enter_control", &"smoker", player)
	_check(not bool(player.get("is_controlled")), "control: immunity blocks chain control")
	await _close_level(scene)
	print("[INTEGRATION] control immunity ok")


func _test_defense() -> void:
	var scene := await _open_level(&"l01")
	var score_before := int(scene.get("_score"))
	scene.call("start_defense", 0.35, 1, 4)
	_check(bool(scene.call("is_defense_active")), "defense starts")
	await _wait(0.65)
	_check(not bool(scene.call("is_defense_active")), "defense completes on timer")
	_check(int(scene.get("_score")) >= score_before + 3000, "defense awards completion score")
	await _close_level(scene)
	print("[INTEGRATION] defense ok")


func _test_spawn_caps() -> void:
	var scene := await _open_level(&"l01")
	DirectorSystem.end_level()
	for kind in [&"hunter", &"smoker", &"boomer", &"charger", &"spitter", &"jockey", &"tank", &"witch"]:
		scene.spawn_special(kind)
	await _frames(2)
	var specials := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
			continue
		var zd: ZombieData = zombie.get("data")
		if zd != null and zd.is_special and zd.id != &"witch":
			specials += 1
	_check(specials <= 4, "same-screen special cap <= 4")
	_check(specials >= 3, "special cap still allows a full wave")

	var player: Node2D = scene.get_player()
	scene.spawn_horde_at(player.global_position, 200, false)
	await _frames(2)
	var commons := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
			continue
		var zd: ZombieData = zombie.get("data")
		if zd != null and not zd.is_special:
			commons += 1
	_check(commons <= 120, "same-screen common cap <= 120")
	_check(commons >= 80, "common cap still allows a large horde")
	await _close_level(scene)
	print("[INTEGRATION] spawn caps ok")


func _test_debug_tools() -> void:
	var scene := await _open_level(&"l01")
	var hud: Node = scene.get("hud")
	_check(hud != null, "debug: hud exists")
	if hud != null:
		EventBus.debug_panel_toggled.emit()
		await _frames(1)
		_check(bool(hud.get("_debug_open")), "debug: F10 panel opens")
		EventBus.debug_vision_toggled.emit()
		await _frames(1)
		var arrows = hud.get("_threat_arrows")
		_check(arrows != null and bool(arrows.get("debug_vision")), "debug: vision overlay toggles")
		EventBus.debug_vision_toggled.emit()
		EventBus.debug_panel_toggled.emit()
		await _frames(1)
		_check(not bool(hud.get("_debug_open")), "debug: F10 panel closes")

	Engine.time_scale = 1.0
	scene.call("_debug_cycle_time_scale")
	_check(is_equal_approx(Engine.time_scale, 2.0), "debug: time scale cycles")
	scene.call("_debug_cycle_time_scale")
	scene.call("_debug_cycle_time_scale")
	_check(is_equal_approx(Engine.time_scale, 1.0), "debug: time scale restores")
	Engine.time_scale = 1.0

	var before := get_tree().get_nodes_in_group("zombies").size()
	scene.call("_debug_spawn_special")
	await _frames(1)
	_check(get_tree().get_nodes_in_group("zombies").size() > before, "debug: spawn special works")
	await _close_level(scene)
	print("[INTEGRATION] debug tools ok")


func _test_command_mode() -> void:
	var scene := await _open_level(&"l07", &"COMMAND")
	var allies: Array = scene.get_allies()
	_check(allies.size() >= 4, "command: squad spawned")
	var gunner: Node = null
	var demolisher: Node = null
	for a in allies:
		if a == null or not is_instance_valid(a):
			continue
		var d = a.get("data")
		if d == null:
			continue
		if d.soldier_role == &"gunner":
			gunner = a
		elif d.soldier_role == &"demolisher":
			demolisher = a
	_check(gunner != null, "command: gunner role present")
	_check(demolisher != null, "command: demolisher role present")
	_check(demolisher != null and int(demolisher.get("grenade_count")) == 2,
		"command: demolisher starts with two grenades")
	var roster: Array = scene.get("_soldier_roster")
	var victim: Node = allies[0]
	victim.die()
	_check(int(scene.get("_soldiers_lost")) >= 1, "command: soldier loss counted")
	scene.call("_on_checkpoint_trigger", scene.get_player())
	await _wait(0.25)
	var alive := 0
	for a in scene.get_allies():
		if a != null and is_instance_valid(a) and not bool(a.get("is_dead")):
			alive += 1
	_check(alive == mini(8, roster.size()), "command: checkpoint reinforces full roster")
	scene.get_player().call("die")
	await _wait(2.0)
	_check(bool(GameManager.last_result.get("failed", false)), "command: commander death fails run")
	_check(String(GameManager.last_result.get("reason", "")).contains("指挥官"),
		"command: defeat reason recorded")
	await _close_level(scene)
	print("[INTEGRATION] command mode ok")


func _test_window_rappel() -> void:
	var scene := await _open_level(&"l01")
	var windows := get_tree().get_nodes_in_group("windows")
	_check(windows.size() >= 1, "window rappel: window spawned")
	if windows.size() > 0:
		var window = windows[0]
		var player: Node2D = scene.get_player()
		player.global_position = Vector2(window.global_position.x, window.global_position.y - 2.0)
		var ground_y: float = scene.get_ground_y(window.global_position.x)
		window.interact(player)
		_check(bool(player.get("rappelling")), "window rappel: descent starts")
		await _wait(0.6)
		_check(not bool(player.get("rappelling")), "window rappel: descent finishes")
		_check(absf(player.global_position.y - ground_y) < 4.0, "window rappel: lands on street")
	await _close_level(scene)
	print("[INTEGRATION] window rappel ok")


func _test_scoring() -> void:
	var scene := await _open_level(&"l01")
	scene.set("_combo", 10)
	_check(is_equal_approx(float(scene.call("get_combo_mult")), 3.5), "scoring: combo multiplier")
	scene.set("_combo", 100)
	_check(is_equal_approx(float(scene.call("get_combo_mult")), 5.0), "scoring: combo multiplier caps at 5")
	_check(GameManager.rank_for(152000, 160000) == "S", "scoring: S threshold")
	_check(GameManager.rank_for(128000, 160000) == "A", "scoring: A threshold")
	_check(GameManager.rank_for(96000, 160000) == "B", "scoring: B threshold")
	_check(GameManager.rank_for(95000, 160000) == "C", "scoring: C threshold")
	scene.set("_score", 0)
	scene.set("_elapsed", 0.0)
	scene.call("_finish_level")
	await _wait(1.7)
	_check(int(GameManager.last_result.get("score", 0)) >= 100000, "scoring: base score included")
	_check(String(GameManager.last_result.get("rank", "")) in ["S", "A"], "scoring: fast clean run ranks high")
	await _close_level(scene)
	print("[INTEGRATION] scoring ok")


func _test_audio_layers() -> void:
	# The Director owns intensity during normal play; stop it so the manual
	# layer transitions below are not overwritten mid-test.
	DirectorSystem.end_level()
	AudioManager.play_level_music("suburb")
	_check(bool(AudioManager.get("_music_started")), "level music starts")
	var layers: Dictionary = AudioManager.get("_layers")
	_check(layers.size() == 4, "four music layers exist")
	for layer in AudioManager.MUSIC_LAYERS:
		var p: AudioStreamPlayer = layers.get(layer)
		_check(p != null and p.stream != null, "music layer loaded: " + String(layer))
	AudioManager.set_intensity(0.9)
	_check(is_equal_approx(float(AudioManager.get("_intensity")), 0.9), "director intensity applies")
	await _wait(1.75)
	var combat: AudioStreamPlayer = layers.get("combat")
	var horde: AudioStreamPlayer = layers.get("horde")
	_check(combat.volume_db > -6.0, "combat layer audible at high intensity")
	_check(horde.volume_db > -6.0, "horde layer audible at high intensity")
	AudioManager.set_tank_active(true)
	await _wait(0.55)
	var tank: AudioStreamPlayer = layers.get("tank")
	_check(tank.volume_db > -6.0, "tank layer takes over")
	AudioManager.set_tank_active(false)
	AudioManager.play_ambience(&"rain")
	var ambience: AudioStreamPlayer = AudioManager.get("_ambience_player")
	_check(ambience.playing, "ambience bed plays")
	AudioManager.stop_level_music()
	_check(not bool(AudioManager.get("_music_started")), "level music stops")
	print("[INTEGRATION] audio ok")


func _test_save_persistence() -> void:
	SaveSystem.set_flag(&"integration_probe")
	SaveSystem.mark_achievement(&"first_blood")
	SaveSystem.unlock_character(&"ninja")
	SaveSystem.save()
	_check(FileAccess.file_exists(SaveSystem.SAVE_PATH), "save file written")

	# Corrupt the in-memory copy, then prove it is reloaded from disk.
	SaveSystem.data["flags"] = []
	SaveSystem.data["achievements"] = []
	SaveSystem.data["unlocks"]["characters"] = []
	SaveSystem.load_game()
	_check(SaveSystem.has_flag(&"integration_probe"), "save flag survives reload")
	_check(SaveSystem.has_achievement(&"first_blood"), "achievement survives reload")
	_check(SaveSystem.is_character_unlocked(&"ninja"), "character unlock survives reload")

	var level := GameManager.get_level(&"l01")
	_check(level != null, "achievement test level exists")
	if level != null:
		var result := {
			"failed": false, "score": 99000, "rank": "S", "max_combo": 50,
			"squad_alive": 4, "soldiers_start": 8, "soldiers_lost": 0,
			"tanks_killed": 1, "tank_kill_time": 42.0, "witch_woken": false,
			"defense_downs": 0, "max_molotov_kills": 0, "codex": [], "hidden_rooms": [],
		}
		var achievements_before: int = SaveSystem.data["achievements"].size()
		SaveSystem.evaluate_result_achievements(result, level, &"SQUAD", &"NORMAL")
		_check(SaveSystem.has_achievement(&"first_blood"), "first_blood awarded on l01")
		_check(SaveSystem.has_achievement(&"mr_perfect"), "S-rank achievement awarded")
		_check(SaveSystem.data["achievements"].size() >= achievements_before,
			"achievement list grows")
	print("[INTEGRATION] persistence ok")


func _test_extraction() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var level_width := float(scene.get("level_width"))
	player.global_position = Vector2(level_width - 150.0,
		float(scene.call("get_ground_y", level_width - 150.0)))
	scene.call("_on_extraction_trigger", player)
	_check(bool(scene.get("_finishing")), "extraction starts mission finish")
	await _wait(1.7)
	_check(GameManager.state == GameManager.State.RESULT, "extraction reaches result state")
	_check(not bool(GameManager.last_result.get("failed", true)), "extraction result succeeds")
	_check(String(GameManager.last_result.get("level_id", "")) == "l01",
		"extraction result carries level id")
	await _close_level(scene)
	print("[INTEGRATION] extraction ok")
