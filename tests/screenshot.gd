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
	# v3.4.2：UI 越界断言（六屏 → wp9 扩为全部 10 屏 + HUD/暂停层）
	await _assert_ui_bounds()
	# wp9-ui-fixes：HUD（强制显示全部布局面板）+ 暂停层 越界断言与可交互性检查
	await _assert_hud_bounds()
	await _capture_result()
	# 无论成败都打印汇总行：验收门以 stdout 中的 `FAILURES: 0` 判定全绿
	# （wp8 修复：原实现只在失败时打印，干净运行永远不含 FAILURES 行，门必败）
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
	var scale := float(w) / 640.0
	# 世界区域（逻辑 0..300 行），排除 HUD 矩形：
	# 左上小队面板 (0..190, 0..160)、顶部目标条 (190..450, 0..36)、
	# 右上计分板 (480..640, 0..110)、底部 HUD 带 (0..640, 300..360)
	var step_x := maxi(1, w / 96)
	var step_y := maxi(1, int(300.0 * scale) / 60)
	var total := 0.0
	var count := 0
	var near_black := 0
	for y in range(0, int(300.0 * scale), step_y):
		for x in range(0, w, step_x):
			var xl := float(x) / scale
			var yl := float(y) / scale
			if (xl < 190.0 and yl < 160.0) or (xl >= 190.0 and xl <= 450.0 and yl < 36.0) \
					or (xl > 480.0 and yl < 110.0) or yl >= 300.0:
				continue
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


## wp9-ui-fixes：清掉残留的剧情对话/抉择横幅（截图隔离，不改游戏状态）。
## 暗关传送会触发剧情对话（如实测残留 l05_descent，4 行带抉择），其横幅是
## DialogueManager 自有 CanvasLayer，会残留到后续所有截图并盖住底部 HUD 带
## 与 result/archive_menu 底部内容；发送空格逐行跳过使其自然播完，抉择弹层
## 直接隐藏（保持挂起态，不代做选择、不写 flag）。play() 结束时自己会再隐藏 _box。
func _clear_dialogue_overlay() -> void:
	var dm: Node = get_node_or_null("/root/DialogueManager")
	if dm == null:
		return
	var guard := 0
	while bool(dm.call("is_playing")) and guard < 32:
		var press := InputEventKey.new()
		press.keycode = KEY_SPACE
		press.pressed = true
		Input.parse_input_event(press)
		var release := InputEventKey.new()
		release.keycode = KEY_SPACE
		release.pressed = false
		Input.parse_input_event(release)
		guard += 1
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().process_frame
	var box = dm.get("_box")
	if box is CanvasItem:
		(box as CanvasItem).visible = false
	var cbox = dm.get("_choice_box")
	if cbox is CanvasItem:
		(cbox as CanvasItem).visible = false


## UI 越界断言（v3.4.2 五-4c）：全部 10 屏实例化，可见 Control 的 global rect 必须在视口内，
## 子控件不得越出父面板边界（滚动容器内容除外）
## wp9-ui-fixes：每屏追加「可交互性」检查（_check_interactivity）
func _assert_ui_bounds() -> void:
	await _clear_dialogue_overlay()  # wp9：暗关残留对话横幅会盖住 archive_menu 等屏的底部
	# P0-3：断言覆盖全部 UI 屏（主菜单溢出正是因未覆盖 main_menu 才漏检）
	# 第三项为截图名（build/screens/*.png）：仅 archive_menu 未被 _capture_screens 覆盖，其余已在前面拍过
	var screens := [
		["res://scenes/ui/main_menu.tscn", {}, ""],
		["res://scenes/ui/level_select.tscn", {"level_id": "l01"}, ""],
		["res://scenes/ui/settings.tscn", {}, ""],
		["res://scenes/ui/briefing.tscn", {"level_id": "l11", "mode": "SQUAD", "difficulty": "NORMAL"}, ""],
		["res://scenes/ui/character_select.tscn", {"from": "levels"}, ""],
		["res://scenes/ui/credits.tscn", {}, ""],
		["res://scenes/ui/codex.tscn", {}, ""],
		["res://scenes/ui/achievements.tscn", {}, ""],
		["res://scenes/ui/archive_menu.tscn", {}, "archive_menu"],
		["res://scenes/ui/result.tscn", {}, ""],
	]
	for row in screens:
		var inst = load(row[0]).instantiate()
		if inst.has_method("setup"):
			inst.setup(row[1])
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		var tag := String(row[0]).get_file()
		_check_control_bounds(inst, tag)
		_check_interactivity(inst, tag)
		if row[2] != "":
			await _snap(row[2])
		inst.queue_free()
		await get_tree().process_frame


