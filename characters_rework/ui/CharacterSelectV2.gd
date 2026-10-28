class_name CharacterSelectV2
extends Control
## ---------------------------------------------------------------------------
## 职责: 角色选择界面(重构版)。读取 data/playable/*.tres,为每个角色用
##       SubViewport 离屏渲染一帧 PlayerRenderer 生成静态预览图
##       (ImageTexture),显示属性与技能说明;支持左右键/数字键选择、
##       确认键选定。UI 全部代码构建,场景文件只有根节点。
## 依赖: ReworkCharacterData / PlayerRenderer / ReworkPalettes;
##       GameManager(可选,存在时写入 selected_character);
##       EventBus(可选,不存在时仅发本地信号)。
## 对外接口:
##   signal character_selected(id: StringName)     # 光标移动
##   signal character_confirmed(id: StringName)    # 确认选定
##   selected_id() -> StringName
## ---------------------------------------------------------------------------

signal character_selected(id: StringName)
signal character_confirmed(id: StringName)
signal ui_ready

const DATA_DIR := "res://characters_rework/data/playable"
const PREVIEW_SIZE := Vector2i(72, 88)
const FALLBACK_ORDER: Array[StringName] = [
	&"assault", &"heavy", &"medic", &"scout", &"operative", &"officer",
]

var characters: Array[ReworkCharacterData] = []
var selected_index: int = 0

var _card_box: HBoxContainer = null
var _cards: Array[Control] = []
var _name_label: Label = null
var _stats_label: Label = null
var _skill_label: Label = null
var _desc_label: Label = null
var _hint_label: Label = null
var _game: Node = null
var _bus: Node = null
var _previews: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_game = _autoload(&"GameManager")
	_bus = _autoload(&"EventBus")
	_load_characters()
	_previews = await _capture_all_previews()
	_build_ui()
	_refresh()
	ui_ready.emit()


func selected_id() -> StringName:
	if characters.is_empty():
		return &""
	return characters[selected_index].id


## ------------------------------------------------------------ 数据 ----

func _load_characters() -> void:
	characters.clear()
	for id in FALLBACK_ORDER:
		var path := "%s/%s.tres" % [DATA_DIR, id]
		if ResourceLoader.exists(path):
			var data := load(path) as ReworkCharacterData
			if data != null:
				characters.append(data)


## ------------------------------------------------------------ UI 构建 ----

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.066, 0.086)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 24
	root.offset_top = 14
	root.offset_right = -24
	root.offset_bottom = -12
	add_child(root)

	var title := Label.new()
	title.text = "选择幸存者"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.8))
	root.add_child(title)

	_card_box = HBoxContainer.new()
	_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_box.add_theme_constant_override("separation", 10)
	_card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_card_box)

	for index in characters.size():
		var preview_texture: Texture2D = _previews[index] if index < _previews.size() \
			else _placeholder_texture(characters[index])
		_card_box.add_child(_build_card(index, preview_texture))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	root.add_child(info)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 18)
	info.add_child(_name_label)
	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 12)
	info.add_child(_stats_label)
	_skill_label = Label.new()
	_skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_label.add_theme_font_size_override("font_size", 12)
	info.add_child(_skill_label)
	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	info.add_child(_desc_label)

	_hint_label = Label.new()
	_hint_label.text = "A/D 或 ←/→ 选择 · Enter/鼠标左键 确认 · 1-6 直选"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
	root.add_child(_hint_label)


func _build_card(index: int, preview_texture: Texture2D) -> Control:
	var data := characters[index]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(88, 118)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)
	var preview := TextureRect.new()
	preview.texture = preview_texture
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vbox.add_child(preview)
	var caption := Label.new()
	caption.text = data.display_name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	vbox.add_child(caption)
	var number := Label.new()
	number.text = "[%d]" % (index + 1)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 9)
	number.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	vbox.add_child(number)
	card.gui_input.connect(_on_card_input.bind(index))
	_cards.append(card)
	return card


