extends Control
## FinalChoiceUI - the binary ending of chapter 4.
##
## A 摧毁信号核心 : immediate, buries the truth, achievement 沉默的代价
## B 解码信号     : requires >= 1 THE_DEEP fragment, then a 90s / 3-wave defense,
##                  achievement 回应, unlocks 林远专属关卡「山猫的搜索」

var level: Node = null

var _decode_button: Button
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()
	EventBus.final_choice_presented.emit(ArchiveManager.can_decode_signal())


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.01, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var kicker := UIKit.label("SIGNAL CORE · 1.7 GHz", 8, UIKit.RED, UIKit.font_latin())
	kicker.position = Vector2(0, 44)
	kicker.size = Vector2(640, 10)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(kicker)

	var title := UIKit.title("最终抉择", 30, UIKit.INK)
	title.position = Vector2(0, 56)
	title.size = Vector2(640, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := UIKit.label("核心还在运转。你有十秒钟决定它该不该继续。", 9, UIKit.MUTED)
	sub.position = Vector2(0, 94)
	sub.size = Vector2(640, 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	_build_option(Vector2(42, 120), "A", "摧毁信号核心", "炸掉核心，终止 1.7GHz 发射。\n真相与里面的一切一起被埋掉。",
		UIKit.RED, "destroy")
	_decode_button = _build_option(Vector2(330, 120), "B", "解码信号", "维持核心运转，解析坐标与名单。\n需要 90 秒防守，且必须持有「深渊」级档案。",
		UIKit.TEAL, "decode")

	_hint = UIKit.label("", 8, UIKit.AMBER)
	_hint.position = Vector2(0, 296)
	_hint.size = Vector2(640, 12)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	var can_decode := ArchiveManager.can_decode_signal()
	_decode_button.disabled = not can_decode
	if not can_decode:
		_hint.text = "缺少「深渊」级档案（信号核心录音）——只能摧毁。"
	else:
		_hint.text = "已持有深渊级档案：解码选项可用。"


func _build_option(pos: Vector2, letter: String, heading: String, body: String,
		accent: Color, choice: String) -> Button:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(268, 158)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.045, 0.045, 0.98), accent))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var badge := UIKit.label(letter, 26, accent, UIKit.font_latin_bold())
	badge.position = Vector2(12, 6)
	badge.size = Vector2(30, 30)
	panel.add_child(badge)

	var name_label := UIKit.label(heading, 14, UIKit.INK)
	name_label.position = Vector2(48, 12)
	name_label.size = Vector2(206, 18)
	panel.add_child(name_label)

	var body_label := UIKit.label(body, 8, UIKit.MUTED)
	body_label.position = Vector2(14, 48)
	body_label.size = Vector2(240, 54)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(body_label)

	var button := UIKit.button("选择 " + heading, 236, 26, choice == "destroy")
	button.position = Vector2(16, 118)
	button.pressed.connect(_choose.bind(choice))
	panel.add_child(button)
	return button


func _exit_tree() -> void:
	# Never leave the tree paused if the level tears down while this is open.
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false


func _choose(choice: String) -> void:
	if choice == "decode" and not ArchiveManager.can_decode_signal():
		AudioManager.play_sfx(&"ui_deny")
		return
	AudioManager.play_sfx(&"ui_confirm")
	ArchiveManager.record_final_choice(choice)
	get_tree().paused = false
	if choice == "destroy":
		if level != null and level.has_method("play_destroy_ending"):
			level.play_destroy_ending()
	else:
		if level != null and level.has_method("start_decode_defense"):
			level.start_decode_defense(90.0, 3)
	queue_free()
