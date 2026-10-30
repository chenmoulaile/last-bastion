extends CanvasLayer
# PostProcess - full-screen post-processing overlay for cinematic effects.
#
# Manages: chromatic aberration, radial blur, damage vignette, blood distortion.
# The shader is applied to a full-rect ColorRect that sits above the game world
# but below the HUD, so text and comic pass remain crisp.
#
# Autoload: PostProcess

const SHADER_PATH := "res://shaders/post_process.gdshader"
const LAYER := 31  # below the comic pass (30) -- actually comic pass is at layer 30, so we need to be below HUD(40) but at or below comic(30)
# Correction: comic pass is at LAYER 30, so we sit at 28 so comic ink renders on top of our blur, then HUD at 40.

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _time: float = 0.0

# Tween tracking for smooth fades
var _ca_tween: Tween = null
var _blur_tween: Tween = null
var _vignette_tween: Tween = null

# Current values (smoothed)
var _target_ca: float = 0.0
var _current_ca: float = 0.0
var _target_blur: float = 0.0
var _current_blur: float = 0.0
var _target_vignette: float = 0.0
var _current_vignette: float = 0.0
var _target_blood: float = 0.0
var _current_blood: float = 0.0

const SMOOTH_SPEED := 12.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_rect = ColorRect.new()
	_rect.name = "PostProcessRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	add_child(_rect)

	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_warning("Post-process shader missing: " + SHADER_PATH)
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("chromatic_aberration", 0.0)
	_material.set_shader_parameter("radial_blur_strength", 0.0)
	_material.set_shader_parameter("damage_vignette", 0.0)
	_material.set_shader_parameter("blood_distortion", 0.0)
	_material.set_shader_parameter("scanline_intensity", 0.03)
	_rect.material = _material


func _process(delta: float) -> void:
	_time += delta
	if _material == null:
		return
	# Smooth all parameter transitions
	_current_ca = lerpf(_current_ca, _target_ca, SMOOTH_SPEED * delta)
	_current_blur = lerpf(_current_blur, _target_blur, SMOOTH_SPEED * delta)
	_current_vignette = lerpf(_current_vignette, _target_vignette, SMOOTH_SPEED * delta)
	_current_blood = lerpf(_current_blood, _target_blood, SMOOTH_SPEED * delta)

	if absf(_current_ca) > 0.0001 or absf(_target_ca) > 0.0001:
		_material.set_shader_parameter("chromatic_aberration", _current_ca)
	if absf(_current_blur) > 0.0001 or absf(_target_blur) > 0.0001:
		_material.set_shader_parameter("radial_blur_strength", _current_blur)
	if absf(_current_vignette) > 0.0001 or absf(_target_vignette) > 0.0001:
		_material.set_shader_parameter("damage_vignette", _current_vignette)
	if absf(_current_blood) > 0.0001 or absf(_target_blood) > 0.0001:
		_material.set_shader_parameter("blood_distortion", _current_blood)
	_material.set_shader_parameter("time", _time)


## ---- Chromatic Aberration ----
func set_chromatic_aberration(amount: float) -> void:
	_target_ca = clampf(amount, 0.0, 0.03)

func fade_chromatic_aberration(to: float, duration: float = 0.3) -> void:
	if _ca_tween != null and _ca_tween.is_valid():
		_ca_tween.kill()
	_ca_tween = create_tween()
	_ca_tween.tween_method(set_chromatic_aberration, _target_ca, clampf(to, 0.0, 0.03), duration)


## ---- Radial Blur ----
func set_radial_blur(amount: float) -> void:
	_target_blur = clampf(amount, 0.0, 1.0)

func fade_radial_blur(duration: float = 0.4) -> void:
	if _blur_tween != null and _blur_tween.is_valid():
		_blur_tween.kill()
	_blur_tween = create_tween()
	_blur_tween.tween_method(set_radial_blur, _target_blur, 0.0, duration)


## ---- Damage Vignette ----
func set_damage_vignette(amount: float) -> void:
	_target_vignette = clampf(amount, 0.0, 1.0)


func pulse_damage_vignette(intensity: float = 0.6, duration: float = 0.35) -> void:
	set_damage_vignette(intensity)
	create_tween().tween_method(set_damage_vignette, intensity, 0.0, duration)


func fade_damage_vignette(duration: float = 0.4) -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(set_damage_vignette, _target_vignette, 0.0, duration)


## ---- Blood Distortion (ear-ringing effect on low health) ----
func set_blood_distortion(amount: float) -> void:
	_target_blood = clampf(amount, 0.0, 1.0)

func pulse_blood_distortion(intensity: float = 0.7, duration: float = 0.5) -> void:
	set_blood_distortion(intensity)
	create_tween().tween_method(set_blood_distortion, intensity, 0.0, duration)


## ---- Scanlines (CRT retention) ----
func set_scanline_intensity(amount: float) -> void:
	if _material != null:
		_material.set_shader_parameter("scanline_intensity", clampf(amount, 0.0, 0.2))


## ---- Full reset ----
func reset() -> void:
	_target_ca = 0.0
	_target_blur = 0.0
	_target_vignette = 0.0
	_target_blood = 0.0
