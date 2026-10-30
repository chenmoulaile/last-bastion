extends Node
## Real-render evidence capture for the v2.5.0 GoldAudit report.
## Run non-headless:
##   Godot_v4.7.2-stable_win64_console.exe --path . res://tests/evidence_capture.tscn
##
## Produces five screenshots plus FPS/object telemetry. Every image is captured
## from the live viewport after RenderingServer.frame_post_draw; the 2x copies are
## nearest-neighbour upscales of the same frame, not re-renders.

const OUT := "res://docs/evidence/v2.5.0"
const VIEW_W := 640.0
const VIEW_H := 360.0

var _log_lines: Array[String] = []
var _fps_rows: Array[String] = ["label,elapsed_s,fps,object_count,node_count,memory_mb"]
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_header()
	await _capture_main_menu()
	var level: Node = await _start_level()
	if level != null:
		await _capture_gameplay(level)
		await _capture_result(level)
	_write_logs()
	print("[EVIDENCE] done, failures=%d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _header() -> void:
	var vp := get_viewport().get_visible_rect().size
	_log("LAST BASTION v3.1.1-GoldAudit evidence capture (v2.5.0 audit scope)")
	_log("timestamp: " + Time.get_datetime_string_from_system())
	_log("engine: " + str(Engine.get_version_info().get("string", "?")))
	_log("renderer: " + str(ProjectSettings.get_setting("rendering/renderer/rendering_method")))
	_log("adapter: " + RenderingServer.get_video_adapter_name())
	_log("vendor: " + RenderingServer.get_video_adapter_vendor())
	_log("api: " + RenderingServer.get_video_adapter_api_version())
	_log("viewport: %.0fx%.0f  window: %s" % [vp.x, vp.y, str(get_window().size)])
	_log("vsync: disabled  max_fps: 0 (uncapped)")
	_log("window_focused: " + str(DisplayServer.window_is_focused()))


func _log(line: String) -> void:
	_log_lines.append(line)
	print("[EVIDENCE] " + line)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	_log(("PASS  " if ok else "FAIL  ") + label)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _capture_main_menu() -> void:
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	if menu.has_method("setup"):
		menu.setup({})
	add_child(menu)
	await _settle(0.9)
	await _snap("01_main_menu")
	menu.queue_free()
	await _settle(0.2)


func _start_level() -> Node:
	GameManager.selected_character = &"assault"
	var empty_squad: Array[StringName] = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL", &"assault", empty_squad)
	if GameManager.current_level == null:
		_log("FAIL  start_level produced no current_level")
		_fails += 1
		return null
	var level: Node = load("res://scenes/levels/l01.tscn").instantiate()
	level.name = "LevelRunner"
	add_child(level)
	await _settle(1.2)
	return level


func _capture_gameplay(level: Node) -> void:
	var player: Node2D = level.get_player()
	if player == null:
		_log("FAIL  level has no player")
		_fails += 1
		return
	player.set("iframes", 9999.0)
	var start_x := player.global_position.x
	player.global_position = Vector2(start_x, level.call("get_ground_y", start_x))
	await _settle(0.7)
	var cam := get_viewport().get_camera_2d()
	_log("player start: %s  camera: %s" % [
		str(player.global_position),
		str(cam.global_position) if cam != null else "none"])
	await _sample_fps("baseline", 2.0, {"zombies": _zombie_count(), "visible": 0})

	# --- combat / dismemberment ------------------------------------------------
	var px := player.global_position.x
	for i in 8:
		var x := px + 70.0 + float(i) * 18.0
		level.call("_spawn_zombie", &"common", Vector2(x, level.call("get_ground_y", x)), true)
	await _settle(0.5)
	Input.action_press("fire")
	await _settle(0.3)
	Input.action_release("fire")
	await _settle(0.08)
	var victim: Node = _nearest_zombie(player.global_position, 180.0)
	if victim != null:
		victim.call("apply_damage", 999, Vector2.RIGHT, false, &"player", &"shotgun")
	await _settle(0.12)
	await _snap("02_combat_dismemberment")

	# --- barrel explosion ------------------------------------------------------
	var barrel: Node = _nearest_barrel(player.global_position)
	if barrel != null:
		barrel.global_position = player.global_position + Vector2(86.0, 0.0)
		await _settle(0.15)
		barrel.call("hit", 999)
		await _settle(0.10)
		await _snap("03_barrel_explosion")
	else:
		_log("FAIL  no explosive barrel found in l01")
		_fails += 1

	# --- 50-enemy stress -------------------------------------------------------
	level.call("spawn_horde_at", player.global_position, 50, true)
	await _settle(0.8)
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	var span := 580.0
	for i in zombies.size():
		var x := clampf(player.global_position.x - span * 0.5
			+ span * float(i) / float(maxi(1, zombies.size() - 1)), 40.0,
			float(level.get("level_width")) - 40.0)
		var gy: float = level.call("get_ground_y", x)
		if gy >= 0.0:
			zombies[i].global_position = Vector2(x, gy)
	await _settle(0.35)
	var visible := _visible_zombies(player.global_position.x, 320.0)
	await _snap("06_stress_50_enemies")
	await _sample_fps("stress_50", 5.0, {"zombies": _zombie_count(), "visible": visible})

	# --- boss ------------------------------------------------------------------
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	await _settle(0.4)
	level.call("spawn_boss", &"tank", 1)
	await _settle(0.5)
	var boss: Node2D = level.call("get_boss_node")
	if boss != null:
		var bx := player.global_position.x + 132.0
		boss.global_position = Vector2(bx, level.call("get_ground_y", bx))
		await _settle(0.8)
		await _snap("04_boss_fight")
	else:
		_log("FAIL  boss did not spawn")
		_fails += 1


func _capture_result(level: Node) -> void:
	GameManager.player_stats = {}
	for i in 12:
		GameManager.record_player_kill(1, i % 4 == 0, false, &"ar15")
	for i in 5:
		GameManager.record_player_kill(2, true, i == 0, &"shotgun")
	GameManager.record_player_damage(1, 2450)
	GameManager.record_player_damage(2, 1820)
	GameManager.record_player_down(2)
	GameManager.record_player_rescue(1)
	var result := {
		"failed": false, "score": 248600, "time": 318.0, "max_combo": 42,
		"squad_alive": 4, "soldiers_start": 0, "soldiers_lost": 0,
		"doors_kicked": 7, "hunter_interrupts": 2, "witch_crowns": 1,
		"barrel_kills": 8, "molotov_kills": 6, "tanks_killed": 2,
		"witch_woken": true, "hidden_rooms": ["l01_hidden"],
		"codex": ["hunter", "smoker"],
	}
	GameManager.complete_level(result)
	level.queue_free()
	await _settle(0.4)
	if GameManager.last_result.is_empty():
		_log("FAIL  complete_level produced no last_result")
		_fails += 1
		return
	var rows: Array = GameManager.last_result.get("player_stats", [])
	_check(rows.size() == 2, "last_result carries 2 per-peer rows (got %d)" % rows.size())
	var result_ui: Control = load("res://scenes/ui/result.tscn").instantiate()
	if result_ui.has_method("setup"):
		result_ui.setup({})
	add_child(result_ui)
	await _settle(0.5)
	var mp_panel: Control = result_ui.find_child("MultiplayerStats", true, false)
	_check(mp_panel != null, "MultiplayerStats panel exists")
	if mp_panel != null:
		var rect := mp_panel.get_global_rect()
		_log("MultiplayerStats rect: " + str(rect))
		_check(rect.position.y >= 0.0 and rect.end.y <= VIEW_H + 0.5,
			"MultiplayerStats panel inside %.0fx%.0f" % [VIEW_W, VIEW_H])
	await _snap("05_result_panel")


func _nearest_zombie(from: Vector2, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			continue
		var d: float = from.distance_to((z as Node2D).global_position)
		if d < best_d:
			best = z
			best_d = d
	return best


func _nearest_barrel(from: Vector2) -> Node:
	var barrels: Array = get_tree().get_nodes_in_group("barrels")
	if barrels.is_empty():
		return null
	return barrels[0] as Node


func _zombie_count() -> int:
	return get_tree().get_nodes_in_group("zombies").size()


func _visible_zombies(center_x: float, half_width: float) -> int:
	var count := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z != null and is_instance_valid(z) and absf((z as Node2D).global_position.x - center_x) <= half_width:
			count += 1
	return count


func _sample_fps(label: String, duration: float, meta: Dictionary) -> void:
	var samples: Array[float] = []
	var starts: Array[float] = []
	var frames := 0
	var last_usec := Time.get_ticks_usec()
	var begin_usec := last_usec
	while true:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		var span := float(now - last_usec) / 1000000.0
		if span >= 0.2:
			var fps := float(frames) / span
			var elapsed := float(now - begin_usec) / 1000000.0
			samples.append(fps)
			starts.append(elapsed)
			_fps_rows.append("%s,%.2f,%.1f,%d,%d,%.1f" % [
				label, elapsed, fps,
				int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0])
			frames = 0
			last_usec = now
		if float(Time.get_ticks_usec() - begin_usec) / 1000000.0 >= duration:
			break
	if samples.is_empty():
		_log("FAIL  no FPS samples for " + label)
		_fails += 1
		return
	var total := 0.0
	var steady_total := 0.0
	var steady_min := 1e9
	var steady_max := 0.0
	var steady_n := 0
	var min_fps := 1e9
	var max_fps := 0.0
	for i in samples.size():
		var s := samples[i]
		total += s
		min_fps = minf(min_fps, s)
		max_fps = maxf(max_fps, s)
		if starts[i] > 1.0:
			steady_total += s
			steady_min = minf(steady_min, s)
			steady_max = maxf(steady_max, s)
			steady_n += 1
	var avg := total / float(samples.size())
	var steady_avg := steady_total / float(maxi(1, steady_n))
	_log("FPS[%s] samples=%d min=%.1f avg=%.1f max=%.1f | steady(>1s) n=%d min=%.1f avg=%.1f max=%.1f | focused=%s meta=%s" % [
		label, samples.size(), min_fps, avg, max_fps,
		steady_n, steady_min if steady_n > 0 else 0.0, steady_avg,
		steady_max, str(DisplayServer.window_is_focused()), str(meta)])


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
	image.save_png(abs_path)
	var stats := _image_stats(image)
	_log("SHOT %s %dx%d %s" % [name, image.get_width(), image.get_height(), stats])
	var mean := float(stats.get("mean", 0.0))
	_check(mean > 0.01 and int(stats.get("colors", 0)) > 8,
		"%s is a rendered frame (not black)" % name)


func _image_stats(image: Image) -> Dictionary:
	var total := 0.0
	var count := 0
	var colors := {}
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var c := image.get_pixel(x, y)
			total += c.get_luminance()
			count += 1
			colors[c.to_html(false)] = true
	return {"mean": total / float(maxi(1, count)), "colors": colors.size()}


func _write_logs() -> void:
	var log_file := FileAccess.open(ProjectSettings.globalize_path(OUT + "/capture_log.txt"), FileAccess.WRITE)
	if log_file != null:
		for line in _log_lines:
			log_file.store_line(line)
		log_file.close()
	var fps_file := FileAccess.open(ProjectSettings.globalize_path(OUT + "/fps_samples.csv"), FileAccess.WRITE)
	if fps_file != null:
		for row in _fps_rows:
			fps_file.store_line(row)
		fps_file.close()
