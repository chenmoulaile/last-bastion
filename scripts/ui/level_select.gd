extends UIScreen
## Campaign map: chapter tabs, 11 mission cards, mode/difficulty, character.

var _chapter: int = 1
var _selected_id: StringName = &""
var _difficulty: StringName = &"NORMAL"
var _mode: StringName = &"SQUAD"
var _selected: LevelData

var _tabs: Dictionary = {}
var _cards: Dictionary = {}
var _cards_box: Control
var _detail_art: TextureRect
var _detail_chapter: Label
var _detail_chapter_num: Label
var _detail_id: Label
var _detail_title: Label
var _detail_sub: Label
var _detail_brief: Label
var _detail_mode: Label
var _detail_difficulty: Label
var _detail_par: Label
var _detail_best: Label
var _detail_hidden: Label
var _detail_threat: Label
var _detail_uncommon: Label
var _detail_new: Label
var _detail_start: Button
var _char_portrait: TextureRect
var _char_name: Label
var _char_skill: Label
var _diff_buttons: Dictionary = {}
var _mode_button: Button


func setup(payload: Dictionary) -> void:
	_difficulty = StringName(payload.get("difficulty", GameManager.current_difficulty))
	_chapter = int(payload.get("chapter", 1))
	var wanted := StringName(payload.get("level_id", ""))
	if wanted != &"":
		var level := GameManager.get_level(wanted)
		if level != null:
			_chapter = level.chapter
			_selected_id = wanted
	if not GameManager.is_chapter_unlocked(_chapter):
		_chapter = 1
	if _selected_id == &"":
		_selected_id = _first_level_in_chapter(_chapter)
	var initial := GameManager.get_level(_selected_id)
	if initial != null:
		_mode = GameManager.default_mode_for(initial)


func _build() -> void:
	add_background("title_bg", 0.42)
	add_header("CAMPAIGN", "章节选择", UIKit.AMBER)
	add_back_button(&"menu", "主菜单")
	add_footer("通关前置关卡解锁后续任务 · 难度影响伤害、特殊感染者频率与医疗资源 · 检查点会保留小队状态")

	_build_tabs()
	_build_cards()
	_build_detail()
	_build_bottom_bar()
	_refresh_all()


func _build_tabs() -> void:
	var names := ["裂城港口", "旧城区", "净化区", "信号核心"]
	for i in 4:
		var chapter := i + 1
		var btn := UIKit.button("CH.%d  %s" % [chapter, names[i]], 140, 22)
		btn.position = Vector2(24 + i * 145, 58)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_tab.bind(chapter))
		add_child(btn)
		_tabs[chapter] = btn


func _build_cards() -> void:
	_cards_box = Control.new()
	_cards_box.position = Vector2(24, 86)
	_cards_box.size = Vector2(220, 208)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_box)


func _build_detail() -> void:
	var panel := add_panel(Vector2(260, 86), Vector2(356, 208), UIKit.PANEL, UIKit.LINE)
	_detail_art = TextureRect.new()
	_detail_art.position = Vector2(8, 8)
	_detail_art.size = Vector2(150, 84)
	_detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_detail_art)

	# The chapter art has its v1.0 title baked in; cover that strip and draw the
	# current chapter name from data so renames never go stale.
	var art_shade := ColorRect.new()
	art_shade.color = Color(0.03, 0.035, 0.045, 0.88)
	art_shade.position = Vector2(8, 54)
	art_shade.size = Vector2(150, 38)
	art_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art_shade)
	_detail_chapter_num = UIKit.label("", 6, UIKit.AMBER, UIKit.font_latin())
	_detail_chapter_num.position = Vector2(14, 56)
	_detail_chapter_num.size = Vector2(138, 8)
	_detail_chapter_num.visible = false
	panel.add_child(_detail_chapter_num)
	_detail_chapter = UIKit.label("", 13, UIKit.INK)
	_detail_chapter.position = Vector2(14, 62)
	_detail_chapter.size = Vector2(138, 18)
	panel.add_child(_detail_chapter)

	_detail_id = UIKit.label("L01", 14, UIKit.AMBER, UIKit.font_latin_bold())
	_detail_id.position = Vector2(166, 6)
	_detail_id.size = Vector2(182, 18)
	panel.add_child(_detail_id)
	_detail_title = UIKit.label("街道突破口", 11, UIKit.INK)
	_detail_title.position = Vector2(166, 24)
	_detail_title.size = Vector2(182, 13)
	_detail_title.clip_text = true
	panel.add_child(_detail_title)
	_detail_sub = UIKit.label("", 8, UIKit.MUTED)
	_detail_sub.position = Vector2(166, 38)
	_detail_sub.size = Vector2(182, 10)
	_detail_sub.clip_text = true
	panel.add_child(_detail_sub)
	_detail_brief = UIKit.label("", 8, UIKit.MUTED)
	_detail_brief.position = Vector2(166, 50)
	_detail_brief.size = Vector2(182, 42)
	_detail_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_detail_brief)

	var line := ColorRect.new()
	line.color = UIKit.LINE
	line.position = Vector2(8, 97)
	line.size = Vector2(340, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	_detail_mode = _stat(panel, Vector2(8, 102), "模式")
	_detail_difficulty = _stat(panel, Vector2(94, 102), "难度")
	_detail_par = _stat(panel, Vector2(180, 102), "目标分")
	_detail_best = _stat(panel, Vector2(8, 126), "最佳记录")
	_detail_hidden = _stat(panel, Vector2(180, 126), "隐藏补给")
	_detail_threat = UIKit.label("", 8, UIKit.RED)
	_detail_threat.position = Vector2(94, 126)
	_detail_threat.size = Vector2(84, 22)
	_detail_threat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_detail_threat)
	_detail_uncommon = UIKit.label("", 8, UIKit.AMBER)
	_detail_uncommon.position = Vector2(8, 150)
	_detail_uncommon.size = Vector2(230, 10)
	_detail_uncommon.clip_text = true
	panel.add_child(_detail_uncommon)
	_detail_new = UIKit.label("", 8, UIKit.MUTED)
	_detail_new.position = Vector2(8, 161)
	_detail_new.size = Vector2(228, 30)
	_detail_new.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_detail_new)

	_detail_start = UIKit.button("任务简报 →", 106, 28, true)
	_detail_start.position = Vector2(242, 170)
	_detail_start.pressed.connect(_open_briefing)
	panel.add_child(_detail_start)


