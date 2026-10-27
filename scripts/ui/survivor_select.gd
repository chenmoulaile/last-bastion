extends UIScreen
## CharacterSelect - the four named survivors of the 2019 RIFT CITY campaign.
##
## Single player: pick one, the other three become your AI squad.
## Co-op: each local slot claims a survivor; taken survivors are greyed out so
## four players always bring four different characters.

const SLOTS := 4

var _back_target: StringName = &"menu"
var _selected: String = "lin_yuan"
var _slot: int = 0
var _cards: Dictionary = {}
var _slot_buttons: Array[Button] = []
var _quote: Label
var _passive: Label
var _loadout: Label
var _confirm: Button


func setup(payload: Dictionary) -> void:
	_back_target = StringName(payload.get("from", "menu"))
	var current := GameManager.selected_character
	var survivor: CharacterData = GameManager.get_survivor(current)
	if survivor != null:
		_selected = String(survivor.id)
	GameManager.coop_active = bool(payload.get("coop", GameManager.coop_active))


func _build() -> void:
	add_background("title_bg", 0.62)
	add_header("RIFT CITY · 2019", "幸存者小队", UIKit.AMBER)
	add_back_button(_back_target, "返回")
	add_footer("单人：其余三人由 AI 接管 ｜ 合作：四名玩家必须选择不同角色 ｜ 被动常驻，无需按键")

	var survivors := GameManager.get_archive_survivors()
	for i in survivors.size():
		var character: CharacterData = survivors[i]
		var card := _make_card(character, Vector2(18 + i * 152, 58))
		add_child(card)
		_cards[String(character.id)] = card

	_build_detail()

	var legacy := UIKit.button("经典小队 →", 92, 20)
	legacy.position = Vector2(24, 314)
	legacy.pressed.connect(func() -> void: go(&"characters"))
	add_child(legacy)

	_refresh()


