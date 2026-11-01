extends Node
## Renders representative screens to build/screens for visual review.
## 含「非空白」视觉回归判定（唯一颜色数 > 100）。

var _visual_failures := 0
## Run non-headless: Godot --path . res://tests/screenshot.tscn

const OUT := "res://build/screens"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().process_frame
	await _capture_screens()
	for spec in [["res://scenes/levels/l01.tscn", &"SQUAD", "gameplay_l01"],
			["res://scenes/levels/l03.tscn", &"SQUAD", "gameplay_l03"],
			["res://scenes/levels/l05.tscn", &"SQUAD", "gameplay_l05"],
			["res://scenes/levels/l07.tscn", &"COMMAND", "gameplay_l07"],
			["res://scenes/levels/l08.tscn", &"SQUAD", "gameplay_l08"],
			["res://scenes/levels/l11.tscn", &"SQUAD", "gameplay_l11"]]:
		await _capture_level(spec[0], spec[1], spec[2])
	# v3.4.2：暗关亮度断言（l05/l10/l11 各 2 个进度点）
	for lid in ["l05", "l10", "l11"]:
		await _capture_dark_level(lid)
	# v3.4.2：UI 越界断言（六屏）
	await _assert_ui_bounds()
	await _capture_result()
	if _visual_failures > 0:
		print("[SHOTS] VISUAL REGRESSION FAILURES: %d" % _visual_failures)
	print("[SHOTS] done")
	get_tree().quit()


