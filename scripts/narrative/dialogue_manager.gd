extends Node
## DialogueManager - 「锈蚀频率」对话系统。
## 职责：加载 dialogues.json，以底部字幕条播放 bark（战斗喊话）与
##       conversation（过场对话）；对话期间广播 dialogue_active（玩家缓速 30%）。
## 依赖：EventBus。字幕 UI 由本节点自建 CanvasLayer，不依赖场景结构。
## 对外接口：play(convo_id) / bark(speaker, text, color) / is_playing()

signal dialogue_active(active: bool)

const DATA_PATH := "res://resources/data/dialogues.json"
const LINE_SECONDS_PER_CHAR := 0.055

var _conversations: Dictionary = {}
var _layer: CanvasLayer
var _box: PanelContainer
var _name_label: Label
var _text_label: Label
var _hint_label: Label
var _playing := false
var _skip_requested := false
var _color_map: Dictionary = {}


func _ready() -> void:
	_load()
	_load_choices()
	_build_ui()
	_build_choice_ui()
	EventBus.story_choice_requested.connect(_request_choice)
	EventBus.notify.connect(_on_notify)
	# 主角台词颜色（含旧角色默认色）
	_color_map = {
		&"lin_yuan": Color(0.78, 0.34, 0.30), &"marcus": Color(0.55, 0.62, 0.45),
		&"lucia": Color(0.90, 0.65, 0.35), &"victor": Color(0.45, 0.75, 0.80),
		&"马洛": Color(0.85, 0.55, 0.20), &"雷耶斯": Color(0.45, 0.55, 0.85),
		&"铁面": Color(0.92, 0.92, 0.95), &"广播": Color(0.95, 0.75, 0.40),
		&"系统": Color(0.70, 0.70, 0.75),
	}


func _load() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("dialogues.json missing")
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_conversations = parsed


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 80
	add_child(_layer)
	_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.035, 0.92)
	style.border_color = Color(0.85, 0.70, 0.15, 0.7)
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	_box.add_theme_stylebox_override("panel", style)
	_box.position = Vector2(40, 292)
	_box.size = Vector2(560, 60)
	_box.visible = false
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_box)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(vbox)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.70, 0.15))
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 11)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(540, 0)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 7)
	_hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_hint_label.text = "[空格 / 点击] 继续"
	vbox.add_child(_name_label)
	vbox.add_child(_text_label)
	vbox.add_child(_hint_label)


func is_playing() -> bool:
	return _playing


## 播放一段对话（数据见 dialogues.json）。完成后可选触发选项事件。
func play(convo_id: StringName) -> void:
	if _playing:
		return
	var convo: Dictionary = _conversations.get(String(convo_id), {})
	var lines: Array = convo.get("lines", [])
	if lines.is_empty():
		return
	_playing = true
	dialogue_active.emit(true)
	_box.visible = true
	for line in lines:
		var who := String(line.get("who", ""))
		var text := String(line.get("text", ""))
		_show_line(who, text)
		var wait := maxf(1.2, text.length() * LINE_SECONDS_PER_CHAR)
		var t := 0.0
		while t < wait:
			await get_tree().process_frame
			if _skip_requested:
				break
			t += get_process_delta_time()
		_skip_requested = false
	_box.visible = false
	_playing = false
	dialogue_active.emit(false)
	var choice: String = String(convo.get("choice", ""))
	if choice != "":
		EventBus.story_choice_requested.emit(choice)


func _show_line(who: String, text: String) -> void:
	_name_label.text = who
	_text_label.text = text
	var speaker := StringName(who)
	if GameManager.get_character(speaker) != null:
		_name_label.add_theme_color_override("font_color",
			(GameManager.get_character(speaker) as CharacterData).dialogue_color)
	elif _color_map.has(speaker):
		_name_label.add_theme_color_override("font_color", _color_map[speaker])
	else:
		_name_label.add_theme_color_override("font_color", Color(0.85, 0.70, 0.15))


func _on_notify(text: String) -> void:
	# 允许用 notify 通道打单条战斗喊话
	if text.begins_with("[bark] "):
		var body := text.trim_prefix("[bark] ")
		var who := body.get_slice("：", 0)
		_bark_label(who, body.get_slice("：", 1))


func bark(speaker: String, text: String) -> void:
	_bark_label(speaker, text)


func _bark_label(who: String, text: String) -> void:
	if _playing:
		return
	_name_label.text = who
	_text_label.text = text
	_box.visible = true
	var timer := get_tree().create_timer(2.4)
	timer.timeout.connect(func() -> void:
		if not _playing:
			_box.visible = false)


func _unhandled_input(event: InputEvent) -> void:
	_unhandled_choice_key(event)
	if not _playing:
		return
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if (key != null and key.pressed and (key.keycode == KEY_SPACE or key.keycode == KEY_ENTER)) \
			or (click != null and click.pressed):
		_skip_requested = true
		get_viewport().set_input_as_handled()

# --- Story choices（剧情抉择） ------------------------------------------------
const CHOICES_PATH := "res://resources/data/story_choices.json"

var _choices: Dictionary = {}
var _choice_layer: CanvasLayer
var _choice_box: VBoxContainer
var _choice_prompt: Label
var _active_choice: StringName = &""


func _load_choices() -> void:
	if not FileAccess.file_exists(CHOICES_PATH):
		return
	var file := FileAccess.open(CHOICES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_choices = parsed


func _build_choice_ui() -> void:
	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = 85
	add_child(_choice_layer)
	_choice_box = VBoxContainer.new()
	_choice_box.position = Vector2(200, 120)
	_choice_box.size = Vector2(240, 120)
	_choice_box.visible = false
	_choice_layer.add_child(_choice_box)


func _request_choice(choice_id: StringName) -> void:
	var data: Dictionary = _choices.get(String(choice_id), {})
	if data.is_empty() or _active_choice != &"":
		return
	_active_choice = choice_id
	for child in _choice_box.get_children():
		child.queue_free()
	var prompt := Label.new()
	prompt.text = String(data.get("prompt", ""))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(240, 0)
	prompt.add_theme_font_size_override("font_size", 10)
	_choice_box.add_child(prompt)
	var options: Array = data.get("options", [])
	for i in options.size():
		var option: Dictionary = options[i]
		var btn := Button.new()
		btn.text = "[%d] %s" % [i + 1, String(option.get("text", ""))]
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_make_choice.bind(choice_id, i + 1))
		_choice_box.add_child(btn)
	_choice_box.visible = true


func _make_choice(choice_id: StringName, option: int) -> void:
	if _active_choice != choice_id:
		return
	_active_choice = &""
	_choice_box.visible = false
	var data: Dictionary = _choices.get(String(choice_id), {})
	var options: Array = data.get("options", [])
	if option >= 1 and option <= options.size():
		var chosen: Dictionary = options[option - 1]
		for flag in chosen.get("set_flags", []):
			SaveSystem.set_flag(StringName(flag))
		for entry in chosen.get("hostility", {}):
			FactionManager.adjust(StringName(entry), float(chosen["hostility"][entry]))
	EventBus.story_choice_made.emit(choice_id, option)
	EventBus.level_event.emit(String(data.get("resolved_text", "")))


func _unhandled_choice_key(event: InputEvent) -> void:
	if _active_choice == &"":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var idx := -1
	match key.keycode:
		KEY_1, KEY_KP_1: idx = 1
		KEY_2, KEY_KP_2: idx = 2
		KEY_3, KEY_KP_3: idx = 3
	if idx > 0:
		_make_choice(_active_choice, idx)
		get_viewport().set_input_as_handled()