func _capture_all_previews() -> Array:
	## 逐个角色离屏渲染一帧并截图。SubViewport 渲染需要真实帧循环,
	## headless 下 get_image() 可能为空 → 回退占位色块,UI 永不崩溃。
	var result: Array = []
	for data in characters:
		result.append(await _capture_preview(data))
	return result


func _capture_preview(data: ReworkCharacterData) -> ImageTexture:
	## SubViewport 离屏渲染一帧 → Image → ImageTexture(静态预览)。
	## headless / 渲染不可用时回退为 accent 色块占位,保证 UI 永不崩溃。
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var renderer := PlayerRenderer.new()
	renderer.setup(data)
	renderer.set_anim_state(CodeRenderer.STATE_IDLE)
	renderer.set_facing(1)
	renderer.position = Vector2(PREVIEW_SIZE.x * 0.5, PREVIEW_SIZE.y - 8.0)
	viewport.add_child(renderer)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return _placeholder_texture(data)
	return ImageTexture.create_from_image(image)


func _placeholder_texture(data: ReworkCharacterData) -> ImageTexture:
	var image := Image.create_empty(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	var palette: Dictionary = data.palette
	if palette.is_empty():
		palette = ReworkPalettes.for_id(data.id)
	var fill: Color = palette.get("body_primary", Color.GRAY)
	image.fill(fill)
	return ImageTexture.create_from_image(image)


## ------------------------------------------------------------ 交互 ----

func _unhandled_input(event: InputEvent) -> void:
	if characters.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode: int = event.keycode
		if keycode >= KEY_1 and keycode <= KEY_9:
			var index := keycode - KEY_1
			if index < characters.size():
				_select(index)
				return
	if _is_nav(event, -1):
		_select(selected_index - 1)
	elif _is_nav(event, 1):
		_select(selected_index + 1)
	elif _is_confirm(event):
		_confirm()


func _is_nav(event: InputEvent, direction: int) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if direction < 0 and (event.keycode == KEY_A or event.keycode == KEY_LEFT):
			return true
		if direction > 0 and (event.keycode == KEY_D or event.keycode == KEY_RIGHT):
			return true
	return false


func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER \
			or event.keycode == KEY_SPACE
	if event is InputEventMouseButton and event.pressed:
		return event.button_index == MOUSE_BUTTON_LEFT
	return false


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_select(index)
		_confirm()


func _select(index: int) -> void:
	if characters.is_empty():
		return
	selected_index = posmod(index, characters.size())
	character_selected.emit(characters[selected_index].id)
	_refresh()


func _confirm() -> void:
	if characters.is_empty():
		return
	var id := characters[selected_index].id
	if _game != null and "selected_character" in _game:
		_game.set("selected_character", id)
	character_confirmed.emit(id)


func _refresh() -> void:
	for index in _cards.size():
		var card := _cards[index]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.12, 0.16) if index != selected_index \
			else Color(0.16, 0.20, 0.27)
		style.border_color = Color(0.25, 0.3, 0.38) if index != selected_index \
			else Color(0.95, 0.8, 0.35)
		style.set_border_width_all(1 if index != selected_index else 2)
		style.set_corner_radius_all(3)
		card.add_theme_stylebox_override("panel", style)
	if characters.is_empty():
		return
	var data := characters[selected_index]
	_name_label.text = "%s · %s" % [data.display_name, data.callsign]
	_name_label.add_theme_color_override("font_color",
		data.palette_color("accent", Color.WHITE))
	_stats_label.text = "HP %d    速度 %d    解锁分数 %s" % [
		data.max_hp, int(data.speed), _format_score(data.unlock_score)]
	_skill_label.text = "技能[%s]：%s — %s（CD %.0fs）" % [
		data.passive_ability_id, data.skill_name, data.skill_desc, data.skill_cd]
	_desc_label.text = data.description


static func _format_score(value: int) -> String:
	if value <= 0:
		return "初始"
	return str(value)


func _autoload(what: StringName) -> Node:
	return get_node_or_null("/root/" + String(what))
