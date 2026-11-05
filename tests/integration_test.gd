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
	await _test_interior_rooms()
	await _test_crash_chain_regression()
	await _test_interior_full_flow()
	await _test_door_entry_residency()
	await _test_interior_walkthrough()
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


## wp8：受 Engine.time_scale 影响的游戏时间等待（_wait 是 ignore_time_scale 的真实时间）。
func _wait_game(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, false).timeout


## wp8：记录一段 objective_changed 文本并断言其中从未出现「任务完成」。
class ObjectiveRecorder:
	var texts: Array[String] = []

	func attach() -> void:
		EventBus.objective_changed.connect(_on_text)

	func detach() -> void:
		if EventBus.objective_changed.is_connected(_on_text):
			EventBus.objective_changed.disconnect(_on_text)

	func _on_text(t: String) -> void:
		texts.append(t)

	func saw_mission_complete() -> bool:
		for t in texts:
			if t.contains("任务完成"):
				return true
		return false


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
		# 建筑窗洞随地形随机生成，可能悬在坑洞上方（get_ground_y<0 时 interact 静默跳过）；
		# 取第一个脚下有真实地面的窗（wp8 加固：原实现固定取 windows[0]，随机偶发失败）。
		var window: Node2D = null
		var ground_y := -1.0
		for w in windows:
			var gy: float = scene.get_ground_y(w.global_position.x)
			if gy >= 0.0:
				window = w
				ground_y = gy
				break
		_check(window != null, "window rappel: window above ground")
		if window != null:
			var player: Node2D = scene.get_player()
			player.global_position = Vector2(window.global_position.x, window.global_position.y - 2.0)
			window.interact(player)
			_check(bool(player.get("rappelling")), "window rappel: descent starts")
			await _wait(0.6)
			_check(not bool(player.get("rappelling")), "window rappel: descent finishes")
			_check(absf(player.global_position.y - ground_y) < 4.0, "window rappel: lands on street")
	await _close_level(scene)
	print("[INTEGRATION] window rappel ok")


