extends Node
## ConfigManager - input remapping, audio buses and display settings.
## Actions are registered at runtime so remaps survive without editing the
## project file. Every change is persisted through SaveSystem.

const REMAPPABLE := [
	{"action": "move_left", "label": "向左移动"},
	{"action": "move_right", "label": "向右移动"},
	{"action": "jump", "label": "跳跃"},
	{"action": "crouch", "label": "蹲下 / 滑铲"},
	{"action": "fire", "label": "开火"},
	{"action": "melee", "label": "近战推开"},
	{"action": "reload", "label": "换弹"},
	{"action": "switch_weapon", "label": "切换武器"},
	{"action": "throw", "label": "投掷物"},
	{"action": "throw_cycle", "label": "切换投掷物"},
	{"action": "flashlight", "label": "手电开关"},
	{"action": "interact", "label": "互动 / 救助"},
	{"action": "skill", "label": "角色技能"},
	{"action": "medkit", "label": "使用医疗包"},
	{"action": "pills", "label": "使用药丸"},
	{"action": "cmd_follow", "label": "指令：跟随"},
	{"action": "cmd_advance", "label": "指令：推进"},
	{"action": "cmd_hold", "label": "指令：防守"},
	{"action": "cmd_focus", "label": "指令：集火"},
	{"action": "cmd_formation", "label": "指令：阵型"},
]

const DEFAULT_KEYS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"crouch": KEY_S,
	"aim_up": KEY_W,
	"aim_down": KEY_S,
	"fire": KEY_J,
	"melee": KEY_F,
	"reload": KEY_R,
	"switch_weapon": KEY_Q,
	"throw": KEY_G,
	"throw_cycle": KEY_V,
	"flashlight": KEY_L,
	"interact": KEY_E,
	"skill": KEY_SHIFT,
	"medkit": KEY_H,
	"pills": KEY_T,
	"pause": KEY_ESCAPE,
	"cmd_follow": KEY_1,
	"cmd_advance": KEY_2,
	"cmd_hold": KEY_3,
	"cmd_focus": KEY_4,
	"cmd_formation": KEY_TAB,
	"toggle_debug": KEY_F10,
}

var _keymap: Dictionary = {}
var _settings: Dictionary = {}


func _ready() -> void:
	_register_all_actions()
	_settings = SaveSystem.get_settings().duplicate(true)
	_keymap = _settings.get("keymap", {}).duplicate()
	_apply_keymap()
	apply_volumes()
	apply_display()


