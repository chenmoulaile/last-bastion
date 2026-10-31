extends UIScreen
## Six playable survivors, unlock requirements, skills and loadout preview.

var _back_target: StringName = &"menu"
var _cards: Dictionary = {}
var _selected: StringName = &"assault"
var _bottom_portrait: TextureRect
var _bottom_name: Label
var _bottom_skill: Label


func setup(payload: Dictionary) -> void:
	_back_target = StringName(payload.get("from", "menu"))
	_selected = GameManager.selected_character


func _build() -> void:
	add_background("title_bg", 0.55)
	add_header("SURVIVORS", "角色档案", UIKit.GREEN)
	add_back_button(_back_target, "返回")
	add_footer("点击卡片设为出战角色 · 每名角色拥有独立主武器与主动技能 · 队友由 AI 自动补齐")

	var characters := GameManager.get_playable_characters()
	for i in characters.size():
		var c: CharacterData = characters[i]
		var col := i % 3
		var row := int(i / 3)
		var pos := Vector2(24 + col * 198, 62 + row * 118)
		var card := _make_card(c, pos)
		add_child(card)
		_cards[String(c.id)] = card
	_refresh_cards()
	_build_bottom()


func _build_bottom() -> void:
	var panel := add_panel(Vector2(24, 300), Vector2(592, 38), UIKit.PANEL, UIKit.LINE)
	_bottom_portrait = UIKit.portrait_rect(_selected, 28.0)
	_bottom_portrait.position = Vector2(5, 5)
	panel.add_child(_bottom_portrait)
	_bottom_name = UIKit.label("", 9, UIKit.INK)
	_bottom_name.position = Vector2(38, 3)
	_bottom_name.size = Vector2(130, 11)
	panel.add_child(_bottom_name)
	_bottom_skill = UIKit.label("", 7, UIKit.MUTED)
	_bottom_skill.position = Vector2(38, 15)
	_bottom_skill.size = Vector2(300, 18)
	_bottom_skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_bottom_skill)
	var back := UIKit.button("返回章节", 100, 24)
	back.position = Vector2(484, 7)
	back.pressed.connect(func() -> void: go(_back_target))
	panel.add_child(back)
	_refresh_bottom()


