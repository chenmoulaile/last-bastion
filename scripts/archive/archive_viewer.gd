extends Control
## ArchiveViewer - full-screen reader shown the moment a fragment is unlocked.
## Pauses the game, renders text/audio/image content and closes on 收录.

var payload: Dictionary = {}

var _fragment: ArchiveFragment = null
var _audio: AudioStreamPlayer = null
var _image: TextureRect = null


func setup(data: Dictionary) -> void:
	payload = data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	_fragment = ArchiveManager.get_fragment(String(payload.get("fragment_id", "")))
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UIKit.add_scanlines(self, 0.07)

	var accent := UIKit.AMBER
	if _fragment != null:
		accent = _fragment.security_color()

	var panel := UIKit.panel(Color(0.045, 0.052, 0.062, 0.99), accent)
	panel.position = Vector2(48, 26)
	panel.size = Vector2(544, 308)
	add_child(panel)

	var kicker := UIKit.label("ARCHIVE FRAGMENT · 档案碎片", 7, accent, UIKit.font_latin())
	kicker.position = Vector2(14, 8)
	kicker.size = Vector2(400, 9)
	panel.add_child(kicker)

	if _fragment == null:
		var missing := UIKit.label("档案数据损坏。", 12, UIKit.MUTED)
		missing.position = Vector2(14, 30)
		panel.add_child(missing)
		_add_close_button(panel, accent)
		return

	var title := UIKit.title(_fragment.title, 20, UIKit.INK)
	title.position = Vector2(12, 18)
	title.size = Vector2(430, 24)
	panel.add_child(title)

	var badge := UIKit.label("%s · %s" % [_fragment.security_name(), _fragment.security_label_zh()],
		8, accent, UIKit.font_latin())
	badge.position = Vector2(14, 44)
	badge.size = Vector2(240, 10)
	panel.add_child(badge)

	var meta := UIKit.label("%s  |  %s" % [_fragment.source, _fragment.timestamp], 7, UIKit.DIM, UIKit.font_latin())
	meta.position = Vector2(250, 44)
	meta.size = Vector2(280, 10)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(meta)

	var rule := UIKit.hsep(panel, UIKit.LINE)
	rule.position = Vector2(14, 58)
	rule.size = Vector2(516, 1)

	var text := UIKit.label(_fragment.content_text, 10, UIKit.INK, UIKit.font_cjk())
	text.position = Vector2(14, 66)
	text.size = Vector2(400, 190)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(text)

	if _fragment.translation != "":
		var translation := UIKit.label(_fragment.translation, 8, UIKit.MUTED, UIKit.font_cjk())
		translation.position = Vector2(14, 214)
		translation.size = Vector2(400, 54)
		translation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(translation)

	_build_media(panel, accent)
	_add_close_button(panel, accent)


func _build_media(panel: Panel, accent: Color) -> void:
	if _fragment == null:
		return
	if _fragment.content_image != null:
		_image = TextureRect.new()
		_image.texture = _fragment.content_image
		_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_image.position = Vector2(424, 66)
		_image.size = Vector2(106, 106)
		panel.add_child(_image)
	else:
		# Placeholder "photo" frame keeps the layout stable without new art.
		var frame := ColorRect.new()
		frame.color = Color(accent.r, accent.g, accent.b, 0.10)
		frame.position = Vector2(424, 66)
		frame.size = Vector2(106, 106)
		panel.add_child(frame)
		var mark := UIKit.label("█ █ █\n█ █ █\n▌▌▌", 10, accent, UIKit.font_latin())
		mark.position = Vector2(446, 96)
		panel.add_child(mark)

	if _fragment.content_audio != null:
		_audio = AudioStreamPlayer.new()
		_audio.stream = _fragment.content_audio
		_audio.bus = "Voice"
		_audio.volume_db = -4.0
		add_child(_audio)
		_audio.play()
		var playing := UIKit.label("▶ 播放录音", 8, accent, UIKit.font_latin())
		playing.position = Vector2(424, 180)
		playing.size = Vector2(110, 10)
		panel.add_child(playing)


func _add_close_button(panel: Panel, accent: Color) -> void:
	var button := UIKit.button("收录", 110, 24, true)
	button.position = Vector2(420, 274)
	button.pressed.connect(_close)
	panel.add_child(button)
	var hint := UIKit.label("ESC / 收录 返回", 7, UIKit.DIM, UIKit.font_latin())
	hint.position = Vector2(14, 288)
	hint.size = Vector2(300, 10)
	panel.add_child(hint)
	if accent == UIKit.AMBER:
		button.grab_focus()


func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false


func _close() -> void:
	if _audio != null and _audio.playing:
		_audio.stop()
	get_tree().paused = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		accept_event()
		_close()
