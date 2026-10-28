extends UIScreen
## Audio, display, accessibility and full keyboard remapping.

var _content: Control
var _tab_buttons: Array[Button] = []
var _tab: int = 0
var _listening_action: String = ""
var _listening_button: Button = null
var _fullscreen_button: Button
var _tips_button: Button
var _shake_label: Label
var _gamefeel_buttons: Dictionary = {}


func _build() -> void:
	add_background("title_bg", 0.62)
	add_header("OPTIONS", "设置", UIKit.BLUE)
	add_back_button(&"menu", "主菜单")
	add_footer("所有设置自动保存 · 按键可重新绑定 · 手柄按键使用默认映射")

	var names := ["音频", "画面", "操作", "手感"]
	for i in 4:
		var btn := UIKit.button(names[i], 96, 26)
		btn.position = Vector2(24, 66 + i * 32)
		btn.pressed.connect(_show_tab.bind(i))
		add_child(btn)
		_tab_buttons.append(btn)

	_content = Control.new()
	_content.position = Vector2(132, 62)
	_content.size = Vector2(484, 238)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var reset := UIKit.button("恢复默认按键", 124, 24)
	reset.position = Vector2(24, 304)
	reset.pressed.connect(_reset_keymap)
	add_child(reset)
	_show_tab(0)


func _show_tab(index: int) -> void:
	_tab = index
	_end_remap()
	if _content != null:
		_content.queue_free()
	_content = Control.new()
	_content.position = Vector2(132, 62)
	_content.size = Vector2(484, 238)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		var active := i == index
		btn.add_theme_color_override("font_color", UIKit.AMBER if active else UIKit.INK)
		btn.add_theme_stylebox_override("normal", UIKit.button_style(
			Color(0.17, 0.13, 0.06, 0.95) if active else UIKit.PANEL_RAISED,
			UIKit.AMBER if active else UIKit.LINE))
	match index:
		0:
			_build_audio()
		1:
			_build_video()
		2:
			_build_controls()
		3:
			_build_gamefeel()
	AudioManager.play_sfx(&"ui_click")


func _panel() -> Panel:
	var panel := UIKit.panel()
	panel.position = Vector2.ZERO
	panel.size = Vector2(484, 238)
	_content.add_child(panel)
	return panel


func _build_audio() -> void:
	var panel := _panel()
	var rows := [
		["Master", "主音量", "MASTER"],
		["Music", "音乐", "MUSIC"],
		["SFX", "音效", "SFX"],
		["Ambience", "环境音", "AMBIENCE"],
		["Voice", "语音", "VOICE"],
	]
	for i in rows.size():
		var bus: String = rows[i][0]
		var label := UIKit.label(rows[i][1], 10, UIKit.INK)
		label.position = Vector2(16, 18 + i * 38)
		label.size = Vector2(90, 12)
		panel.add_child(label)
		var latin := UIKit.label(rows[i][2], 6, UIKit.DIM, UIKit.font_latin())
		latin.position = Vector2(16, 30 + i * 38)
		latin.size = Vector2(90, 7)
		panel.add_child(latin)

		var slider := HSlider.new()
		slider.position = Vector2(112, 18 + i * 38)
		slider.size = Vector2(300, 14)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = ConfigManager.get_volume(bus)
		panel.add_child(slider)
		var value := UIKit.label("%d%%" % int(slider.value * 100.0), 9, UIKit.AMBER, UIKit.font_latin())
		value.position = Vector2(424, 17 + i * 38)
		value.size = Vector2(46, 11)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(value)
		slider.value_changed.connect(func(v: float) -> void:
			ConfigManager.set_volume(bus, v)
			value.text = "%d%%" % int(v * 100.0)
		)
	var hint := UIKit.label("音量会立即生效。音乐层会随 AI Director 强度自适应混音。", 8, UIKit.MUTED)
	hint.position = Vector2(16, 208)
	hint.size = Vector2(452, 18)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)