func _make_card(c: CharacterData, pos: Vector2) -> Control:
	var unlocked := GameManager.is_character_unlocked(c.id)
	var card := Control.new()
	card.position = pos
	card.size = Vector2(188, 110)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.size = Vector2(188, 110)
	bg.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL, UIKit.LINE))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var accent := ColorRect.new()
	accent.color = c.accent
	accent.position = Vector2(0, 0)
	accent.size = Vector2(3, 110)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(accent)

	var portrait := UIKit.portrait_rect(c.portrait, 42.0)
	portrait.position = Vector2(8, 7)
	portrait.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.35, 0.35, 0.35, 0.8)
	card.add_child(portrait)

	var name_label := UIKit.label(c.display_name, 12, UIKit.INK if unlocked else UIKit.DIM)
	name_label.position = Vector2(56, 5)
	name_label.size = Vector2(126, 14)
	card.add_child(name_label)
	var callsign := UIKit.label(c.callsign, 7, c.accent if unlocked else UIKit.DIM, UIKit.font_latin())
	callsign.position = Vector2(56, 20)
	callsign.size = Vector2(126, 8)
	card.add_child(callsign)

	var skill_icon := UIKit.icon_rect("skill_" + String(c.id), 16.0)
	skill_icon.position = Vector2(8, 54)
	skill_icon.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.4, 0.4, 0.4, 0.8)
	card.add_child(skill_icon)
	var skill := UIKit.label(c.skill_name, 8, UIKit.AMBER if unlocked else UIKit.DIM)
	skill.position = Vector2(28, 53)
	skill.size = Vector2(152, 10)
	card.add_child(skill)
	var skill_desc := UIKit.label(c.skill_desc, 7, UIKit.MUTED)
	skill_desc.position = Vector2(28, 64)
	skill_desc.size = Vector2(152, 18)
	skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(skill_desc)

	var stats := UIKit.label("HP %d   SPD %d   CD %.0fs" % [c.max_hp, int(c.speed), c.skill_cd], 7, UIKit.INK, UIKit.font_latin())
	stats.position = Vector2(8, 84)
	stats.size = Vector2(172, 8)
	card.add_child(stats)

	var status := UIKit.label("", 6, UIKit.DIM, UIKit.font_latin())
	status.position = Vector2(8, 95)
	status.size = Vector2(172, 8)
	card.add_child(status)
	if not unlocked:
		status.text = _unlock_hint(c.id)
		status.add_theme_color_override("font_color", UIKit.AMBER)
	elif c.id == GameManager.selected_character:
		status.text = "SELECTED  ·  当前出战"
		status.add_theme_color_override("font_color", UIKit.GREEN)
	else:
		status.text = "AVAILABLE  ·  点击选择"
	# 「锈蚀频率」四主角：显示代号/被动/中文简介；旧六角色标注「原型小队」（P0-3c）
	if c.survivor:
		var passive := UIKit.label("%s · %s" % [c.codename, c.passive_name], 7, c.accent)
		passive.position = Vector2(56, 30)
		passive.size = Vector2(126, 9)
		passive.clip_text = true
		card.add_child(passive)
		var bio := UIKit.label(c.bio, 6, UIKit.MUTED)
		bio.position = Vector2(8, 31)
		bio.size = Vector2(46, 22)
		bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bio.visible = false  # 卡片空间有限；简介显示在底部详情栏
		card.add_child(bio)
	else:
		var legacy := UIKit.label("原型小队", 6, UIKit.DIM)
		legacy.position = Vector2(56, 30)
		legacy.size = Vector2(126, 9)
		card.add_child(legacy)

	var button := Button.new()
	button.size = Vector2(188, 110)
	button.disabled = not unlocked
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", UIKit.panel_style(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed", UIKit.panel_style(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.pressed.connect(_select_character.bind(c.id))
	card.add_child(button)
	card.set_meta("bg", bg)
	card.set_meta("accent", accent)
	card.set_meta("status", status)
	card.set_meta("portrait", portrait)
	return card


func _refresh_cards() -> void:
	for id in _cards.keys():
		var card: Control = _cards[id]
		var unlocked := GameManager.is_character_unlocked(StringName(id))
		var selected: bool = String(id) == String(_selected)
		var bg: Panel = card.get_meta("bg")
		bg.add_theme_stylebox_override("panel", UIKit.panel_style(
			Color(0.10, 0.09, 0.06, 0.95) if selected else UIKit.PANEL,
			UIKit.AMBER if selected else UIKit.LINE))
		card.modulate = Color.WHITE if unlocked else Color(0.8, 0.8, 0.8, 1)
		var status: Label = card.get_meta("status")
		if not unlocked:
			status.text = _unlock_hint(StringName(id))
			status.add_theme_color_override("font_color", UIKit.AMBER)
		elif selected:
			status.text = "SELECTED  ·  当前出战"
			status.add_theme_color_override("font_color", UIKit.GREEN)
		else:
			status.text = "AVAILABLE  ·  点击选择"
			status.add_theme_color_override("font_color", UIKit.DIM)
		var portrait: TextureRect = card.get_meta("portrait")
		portrait.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.35, 0.35, 0.35, 0.8)
	if _bottom_name != null:
		_refresh_bottom()


func _refresh_bottom() -> void:
	var c := GameManager.get_character(_selected)
	if c == null:
		return
	_bottom_portrait.texture = UIKit.portrait(c.portrait)
	_bottom_name.text = c.display_name + "  ·  " + c.callsign
	# 「锈蚀频率」主角展示被动与中文简介；旧角色展示技能与原型标注（P0-3c）
	if c.survivor:
		_bottom_name.text += "  ·「%s」" % c.codename
		_bottom_skill.text = "被动 %s — %s\n%s" % [c.passive_name, c.passive_desc, c.bio]
	else:
		_bottom_name.text += "  · 原型小队"
		_bottom_skill.text = "技能 " + c.skill_name + " — " + c.skill_desc


func _select_character(id: StringName) -> void:
	if not GameManager.is_character_unlocked(id):
		AudioManager.play_sfx(&"ui_deny")
		return
	GameManager.selected_character = id
	_selected = id
	GameManager.selected_squad = []
	_refresh_cards()
	AudioManager.play_sfx(&"ui_click")
	var c := GameManager.get_character(id)
	if c != null:
		EventBus.notify.emit("出战角色：" + c.display_name)


func _unlock_hint(id: StringName) -> String:
	match id:
		&"ninja":
			return "LOCKED  ·  累计 100,000 分解锁"
		&"officer":
			return "LOCKED  ·  获得 3 个 S 评价解锁"
		_:
			return "LOCKED  ·  完成战役解锁"
