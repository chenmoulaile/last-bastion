extends UIScreen
## Title screen: campaign resume, archive summary and secondary screens.

var _continue_level: LevelData


func _build() -> void:
	add_background("title_bg", 0.20)

	var logo := TextureRect.new()
	logo.texture = UIKit.texture("res://assets/sprites/environment/logo.png")
	logo.position = Vector2(100, 16)
	logo.size = Vector2(440, 118)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var tagline := UIKit.label("四人小队 · 尸潮求生 · 像素跑射", 9, UIKit.MUTED)
	tagline.position = Vector2(100, 132)
	tagline.size = Vector2(440, 12)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tagline)

	var menu_panel := add_panel(Vector2(24, 154), Vector2(212, 190), Color(0.035, 0.045, 0.058, 0.90), UIKit.LINE)
	var menu_title := UIKit.label("CAMPAIGN", 7, UIKit.AMBER, UIKit.font_latin())
	menu_title.position = Vector2(8, 4)
	menu_panel.add_child(menu_title)

	var next_id := GameManager.continue_level_id()
	_continue_level = GameManager.get_level(next_id)
	var continue_text := "开始战役"
	if _completed_count() > 0:
		continue_text = "继续战役"
	if _continue_level != null:
		continue_text += "  " + String(_continue_level.id).to_upper()
	var continue_button := UIKit.button(continue_text, 196, 22, true)
	continue_button.position = Vector2(8, 18)
	continue_button.pressed.connect(_on_continue)
	menu_panel.add_child(continue_button)

	var level_button := UIKit.button("章节选择", 196, 22)
	level_button.position = Vector2(8, 42)
	level_button.pressed.connect(func() -> void: go(&"levels"))
	menu_panel.add_child(level_button)

	var survivor_button := UIKit.button("幸存者小队", 196, 22)
	survivor_button.position = Vector2(8, 66)
	survivor_button.pressed.connect(func() -> void: go(&"survivors"))
	menu_panel.add_child(survivor_button)

	var archive_button := UIKit.button("档案库  " + _archive_summary(), 196, 22)
	archive_button.position = Vector2(8, 90)
	archive_button.pressed.connect(func() -> void: go(&"archives"))
	menu_panel.add_child(archive_button)

	var settings_button := UIKit.button("设置", 196, 22)
	settings_button.position = Vector2(8, 114)
	settings_button.pressed.connect(func() -> void: go(&"settings"))
	menu_panel.add_child(settings_button)

	var credits_button := UIKit.button("制作人员", 196, 22)
	credits_button.position = Vector2(8, 138)
	credits_button.pressed.connect(func() -> void: go(&"credits"))
	menu_panel.add_child(credits_button)

	var quit_button := UIKit.button("退出游戏", 196, 22)
	quit_button.position = Vector2(8, 162)
	quit_button.pressed.connect(func() -> void: go(&"quit"))
	menu_panel.add_child(quit_button)

	# Add neon hover animation to all menu buttons
	for btn in [continue_button, level_button, survivor_button, archive_button, settings_button, credits_button, quit_button]:
		_animate_button_hover(btn)
	_build_archive()
	continue_button.grab_focus()


func _animate_button_hover(button: Button) -> void:
	var original := Color(0.95, 0.72, 0.22, 1.0)
	button.mouse_entered.connect(func() -> void:
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.45, 1.0))
		button.create_tween().tween_property(button, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_BACK)
	)
	button.mouse_exited.connect(func() -> void:
		button.add_theme_color_override("font_hover_color", original)
		button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)
	)