## wp5-interior-rooms-harden + wp1-door-entry：打爆门不再传送（wp1 废除破门即传送），
## 玩家走入门洞 Area2D 才传送进远端房间，出口回街道（level_runner.gd:359-470）。
func _test_interior_rooms() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var level_width := float(scene.get("level_width"))
	var buildings: Array = scene.get("_buildings")
	var enterable: Array = buildings.filter(func(b): return bool(b.get("enterable", false)))
	var room_idx := 0
	for b in enterable:
		room_idx += 1
		var room: Dictionary = b.get("interior", {})
		# 断言1：房间建在 level_width+700+idx*1300 的远端实例区（level_runner.gd
		# _build_buildings；wp4 复杂室内占地最宽 768px，间距 760→1300）。
		_check(not room.is_empty() and (room["rect"] as Rect2).position.x > level_width,
			"interior: room#%d built at remote origin beyond level_width" % room_idx)
	if enterable.is_empty():
		_check(false, "interior: l01 has enterable buildings")
	var b0: Dictionary = enterable[0] if not enterable.is_empty() else {}
	var room0: Dictionary = b0.get("interior", {})
	if not room0.is_empty():
		var door_x := float(b0["door_x"])
		var ground_y := float(b0["ground_y"])
		var back := Vector2(door_x - 26.0, ground_y - 2.0)
		# 断言2（wp1）：远距打爆门不传送玩家——玩家原地不动，也不在室内 entry。
		var door: Node2D = null
		for d in get_tree().get_nodes_in_group("doors"):
			if absf(d.global_position.x - door_x) < 24.0:
				door = d
				break
		_check(door != null, "interior: enterable door spawned at door_x")
		# 断言2a（P1-4）：enterable 门免疫僵尸挠——12 只僵尸连挠 30 秒（0.75s 冷却内
		# 12 只轮番，等效持续挠门），门血量不变；门上标记 enterable=true。
		if door != null:
			_check(bool(door.get("enterable")), "interior: enterable door flagged enterable (P1-4)")
			var hp_before := int(door.get("health"))
			for _i in 12:
				door.set("scratch_cd", 0.0)
				door.call("zombie_scratch", null)
			_check(int(door.get("health")) == hp_before and not bool(door.get("broken")),
				"interior: 12 zombie scratches leave enterable door health intact (P1-4)")
			# 对照组：街面普通路障门（enterable=false）维持现状，挠门照样掉血。
			var barricade: Node2D = null
			for d in get_tree().get_nodes_in_group("doors"):
				if absf(d.global_position.x - door_x) > 24.0 and not bool(d.get("enterable")):
					barricade = d
					break
			if barricade != null:
				var bhp_before := int(barricade.get("health"))
				barricade.set("scratch_cd", 0.0)
				barricade.call("zombie_scratch", null)
				_check(int(barricade.get("health")) < bhp_before,
					"interior: barricade door still takes scratch damage (P1-4)")
		var street_pos := Vector2(600.0, ground_y - 2.0)
		player.global_position = street_pos
		if door != null:
			door.call("hit", 999)
		for _i in 10:
			await get_tree().physics_frame
		_check(player.global_position.distance_to(street_pos) < 50.0,
			"interior: door broken far away does NOT teleport player (wp1)")
		# 断言2b（wp1）：玩家站在门口、由玩家行为发起走入门洞 → 传送到 entry 并记录 _street_return。
		player.global_position = Vector2(door_x - 30.0, ground_y - 2.0)
		scene.call("_try_enter_interior", b0, null, true)
		_check(player.global_position.distance_to(room0["entry"]) < 0.5
				and (scene.get("_street_return") as Vector2).distance_to(back) < 0.5,
			"interior: walking into doorway teleports to entry and street return recorded (wp1)")
		# 断言3：走进出口 Area2D 被传回街道 back 点（:370-389）。
		var exit_area: Area2D = null
		for child in scene.get_children():
			if child is Area2D and (child as Area2D).position.distance_to(
					(room0["exit"] as Vector2) + Vector2(0, -8)) < 1.0:
				exit_area = child
				break
		if exit_area != null:
			player.global_position = exit_area.global_position
			for _i in 4:
				await get_tree().physics_frame
			_check(player.global_position.distance_to(back) < 8.0,
				"interior: exit area returns player to street")
		else:
			_check(false, "interior: exit area returns player to street")
	await _close_level(scene)
	print("[INTEGRATION] interior rooms ok")