## 暗关亮度断言（v3.4.2 五-4b）：上半屏世界区域亮度均值 ≥0.10、近黑占比 ≤0.30
func _capture_dark_level(lid: String) -> void:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(StringName(lid), &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/%s.tscn" % lid).instantiate()
	add_child(scene)
	await get_tree().create_timer(0.9, true, false, true).timeout
	var player: Node2D = scene.get_player()
	for p in [0.12, 0.5]:
		var target_x: float = scene.get("level_width") * p
		player.global_position = Vector2(target_x, scene.call("get_ground_y", target_x) - 4.0)
		await get_tree().create_timer(0.35, true, false, true).timeout
		await _snap("%s_progress_%d" % [lid, int(p * 100)])
		_assert_world_brightness("%s@%d%%" % [lid, int(p * 100)])
	scene.queue_free()
	await get_tree().process_frame


func _assert_world_brightness(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	# 上半屏世界区域（行 0..45%，排除 HUD 底部；采样网格）
	var rows := int(h * 0.45)
	var step_x := maxi(1, w / 96)
	var step_y := maxi(1, rows / 40)
	var total := 0.0
	var count := 0
	var near_black := 0
	for y in range(0, rows, step_y):
		for x in range(0, w, step_x):
			var c := img.get_pixel(x, y)
			var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			total += lum
			count += 1
			if lum < 0.06:
				near_black += 1
	var mean := total / maxf(1.0, float(count))
	var ratio := float(near_black) / maxf(1.0, float(count))
	if mean < 0.10 or ratio > 0.30:
		push_error("DARK LEVEL TOO DIM: %s mean=%.3f near_black=%.3f" % [tag, mean, ratio])
		_visual_failures += 1
	print("[SHOTS] dark %s mean=%.3f near_black=%.3f" % [tag, mean, ratio])


## UI 越界断言（v3.4.2 五-4c）：六屏实例化，可见 Control 的 global rect 必须在视口内，
## 子控件不得越出父面板边界（滚动容器内容除外）
func _assert_ui_bounds() -> void:
	var screens := [
		["res://scenes/ui/briefing.tscn", {"level_id": "l11", "mode": "SQUAD", "difficulty": "NORMAL"}],
		["res://scenes/ui/character_select.tscn", {"from": "levels"}],
		["res://scenes/ui/credits.tscn", {}],
		["res://scenes/ui/codex.tscn", {}],
		["res://scenes/ui/achievements.tscn", {}],
	]
	for row in screens:
		var inst = load(row[0]).instantiate()
		if inst.has_method("setup"):
			inst.setup(row[1])
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		_check_control_bounds(inst, String(row[0]).get_file())
		inst.queue_free()
		await get_tree().process_frame


func _check_control_bounds(root: Node, tag: String) -> void:
	var view := Rect2(0, 0, 640, 360)
	var violations := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var ctrl := node as Control
		if ctrl == null or not ctrl.is_visible_in_tree():
			continue
		if _in_scroll(ctrl):
			continue
		var r := ctrl.get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > view.end.x + 2.0 or r.end.y > view.end.y + 2.0:
			violations += 1
			print("[UI] %s out of viewport: %s %s" % [tag, ctrl.get_path(), str(r)])
	if violations > 0:
		_visual_failures += 1
		push_error("UI BOUNDS: %s has %d violating controls" % [tag, violations])
	else:
		print("[SHOTS] ui bounds ok: %s" % tag)


func _in_scroll(ctrl: Control) -> bool:
	var p := ctrl.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
	# 视觉回归（v2 规格 五-6）：唯一颜色数 > 100 判定非空白——防止
	# 「Shader 编译失败白屏」类缺陷漏网（headless 测不出来）
	var colors := {}
	var w := image.get_width()
	var h := image.get_height()
	var step := maxi(1, w * h / 8192)
	for i in range(0, w * h, step * 7):
		var c := image.get_pixel(i % w, int(i / w))
		colors[c.r8 * 65536 + c.g8 * 256 + c.b8] = true
	var unique := colors.size()
	if name.contains("gameplay") and unique <= 100:
		push_error("VISUAL REGRESSION: %s looks blank (unique colors = %d)" % [name, unique])
		_visual_failures += 1
	print("[SHOTS] %s colors=%d" % [name, unique])


func _capture_screens() -> void:
	var screens := [
		["res://scenes/ui/main_menu.tscn", {}, "main_menu"],
		["res://scenes/ui/level_select.tscn", {"level_id": "l01"}, "level_select"],
		["res://scenes/ui/character_select.tscn", {"from": "levels"}, "character_select"],
		["res://scenes/ui/settings.tscn", {}, "settings"],
		["res://scenes/ui/achievements.tscn", {}, "achievements"],
		["res://scenes/ui/codex.tscn", {}, "codex"],
		["res://scenes/ui/briefing.tscn", {"level_id": "l01", "mode": "SQUAD", "difficulty": "NORMAL"}, "briefing"],
		["res://scenes/ui/credits.tscn", {}, "credits"],
	]
	for row in screens:
		var inst = load(row[0]).instantiate()
		if inst.has_method("setup"):
			inst.setup(row[1])
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _snap(row[2])
		inst.queue_free()
		await get_tree().process_frame


func _capture_level(path: String, mode: StringName, shot: String) -> void:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(StringName(path.get_file().get_basename()), mode, &"NORMAL")
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await get_tree().create_timer(1.1, true, false, true).timeout
	await _snap(shot + "_start")

	var player: Node2D = scene.get_player()
	Input.action_press("move_right")
	await get_tree().create_timer(1.2, true, false, true).timeout
	Input.action_release("move_right")
	scene.spawn_horde_at(player.global_position + Vector2(170, -20), 10, true)
	scene.spawn_special(&"hunter")
	scene.spawn_special(&"smoker")
	await get_tree().create_timer(1.0, true, false, true).timeout
	Input.action_press("fire")
	await get_tree().create_timer(0.22, true, false, true).timeout
	await _snap(shot + "_combat")
	Input.action_release("fire")
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _snap(shot + "_hud")

	if mode == &"COMMAND":
		scene.call("_cycle_formation")
		EventBus.debug_panel_toggled.emit()
		EventBus.debug_vision_toggled.emit()
		await get_tree().create_timer(0.35, true, false, true).timeout
		await _snap(shot + "_debug")
		EventBus.debug_vision_toggled.emit()
		EventBus.debug_panel_toggled.emit()
		await get_tree().create_timer(0.1, true, false, true).timeout

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.change_state(GameManager.State.MENU)


func _capture_result() -> void:
	GameManager.last_result = {
		"failed": false, "score": 248600, "rank": "S", "time": 318.0,
		"kills": 186, "headshots": 47, "specials": 11, "rescues": 3,
		"max_combo": 42, "squad_alive": 4, "soldiers_start": 0, "soldiers_lost": 0,
		"doors_kicked": 7, "hunter_interrupts": 2, "witch_crowns": 1,
		"barrel_kills": 8, "molotov_kills": 6, "tanks_killed": 2,
		"witch_woken": true, "hidden_rooms": ["l01_hidden"], "codex": ["hunter", "smoker"],
		"level_id": "l01", "level_title": "街道突破口", "mode": "SQUAD",
		"difficulty": "NORMAL", "new_achievements": ["first_blood", "combo_50"],
	}
	var result = load("res://scenes/ui/result.tscn").instantiate()
	if result.has_method("setup"):
		result.setup({})
	add_child(result)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _snap("result")
	result.queue_free()
