extends CanvasLayer
## ComicPostProcess - full-screen ink/posterize pass layered on top of the
## existing 640x360 pixel rendering. It never replaces sprites; it only grades
## the frame, so the original art direction survives.
##
## GoreEvent temporarily thickens outlines and pushes reds for 0.5s.

const SHADER_PATH := "res://shaders/comic_post_process.gdshader"
const LAYER := 30 # below the HUD (40) so text stays crisp
const GORE_DECAY := 0.5

var rect: ColorRect
var material: ShaderMaterial
var enabled: bool = true

var _gore: float = 0.0
var _gore_tween: Tween
var _noise: NoiseTexture2D


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	EventBus.gore_event.connect(_on_gore_event)
	EventBus.damage_flash.connect(_on_damage_flash)
	EventBus.signal_noise_changed.connect(_on_signal_noise)


func _build() -> void:
	rect = ColorRect.new()
	rect.name = "ComicPass"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	add_child(rect)

	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_warning("Comic shader missing: " + SHADER_PATH)
		enabled = false
		return
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("paper_noise", _make_paper_noise())
	material.set_shader_parameter("outline_strength", 0.5)
	material.set_shader_parameter("outline_threshold", 0.55)
	material.set_shader_parameter("posterize_levels", 8.0)
	material.set_shader_parameter("posterize_mix", 0.35)
	material.set_shader_parameter("paper_strength", 0.08)
	material.set_shader_parameter("gore_boost", 0.0)
	rect.material = material


func _make_paper_noise() -> NoiseTexture2D:
	var fast := FastNoiseLite.new()
	fast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fast.frequency = 0.09
	fast.seed = 20190911
	_noise = NoiseTexture2D.new()
	_noise.width = 128
	_noise.height = 128
	_noise.seamless = true
	_noise.noise = fast
	_noise.generate_mipmaps = false
	return _noise


func _on_gore_event(intensity: float) -> void:
	if not enabled or material == null:
		return
	_gore = clampf(maxf(_gore, intensity), 0.0, 2.0)
	material.set_shader_parameter("gore_boost", _gore)
	if _gore_tween != null and _gore_tween.is_valid():
		_gore_tween.kill()
	_gore_tween = create_tween()
	_gore_tween.tween_method(_set_gore, _gore, 0.0, GORE_DECAY)


func _set_gore(value: float) -> void:
	_gore = value
	if material != null:
		material.set_shader_parameter("gore_boost", value)


func _on_damage_flash() -> void:
	if not enabled or material == null:
		return
	_gore = clampf(maxf(_gore, 1.2), 0.0, 2.0)
	material.set_shader_parameter("gore_boost", _gore)
	if _gore_tween != null and _gore_tween.is_valid():
		_gore_tween.kill()
	_gore_tween = create_tween()
	_gore_tween.tween_method(_set_gore, _gore, 0.0, 0.35)


## The signal noise raises contrast slightly as the archive deepens: a visual
## echo of the audio layer.
func _on_signal_noise(level: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("paper_strength", 0.08 + level * 0.07)
	material.set_shader_parameter("saturation", 1.05 - level * 0.10)


func set_outline(value: float) -> void:
	if material != null:
		material.set_shader_parameter("outline_strength", clampf(value, 0.0, 3.0))


func set_posterize(levels: float) -> void:
	if material != null:
		material.set_shader_parameter("posterize_levels", clampf(levels, 2.0, 16.0))


func set_paper(value: float) -> void:
	if material != null:
		material.set_shader_parameter("paper_strength", clampf(value, 0.0, 1.0))
