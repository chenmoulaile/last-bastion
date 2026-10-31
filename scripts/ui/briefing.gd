extends UIScreen
## Pre-mission briefing: objectives, threats, loadout and squad.

var _level_id: StringName = &"l01"
var _mode: StringName = &"SQUAD"
var _difficulty: StringName = &"NORMAL"
var _level: LevelData
var _squad_box: Control


func setup(payload: Dictionary) -> void:
	_level_id = StringName(payload.get("level_id", String(GameManager.current_level_id)))
	_mode = StringName(payload.get("mode", String(GameManager.current_mode)))
	_difficulty = StringName(payload.get("difficulty", String(GameManager.current_difficulty)))
	_level = GameManager.get_level(_level_id)
	if _level == null:
		_level_id = GameManager.continue_level_id()
		_level = GameManager.get_level(_level_id)
	if _level != null and not GameManager.is_level_unlocked(_level.id):
		_level_id = GameManager.continue_level_id()
		_level = GameManager.get_level(_level_id)
	if _level != null:
		if _mode == &"":
			_mode = GameManager.default_mode_for(_level)
		if _level.chapter < 3:
			_mode = &"SQUAD"


func _build() -> void:
	add_background("title_bg", 0.48)
	add_header("MISSION BRIEFING", "任务简报", UIKit.chapter_color(_level.chapter if _level else 1))
	add_back_button(&"levels", "章节")
	add_footer("检查点会自动记录队伍状态 · 倒地队友需要靠近按住 E 救助 · 撤离点通常需要坚守")
	_build_left()
	_build_right()
	_build_bottom()


func _build_left() -> void:
	var panel := add_panel(Vector2(24, 62), Vector2(336, 226), UIKit.PANEL, UIKit.LINE)
	var chapter := UIKit.label(UIKit.chapter_subtitle(_level.chapter), 7, UIKit.chapter_color(_level.chapter), UIKit.font_latin())
	chapter.position = Vector2(8, 5)
	chapter.size = Vector2(320, 8)
	panel.add_child(chapter)

	var id_label := UIKit.label(String(_level.id).to_upper() + "  ·  " + _level.chapter_name, 8, UIKit.AMBER, UIKit.font_latin())
	id_label.position = Vector2(8, 16)
	id_label.size = Vector2(320, 9)
	panel.add_child(id_label)

	var title := UIKit.title(_level.title, 20, UIKit.INK)
	title.position = Vector2(8, 26)
	title.size = Vector2(320, 24)
	panel.add_child(title)

	var subtitle := UIKit.label(_level.subtitle, 9, UIKit.MUTED)
	subtitle.position = Vector2(8, 50)
	subtitle.size = Vector2(320, 11)
	panel.add_child(subtitle)

	var line := ColorRect.new()
	line.color = UIKit.LINE
	line.position = Vector2(8, 64)
	line.size = Vector2(320, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

	var brief := UIKit.label(_level.briefing, 9, UIKit.INK)
	brief.position = Vector2(8, 70)
	brief.size = Vector2(320, 48)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(brief)

	var obj_head := UIKit.label("OBJECTIVES  任务目标", 7, UIKit.AMBER, UIKit.font_latin())
	obj_head.position = Vector2(8, 118)
	obj_head.size = Vector2(320, 8)
	panel.add_child(obj_head)
	var objectives := _objectives()
	for i in objectives.size():
		var bullet := UIKit.label("▸ " + objectives[i], 8, UIKit.INK)
		bullet.position = Vector2(8, 129 + i * 12)
		bullet.size = Vector2(320, 11)
		panel.add_child(bullet)

	var threat_head := UIKit.label("THREATS  威胁情报", 7, UIKit.RED, UIKit.font_latin())
	threat_head.position = Vector2(8, 187)
	threat_head.size = Vector2(320, 8)
	panel.add_child(threat_head)
	var threats := UIKit.label(_threat_text(), 8, UIKit.MUTED)
	threats.position = Vector2(8, 197)
	threats.size = Vector2(320, 24)
	threats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(threats)


func _build_right() -> void:
	var panel := add_panel(Vector2(368, 62), Vector2(248, 226), UIKit.PANEL, UIKit.LINE)
	var art := TextureRect.new()
	art.texture = UIKit.texture("res://assets/sprites/ui/ch%d.png" % _level.chapter)
	art.position = Vector2(8, 8)
	art.size = Vector2(232, 130)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)

	var mode := UIKit.label("模式", 7, UIKit.DIM, UIKit.font_latin())
	mode.position = Vector2(8, 144)
	mode.size = Vector2(40, 8)
	panel.add_child(mode)
	var mode_value := UIKit.label(UIKit.mode_name(_mode), 9, UIKit.TEAL if _mode == &"COMMAND" else UIKit.INK)
	mode_value.position = Vector2(48, 142)
	mode_value.size = Vector2(90, 11)
	panel.add_child(mode_value)

	var diff := UIKit.label("难度", 7, UIKit.DIM, UIKit.font_latin())
	diff.position = Vector2(142, 144)
	diff.size = Vector2(40, 8)
	panel.add_child(diff)
	var diff_value := UIKit.label(UIKit.difficulty_name(_difficulty), 9, UIKit.AMBER)
	diff_value.position = Vector2(182, 142)
	diff_value.size = Vector2(58, 11)
	panel.add_child(diff_value)

	var par := UIKit.label("目标分  " + UIKit.format_score(_level.par_score), 8, UIKit.MUTED)
	par.position = Vector2(8, 158)
	par.size = Vector2(232, 10)
	panel.add_child(par)

	var squad_head := UIKit.label("SQUAD  队伍编成", 7, UIKit.AMBER, UIKit.font_latin())
	squad_head.position = Vector2(8, 172)
	squad_head.size = Vector2(232, 8)
	panel.add_child(squad_head)

	_squad_box = Control.new()
	_squad_box.position = Vector2(8, 183)
	_squad_box.size = Vector2(232, 38)
	_squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_squad_box)
	_build_squad()