func _stat(parent: Node, pos: Vector2, key_text: String) -> Label:
	var key := UIKit.label(key_text, 7, UIKit.DIM, UIKit.font_latin())
	key.position = pos
	key.size = Vector2(80, 8)
	parent.add_child(key)
	var value := UIKit.label("—", 10, UIKit.INK)
	value.position = pos + Vector2(0, 9)
	value.size = Vector2(80, 12)
	value.clip_text = true
	parent.add_child(value)
	return value


func _build_bottom_bar() -> void:
	var panel := add_panel(Vector2(24, 300), Vector2(592, 42), UIKit.PANEL, UIKit.LINE)

	_char_portrait = UIKit.portrait_rect(GameManager.selected_character, 28.0)
	_char_portrait.position = Vector2(5, 7)
	panel.add_child(_char_portrait)
	_char_name = UIKit.label("", 9, UIKit.INK)
	_char_name.position = Vector2(38, 3)
	_char_name.size = Vector2(92, 11)
	panel.add_child(_char_name)
	_char_skill = UIKit.label("", 7, UIKit.MUTED)
	_char_skill.position = Vector2(38, 15)
	_char_skill.size = Vector2(92, 16)
	_char_skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_char_skill)
	var change := UIKit.button("更换", 54, 22)
	change.position = Vector2(132, 9)
	change.pressed.connect(func() -> void: go(&"characters", {"from": "levels"}))
	panel.add_child(change)

	var diff_label := UIKit.label("难度", 6, UIKit.DIM, UIKit.font_latin())
	diff_label.position = Vector2(200, 3)
	diff_label.size = Vector2(50, 7)
	panel.add_child(diff_label)
	var diffs := [&"NORMAL", &"HARD", &"EXPERT"]
	for i in 3:
		var diff: StringName = diffs[i]
		var btn := UIKit.button(UIKit.difficulty_name(diff), 58, 22)
		btn.position = Vector2(200 + i * 62, 12)
		btn.pressed.connect(_on_difficulty.bind(diff))
		panel.add_child(btn)
		_diff_buttons[diff] = btn

	_mode_button = UIKit.button("小队 4人", 88, 22)
	_mode_button.position = Vector2(390, 9)
	_mode_button.pressed.connect(_toggle_mode)
	panel.add_child(_mode_button)

	var start := UIKit.button("任务简报 →", 100, 28, true)
	start.position = Vector2(484, 6)
	start.pressed.connect(_open_briefing)
	panel.add_child(start)


func _refresh_all() -> void:
	_refresh_tabs()
	_refresh_cards()
	_refresh_detail()
	_refresh_bottom()