## wp9-ui-fixes：HUD（第 11 屏）+ 暂停层（第 12 屏）越界断言与可交互性检查。
## 强制显示 HUDRoot 下所有隐藏的布局面板（boss 条/计时条/指挥面板/事件横幅/通知/调试面板等），
## 扫描其编码矩形；快照前再把全屏效果叠层隐藏，避免截图被染色。
func _assert_hud_bounds() -> void:
	await _clear_dialogue_overlay()  # wp9：残留对话横幅会盖住底部 HUD 带，污染快照
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud_root: Control = hud.get_node("HUDRoot")
	var shown := 0
	for child in hud_root.get_children():
		var c := child as Control
		if c != null and not c.visible:
			c.visible = true
			shown += 1
	print("[SHOTS] hud panels force-shown: %d" % shown)
	await get_tree().process_frame
	_check_control_bounds(hud, "hud_all_panels")
	_check_interactivity(hud, "hud_all_panels")
	# 效果叠层（满屏锚定的受击闪红/低血/胆汁/静电/颗粒/雨）与暂停层不进快照（暂停层单独拍）
	for ov in ["_damage_flash", "_lowhp", "_bile", "_static_rect", "_grain", "rain", "_pause_root"]:
		var n = hud.get(ov)
		if n is CanvasItem:
			(n as CanvasItem).visible = false
	await _snap("hud_all_panels")
	hud.call("_open_pause")
	await get_tree().process_frame
	await get_tree().process_frame
	_check_control_bounds(hud, "hud_pause")
	_check_interactivity(hud, "hud_pause")
	await _snap("hud_pause")
	hud.queue_free()
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
		# wp9：准星/命中标记是鼠标锚定的纯绘制控件（mouse_filter=IGNORE），
		# 鼠标贴近屏缘时其 32x32/24x24 矩形天然出屏，属设计行为，豁免边界断言
		if ctrl is PixelCrosshair or ctrl is PixelHitmarker:
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


# ------------------------------------------------------------ 可交互性（wp9） ----
## 先序收集 Control（= Godot 绘制顺序：父先于子，早兄弟先于晚兄弟）
func _collect_controls(n: Node, out: Array[Control]) -> void:
	var ctrl := n as Control
	if ctrl != null:
		out.append(ctrl)
	for c in n.get_children():
		_collect_controls(c, out)


## 裁剪感知有效矩形：与所有开启裁剪的祖先（ScrollContainer / clip_contents=true）矩形求交。
## 滚动视口外的列表行/卡片按钮的有效矩形为空——既不可见也不可点（点击实测被裁剪挡住，
## 见 wp9 汇报的 character_select 点击模拟），因此可交互性检查全部按有效矩形判定。
func _effective_rect(ctrl: Control) -> Rect2:
	var r := ctrl.get_global_rect()
	var p := ctrl.get_parent()
	while p != null:
		var pc := p as Control
		if pc != null and (pc is ScrollContainer or pc.clip_contents):
			r = r.intersection(pc.get_global_rect())
		p = p.get_parent()
	return r


func _has_clip_ancestor(ctrl: Control) -> bool:
	var p := ctrl.get_parent()
	while p != null:
		var pc := p as Control
		if pc != null and (pc is ScrollContainer or pc.clip_contents):
			return true
		p = p.get_parent()
	return false