## wp8-tests-ci：崩溃链回归（审计场景护栏，wp1/wp2/wp4 修复不得回退）。
## 链A：玩家 x=600 远距 hit(999) 打爆可进入门 → 10 物理帧位移 <50px、不进室内、不结算。
## 链B：玩家贴 17% 进度门，附近刷 12 只尸潮持续 30 游戏秒 → 玩家未被传送、
##      enterable 门不掉血不破、objective 从未出现「任务完成」。
func _test_crash_chain_regression() -> void:
	# ---------- 链A：远距打爆门不传送 ----------
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var buildings: Array = scene.get("_buildings")
	var enterable: Array = buildings.filter(func(b): return bool(b.get("enterable", false)))
	_check(not enterable.is_empty(), "crash chain: l01 has enterable buildings")
	if enterable.is_empty():
		await _close_level(scene)
		return
	var b0: Dictionary = enterable[0]
	var door_x := float(b0["door_x"])
	var ground_y := float(b0["ground_y"])
	var door: Node2D = null
	for d in get_tree().get_nodes_in_group("doors"):
		if absf(d.global_position.x - door_x) < 24.0:
			door = d
			break
	_check(door != null, "crash chain: enterable door spawned at door_x=%.0f" % door_x)
	if door != null:
		var parked := Vector2(600.0, ground_y - 2.0)
		player.global_position = parked
		player.velocity = Vector2.ZERO
		_check(absf(player.global_position.x - door_x) > 400.0,
			"crash chain A: player parked far from door (dx=%.0f)" % absf(player.global_position.x - door_x))
		var rec := ObjectiveRecorder.new()
		rec.attach()
		door.call("hit", 999)
		_check(not is_instance_valid(door) or bool(door.get("broken")),
			"crash chain A: door broke from hit(999)")
		for _i in 10:
			await get_tree().physics_frame
		var disp := player.global_position.distance_to(parked)
		_check(disp < 50.0,
			"crash chain A: door broken far away does NOT teleport player (10 physics frames, disp=%.1fpx)" % disp)
		_check(not bool(scene.get("_in_interior")), "crash chain A: player not in interior")
		_check(not bool(scene.get("_finishing")), "crash chain A: level not finishing after door break")
		_check(not rec.saw_mission_complete(), "crash chain A: objective never says 任务完成")
		rec.detach()
	await _close_level(scene)

	# ---------- 链B：尸潮贴门 30 秒不传送不结算 ----------
	scene = await _open_level(&"l01")
	player = scene.get_player()
	buildings = scene.get("_buildings")
	enterable = buildings.filter(func(b): return bool(b.get("enterable", false)))
	if enterable.is_empty():
		_check(false, "crash chain B: l01 has enterable buildings")
		await _close_level(scene)
		return
	b0 = enterable[0]
	door_x = float(b0["door_x"])
	ground_y = float(b0["ground_y"])
	var door2: Node2D = null
	for d in get_tree().get_nodes_in_group("doors"):
		if absf(d.global_position.x - door_x) < 24.0:
			door2 = d
			break
	_check(door2 != null, "crash chain B: enterable door spawned")
	if door2 != null:
		var parked2 := Vector2(door_x - 30.0, ground_y - 2.0)
		player.global_position = parked2
		player.velocity = Vector2.ZERO
		player.call("heal_full")
		var hp_before := int(door2.get("health"))
		var rec2 := ObjectiveRecorder.new()
		rec2.attach()
		# 12 只尸潮在门附近刷出（spawn_horde_at 在目标 ±260-620px 落地后涌向玩家/门口）
		scene.spawn_horde_at(Vector2(door_x, ground_y), 12, true)
		# 30 游戏秒：time_scale=3 加速（墙钟约 10s），每游戏秒续满无敌帧防止
		# 玩家被围殴死亡干扰「未被传送」断言（本测试聚焦传送/结算，不测生存）。
		Engine.time_scale = 3.0
		for _s in 30:
			await _wait_game(1.0)
			if is_instance_valid(player):
				player.call("heal_full")
				player.set("iframes", 2.0)
		Engine.time_scale = 1.0
		_check(not rec2.saw_mission_complete(), "crash chain B: objective never says 任务完成")
		_check(not bool(scene.get("_finishing")), "crash chain B: level not finishing")
		_check(not bool(scene.get("_extraction_started")), "crash chain B: extraction not started")
		_check(not bool(scene.get("_in_interior")), "crash chain B: player not teleported into interior")
		_check(not is_instance_valid(door2) or bool(door2.get("broken")) == false,
			"crash chain B: enterable door not broken by horde (P1-4)")
		if is_instance_valid(door2):
			_check(int(door2.get("health")) == hp_before,
				"crash chain B: enterable door health intact after 30s horde (%d->%d)" % [hp_before, int(door2.get("health"))])
		if is_instance_valid(player):
			var disp2 := player.global_position.distance_to(parked2)
			_check(not bool(player.get("is_dead")) and disp2 < 300.0,
				"crash chain B: player NOT teleported after 30s horde at door (disp=%.1fpx)" % disp2)
		rec2.detach()
	await _close_level(scene)
	print("[INTEGRATION] crash chain ok")


