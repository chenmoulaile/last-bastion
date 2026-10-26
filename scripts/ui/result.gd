extends UIScreen
## End-of-mission debrief with rank, statistics and newly earned achievements.

var _result: Dictionary = {}
var _failed: bool = false


func setup(_payload: Dictionary) -> void:
	_result = GameManager.last_result.duplicate(true)
	_failed = bool(_result.get("failed", false))


func _build() -> void:
	if _result.is_empty():
		_result = GameManager.last_result.duplicate(true)
		_failed = bool(_result.get("failed", false))
	add_background("title_bg", 0.62)
	var accent := UIKit.RED if _failed else UIKit.AMBER
	var kicker := "MISSION FAILED" if _failed else "MISSION COMPLETE"
	add_header(kicker, String(_result.get("level_title", "任务结算")), accent)
	_build_rank_panel()
	_build_stats_panel()
	_build_bottom()
	add_footer("检查点记录会保留 · 失败不会扣除总分 · 重新部署后 AI Director 会重新计算节奏")


func _build_rank_panel() -> void:
	var accent := UIKit.RED if _failed else UIKit.AMBER
	var panel := add_panel(Vector2(24, 62), Vector2(200, 230), UIKit.PANEL, UIKit.LINE)
	var label := UIKit.label("RANK", 7, UIKit.DIM, UIKit.font_latin())
	label.position = Vector2(8, 5)
	label.size = Vector2(184, 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	var rank := String(_result.get("rank", "F"))
	if _failed:
		var fail := UIKit.title("FAILED", 30, UIKit.RED)
		fail.position = Vector2(0, 26)
		fail.size = Vector2(200, 38)
		fail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(fail)
		var reason := UIKit.label(String(_result.get("reason", "小队全灭")), 9, UIKit.MUTED)
		reason.position = Vector2(12, 68)
		reason.size = Vector2(176, 24)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(reason)
	else:
		var stamp := TextureRect.new()
		stamp.texture = UIKit.icon("rank_" + rank)
		stamp.position = Vector2(52, 20)
		stamp.size = Vector2(96, 96)
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(stamp)
		var rank_label := UIKit.label(rank + " 评价", 10, UIKit.rank_color(rank))
		rank_label.position = Vector2(0, 116)
		rank_label.size = Vector2(200, 12)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(rank_label)

	var score := int(_result.get("score", 0))
	var score_label := UIKit.label(UIKit.format_score(score), 20, accent, UIKit.font_latin_bold())
	score_label.position = Vector2(0, 136)
	score_label.size = Vector2(200, 24)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(score_label)
	var score_caption := UIKit.label("SCORE", 6, UIKit.DIM, UIKit.font_latin())
	score_caption.position = Vector2(0, 159)
	score_caption.size = Vector2(200, 8)
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(score_caption)

	var level := GameManager.get_level(StringName(_result.get("level_id", "")))
	if level != null:
		var par := UIKit.label("目标 " + UIKit.format_score(level.par_score), 8, UIKit.MUTED)
		par.position = Vector2(0, 172)
		par.size = Vector2(200, 10)
		par.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(par)

	var mode := UIKit.label("%s · %s" % [UIKit.mode_name(StringName(_result.get("mode", "SQUAD"))),
		UIKit.difficulty_name(StringName(_result.get("difficulty", "NORMAL")))], 8, UIKit.INK)
	mode.position = Vector2(0, 188)
	mode.size = Vector2(200, 10)
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(mode)

	var id_label := UIKit.label(String(_result.get("level_id", "")).to_upper(), 7, UIKit.DIM, UIKit.font_latin())
	id_label.position = Vector2(0, 204)
	id_label.size = Vector2(200, 8)
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(id_label)


func _build_stats_panel() -> void:
	var panel := add_panel(Vector2(236, 62), Vector2(380, 230), UIKit.PANEL, UIKit.LINE)
	var head := UIKit.label("DEBRIEF  战斗统计", 7, UIKit.AMBER, UIKit.font_latin())
	head.position = Vector2(8, 5)
	head.size = Vector2(364, 8)
	panel.add_child(head)

	var stats := [
		["击杀", str(int(_result.get("kills", 0))), UIKit.INK],
		["爆头", str(int(_result.get("headshots", 0))), UIKit.AMBER],
		["特殊感染者", str(int(_result.get("specials", 0))), UIKit.RED],
		["最高连击", str(int(_result.get("max_combo", 0))), UIKit.GREEN],
		["救助队友", str(int(_result.get("rescues", 0))), UIKit.TEAL],
		["队伍存活", str(int(_result.get("squad_alive", 1))), UIKit.INK],
		["用时", UIKit.format_time(float(_result.get("time", 0.0))), UIKit.INK],
		["隐藏房间", str(_result.get("hidden_rooms", []).size()), UIKit.TEAL],
		["图鉴条目", str(_result.get("codex", []).size()), UIKit.BLUE],
		["油桶击杀", str(int(_result.get("barrel_kills", 0))), UIKit.AMBER],
		["燃烧瓶击杀", str(int(_result.get("molotov_kills", 0))), UIKit.RED],
		["踹门", str(int(_result.get("doors_kicked", 0))), UIKit.MUTED],
		["士兵损失", str(int(_result.get("soldiers_lost", 0))), UIKit.RED],
		["Tank 击杀", str(int(_result.get("tanks_killed", 0))), UIKit.AMBER],
		["Witch 惊动", "是" if bool(_result.get("witch_woken", false)) else "否", UIKit.PURPLE],
	]
	for i in stats.size():
		var col := i % 3
		var row := int(i / 3)
		var x := 8.0 + col * 122.0
		var y := 18.0 + row * 34.0
		var key := UIKit.label(stats[i][0], 7, UIKit.DIM)
		key.position = Vector2(x, y)
		key.size = Vector2(116, 8)
		panel.add_child(key)
		var value := UIKit.label(stats[i][1], 12, stats[i][2], UIKit.font_latin())
		value.position = Vector2(x, y + 8)
		value.size = Vector2(116, 14)
		panel.add_child(value)

	var line := ColorRect.new()
	line.color = UIKit.LINE
	line.position = Vector2(8, 192)
	line.size = Vector2(364, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var new_head := UIKit.label("NEW ACHIEVEMENTS  本局新成就", 7, UIKit.AMBER, UIKit.font_latin())
	new_head.position = Vector2(8, 198)
	new_head.size = Vector2(364, 8)
	panel.add_child(new_head)
	var new_achievements: Array = _result.get("new_achievements", [])
	if new_achievements.is_empty():
		var none := UIKit.label("无 · 继续推进战役以解锁更多成就", 8, UIKit.DIM)
		none.position = Vector2(8, 208)
		none.size = Vector2(364, 12)
		panel.add_child(none)
	else:
		for i in mini(new_achievements.size(), 5):
			var id := String(new_achievements[i])
			var icon := UIKit.icon_rect(_achievement_icon(id), 16.0)
			icon.position = Vector2(8 + i * 72, 207)
			panel.add_child(icon)
			var name := _achievement_name(id)
			var label := UIKit.label(name, 7, UIKit.INK)
			label.position = Vector2(27 + i * 72, 207)
			label.size = Vector2(50, 16)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add_child(label)


func _build_bottom() -> void:
	var panel := add_panel(Vector2(24, 300), Vector2(592, 42), UIKit.PANEL, UIKit.LINE)
	var retry := UIKit.button("重新部署", 112, 26)
	retry.position = Vector2(6, 8)
	retry.pressed.connect(func() -> void: go(&"retry"))
	panel.add_child(retry)

	var achievements := UIKit.button("成就墙", 100, 26)
	achievements.position = Vector2(126, 8)
	achievements.pressed.connect(func() -> void: go(&"achievements"))
	panel.add_child(achievements)

	var menu := UIKit.button("主菜单", 100, 26)
	menu.position = Vector2(234, 8)
	menu.pressed.connect(func() -> void: go(&"menu"))
	panel.add_child(menu)

	var is_last := _is_last_level()
	var next := UIKit.button("返回主菜单" if is_last else "下一关  →", 150, 28, not _failed)
	next.position = Vector2(436, 6)
	if _failed:
		next.text = "重新部署  →"
		next.pressed.connect(func() -> void: go(&"retry"))
	else:
		next.pressed.connect(_next_pressed)
	panel.add_child(next)
	next.grab_focus()


func _next_pressed() -> void:
	if _is_last_level():
		go(&"menu")
	else:
		go(&"next")


func _is_last_level() -> bool:
	var levels := GameManager.get_levels()
	if levels.is_empty():
		return true
	return String(levels[levels.size() - 1].id) == String(_result.get("level_id", ""))


func _achievement_name(id: String) -> String:
	for row in SaveSystem.ACHIEVEMENTS:
		if String(row.get("id", "")) == id:
			return String(row.get("name", id))
	return id


func _achievement_icon(id: String) -> String:
	for row in SaveSystem.ACHIEVEMENTS:
		if String(row.get("id", "")) == id:
			return String(row.get("icon", "ach_" + id))
	return "ach_" + id
