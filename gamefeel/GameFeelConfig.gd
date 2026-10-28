extends Node
## GameFeelConfig - the single source of truth for the presentation-only
## "game feel" layer.
##
## Everything here is local presentation. No combat value (damage, health, RPM)
## is ever written by this module. Every subsystem reads its scale from here and
## can be switched off independently for performance or accessibility.
##
## Autoload: GameFeelConfig (must load after SaveSystem / ConfigManager).

signal config_changed(key: StringName, value: Variant)

const SAVE_KEY := "gamefeel"
const SAVE_DELAY := 0.6

const MODULE_DEFAULTS := {
	&"hitstop": true,
	&"screenshake": true,
	&"camera_punch": true,
	&"hit_flash": true,
	&"knockback": true,
	&"muzzle_flash": true,
	&"impact_particles": true,
	&"shell_eject": true,
	&"death_ragdoll": true,
	&"damage_numbers": true,
	&"recoil": true,
	&"audio_layers": true,
	&"hit_direction": true,
	&"low_health": true,
	&"kill_streak": true,
}

## Master switch. false restores the legacy camera/hitstop behaviour.
@export var enabled: bool = true
## Accessibility: kills shake amplitude and zoom pulses, keeps flashes/audio.
@export var reduced_motion: bool = false

@export_range(0.0, 1.0, 0.01) var hitstop_scale: float = 1.0:
	set(value):
		hitstop_scale = clampf(value, 0.0, 1.0)
		_changed(&"hitstop_scale", hitstop_scale)

@export_range(0.0, 2.0, 0.01) var screenshake_scale: float = 1.0:
	set(value):
		screenshake_scale = clampf(value, 0.0, 2.0)
		_changed(&"screenshake_scale", screenshake_scale)

@export_range(0.0, 1.0, 0.01) var camera_punch_scale: float = 1.0:
	set(value):
		camera_punch_scale = clampf(value, 0.0, 1.0)
		_changed(&"camera_punch_scale", camera_punch_scale)

@export_range(0.0, 1.0, 0.01) var flash_intensity: float = 1.0:
	set(value):
		flash_intensity = clampf(value, 0.0, 1.0)
		_changed(&"flash_intensity", flash_intensity)

@export_range(0.0, 1.0, 0.01) var particle_density: float = 1.0:
	set(value):
		particle_density = clampf(value, 0.0, 1.0)
		_changed(&"particle_density", particle_density)

@export var damage_number_enabled: bool = true:
	set(value):
		damage_number_enabled = value
		_changed(&"damage_number_enabled", damage_number_enabled)

@export_range(0.0, 1.0, 0.01) var audio_scale: float = 1.0:
	set(value):
		audio_scale = clampf(value, 0.0, 1.0)
		_changed(&"audio_scale", audio_scale)

var modules: Dictionary = {}

var _loading: bool = false
var _dirty: bool = false
var _save_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_project_settings()
	_reset_modules()
	enabled = bool(ProjectSettings.get_setting("gamefeel/enabled", true))
	reduced_motion = bool(ProjectSettings.get_setting("gamefeel/reduced_motion", false))
	_load_saved()
	_dirty = false


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_accum += delta
	if _save_accum >= SAVE_DELAY:
		_save_now()


func _exit_tree() -> void:
	if _dirty:
		_save_now()


# ------------------------------------------------------------------ queries --
func is_module_enabled(module: StringName) -> bool:
	if not enabled:
		return false
	return bool(modules.get(module, true))


func effective_particle_density() -> float:
	if not enabled:
		return 0.0
	return clampf(particle_density, 0.0, 1.0)


## Multiplier applied to every "screen motion" effect. Reduced motion drops it
## to 30% but never to zero: a faint directional nudge preserves readability.
func motion_scale() -> float:
	if not enabled:
		return 0.0
	return 0.3 if reduced_motion else 1.0


func shake_multiplier() -> float:
	if not enabled:
		return 0.0
	return screenshake_scale * motion_scale()


func flash_multiplier() -> float:
	if not enabled:
		return 0.0
	return flash_intensity


# ------------------------------------------------------------------ setters --
func set_enabled(value: bool) -> void:
	enabled = value
	ProjectSettings.set_setting("gamefeel/enabled", enabled)
	_changed(&"enabled", enabled)
	_persist_soon()


func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	ProjectSettings.set_setting("gamefeel/reduced_motion", reduced_motion)
	_changed(&"reduced_motion", reduced_motion)
	_persist_soon()