func _make_card(character: CharacterData, pos: Vector2) -> Control:
	var card := Control.new()
	card.position = pos
	card.size = Vector2(146, 138)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.size = Vector2(146, 138)
	bg.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL, UIKit.LINE))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var accent := ColorRect.new()
	accent.color = character.accent
	accent.size = Vector2(3, 138)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(accent)

	var portrait := UIKit.portrait_rect(character.portrait, 44.0)
	portrait.position = Vector2(7, 7)
	portrait.modulate = character.palette_tint
	card.add_child(portrait)

	var name_label := UIKit.label(character.display_name, 12, UIKit.INK)
	name_label.position = Vector2(56, 6)
	name_label.size = Vector2(86, 14)
	card.add_child(name_label)

	var codename := UIKit.label(character.codename + " · " + character.callsign, 6, character.accent, UIKit.font_latin())
	codename.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codename.position = Vector2(56, 22)
	codename.size = Vector2(86, 12)
	card.add_child(codename)

	var passive := UIKit.label(character.passive_name, 8, UIKit.AMBER)
	passive.position = Vector2(7, 54)
	passive.size = Vector2(132, 10)
	card.add_child(passive)

	var short_desc := character.passive_desc
	if short_desc.length() > 30:
		short_desc = short_desc.substr(0, 29) + "…"
	var desc := UIKit.label(short_desc, 7, UIKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(7, 64)
	desc.size = Vector2(132, 46)
	card.add_child(desc)

	var stats := UIKit.label("HP %d  SPD %d  STL ×%.1f" % [character.max_hp, int(character.speed),
		character.stealth_speed_multiplier], 6, UIKit.DIM, UIKit.font_latin())
	stats.position = Vector2(7, 112)
	stats.size = Vector2(132, 8)
	card.add_child(stats)

	var owner := UIKit.label("", 6, UIKit.GREEN, UIKit.font_latin())
	owner.position = Vector2(7, 124)
	owner.size = Vector2(132, 8)
	card.add_child(owner)

	var button := Button.new()
	button.size = Vector2(146, 138)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", UIKit.panel_style(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed", UIKit.panel_style(Color(0, 0, 0, 0.16), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_select.bind(String(character.id)))
	card.add_child(button)

	card.set_meta("bg", bg)
	card.set_meta("owner", owner)
	card.set_meta("portrait", portrait)
	return card


func _build_detail() -> void:
	var panel := add_panel(Vector2(18, 202), Vector2(604, 100), Color(0.035, 0.045, 0.058, 0.95), UIKit.LINE)
	var kicker := UIKit.label("SURVIVOR FILE", 6, UIKit.AMBER, UIKit.font_latin())
	kicker.position = Vector2(8, 4)
	panel.add_child(kicker)

	_quote = UIKit.label("", 11, UIKit.INK)
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.position = Vector2(8, 12)
	_quote.size = Vector2(380, 32)
	panel.add_child(_quote)

	_passive = UIKit.label("", 8, UIKit.AMBER)
	_passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive.position = Vector2(8, 46)
	_passive.size = Vector2(380, 20)
	panel.add_child(_passive)

	_loadout = UIKit.label("", 7, UIKit.MUTED, UIKit.font_latin())
	_loadout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout.position = Vector2(8, 70)
	_loadout.size = Vector2(380, 22)
	panel.add_child(_loadout)

	var slot_label := UIKit.label("CO-OP SLOT", 6, UIKit.DIM, UIKit.font_latin())
	slot_label.position = Vector2(400, 4)
	slot_label.size = Vector2(120, 8)
	panel.add_child(slot_label)
	for i in SLOTS:
		var button := UIKit.button("P%d" % (i + 1), 44, 20)
		button.position = Vector2(400 + i * 48, 14)
		button.pressed.connect(_set_slot.bind(i))
		panel.add_child(button)
		_slot_buttons.append(button)

	_confirm = UIKit.button("确认出战", 120, 26, true)
	_confirm.position = Vector2(472, 62)
	_confirm.pressed.connect(_confirm_selection)
	panel.add_child(_confirm)

	var hint := UIKit.label("合作模式下已选角色会置灰", 7, UIKit.DIM)
	hint.position = Vector2(400, 42)
	hint.size = Vector2(196, 10)
	panel.add_child(hint)


func _set_slot(slot: int) -> void:
	_slot = slot
	GameManager.coop_active = slot > 0 or GameManager.coop_active
	AudioManager.play_sfx(&"ui_click")
	_refresh()


func _select(character_id: String) -> void:
	if GameManager.character_taken_by_other(_slot, StringName(character_id)):
		AudioManager.play_sfx(&"ui_deny")
		EventBus.notify.emit("该角色已被其他玩家选择")
		return
	_selected = character_id
	GameManager.claim_character(_slot, StringName(character_id))
	AudioManager.play_sfx(&"ui_click")
	_refresh()


func _refresh() -> void:
	for id in _cards.keys():
		var card: Control = _cards[id]
		var is_selected: bool = String(id) == _selected
		var taken_by := _slot_owner(String(id))
		var bg: Panel = card.get_meta("bg")
		bg.add_theme_stylebox_override("panel", UIKit.panel_style(
			Color(0.10, 0.09, 0.06, 0.95) if is_selected else UIKit.PANEL,
			UIKit.AMBER if is_selected else UIKit.LINE))
		card.modulate = Color(0.55, 0.55, 0.55, 1.0) if taken_by >= 0 else Color.WHITE
		var owner: Label = card.get_meta("owner")
		owner.text = ("P%d 已选" % (taken_by + 1)) if taken_by >= 0 else ""
	for i in _slot_buttons.size():
		_slot_buttons[i].add_theme_color_override("font_color",
			UIKit.AMBER if i == _slot else UIKit.INK)
	var character := GameManager.get_survivor(StringName(_selected))
	if character == null:
		return
	_quote.text = "「%s」" % character.monologue
	_passive.text = "%s — %s（冷却 %.0fs）" % [character.passive_name, character.passive_desc, character.passive_cooldown]
	_loadout.text = "主武器 %s  ·  副武器 %s  ·  近战 %s  ·  可解读档案：%s" % [
		String(character.primary_weapon).to_upper(),
		String(character.secondary_weapon).to_upper(),
		String(character.melee_weapon).to_upper(),
		", ".join(character.unlock_archive_types) if not character.unlock_archive_types.is_empty() else "—",
	]


func _slot_owner(character_id: String) -> int:
	for slot in GameManager.coop_slots.keys():
		if String(GameManager.coop_slots[slot]) == character_id:
			return int(slot)
	return -1


func _confirm_selection() -> void:
	var character := GameManager.get_survivor(StringName(_selected))
	if character == null:
		return
	GameManager.selected_character = character.id
	# Single player: the other three survivors become the AI squad.
	var squad: Array[StringName] = []
	for other in GameManager.get_archive_survivors():
		if other.id != character.id:
			squad.append(other.id)
	GameManager.selected_squad = squad
	AudioManager.play_sfx(&"ui_confirm")
	EventBus.notify.emit("出战角色：" + character.display_name)
	go(_back_target)