func _build_archive() -> void:
	var panel := add_panel(Vector2(332, 154), Vector2(284, 190), Color(0.035, 0.045, 0.058, 0.88), UIKit.LINE)
	var head := UIKit.label("FIELD RECORD", 7, UIKit.AMBER, UIKit.font_latin())
	head.position = Vector2(8, 4)
	panel.add_child(head)

	var completed := _completed_count()
	var total := GameManager.get_levels().size()
	var score := SaveSystem.get_score_total()
	var s_ranks := SaveSystem.s_rank_count()
	var achievements: int = SaveSystem.data.get("achievements", []).size()
	var hidden := SaveSystem.get_hidden_room_count()

	_stat(panel, Vector2(8, 20), "总分 SCORE", UIKit.format_score(score), UIKit.AMBER)
	_stat(panel, Vector2(146, 20), "S 评价", "%d / %d" % [s_ranks, total], UIKit.GREEN)
	_stat(panel, Vector2(8, 48), "战役进度", "%d / %d" % [completed, total], UIKit.INK)
	_stat(panel, Vector2(146, 48), "成就", "%d / %d" % [achievements, SaveSystem.ACHIEVEMENTS.size()], UIKit.INK)
	_stat(panel, Vector2(8, 76), "隐藏房间", "%d / %d" % [hidden, 11], UIKit.TEAL)
	_stat(panel, Vector2(146, 76), "已解锁武器", "%d / 9" % _weapon_count(), UIKit.BLUE)

	var progress_back := ColorRect.new()
	progress_back.color = Color(0.01, 0.015, 0.02, 0.9)
	progress_back.position = Vector2(8, 106)
	progress_back.size = Vector2(268, 5)
	progress_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(progress_back)
	var progress_fill := ColorRect.new()
	progress_fill.color = UIKit.AMBER
	progress_fill.position = Vector2(8, 106)
	progress_fill.size = Vector2(268.0 * clampf(float(completed) / float(maxi(1, total)), 0.0, 1.0), 5)
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(progress_fill)

	var next_text := "下一站：—"
	if _continue_level != null:
		next_text = "下一站：%s · %s" % [String(_continue_level.id).to_upper(), _continue_level.title]
	var next := UIKit.label(next_text, 9, UIKit.INK)
	next.position = Vector2(8, 118)
	next.size = Vector2(268, 12)
	next.clip_text = true
	panel.add_child(next)

	var mode := UIKit.label("模式 %s · 难度 %s · 档案 %s" % [UIKit.mode_name(GameManager.current_mode),
		UIKit.difficulty_name(GameManager.current_difficulty), _archive_summary()], 8, UIKit.MUTED)
	mode.position = Vector2(8, 132)
	mode.size = Vector2(268, 10)
	panel.add_child(mode)

	var ach_button := UIKit.button("成就墙", 130, 22)
	ach_button.position = Vector2(8, 154)
	ach_button.pressed.connect(func() -> void: go(&"achievements"))
	panel.add_child(ach_button)

	var codex_button := UIKit.button("感染图鉴", 130, 22)
	codex_button.position = Vector2(146, 154)
	codex_button.pressed.connect(func() -> void: go(&"codex"))
	panel.add_child(codex_button)
	_animate_button_hover(ach_button)
	_animate_button_hover(codex_button)

	var version := UIKit.label("v%s  ·  MIT  ·  ORIGINAL PIXEL ASSETS"
		% str(ProjectSettings.get_setting("application/config/version", "3.1.1")),
		6, UIKit.DIM, UIKit.font_latin())
	version.position = Vector2(332, 348)
	version.size = Vector2(284, 8)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


func _stat(parent: Node, pos: Vector2, key_text: String, value_text: String, color: Color) -> void:
	var key := UIKit.label(key_text, 7, UIKit.DIM, UIKit.font_latin())
	key.position = pos
	key.size = Vector2(130, 8)
	parent.add_child(key)
	var value := UIKit.label(value_text, 10, color, UIKit.font_latin())
	value.position = pos + Vector2(0, 9)
	value.size = Vector2(130, 12)
	parent.add_child(value)


func _completed_count() -> int:
	var count := 0
	for level in GameManager.get_levels():
		if SaveSystem.is_level_completed(level.id):
			count += 1
	return count


func _weapon_count() -> int:
	var count := 0
	for id in [&"ar15", &"smg", &"shotgun", &"sniper", &"lmg", &"m9", &"axe", &"katana", &"chainsaw"]:
		if SaveSystem.is_weapon_unlocked(id):
			count += 1
	return count


func _on_continue() -> void:
	if _continue_level == null:
		go(&"levels")
		return
	go(&"briefing", {"level_id": String(_continue_level.id)})


func _archive_summary() -> String:
	if ArchiveManager == null:
		return "0/0"
	return "%d/%d" % [ArchiveManager.unlocked_count(), ArchiveManager.total_count()]
