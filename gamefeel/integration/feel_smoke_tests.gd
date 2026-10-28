extends Node
## Game-feel smoke test. Run:
##   Godot --headless --path . res://gamefeel/integration/feel_smoke_tests.tscn
##
## Exercises every pool, config switch, accessibility path, hitstop/input
## cooperation and the settings-menu integration. The test never starts a
## level, so it is fast and cannot touch combat state.

const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	_test_autoloads()
	_test_config()
	_test_hitstop()
	_test_screenshake()
	_test_camera_punch()
	_test_pools()
	_test_ui_modules()
	_test_audio()
	_test_input_buffer()
	_test_recoil()
	_test_reduced_motion()
	_test_bridge_and_settings()

	GameFeelConfig.reset_to_defaults()
	GameFeelConfig.set_enabled(true)
	GameFeelConfig.set_reduced_motion(false)
	HitStop.cancel_all()
	ScreenShake.reset()
	CameraPunch.reset()
	InputBuffer.reset()
	RecoilController.reset()

	print("[GAMEFEEL] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[GAMEFEEL] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[GAMEFEEL] FAIL: " + failure)
		print("[GAMEFEEL] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _test_autoloads() -> void:
	var names: Array[String] = [
		"GameFeelConfig", "InputBuffer", "CameraPunch", "ScreenShake",
		"HitStop", "AudioLayerManager", "RecoilController", "GameFeelBridge",
	]
	for name in names:
		_check(get_node_or_null("/root/" + name) != null, "autoload " + name)
	_check(GameFeelConfig.MODULE_DEFAULTS.size() >= 14, "module defaults registered")
	_check(GameFeelConfig.modules.has(&"recoil"), "recoil module registered")
	_check(GameFeelBridge.router != null, "feedback router created")
	_check(GameFeelBridge.damage_numbers != null, "bridge owns damage numbers")


func _test_config() -> void:
	_check(ProjectSettings.has_setting("gamefeel/enabled"), "project setting enabled")
	_check(ProjectSettings.has_setting("gamefeel/reduced_motion"), "project setting reduced_motion")
	GameFeelConfig.set_enabled(false)
	_check(not GameFeelConfig.is_module_enabled(&"hitstop"), "master switch disables modules")
	_check(HitStop.request(&"normal") == false, "hitstop refuses while disabled")
	GameFeelConfig.set_enabled(true)
	GameFeelConfig.set_module_enabled(&"hitstop", false)
	_check(HitStop.request(&"normal") == false, "per-module switch disables hitstop")
	GameFeelConfig.set_module_enabled(&"hitstop", true)
	_check(GameFeelConfig.is_module_on(&"hitstop"), "per-module switch restores hitstop")


func _test_hitstop() -> void:
	GameFeelConfig.set_hitstop_scale(1.0)
	_check(HitStop.request(&"normal") == true, "normal hitstop requested")
	_check(HitStop.remaining() > 0.0, "hitstop has remaining time")
	await get_tree().create_timer(0.12, true, false, true).timeout
	_check(Engine.time_scale == 1.0, "hitstop restores time scale")
	_check(not HitStop.is_active(), "hitstop finished")
	var dummy := Node2D.new()
	add_child(dummy)
	_check(HitStop.request(&"crit", dummy) == true, "crit hitstop requested")
	HitStop.cancel_all()
	_check(dummy.is_physics_processing(), "crit freeze releases target")
	dummy.queue_free()


func _test_screenshake() -> void:
	ScreenShake.reset()
	ScreenShake.add_shot(true, Vector2.RIGHT)
	_check(ScreenShake.trauma > 0.0, "screenshake trauma rises")
	_check(ScreenShake.max_offset > ScreenShake.DEFAULT_PEAK, "heavy shot raises peak")
	ScreenShake.reset()
	_check(ScreenShake.trauma == 0.0, "screenshake reset")


func _test_camera_punch() -> void:
	CameraPunch.reset()
	CameraPunch.punch(Vector2.RIGHT, &"shotgun")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(CameraPunch.punch_offset.length() > 0.0, "camera punch offsets")
	CameraPunch.reset()
	_check(CameraPunch.punch_offset == Vector2.ZERO, "camera punch reset")


func _test_pools() -> void:
	GameFeelBridge.muzzle_flash.clear()
	_check(GameFeelBridge.muzzle_flash.pool_size() == 12, "muzzle flash pool size")
	GameFeelBridge.muzzle_flash.flash(Vector2.ZERO, Vector2.RIGHT, &"shotgun", true)
	_check(GameFeelBridge.muzzle_flash.active_count() == 1, "muzzle flash spawns")
	GameFeelBridge.muzzle_flash.clear()
	_check(GameFeelBridge.muzzle_flash.active_count() == 0, "muzzle flash clears")

	GameFeelBridge.impact_particles.clear()
	_check(GameFeelBridge.impact_particles.pool_size() == 20, "impact particle pool size")
	GameFeelBridge.impact_particles.burst(&"blood", Vector2.ZERO, Vector2.UP)
	_check(GameFeelBridge.impact_particles.active_count() >= 1, "impact particles burst")
	GameFeelBridge.impact_particles.clear()
	_check(GameFeelBridge.impact_particles.active_count() == 0, "impact particles clear")

	GameFeelBridge.shell_eject.clear()
	_check(GameFeelBridge.shell_eject.pool_size() == 30, "shell pool size")
	GameFeelBridge.shell_eject.eject(Vector2.ZERO, Vector2.RIGHT, 2)
	_check(GameFeelBridge.shell_eject.active_count() == 2, "shells eject")
	GameFeelBridge.shell_eject.clear()
	_check(GameFeelBridge.shell_eject.active_count() == 0, "shells clear")

	GameFeelBridge.death_ragdoll.clear()
	_check(GameFeelBridge.death_ragdoll.pool_size() == 12, "ragdoll pool size")
	var limbs := GameFeelBridge.death_ragdoll.spawn(Vector2.ZERO, Vector2.RIGHT, Color.RED)
	_check(limbs >= 1, "normal enemy ragdoll")
	_check(GameFeelBridge.death_ragdoll.spawn(Vector2.ZERO, Vector2.RIGHT, Color.RED, true) == 0,
		"boss ragdoll suppressed")
	GameFeelBridge.death_ragdoll.clear()
	_check(GameFeelBridge.death_ragdoll.active_count() == 0, "ragdoll clears")

	GameFeelBridge.damage_numbers.clear_all()
	_check(GameFeelBridge.damage_numbers.pool_size() == 40, "damage number pool size")
	GameFeelBridge.damage_numbers.spawn(12, Vector2.ZERO, false, 0)
	_check(GameFeelBridge.damage_numbers.active_count() == 1, "damage number spawns")
	GameFeelBridge.damage_numbers.spawn_text("爆头", Vector2.ZERO, Color.YELLOW)
	_check(GameFeelBridge.damage_numbers.active_count() == 2, "damage text spawns")
	GameFeelBridge.damage_numbers.clear_all()
	_check(GameFeelBridge.damage_numbers.active_count() == 0, "damage numbers clear")


func _test_ui_modules() -> void:
	GameFeelConfig.set_reduced_motion(false)
	GameFeelBridge.hit_direction.clear()
	_check(GameFeelBridge.hit_direction.max_arcs() == 4, "hit direction cap")
	GameFeelBridge.hit_direction.add_from_direction(Vector2.LEFT)
	_check(GameFeelBridge.hit_direction.arc_count() == 1, "hit direction arc spawns")
	GameFeelBridge.hit_direction.clear()
	_check(GameFeelBridge.hit_direction.arc_count() == 0, "hit direction clears")
	var normal := GameFeelLowHealth.alpha_for_ratio(0.10, false)
	var reduced := GameFeelLowHealth.alpha_for_ratio(0.10, true)
	_check(normal > 0.0 and reduced > 0.0 and reduced < normal, "low health accessibility alpha")
	_check(GameFeelLowHealth.alpha_for_ratio(0.60, false) == 0.0, "low health threshold")
	GameFeelBridge.kill_streak.reset()
	_check(GameFeelBridge.kill_streak.current_streak() == 0, "kill streak reset")


func _test_audio() -> void:
	_check(AudioLayerManager.has_bus("SFX_Combat"), "SFX_Combat bus")
	_check(AudioLayerManager.has_bus("SFX_UI"), "SFX_UI bus")
	_check(AudioLayerManager.has_bus("SFX_Ambient"), "SFX_Ambient bus")
	_check(AudioLayerManager.pool_size() == 24, "audio voice pool size")
	_check(AudioLayerManager.stream_count() >= 15, "procedural layer streams")
	var varied := PitchRandomizer.vary(1.0, 0.03)
	_check(absf(varied - 1.0) <= 0.031, "pitch randomizer range")


func _test_input_buffer() -> void:
	InputBuffer.reset()
	InputBuffer.note_press(&"jump")
	_check(InputBuffer.is_buffered(&"jump", 0.12), "input press buffered")
	_check(InputBuffer.consume(&"jump", 0.12), "buffered input consumed")
	_check(not InputBuffer.consume(&"jump", 0.12), "buffered input consumed once")
	InputBuffer.begin_hitstop()
	InputBuffer.note_press(&"fire")
	InputBuffer.end_hitstop()
	_check(InputBuffer.pressed_during_hitstop(&"fire"), "hitstop press captured")
	_check(InputBuffer.consume_after_hitstop(&"fire"), "hitstop press consumed after freeze")
	_check(InputBuffer.reload_cancel_open(0.8, 1.0), "reload cancel window opens late")
	_check(not InputBuffer.reload_cancel_open(0.2, 1.0), "reload cancel window closed early")
	InputBuffer.reset()


func _test_recoil() -> void:
	RecoilController.reset()
	RecoilController.kick(&"shotgun")
	_check(RecoilController.recoil_degrees > 0.0, "recoil kick")
	_check(RecoilController.spread_radius > RecoilController.SPREAD_MIN, "recoil spread")
	RecoilController.reset()
	_check(RecoilController.recoil_degrees == 0.0, "recoil reset")


func _test_reduced_motion() -> void:
	GameFeelConfig.set_reduced_motion(true)
	_check(is_equal_approx(GameFeelConfig.motion_scale(), 0.3), "reduced motion scale")
	_check(is_equal_approx(GameFeelConfig.flash_multiplier(), 1.0), "reduced motion keeps flash")
	ScreenShake.reset()
	ScreenShake.add_trauma(0.5, 10.0)
	_check(ScreenShake.max_offset <= 3.01, "reduced motion caps shake")
	ScreenShake.reset()
	GameFeelConfig.set_reduced_motion(false)


func _test_bridge_and_settings() -> void:
	_check(GameFeelBridge.tracked_enemy_count() >= 0, "bridge diagnostics accessible")
	_check(GameFeelBridge.perf_average_ms() >= 0.0, "bridge perf counter accessible")
	_check(GameFeelBridge.perf_max_ms() >= 0.0, "bridge perf max accessible")

	var scene: PackedScene = load(SETTINGS_SCENE)
	_check(scene != null, "settings scene loads")
	if scene != null:
		var settings := scene.instantiate()
		add_child(settings)
		var tabs: Array = settings.get("_tab_buttons")
		_check(tabs.size() == 4, "settings exposes 4 tabs")
		_check(settings.has_method("_build_gamefeel"), "settings game feel tab")
		settings.call("_show_tab", 3)
		var buttons: Dictionary = settings.get("_gamefeel_buttons")
		_check(buttons.size() == 4, "settings game feel toggles")
		settings.queue_free()
		await get_tree().process_frame
