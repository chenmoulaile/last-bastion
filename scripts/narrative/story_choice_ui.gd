extends Control
## StoryChoiceUI - generic mid-campaign binary/ternary choice.
## Pauses the game, applies flags / hostility / world events on selection.

var level: Node = null
var choice_id: String = ""

var _data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_data = StoryChoices.get_choice(choice_id)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var title := UIKit.title(String(_data.get("title", "抉择")), 24, UIKit.INK)
	title.position = Vector2(0, 58)
	title.size = Vector2(640, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var prompt := UIKit.label(String(_data.get("prompt", "")), 9, UIKit.MUTED)
	prompt.position = Vector2(40, 92)
	prompt.size = Vector2(560, 26)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(prompt)

	var options: Array = _data.get("options", [])
	var width := 260.0
	var gap := 20.0
	var total := options.size() * width + maxi(0, options.size() - 1) * gap
	var start_x := (640.0 - total) * 0.5
	for i in options.size():
		var option: Dictionary = options[i]
		_build_option(option, Vector2(start_x + i * (width + gap), 136), width)

	var hint := UIKit.label("选择会立即生效，并写入存档标记", 7, UIKit.DIM, UIKit.font_latin())
	hint.position = Vector2(0, 320)
	hint.size = Vector2(640, 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _build_option(option: Dictionary, pos: Vector2, width: float) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(width, 156)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.055, 0.065, 0.98), UIKit.AMBER))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var label := UIKit.label(String(option.get("label", "选项")), 15, UIKit.INK)
	label.position = Vector2(14, 12)
	label.size = Vector2(width - 28, 20)
	panel.add_child(label)

	var desc := UIKit.label(String(option.get("desc", "")), 8, UIKit.MUTED)
	desc.position = Vector2(14, 40)
	desc.size = Vector2(width - 28, 70)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(desc)

	var button := UIKit.button("选择", width - 28, 26, true)
	button.position = Vector2(14, 116)
	button.pressed.connect(_choose.bind(String(option.get("id", ""))))
	panel.add_child(button)


func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false


func _choose(option_id: String) -> void:
	var options: Array = _data.get("options", [])
	var picked: Dictionary = {}
	for option in options:
		if String(option.get("id", "")) == option_id:
			picked = option
			break
	if picked.is_empty():
		return
	for flag in picked.get("flags", []):
		SaveSystem.set_flag(StringName(String(flag)))
	var hostility: Dictionary = picked.get("hostility", {})
	for faction_id in hostility.keys():
		FactionManager.add_hostility(String(faction_id), float(hostility[faction_id]))
	var spawn := String(picked.get("spawn", ""))
	if spawn != "" and level != null and level.has_method("spawn_faction_event"):
		level.spawn_faction_event(spawn, get_tree().get_first_node_in_group("player"))
	AudioManager.play_sfx(&"ui_confirm")
	EventBus.notify.emit("抉择：" + String(picked.get("label", option_id)))
	get_tree().paused = false
	queue_free()