## 「可交互性」断言（wp9-ui-fixes，验收项）：对每个屏幕的全部 Button 检查——
##   · 启用按钮不得 mouse_filter=IGNORE（死按钮）
##   · 启用按钮不得 focus_mode=NONE（键盘不可达）
##   · 有效可视矩形 ≥12x10 命中区（禁用按钮豁免——不可点）
##   · 有效可视矩形不得被屏缘裁切（按钮在可视区内）
##   · 非祖先关系的启用按钮两两有效矩形重叠 ≤25% 小面积（点击热区互不抢占）
##   · 按钮中心点的鼠标拾取目标必须是按钮自身或其后代（无遮挡）
##   · 禁用按钮必须能解析出 disabled 样式盒（禁用态可见）
## 折叠区（滚动视口外）的启用按钮只打 info 不计违例（滚动列表的正常状态）
func _check_interactivity(root: Node, tag: String) -> void:
	var ctrls: Array[Control] = []
	_collect_controls(root, ctrls)
	var buttons: Array[Button] = []
	for c in ctrls:
		var b := c as Button
		if b != null and b.is_visible_in_tree():
			buttons.append(b)
	var violations := 0
	for b in buttons:
		var eff := _effective_rect(b)
		if b.disabled:
			if b.get_theme_stylebox("disabled") == null:
				violations += 1
				print("[UI] %s disabled button without disabled stylebox: %s" % [tag, b.get_path()])
			continue
		if b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			violations += 1
			print("[UI] %s enabled button has mouse_filter=IGNORE (dead): %s" % [tag, b.get_path()])
		if b.focus_mode == Control.FOCUS_NONE:
			violations += 1
			print("[UI] %s enabled button not keyboard-focusable: %s" % [tag, b.get_path()])
		if eff.size.x <= 0.0 or eff.size.y <= 0.0:
			if _has_clip_ancestor(b):
				print("[UI] %s enabled button fully below fold (scroll content): %s" % [tag, b.get_path()])
			else:
				violations += 1
				print("[UI] %s enabled button has empty effective rect without clip ancestor: %s" % [tag, b.get_path()])
			continue
		if eff.size.x < 12.0 or eff.size.y < 10.0:
			violations += 1
			print("[UI] %s button effective hit rect %s < 12x10: %s" % [tag, str(eff), b.get_path()])
		if eff.position.x < -2.0 or eff.position.y < -2.0 or eff.end.x > 642.0 or eff.end.y > 362.0:
			violations += 1
			print("[UI] %s enabled button visually cut by screen edge: %s eff=%s" % [tag, b.get_path(), str(eff)])
	# 非祖先按钮互叠（有效矩形）
	for i in buttons.size():
		var a := buttons[i]
		if a.disabled or _effective_rect(a).get_area() <= 0.0:
			continue
		for j in range(i + 1, buttons.size()):
			var b2 := buttons[j]
			if b2.disabled or a.is_ancestor_of(b2) or b2.is_ancestor_of(a):
				continue
			var eb := _effective_rect(b2)
			if eb.get_area() <= 0.0:
				continue
			var inter := _effective_rect(a).intersection(eb)
			if inter.size.x <= 0.0 or inter.size.y <= 0.0:
				continue
			var small := minf(_effective_rect(a).get_area(), eb.get_area())
			if small > 0.0 and inter.get_area() / small > 0.25:
				violations += 1
				print("[UI] %s buttons overlap >25%%: %s vs %s (%.0f%% of smaller)" % [
					tag, a.get_path(), b2.get_path(), inter.get_area() / small * 100.0])
	# 中心点遮挡：绘制序最顶、可见且 filter!=IGNORE 的控件必须是按钮自身/后代
	for b in buttons:
		if b.disabled or _effective_rect(b).get_area() <= 0.0:
			continue
		var center := _effective_rect(b).get_center()
		var hit: Control = null
		for c in ctrls:
			if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			if not c.get_global_rect().has_point(center):
				continue
			hit = c
		if hit != null and hit != b and not b.is_ancestor_of(hit):
			violations += 1
			print("[UI] %s button center occluded by %s: %s center=%s" % [tag, hit.get_path(), b.get_path(), str(center)])
	if violations > 0:
		_visual_failures += 1
		push_error("UI INTERACTIVITY: %s has %d violating buttons" % [tag, violations])
	else:
		print("[SHOTS] ui interactivity ok: %s (%d buttons)" % [tag, buttons.size()])


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
	await _clear_dialogue_overlay()  # wp9：残留对话横幅会盖住 result 底部按钮
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