func _build_video() -> void:
	var panel := _panel()
	var fs_label := UIKit.label("显示模式", 10, UIKit.INK)
	fs_label.position = Vector2(16, 20)
	fs_label.size = Vector2(120, 12)
	panel.add_child(fs_label)
	_fullscreen_button = UIKit.button("", 110, 24)
	_fullscreen_button.position = Vector2(150, 16)
	_fullscreen_button.pressed.connect(_toggle_fullscreen)
	panel.add_child(_fullscreen_button)
	_refresh_video_buttons()

	var mode := UIKit.label("窗口 1280 × 720 · 画布 640 × 360 · 整数缩放", 8, UIKit.MUTED)
	mode.position = Vector2(16, 48)
	mode.size = Vector2(430, 10)
	panel.add_child(mode)

	var shake := UIKit.label("屏幕震动", 10, UIKit.INK)
	shake.position = Vector2(16, 82)
	shake.size = Vector2(120, 12)
	panel.add_child(shake)
	var slider := HSlider.new()
	slider.position = Vector2(150, 82)
	slider.size = Vector2(240, 14)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = ConfigManager.screenshake_strength()
	panel.add_child(slider)
	_shake_label = UIKit.label("%d%%" % int(slider.value * 100.0), 9, UIKit.AMBER, UIKit.font_latin())
	_shake_label.position = Vector2(400, 81)
	_shake_label.size = Vector2(60, 11)
	_shake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_shake_label)
	slider.value_changed.connect(func(v: float) -> void:
		ConfigManager.set_screenshake(v)
		_shake_label.text = "%d%%" % int(v * 100.0)
	)

	var tips_label := UIKit.label("教学提示", 10, UIKit.INK)
	tips_label.position = Vector2(16, 120)
	tips_label.size = Vector2(120, 12)
	panel.add_child(tips_label)
	_tips_button = UIKit.button("", 110, 24)
	_tips_button.position = Vector2(150, 116)
	_tips_button.pressed.connect(_toggle_tips)
	panel.add_child(_tips_button)
	_refresh_video_buttons()

	var perf := UIKit.label("兼容性渲染器 · 关闭 MSAA · 像素对齐 · 物理插值", 8, UIKit.MUTED)
	perf.position = Vector2(16, 158)
	perf.size = Vector2(440, 10)
	panel.add_child(perf)

	var note := UIKit.label("震动可在选项中完全关闭。低生命、胆汁与受击反馈仍会保留。", 8, UIKit.DIM)
	note.position = Vector2(16, 190)
	note.size = Vector2(448, 22)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(note)


func _refresh_video_buttons() -> void:
	if _fullscreen_button != null:
		_fullscreen_button.text = "全屏：开" if ConfigManager.is_fullscreen() else "全屏：关"
	if _tips_button != null:
		_tips_button.text = "提示：开" if ConfigManager.show_tips() else "提示：关"


func _toggle_fullscreen() -> void:
	ConfigManager.set_fullscreen(not ConfigManager.is_fullscreen())
	_refresh_video_buttons()


func _toggle_tips() -> void:
	ConfigManager.set_show_tips(not ConfigManager.show_tips())
	_refresh_video_buttons()


func _build_controls() -> void:
	var panel := _panel()
	var actions: Array = ConfigManager.REMAPPABLE
	for i in actions.size():
		var row: Dictionary = actions[i]
		var col := 0 if i < 10 else 1
		var row_index := i if i < 10 else i - 10
		var x := 12.0 + col * 234.0
		var y := 10.0 + row_index * 22.0
		var label := UIKit.label(String(row.get("label", row.get("action", ""))), 8, UIKit.INK)
		label.position = Vector2(x, y + 3)
		label.size = Vector2(104, 10)
		panel.add_child(label)
		var btn := UIKit.button(ConfigManager.key_display(String(row.get("action", ""))), 102, 20)
		btn.position = Vector2(x + 108, y)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_begin_remap.bind(String(row.get("action", "")), btn))
		panel.add_child(btn)
		btn.set_meta("action", String(row.get("action", "")))
	var hint := UIKit.label("点击按键后按下新键 · ESC 取消 · 冲突按键会被拒绝", 7, UIKit.DIM)
	hint.position = Vector2(12, 224)
	hint.size = Vector2(452, 9)
	panel.add_child(hint)


func _build_gamefeel() -> void:
	var panel := _panel()
	_gamefeel_buttons.clear()
	_gamefeel_toggle(panel, &"enabled", "手感特效总开关", 12, 10)
	_gamefeel_toggle(panel, &"reduced_motion", "减少动态（晕动症）", 246, 10)
	_gamefeel_toggle(panel, &"damage_numbers", "伤害数字", 12, 40)
	_gamefeel_toggle(panel, &"hit_flash", "命中闪光", 246, 40)
	_gamefeel_slider(panel, "命中停顿", 72, Callable(GameFeelConfig, "set_hitstop_scale"), GameFeelConfig.hitstop_scale)
	_gamefeel_slider(panel, "屏幕震动", 98, Callable(GameFeelConfig, "set_screenshake_scale"), GameFeelConfig.screenshake_scale, 2.0)
	_gamefeel_slider(panel, "闪光强度", 124, Callable(GameFeelConfig, "set_flash_intensity"), GameFeelConfig.flash_intensity)
	_gamefeel_slider(panel, "粒子密度", 150, Callable(GameFeelConfig, "set_particle_density"), GameFeelConfig.particle_density)

	var note := UIKit.label("关闭总开关会完整恢复旧版相机与命中停顿。减少动态会削弱震动与缩放，保留可读性反馈。", 8, UIKit.DIM)
	note.position = Vector2(12, 178)
	note.size = Vector2(452, 22)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(note)

	var reset := UIKit.button("手感默认值", 108, 22)
	reset.position = Vector2(12, 204)
	reset.pressed.connect(_reset_gamefeel)
	panel.add_child(reset)
	_refresh_gamefeel_buttons()


