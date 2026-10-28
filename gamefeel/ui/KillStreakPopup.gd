class_name GameFeelKillStreak
extends CanvasLayer
## Personal kill-streak feedback: 3 / 5 / 10 milestones, 3 s reset, and a
## short chromatic-aberration pulse on 10. All nodes are created once.

const RESET_SECONDS := 3.0
const MILESTONES: Array[int] = [3, 5, 10]

const TEXT := {
	3: "三重击杀",
	5: "五连杀",
	10: "十连杀 · 收割者",
}

const COLORS := {
	3: Color(1.0, 0.92, 0.72, 1.0),
	5: Color(1.0, 0.80, 0.26, 1.0),
	10: Color(1.0, 0.42, 0.20, 1.0),
}

var _root: Control = null
var _label: Label = null
var _aberration: ColorRect = null
var _aberration_material: ShaderMaterial = null
var _label_tween: Tween = null
var _aberration_tween: Tween = null
var _streak: int = 0
var _last_kill_usec: int = 0
var _popup_count: int = 0


func _ready() -> void:
	layer = 69
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "KillStreakRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_label = Label.new()
	_label.name = "StreakLabel"
	_label.position = Vector2(140, 44)
	_label.size = Vector2(360, 30)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.pivot_offset = Vector2(180, 15)
	_label.visible = false
	var font: Font = load("res://assets/fonts/zcool.ttf")
	if font != null:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", COLORS[3])
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.01, 0.95))
	_label.add_theme_constant_override("outline_size", 5)
	_root.add_child(_label)
	_build_aberration()


func _process(_delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"kill_streak"):
		if _label.visible:
			_label.visible = false
		if _aberration.visible:
			_aberration.visible = false
		_streak = 0
		return
	if _streak > 0 and Time.get_ticks_usec() - _last_kill_usec > int(RESET_SECONDS * 1_000_000.0):
		_streak = 0


## Returns true when a milestone fired.
func note_kill(source: StringName) -> bool:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"kill_streak"):
		return false
	if source != &"player" and source != &"barrel":
		return false
	var now := Time.get_ticks_usec()
	if _streak > 0 and now - _last_kill_usec > int(RESET_SECONDS * 1_000_000.0):
		_streak = 0
	_streak += 1
	_last_kill_usec = now
	if _streak in MILESTONES:
		show_milestone(_streak)
		return true
	return false


func show_milestone(tier: int) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"kill_streak"):
		return
	if not MILESTONES.has(tier):
		tier = 3
	_popup_count += 1
	_label.text = String(TEXT.get(tier, "连杀"))
	_label.add_theme_color_override("font_color", COLORS.get(tier, COLORS[3]))
	_label.add_theme_font_size_override("font_size", 24 if tier >= 10 else (20 if tier == 5 else 18))
	_label.modulate = Color(1, 1, 1, 1)
	_label.scale = Vector2(1.28, 1.28)
	_label.visible = true
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	_label_tween = create_tween()
	_label_tween.set_ignore_time_scale(true)
	_label_tween.set_trans(Tween.TRANS_BACK)
	_label_tween.set_ease(Tween.EASE_OUT)
	_label_tween.tween_property(_label, "scale", Vector2.ONE, 0.14)
	_label_tween.tween_interval(0.55)
	_label_tween.set_trans(Tween.TRANS_QUAD)
	_label_tween.tween_property(_label, "modulate:a", 0.0, 0.28)
	_label_tween.tween_callback(func() -> void: _label.visible = false)
	AudioLayerManager.play_streak(tier)
	if tier >= 10:
		_pulse_aberration()


func reset() -> void:
	_streak = 0
	_last_kill_usec = 0
	_popup_count = 0
	if _label != null:
		_label.visible = false
	if _aberration != null:
		_aberration.visible = false


func current_streak() -> int:
	return _streak


func popup_count() -> int:
	return _popup_count


func _pulse_aberration() -> void:
	if _aberration == null:
		return
	_aberration.visible = true
	if _aberration_tween != null and _aberration_tween.is_valid():
		_aberration_tween.kill()
	_aberration_material.set_shader_parameter("strength", 0.0 if GameFeelConfig.reduced_motion else 0.0045)
	_aberration_tween = create_tween()
	_aberration_tween.set_ignore_time_scale(true)
	_aberration_tween.tween_method(_set_aberration, 0.0045 if not GameFeelConfig.reduced_motion else 0.0, 0.0, 0.30)
	_aberration_tween.tween_callback(_hide_aberration)


func _set_aberration(value: float) -> void:
	if _aberration_material != null:
		_aberration_material.set_shader_parameter("strength", value)


func _hide_aberration() -> void:
	if _aberration != null:
		_aberration.visible = false


func _build_aberration() -> void:
	_aberration = ColorRect.new()
	_aberration.name = "ChromaticPulse"
	_aberration.color = Color(1, 1, 1, 1)
	_aberration.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aberration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aberration.visible = false
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.02) = 0.0;
void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5);
	float r = texture(screen_texture, SCREEN_UV + dir * strength).r;
	float g = texture(screen_texture, SCREEN_UV).g;
	float b = texture(screen_texture, SCREEN_UV - dir * strength).b;
	COLOR = vec4(r, g, b, 1.0);
}
"""
	_aberration_material = ShaderMaterial.new()
	_aberration_material.shader = shader
	_aberration_material.set_shader_parameter("strength", 0.0)
	_aberration.material = _aberration_material
	_root.add_child(_aberration)