func _register_all_actions() -> void:
	for action in DEFAULT_KEYS.keys():
		_ensure_action(action)
	_add_key("move_left", DEFAULT_KEYS["move_left"])
	_add_key("move_right", DEFAULT_KEYS["move_right"])
	_add_key("jump", DEFAULT_KEYS["jump"])
	_add_key("crouch", DEFAULT_KEYS["crouch"])
	_add_key("aim_up", DEFAULT_KEYS["aim_up"])
	_add_key("aim_down", DEFAULT_KEYS["aim_down"])
	_add_key("fire", DEFAULT_KEYS["fire"])
	_add_key("melee", DEFAULT_KEYS["melee"])
	_add_key("reload", DEFAULT_KEYS["reload"])
	_add_key("switch_weapon", DEFAULT_KEYS["switch_weapon"])
	_add_key("throw", DEFAULT_KEYS["throw"])
	_add_key("throw_cycle", DEFAULT_KEYS["throw_cycle"])
	_add_key("flashlight", DEFAULT_KEYS["flashlight"])
	_add_key("interact", DEFAULT_KEYS["interact"])
	_add_key("skill", DEFAULT_KEYS["skill"])
	_add_key("medkit", DEFAULT_KEYS["medkit"])
	_add_key("pills", DEFAULT_KEYS["pills"])
	_add_key("pause", DEFAULT_KEYS["pause"])
	_add_key("cmd_follow", DEFAULT_KEYS["cmd_follow"])
	_add_key("cmd_advance", DEFAULT_KEYS["cmd_advance"])
	_add_key("cmd_hold", DEFAULT_KEYS["cmd_hold"])
	_add_key("cmd_focus", DEFAULT_KEYS["cmd_focus"])
	_add_key("cmd_formation", DEFAULT_KEYS["cmd_formation"])
	_add_key("toggle_debug", DEFAULT_KEYS["toggle_debug"])

	# Mouse fire.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mouse)

	# Gamepad mapping.
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("crouch", JOY_BUTTON_B)
	_add_joy_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_button("melee", JOY_BUTTON_RIGHT_STICK)
	_add_joy_button("reload", JOY_BUTTON_Y)
	_add_joy_button("switch_weapon", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("throw", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("throw_cycle", JOY_BUTTON_LEFT_STICK)
	_add_joy_button("flashlight", JOY_BUTTON_BACK)
	_add_joy_button("interact", JOY_BUTTON_X)
	_add_joy_axis("skill", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_joy_button("cmd_follow", JOY_BUTTON_DPAD_UP)
	_add_joy_button("cmd_advance", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("cmd_hold", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("cmd_focus", JOY_BUTTON_DPAD_LEFT)


func action_for_key(key: String) -> String:
	return key


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)


func _add_key(action: String, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _add_joy_button(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _add_joy_axis(action: String, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


func _apply_keymap() -> void:
	for action in _keymap.keys():
		if not InputMap.has_action(action):
			continue
		var keycode := int(_keymap[action])
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		_add_key(action, keycode)


func get_action_key(action: String) -> int:
	if _keymap.has(action):
		return int(_keymap[action])
	return int(DEFAULT_KEYS.get(action, 0))


func set_action_key(action: String, keycode: int) -> bool:
	if keycode == 0:
		return false
	for other in DEFAULT_KEYS.keys():
		if other == action:
			continue
		if get_action_key(other) == keycode and not _allowed_duplicate(action, other):
			return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	_add_key(action, keycode)
	_keymap[action] = keycode
	_settings["keymap"] = _keymap
	SaveSystem.set_settings(_settings)
	return true


func _allowed_duplicate(a: String, b: String) -> bool:
	return (a == "crouch" and b == "aim_down") or (a == "aim_down" and b == "crouch")


func reset_keymap() -> void:
	_keymap.clear()
	for action in DEFAULT_KEYS.keys():
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		_add_key(action, DEFAULT_KEYS[action])
	_settings["keymap"] = {}
	SaveSystem.set_settings(_settings)


func key_display(action: String) -> String:
	var keycode := get_action_key(action)
	if keycode == 0:
		return "—"
	return OS.get_keycode_string(keycode)


func set_volume(bus: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, value)))
		AudioServer.set_bus_mute(index, value <= 0.001)
	var volumes: Dictionary = _settings.get("volumes", {})
	volumes[bus] = value
	_settings["volumes"] = volumes
	SaveSystem.set_settings(_settings)


func get_volume(bus: String) -> float:
	return float(_settings.get("volumes", {}).get(bus, 1.0))


func apply_volumes() -> void:
	var volumes: Dictionary = _settings.get("volumes", {})
	for bus in ["Master", "Music", "SFX", "Ambience", "Voice"]:
		var value := float(volumes.get(bus, 1.0))
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, value)))
			AudioServer.set_bus_mute(index, value <= 0.001)


func set_fullscreen(enabled: bool) -> void:
	_settings["fullscreen"] = enabled
	SaveSystem.set_settings(_settings)
	apply_display()


func is_fullscreen() -> bool:
	return bool(_settings.get("fullscreen", false))


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen() else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func set_screenshake(value: float) -> void:
	_settings["screenshake"] = clampf(value, 0.0, 1.0)
	SaveSystem.set_settings(_settings)


func screenshake_strength() -> float:
	return float(_settings.get("screenshake", 1.0))


func show_tips() -> bool:
	return bool(_settings.get("show_tips", true))


func set_show_tips(value: bool) -> void:
	_settings["show_tips"] = value
	SaveSystem.set_settings(_settings)