func _refresh_tabs() -> void:
	for chapter in _tabs.keys():
		var btn: Button = _tabs[chapter]
		var unlocked := GameManager.is_chapter_unlocked(int(chapter))
		var active: bool = int(chapter) == _chapter
		btn.disabled = not unlocked
		btn.add_theme_color_override("font_color", UIKit.AMBER if active else (UIKit.INK if unlocked else UIKit.DIM))
		btn.add_theme_stylebox_override("normal", UIKit.button_style(
			Color(0.17, 0.13, 0.06, 0.95) if active else UIKit.PANEL_RAISED,
			UIKit.AMBER if active else UIKit.LINE))
		btn.add_theme_stylebox_override("hover", UIKit.button_style(Color("222b34"), UIKit.AMBER))
		btn.add_theme_stylebox_override("disabled", UIKit.button_style(Color("101418"), Color("22282e")))


func _refresh_cards() -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_cards.clear()
	var levels := _levels_in_chapter(_chapter)
	for i in levels.size():
		var level: LevelData = levels[i]
		var card := _make_card(level, i)
		_cards_box.add_child(card)
		_cards[String(level.id)] = card
	_update_card_visuals()


func _make_card(level: LevelData, index: int) -> Control:
	var unlocked := GameManager.is_level_unlocked(level.id)
	var card := Control.new()
	card.position = Vector2(0, index * 46)
	card.size = Vector2(220, 42)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.size = Vector2(220, 42)
	bg.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL, UIKit.LINE))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var accent := ColorRect.new()
	accent.color = UIKit.chapter_color(level.chapter)
	accent.position = Vector2(0, 0)
	accent.size = Vector2(3, 42)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(accent)

	var id_label := UIKit.label(String(level.id).to_upper(), 14, UIKit.AMBER if unlocked else UIKit.DIM, UIKit.font_latin_bold())
	id_label.position = Vector2(10, 4)
	id_label.size = Vector2(36, 18)
	card.add_child(id_label)

	var title := UIKit.label(level.title, 10, UIKit.INK if unlocked else UIKit.DIM)
	title.position = Vector2(48, 4)
	title.size = Vector2(164, 12)
	title.clip_text = true
	card.add_child(title)

	var hs: Dictionary = SaveSystem.data.get("highscores", {}).get(String(level.id), {})
	var status_text := "未解锁 · 完成前置任务"
	var status_color := UIKit.DIM
	if unlocked:
		if SaveSystem.is_level_completed(level.id):
			status_text = "已完成 · %s 评价" % String(hs.get("rank", "C"))
			status_color = UIKit.rank_color(String(hs.get("rank", "C")))
		else:
			status_text = "待执行 · 目标 %s" % UIKit.format_score(level.par_score)
			status_color = UIKit.MUTED
	var status := UIKit.label(status_text, 7, status_color)
	status.position = Vector2(48, 20)
	status.size = Vector2(164, 9)
	card.add_child(status)

	var hidden := UIKit.label("隐藏补给 %d/1" % (1 if String(level.id) + "_hidden" in SaveSystem.data.get("hidden_rooms", []) else 0), 6, UIKit.DIM, UIKit.font_latin())
	hidden.position = Vector2(48, 30)
	hidden.size = Vector2(164, 7)
	card.add_child(hidden)

	var button := Button.new()
	button.size = Vector2(220, 42)
	button.flat = false
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not unlocked
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", UIKit.panel_style(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed", UIKit.panel_style(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.pressed.connect(_on_card_pressed.bind(level.id))
	card.add_child(button)
	card.set_meta("button", button)
	return card


func _update_card_visuals() -> void:
	for id in _cards.keys():
		var card: Control = _cards[id]
		var selected: bool = String(id) == String(_selected_id)
		var bg: Panel = card.get_child(0)
		bg.add_theme_stylebox_override("panel", UIKit.panel_style(
			Color(0.10, 0.085, 0.055, 0.95) if selected else UIKit.PANEL,
			UIKit.AMBER if selected else UIKit.LINE))
		var button: Button = card.get_meta("button")
		button.modulate = Color(1, 1, 1, 1) if selected else Color(0.92, 0.92, 0.92, 0.9)


func _refresh_detail() -> void:
	_selected = GameManager.get_level(_selected_id)
	if _selected == null:
		return
	if not _command_available():
		_mode = &"SQUAD"
	var unlocked := GameManager.is_level_unlocked(_selected.id)
	_detail_art.texture = UIKit.texture("res://assets/sprites/ui/ch%d.png" % _selected.chapter)
	if _detail_chapter != null:
		_detail_chapter.text = UIKit.chapter_title(_selected.chapter)
	if _detail_chapter_num != null:
		_detail_chapter_num.text = "CHAPTER %d" % _selected.chapter
	_detail_id.text = String(_selected.id).to_upper() + "  ·  " + _selected.chapter_name
	_detail_title.text = _selected.title
	_detail_sub.text = _selected.subtitle
	_detail_brief.text = _selected.briefing
	_detail_mode.text = UIKit.mode_name(_mode)
	_detail_difficulty.text = UIKit.difficulty_name(_difficulty)
	_detail_par.text = UIKit.format_score(_selected.par_score)
	var hs: Dictionary = SaveSystem.data.get("highscores", {}).get(String(_selected.id), {})
	if hs.is_empty():
		_detail_best.text = "—"
	else:
		_detail_best.text = "%s  %s" % [String(hs.get("rank", "C")), UIKit.format_score(int(hs.get("score", 0)))]
	_detail_hidden.text = "%d / 1" % (1 if String(_selected.id) + "_hidden" in SaveSystem.data.get("hidden_rooms", []) else 0)
	var threat_names: Array[String] = []
	for kind in _selected.special_weights.keys():
		var zd := GameManager.get_zombie(StringName(kind))
		threat_names.append(zd.display_name if zd else String(kind))
	_detail_threat.text = "特殊威胁\n" + (" / ".join(threat_names) if not threat_names.is_empty() else "无记录")
	var uncommon_names: Array[String] = []
	for kind in _selected.uncommon_weights.keys():
		var zd := GameManager.get_zombie(StringName(kind))
		uncommon_names.append(zd.display_name if zd else String(kind))
	_detail_uncommon.text = "变异普感：" + (" / ".join(uncommon_names) if not uncommon_names.is_empty() else "无")
	_detail_new.text = "新威胁：" + _selected.new_threat
	_detail_start.disabled = not unlocked
	_detail_start.text = "任务简报 →" if unlocked else "尚未解锁"


func _refresh_bottom() -> void:
	var character := GameManager.get_character(GameManager.selected_character)
	if character != null:
		_char_portrait.texture = UIKit.portrait(character.portrait)
		_char_name.text = character.display_name
		_char_skill.text = character.skill_name
	for diff in _diff_buttons.keys():
		var btn: Button = _diff_buttons[diff]
		var active: bool = diff == _difficulty
		btn.add_theme_color_override("font_color", UIKit.AMBER if active else UIKit.INK)
		btn.add_theme_stylebox_override("normal", UIKit.button_style(
			Color(0.17, 0.13, 0.06, 0.95) if active else UIKit.PANEL_RAISED,
			UIKit.AMBER if active else UIKit.LINE))
	var command := _command_available()
	_mode_button.disabled = not command
	_mode_button.text = "指挥 6-8" if _mode == &"COMMAND" else "小队 4人"
	_mode_button.add_theme_color_override("font_color", UIKit.TEAL if _mode == &"COMMAND" else UIKit.INK)


func _on_tab(chapter: int) -> void:
	if not GameManager.is_chapter_unlocked(chapter):
		return
	_chapter = chapter
	_selected_id = _first_level_in_chapter(chapter)
	var level := GameManager.get_level(_selected_id)
	if level != null:
		_mode = GameManager.default_mode_for(level)
	_refresh_all()
	AudioManager.play_sfx(&"ui_click")


func _on_card_pressed(id: StringName) -> void:
	if not GameManager.is_level_unlocked(id):
		AudioManager.play_sfx(&"ui_deny")
		return
	_selected_id = id
	var level := GameManager.get_level(id)
	if level != null:
		_mode = GameManager.default_mode_for(level)
	_refresh_all()
	AudioManager.play_sfx(&"ui_click")


func _on_difficulty(diff: StringName) -> void:
	_difficulty = diff
	GameManager.current_difficulty = diff
	_refresh_detail()
	_refresh_bottom()
	AudioManager.play_sfx(&"ui_click")


func _toggle_mode() -> void:
	if not _command_available():
		return
	_mode = &"SQUAD" if _mode == &"COMMAND" else &"COMMAND"
	GameManager.current_mode = _mode
	_refresh_detail()
	_refresh_bottom()
	AudioManager.play_sfx(&"ui_click")


func _open_briefing() -> void:
	if _selected == null or not GameManager.is_level_unlocked(_selected.id):
		return
	GameManager.current_difficulty = _difficulty
	GameManager.current_mode = _mode
	go(&"briefing", {
		"level_id": String(_selected.id),
		"mode": String(_mode),
		"difficulty": String(_difficulty),
	})


func _command_available() -> bool:
	return _selected != null and _selected.chapter >= 3


func _levels_in_chapter(chapter: int) -> Array[LevelData]:
	var out: Array[LevelData] = []
	for level in GameManager.get_levels():
		if level.chapter == chapter:
			out.append(level)
	return out


func _first_level_in_chapter(chapter: int) -> StringName:
	var levels := _levels_in_chapter(chapter)
	for level in levels:
		if GameManager.is_level_unlocked(level.id):
			return level.id
	return levels[0].id if not levels.is_empty() else &"l01"