func _build_bottom() -> void:
	var panel := add_panel(Vector2(24, 300), Vector2(592, 42), UIKit.PANEL, UIKit.LINE)
	var character := GameManager.get_character(GameManager.selected_character)
	var portrait := UIKit.portrait_rect(GameManager.selected_character, 30.0)
	portrait.position = Vector2(5, 6)
	panel.add_child(portrait)
	var name_label := UIKit.label(character.display_name if character else "突击兵", 9, UIKit.INK)
	name_label.position = Vector2(40, 3)
	name_label.size = Vector2(130, 11)
	panel.add_child(name_label)
	var loadout := UIKit.label(_loadout_text(character), 7, UIKit.MUTED)
	loadout.position = Vector2(40, 15)
	loadout.size = Vector2(270, 20)
	loadout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(loadout)
	var tip := UIKit.label("ENTER 开始任务", 7, UIKit.DIM, UIKit.font_latin())
	tip.position = Vector2(320, 16)
	tip.size = Vector2(140, 9)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(tip)
	var start := UIKit.button("开始任务  →", 140, 30, true)
	start.position = Vector2(444, 6)
	start.pressed.connect(_start)
	panel.add_child(start)
	start.grab_focus()


func _build_squad() -> void:
	var members: Array[CharacterData] = []
	if _mode == &"COMMAND":
		for role in _level.commander_squad:
			var c := GameManager.get_character(StringName(role))
			if c != null:
				members.append(c)
		if members.is_empty():
			for role in [&"rifleman", &"gunner", &"medic", &"demolisher"]:
				var c := GameManager.get_character(role)
				if c != null:
					members.append(c)
	else:
		for c in GameManager.get_playable_characters():
			if c.id != GameManager.selected_character and GameManager.is_character_unlocked(c.id):
				members.append(c)
			if members.size() >= 3:
				break
	var limit := mini(members.size(), 8)
	for i in limit:
		var c: CharacterData = members[i]
		var portrait := UIKit.portrait_rect(c.portrait, 16.0)
		portrait.position = Vector2(i * 28, 0)
		_squad_box.add_child(portrait)
		var name_label := UIKit.label(c.display_name, 6, UIKit.MUTED)
		name_label.position = Vector2(i * 28 - 2, 17)
		name_label.size = Vector2(24, 7)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		_squad_box.add_child(name_label)


func _objectives() -> Array[String]:
	var out: Array[String] = []
	out.append("推进至撤离点 · 总长 %d m" % int(_level.length / 10.0))
	if _level.extraction_defense > 0.0:
		out.append("守住撤离点 %.0f 秒" % _level.extraction_defense)
	if _level.escort_vehicle:
		out.append("护送装甲车穿过封锁区")
	if not _level.bosses.is_empty():
		var names: Array[String] = []
		for kind in _level.bosses:
			var zd := GameManager.get_zombie(StringName(kind))
			names.append(zd.display_name if zd else String(kind))
		out.append("击杀首领：" + " / ".join(names))
	for ev in _level.events:
		if String(ev.get("type", "")) == "defense":
			out.append("防守 %.0f 秒" % float(ev.get("seconds", 40.0)))
			break
	out.append("搜索隐藏补给点（1 处）")
	return out


func _threat_text() -> String:
	var names: Array[String] = []
	for kind in _level.special_weights.keys():
		var zd := GameManager.get_zombie(StringName(kind))
		names.append(zd.display_name if zd else String(kind))
	var uncommon: Array[String] = []
	for kind in _level.uncommon_weights.keys():
		var zd := GameManager.get_zombie(StringName(kind))
		uncommon.append(zd.display_name if zd else String(kind))
	var text := "特殊感染者：" + (" / ".join(names) if not names.is_empty() else "尚未发现")
	if not uncommon.is_empty():
		text += "\n变异普感：" + " / ".join(uncommon)
	if _level.dark:
		text += "\n环境：黑暗（L 手电）"
	if _level.rain:
		text += "\n天气：降雨"
	return text


func _loadout_text(character: CharacterData) -> String:
	if character == null:
		return ""
	var primary := GameManager.get_weapon(character.primary_weapon)
	var secondary := GameManager.get_weapon(character.secondary_weapon)
	var melee := GameManager.get_weapon(character.melee_weapon)
	var parts: Array[String] = []
	if primary:
		parts.append(primary.display_name)
	if secondary:
		parts.append(secondary.display_name)
	if melee:
		parts.append(melee.display_name)
	parts.append("技能：" + character.skill_name)
	return "  ·  ".join(parts)


func _start() -> void:
	if _level == null:
		return
	GameManager.selected_character = GameManager.selected_character
	GameManager.current_difficulty = _difficulty
	GameManager.current_mode = _mode
	GameManager.start_level(_level.id, _mode, _difficulty, GameManager.selected_character)