func _gamefeel_toggle(panel: Panel, key: StringName, title: String, x: float, y: float) -> void:
	var label := UIKit.label(title, 9, UIKit.INK)
	label.position = Vector2(x, y + 4)
	label.size = Vector2(150, 12)
	panel.add_child(label)
	var btn := UIKit.button("", 60, 22)
	btn.position = Vector2(x + 156, y)
	btn.pressed.connect(_toggle_gamefeel.bind(key))
	panel.add_child(btn)
	_gamefeel_buttons[key] = btn


func _gamefeel_slider(panel: Panel, title: String, y: float, setter: Callable,
		value_now: float, max_value: float = 1.0) -> void:
	var label := UIKit.label(title, 9, UIKit.INK)
	label.position = Vector2(12, y + 4)
	label.size = Vector2(100, 12)
	panel.add_child(label)
	var slider := HSlider.new()
	slider.position = Vector2(118, y + 2)
	slider.size = Vector2(266, 14)
	slider.min_value = 0.0
	slider.max_value = max_value
	slider.step = 0.05
	slider.value = clampf(value_now, 0.0, max_value)
	panel.add_child(slider)
	var value := UIKit.label("%d%%" % int(slider.value * 100.0), 9, UIKit.AMBER, UIKit.font_latin())
	value.position = Vector2(392, y + 1)
	value.size = Vector2(60, 11)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value.text = "%d%%" % int(v * 100.0)
	)


func _refresh_gamefeel_buttons() -> void:
	for raw_key in _gamefeel_buttons.keys():
		var key := StringName(String(raw_key))
		var btn: Button = _gamefeel_buttons[raw_key]
		if btn == null or not is_instance_valid(btn):
			continue
		var on := false
		match key:
			&"enabled":
				on = GameFeelConfig.enabled
			&"reduced_motion":
				on = GameFeelConfig.reduced_motion
			&"damage_numbers":
				on = GameFeelConfig.damage_number_enabled
			_:
				on = GameFeelConfig.is_module_on(key)
		btn.text = "开" if on else "关"
		btn.add_theme_color_override("font_color", UIKit.AMBER if on else UIKit.DIM)


func _toggle_gamefeel(key: StringName) -> void:
	AudioManager.play_sfx(&"ui_click")
	match key:
		&"enabled":
			GameFeelConfig.set_enabled(not GameFeelConfig.enabled)
		&"reduced_motion":
			GameFeelConfig.set_reduced_motion(not GameFeelConfig.reduced_motion)
		&"damage_numbers":
			GameFeelConfig.set_damage_numbers_enabled(not GameFeelConfig.damage_number_enabled)
		_:
			GameFeelConfig.set_module_enabled(key, not GameFeelConfig.is_module_on(key))
	_refresh_gamefeel_buttons()


func _reset_gamefeel() -> void:
	AudioManager.play_sfx(&"ui_click")
	GameFeelConfig.reset_to_defaults()
	_show_tab(_tab)
	_refresh_gamefeel_buttons()


func _begin_remap(action: String, button: Button) -> void:
	_end_remap()
	_listening_action = action
	_listening_button = button
	button.text = "按下按键…"
	button.add_theme_color_override("font_color", UIKit.AMBER)
	set_process_input(true)


func _end_remap() -> void:
	if _listening_button != null and is_instance_valid(_listening_button):
		_listening_button.text = ConfigManager.key_display(_listening_action)
		_listening_button.add_theme_color_override("font_color", UIKit.INK)
	_listening_action = ""
	_listening_button = null
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		var keycode := key_event.physical_keycode
		if keycode == 0:
			keycode = key_event.keycode
		if keycode == KEY_ESCAPE:
			_end_remap()
			get_viewport().set_input_as_handled()
			return
		var action := _listening_action
		var ok := ConfigManager.set_action_key(action, keycode)
		if ok:
			AudioManager.play_sfx(&"ui_click")
			_end_remap()
		else:
			if _listening_button != null:
				_listening_button.text = "按键冲突"
				_listening_button.add_theme_color_override("font_color", UIKit.RED)
			AudioManager.play_sfx(&"ui_deny")
		get_viewport().set_input_as_handled()


func _reset_keymap() -> void:
	_end_remap()
	ConfigManager.reset_keymap()
	AudioManager.play_sfx(&"ui_click")
	if _tab == 2:
		_show_tab(2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _listening_action != "":
			_end_remap()
			get_viewport().set_input_as_handled()
			return
		go(&"menu")
		get_viewport().set_input_as_handled()