## wp8-tests-ci：进屋全流程——踢两脚破门 → 走入门洞传入室内 → 室内站 60 游戏秒
## （进度/剧情事件/教程提示/撤离全部冻结）→ 出口返回街道 ±60px。
## 全程由外部 CI 扫描本测试日志确认 0 条 SCRIPT ERROR（tools/ci_checks.bat）。
func _test_interior_full_flow() -> void:
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var buildings: Array = scene.get("_buildings")
	var enterable: Array = buildings.filter(func(b): return bool(b.get("enterable", false)))
	_check(not enterable.is_empty(), "interior flow: l01 has enterable buildings")
	if enterable.is_empty():
		await _close_level(scene)
		return
	var b0: Dictionary = enterable[0]
	var door_x := float(b0["door_x"])
	var ground_y := float(b0["ground_y"])
	var room: Dictionary = b0.get("interior", {})
	var door: Node2D = null
	for d in get_tree().get_nodes_in_group("doors"):
		if absf(d.global_position.x - door_x) < 24.0:
			door = d
			break
	_check(door != null and not room.is_empty(), "interior flow: door and interior room exist")
	if door != null and not room.is_empty():
		# ① 踢两脚破门（与 _test_interactables 同规格：重置 kick_cd 后 interact）
		player.global_position = Vector2(door_x - 30.0, ground_y - 2.0)
		player.velocity = Vector2.ZERO
		for _k in 2:
			door.set("kick_cd", 0.0)
			door.call("interact", player)
		_check(not is_instance_valid(door) or bool(door.get("broken")),
			"interior flow: two kicks break the door")
		# ② 真实输入走入门洞 → 门洞 Area2D 触发 _try_enter_interior
		Input.action_press("move_right")
		var entered := false
		for _i in 240:
			await get_tree().physics_frame
			if bool(scene.get("_in_interior")):
				entered = true
				break
		Input.action_release("move_right")
		_check(entered, "interior flow: walking into doorway enters interior")
		_check(player.global_position.distance_to(room["entry"]) < 2.0,
			"interior flow: player placed at interior entry")
		_check((scene.get("_street_return") as Vector2).distance_to(
				Vector2(door_x - 26.0, ground_y - 2.0)) < 0.5,
			"interior flow: street return recorded at doorway")
		# ③ 室内站 60 游戏秒（time_scale=3 → 墙钟 20s）：进度/事件/提示/撤离全冻结
		var progress_before := float(scene.get("_progress"))
		var events_before: int = (scene.get("_events_fired") as Dictionary).size()
		var tips_before: int = int(scene.get("_tips_shown"))
		var rec := ObjectiveRecorder.new()
		rec.attach()
		Engine.time_scale = 3.0
		var froze := true
		for _s in 12:
			await _wait_game(5.0)
			if float(scene.get("_progress")) != progress_before \
					or bool(scene.get("_finishing")) \
					or bool(scene.get("_extraction_started")) \
					or (scene.get("_events_fired") as Dictionary).size() != events_before \
					or int(scene.get("_tips_shown")) != tips_before:
				froze = false
				break
			if is_instance_valid(player):
				player.call("heal_full")
		Engine.time_scale = 1.0
		_check(froze, "interior flow: 60s inside freezes progress/events/tips/extraction")
		_check(float(scene.get("_progress")) == progress_before,
			"interior flow: progress frozen at %.3f" % progress_before)
		_check(not rec.saw_mission_complete(), "interior flow: objective never says 任务完成 inside")
		rec.detach()
		# ④ 出口返回街道 ±60px
		var back := Vector2(door_x - 26.0, ground_y - 2.0)
		player.global_position = (room["exit"] as Vector2) + Vector2(0, -8)
		for _i in 8:
			await get_tree().physics_frame
		_check(not bool(scene.get("_in_interior")), "interior flow: exit clears interior state")
		_check(player.global_position.distance_to(back) <= 60.0,
			"interior flow: exit returns player to street ±60px (dx=%.1f)" % player.global_position.distance_to(back))
	await _close_level(scene)
	print("[INTEGRATION] interior full flow ok")