func set_damage_numbers_enabled(value: bool) -> void:
	damage_number_enabled = value
	_changed(&"damage_number_enabled", damage_number_enabled)
	_persist_soon()


func set_module_enabled(module: StringName, value: bool) -> void:
	modules[module] = value
	_changed(StringName("module:" + String(module)), value)
	_persist_soon()


func is_module_on(module: StringName) -> bool:
	return bool(modules.get(module, true))


func set_particle_density(value: float) -> void:
	particle_density = value
	_persist_soon()


func set_hitstop_scale(value: float) -> void:
	hitstop_scale = value
	_persist_soon()


func set_screenshake_scale(value: float) -> void:
	screenshake_scale = value
	_persist_soon()


func set_camera_punch_scale(value: float) -> void:
	camera_punch_scale = value
	_persist_soon()


func set_flash_intensity(value: float) -> void:
	flash_intensity = value
	_persist_soon()


func set_audio_scale(value: float) -> void:
	audio_scale = value
	_persist_soon()


# ------------------------------------------------------------------- data ----
func settings_snapshot() -> Dictionary:
	var saved_modules: Dictionary = {}
	for key in modules.keys():
		saved_modules[String(key)] = bool(modules[key])
	return {
		"enabled": enabled,
		"reduced_motion": reduced_motion,
		"hitstop_scale": hitstop_scale,
		"screenshake_scale": screenshake_scale,
		"camera_punch_scale": camera_punch_scale,
		"flash_intensity": flash_intensity,
		"particle_density": particle_density,
		"damage_number_enabled": damage_number_enabled,
		"audio_scale": audio_scale,
		"modules": saved_modules,
	}


func apply_snapshot(data: Dictionary) -> void:
	_loading = true
	enabled = bool(data.get("enabled", enabled))
	reduced_motion = bool(data.get("reduced_motion", reduced_motion))
	hitstop_scale = float(data.get("hitstop_scale", hitstop_scale))
	screenshake_scale = float(data.get("screenshake_scale", screenshake_scale))
	camera_punch_scale = float(data.get("camera_punch_scale", camera_punch_scale))
	flash_intensity = float(data.get("flash_intensity", flash_intensity))
	particle_density = float(data.get("particle_density", particle_density))
	damage_number_enabled = bool(data.get("damage_number_enabled", damage_number_enabled))
	audio_scale = float(data.get("audio_scale", audio_scale))
	var saved_modules: Variant = data.get("modules", {})
	if saved_modules is Dictionary:
		for raw_key in (saved_modules as Dictionary).keys():
			var key := StringName(String(raw_key))
			if MODULE_DEFAULTS.has(key):
				modules[key] = bool((saved_modules as Dictionary)[raw_key])
	_loading = false
	_changed(&"reset", null)
	_persist_soon()


func reset_to_defaults() -> void:
	_reset_modules()
	apply_snapshot({
		"enabled": true,
		"reduced_motion": false,
		"hitstop_scale": 1.0,
		"screenshake_scale": 1.0,
		"camera_punch_scale": 1.0,
		"flash_intensity": 1.0,
		"particle_density": 1.0,
		"damage_number_enabled": true,
		"audio_scale": 1.0,
		"modules": {},
	})


# --------------------------------------------------------------- internals ---
func _ensure_project_settings() -> void:
	if not ProjectSettings.has_setting("gamefeel/enabled"):
		ProjectSettings.set_setting("gamefeel/enabled", true)
	if not ProjectSettings.has_setting("gamefeel/reduced_motion"):
		ProjectSettings.set_setting("gamefeel/reduced_motion", false)


func _reset_modules() -> void:
	modules.clear()
	for key in MODULE_DEFAULTS.keys():
		modules[key] = bool(MODULE_DEFAULTS[key])


func _load_saved() -> void:
	var store: Dictionary = SaveSystem.get_settings()
	var raw: Variant = store.get(SAVE_KEY, null)
	if raw is Dictionary:
		apply_snapshot(raw as Dictionary)
		_dirty = false


func _changed(key: StringName, value: Variant) -> void:
	if _loading:
		return
	config_changed.emit(key, value)
	_dirty = true
	_save_accum = 0.0


func _persist_soon() -> void:
	if _loading:
		return
	_dirty = true
	_save_accum = 0.0


func _save_now() -> void:
	_dirty = false
	_save_accum = 0.0
	var store: Dictionary = SaveSystem.get_settings()
	store[SAVE_KEY] = settings_snapshot()
	SaveSystem.set_settings(store)
	SaveSystem.save()