## wp1-door-entry-fix：门洞一发性触发缺陷（双通道修复）的验收用例。
## 缺陷：玩家贴门站位（碰撞体 12×28 与 26×48 entry_area 重叠约 2px）时
## body_entered 在门未破时被 _try_enter_interior 的门破复核拒绝并消费，
## Area2D 一发性不补发，破门后按住方向键走过门洞永不传送。
## 旧 wp8 用例（_test_interior_full_flow）站位 door_x-30 不重叠且踢门时无输入，
## body_entered 未被提前消费，恰好绕开了本缺陷——本用例补上该盲区。
## 场景A：玩家真实输入走到门前顶住门（贴住）→ interact() 踢两脚破门 →
##        不松方向键继续向门洞走 → 2 秒内 _in_interior == true 且落在 entry。
## 场景B（回归护栏）：破门后玩家站门外 >30px → 走入门洞 → 断言传送
##        （body_entered 新鲜触发路径仍工作；与 _test_interior_full_flow 同语义）。
func _test_door_entry_residency() -> void:
	# ---------- 场景 A：贴门站位破门后不松键继续走 ----------
	var scene := await _open_level(&"l01")
	var player: Node2D = scene.get_player()
	var buildings: Array = scene.get("_buildings")
	var enterable: Array = buildings.filter(func(b): return bool(b.get("enterable", false)))
	_check(not enterable.is_empty(), "door residency: l01 has enterable buildings")
	if not enterable.is_empty():
		var b0: Dictionary = enterable[0]
		var door_x := float(b0["door_x"])
		var ground_y := float(b0["ground_y"])
		var room: Dictionary = b0.get("interior", {})
		var door: Node2D = null
		for d in get_tree().get_nodes_in_group("doors"):
			if absf(d.global_position.x - door_x) < 24.0:
				door = d
				break
		# wp1-door-entry-fix 修复附带的登记表：按 door_x 找该门口 entry_area
		# （Variant 接收：未修复代码上该成员不存在，get 返回 Nil，走下方兜底扫描）
		var entry_area: Area2D = null
		var areas_registered: Variant = scene.get("_entry_areas")
		if areas_registered is Array:
			for pair in areas_registered:
				if absf(float(pair["b"]["door_x"]) - door_x) < 24.0:
					entry_area = pair["area"]
					break
		if entry_area == null:
			# 兜底：按位置直接扫描 LevelRunner 直接子 Area2D（entry_area 中心
			# 恒为 (door_x, ground_y-24)，见 level_runner.gd _build_buildings）。
			# 不依赖修复引入的登记表，未修复代码上也能定位触发区完成反向验证。
			for child in scene.get_children():
				if child is Area2D \
						and absf((child as Area2D).global_position.x - door_x) < 1.0 \
						and absf((child as Area2D).global_position.y - (ground_y - 24.0)) < 1.0:
					entry_area = child
					break
		_check(door != null and not room.is_empty() and entry_area != null,
			"door residency A: door, interior room and entry_area exist")
		if door != null and not room.is_empty() and entry_area != null:
			# 场景准备：清除门口 ±100px 内程序化随机生成的桶/箱——实测（run8）
			# 桶偶发落在门口左侧 ~32px 挡死走位路径（玩家卡 door_x-32.1）。
			# 门（LevelDoor）与补给/告示等其他 interactables 不动。
			for child in scene.get_node("Interactables").get_children():
				if (child is ExplosiveBarrel or child is BreakableCrate) \
						and absf(child.global_position.x - door_x) < 100.0:
					child.queue_free()
			for _i in 2:
				await get_tree().physics_frame
			# ① 真实输入走到门前顶住门。物理顶死位 x≈door_x-17（玩家碰撞右缘
			# door_x-11 贴门体碰撞左缘 door_x-11）；door_x-19 时碰撞已与区域重叠，
			# 故到达顶死位前 body_entered 必已触发并在门未破时被消费（缺陷前提）。
			# 出发位从 door_x-34 起向左扫描脚下有真实地面的 x（地形随机坑防御，
			# 同 wp8 window_rappel 用例 get_ground_y<0 加固先例）。
			var start_x := door_x - 34.0
			for _s in 8:
				if scene.get_ground_y(start_x) >= 0.0:
					break
				start_x -= 2.0
			player.global_position = Vector2(start_x, ground_y - 2.0)
			player.velocity = Vector2.ZERO
			Input.action_press("move_right")
			var pressed := false
			for _i in 60:
				await get_tree().physics_frame
				if player.global_position.x >= door_x - 17.5:
					pressed = true
					break
			_check(pressed,
				"door residency A: player pressed against door (x=%.1f, door_x=%.0f)" % [player.global_position.x, door_x])
			# 盲区前提实证：玩家驻留在 entry_area 内（body_entered 已消费的一发性状态）。
			# await physics_frame 恢复在当帧物理 step 之前，跨边缘当帧 overlap 快照
			# 可能滞后——弹性等待最多 10 帧。
			var resident := false
			for _i in 10:
				await get_tree().physics_frame
				if entry_area.get_overlapping_bodies().has(player):
					resident = true
					break
			_check(resident,
				"door residency A: player still overlaps entry_area (body_entered already consumed; px=%.1f ax=%.1f n=%d)" % [player.global_position.x, entry_area.global_position.x, entry_area.get_overlapping_bodies().size()])
			# ② interact() 踢两脚破门（重置 kick_cd，与旧用例同规格）
			for _k in 2:
				door.set("kick_cd", 0.0)
				door.call("interact", player)
			_check(not is_instance_valid(door) or bool(door.get("broken")),
				"door residency A: two kicks break the door")
			# ③ 不松方向键继续向门洞走 → 2 秒（120 物理帧）内传送进室内
			var entered := false
			var frames_used := -1
			for _i in 120:
				await get_tree().physics_frame
				if bool(scene.get("_in_interior")):
					entered = true
					frames_used = _i
					break
			Input.action_release("move_right")
			_check(entered,
				"door residency A: holding direction after break enters interior within 2s (frames=%d)" % frames_used)
			# 传送落点为 room entry；玩家按住的 move_right 在传送当帧还会被
			# LevelRunner(父)→Player(子) 的 _physics_process 顺序多推 1-2 帧
			# （≈3.7-7.3px），故容忍 8px 内的输入残余漂移（精确 <2.0 断言
			# 由 body_entered 路径的场景 B / 旧用例承担）。
			_check(player.global_position.distance_to(room["entry"]) < 8.0,
				"door residency A: player placed at interior entry (dist=%.1f)" % player.global_position.distance_to(room["entry"]))
			_check((scene.get("_street_return") as Vector2).distance_to(
					Vector2(door_x - 26.0, ground_y - 2.0)) < 0.5,
				"door residency A: street return recorded at doorway")
	await _close_level(scene)

	# ---------- 场景 B：破门后站门外 >30px 走入门洞（新开一关，冷却干净） ----------
	scene = await _open_level(&"l01")
	player = scene.get_player()
	buildings = scene.get("_buildings")
	enterable = buildings.filter(func(b): return bool(b.get("enterable", false)))
	if not enterable.is_empty():
		var b1: Dictionary = enterable[0]
		var door_x1 := float(b1["door_x"])
		var ground_y1 := float(b1["ground_y"])
		var room1: Dictionary = b1.get("interior", {})
		var door1: Node2D = null
		for d in get_tree().get_nodes_in_group("doors"):
			if absf(d.global_position.x - door_x1) < 24.0:
				door1 = d
				break
		_check(door1 != null and not room1.is_empty(), "door residency B: door and interior room exist")
		if door1 != null and not room1.is_empty():
			# 场景准备：同场景 A，清门口 ±100px 内随机桶/箱防走位路径被挡
			for child in scene.get_node("Interactables").get_children():
				if (child is ExplosiveBarrel or child is BreakableCrate) \
						and absf(child.global_position.x - door_x1) < 100.0:
					child.queue_free()
			for _i in 2:
				await get_tree().physics_frame
			# 站门外 >30px（door_x-31：碰撞右缘 door_x-25，距区域左缘 door_x-13
			# 还差 12px，不重叠——body_entered 未被消费）。出发点从 door_x-31 起向左
			# 扫描脚下有真实地面的 x（随机地形坑防御；door_x-40 实测偶被地形/道具
			# 挡路导致偶发失败，故贴近旧用例 door_x-30 的已验证稳定邻域）。
			var start_bx := door_x1 - 31.0
			for _s in 10:
				if scene.get_ground_y(start_bx) >= 0.0:
					break
				start_bx -= 2.0
			player.global_position = Vector2(start_bx, ground_y1 - 2.0)
			player.velocity = Vector2.ZERO
			for _k in 2:
				door1.set("kick_cd", 0.0)
				door1.call("interact", player)
			_check(not is_instance_valid(door1) or bool(door1.get("broken")),
				"door residency B: two kicks break the door")
			for _i in 3:
				await get_tree().physics_frame
			_check(not bool(scene.get("_in_interior")),
				"door residency B: player outside entry_area is NOT auto-teleported on break")
			# 真实输入走入门洞 → body_entered 新鲜触发 → 传送
			Input.action_press("move_right")
			var entered_b := false
			var reached_zone := false
			for _i in 120:
				await get_tree().physics_frame
				if player.global_position.x > door_x1 - 19.0:
					reached_zone = true
				if bool(scene.get("_in_interior")):
					entered_b = true
					break
			Input.action_release("move_right")
			_check(entered_b,
				"door residency B: walking into doorway from >30px teleports (body_entered path intact; reached=%s px=%.1f door=%.0f)" % [str(reached_zone), player.global_position.x, door_x1])
			_check(player.global_position.distance_to(room1["entry"]) < 2.0,
				"door residency B: player placed at interior entry")
	await _close_level(scene)
	print("[INTEGRATION] door entry residency ok")


## wp4-interior-complex：5 主题复杂室内走位验收——踢门（按门材踢到破门：wood 62/
## glass 42 需 2 脚、metal 95 需 3 脚，每脚 36 伤）→ 真实输入走入门洞 → 两相导航
## 依次走遍每个功能房间 → 出口 Area 回街 ±60px。两相导航：先横移到路标 x（被
## 家具/矮台卡住 20 物理帧则小跳越障），需爬层（路标高于玩家）时松横移、原地
## 起跳脉冲——室内台阶堆为 one-way 平台：上行穿过、下行被最高一级接住。
## 路标序列来自 build_interior 的 room["path"]（每房间中心 + 每次爬层的台阶列
## 中心，末点=出口）。dy 阈值放宽到 40px：房间中心可能落在 16-30px 高的家具顶上。
func _test_interior_walkthrough() -> void:
	var theme_levels := {"suburb": &"l01", "city": &"l04", "subway": &"l05",
			"military": &"l08", "bridge": &"l02"}
	for theme: String in theme_levels:
		var scene := await _open_level(theme_levels[theme])
		var player: Node2D = scene.get_player()
		var level_width := float(scene.get("level_width"))
		var buildings: Array = scene.get("_buildings")
		var enterable: Array = buildings.filter(func(b): return bool(b.get("enterable", false)))
		_check(not enterable.is_empty(), "walkthrough %s: enterable buildings exist" % theme)
		if enterable.is_empty() or player == null:
			await _close_level(scene)
			continue
		var b0: Dictionary = enterable[0]
		var room: Dictionary = b0.get("interior", {})
		var door_x := float(b0["door_x"])
		var ground_y := float(b0["ground_y"])
		var door: Node2D = null
		for d in get_tree().get_nodes_in_group("doors"):
			if absf(d.global_position.x - door_x) < 24.0:
				door = d
				break
		_check(door != null and not room.is_empty(), "walkthrough %s: door + interior exist" % theme)
		if door == null or room.is_empty():
			await _close_level(scene)
			continue
		var room_infos: Array = room.get("rooms", [])
		_check(room_infos.size() >= 2 and room_infos.size() <= 4,
			"walkthrough %s: %d functional rooms in [2,4]" % [theme, room_infos.size()])
		var rect: Rect2 = room["rect"]
		_check(rect.position.x > level_width,
			"walkthrough %s: complex built beyond level_width" % theme)
		var last_rect: Rect2 = room_infos[room_infos.size() - 1]["rect"]
		_check(last_rect.grow(8.0).has_point(room["exit"]),
			"walkthrough %s: exit inside last room" % theme)
		var spots: Array = room.get("supply_spots", [])
		_check(spots.size() >= 2 and not last_rect.grow(8.0).has_point(spots[0])
				and not last_rect.grow(8.0).has_point(spots[1]),
			"walkthrough %s: supplies outside exit room" % theme)
		# 踢到破门
		player.global_position = Vector2(door_x - 30.0, ground_y - 2.0)
		player.velocity = Vector2.ZERO
		var kicks := 0
		while (is_instance_valid(door) and not bool(door.get("broken"))) and kicks < 4:
			door.set("kick_cd", 0.0)
			door.call("interact", player)
			kicks += 1
		_check(not is_instance_valid(door) or bool(door.get("broken")),
			"walkthrough %s: kicks (%d) break the door" % [theme, kicks])
		# 真实输入走入门洞
		Engine.time_scale = 3.0
		Input.action_press("move_right")
		var entered := false
		for _i in 240:
			await get_tree().physics_frame
			if bool(scene.get("_in_interior")):
				entered = true
				break
		Input.action_release("move_right")
		Engine.time_scale = 1.0
		_check(entered, "walkthrough %s: real-input doorway entry" % theme)
		if not entered:
			await _close_level(scene)
			continue
		_check(player.global_position.distance_to(room["entry"]) < 2.0,
			"walkthrough %s: placed at entry" % theme)
		# 走完 path 路标（末点=出口 Area，以 _in_interior 翻转为到达）
		var path: Array = room.get("path", [])
		Engine.time_scale = 3.0
		var visited: Array = []
		for _r in room_infos.size():
			visited.append(false)
		var walk_ok := true
		for i in path.size():
			var reached := await _walk_interior_path(scene, player, path[i], i == path.size() - 1)
			if not reached:
				walk_ok = false
				break
			for ri in room_infos.size():
				if (room_infos[ri]["rect"] as Rect2).has_point(player.global_position):
					visited[ri] = true
		Engine.time_scale = 1.0
		_check(walk_ok, "walkthrough %s: path fully walked" % theme)
		for ri in room_infos.size():
			_check(visited[ri], "walkthrough %s: visited room#%d %s"
				% [theme, ri + 1, room_infos[ri]["name"]])
		if not walk_ok:
			await _close_level(scene)
			continue
		var back := Vector2(door_x - 26.0, ground_y - 2.0)
		var exited := false
		for _i in 120:
			await get_tree().physics_frame
			if not bool(scene.get("_in_interior")):
				exited = true
				break
		_check(exited, "walkthrough %s: exit clears interior state" % theme)
		_check(player.global_position.distance_to(back) <= 60.0,
			"walkthrough %s: exit returns to street ±60px (dx=%.1f)"
				% [theme, player.global_position.distance_to(back)])
		await _close_level(scene)
	print("[INTEGRATION] interior walkthrough ok")


## wp4：室内走位导航器（与 Temp 验收脚本同款算法）。先横移到 target.x（被
## 家具/矮台卡住 20 物理帧无横向位移则小跳越障），需爬层（target.y 高于玩家
## 8px 以上）时松横移、以 12 帧周期原地起跳脉冲。on_last=true 时以
## _in_interior 翻转（出口 Area 回街）作为到达判定。900 帧未到达返回 false。
func _walk_interior_path(scene: Node, player: Node2D, target: Vector2, on_last: bool) -> bool:
	var ok := false
	var last_x := player.global_position.x
	var stall := 0
	var jump_cd := 0
	for frame in range(0, 900):
		await get_tree().physics_frame
		if not is_instance_valid(player):
			break
		if on_last and not bool(scene.get("_in_interior")):
			ok = true
			break
		var p := player.global_position
		var dx := target.x - p.x
		var dy := target.y - p.y
		if absf(dx) < 12.0 and absf(dy) < 40.0:
			ok = true
			break
		if absf(dx) >= 12.0:
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if dx > 0.0 else "move_left")
			if absf(p.x - last_x) < 1.0:
				stall += 1
			else:
				stall = 0
				last_x = p.x
			if jump_cd > 0:
				jump_cd -= 1
				if jump_cd == 20:
					Input.action_release("jump")
			elif stall >= 20:
				jump_cd = 24
				Input.action_press("jump")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")
			if dy < -8.0:
				if frame % 12 < 3:
					Input.action_press("jump")
				else:
					Input.action_release("jump")
			else:
				Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
	return ok


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
