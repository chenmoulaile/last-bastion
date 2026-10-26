extends Node
## Manual performance gate for the 120-common budget. Run with a real window
## (not --headless) so rendering and draw calls are included.
## Godot --path . --resolution 1280x720 res://tests/performance.tscn

const SAMPLE_SECONDS := 5.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	# Measure raw frame throughput instead of the display refresh rate: the
	# gate is about the 60 FPS budget, and some remote/virtual displays cap
	# vsync at 30 Hz.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(0.8, true, false, true).timeout
	DirectorSystem.end_level()
	var player: Node2D = scene.get_player()
	player.set("iframes", 9999.0)
	scene.spawn_horde_at(player.global_position, 120, false)
	for kind in [&"hunter", &"smoker", &"boomer", &"charger"]:
		scene.spawn_special(kind)
	await get_tree().create_timer(0.6, true, false, true).timeout
	# Warm up shader compilation and physics broadphase before sampling.
	await get_tree().create_timer(1.0, true, false, true).timeout

	var start := Time.get_ticks_usec()
	var frames := 0
	var min_fps := 9999.0
	var elapsed := 0.0
	var last := Time.get_ticks_usec()
	var process_sum := 0.0
	var physics_sum := 0.0
	var objects_sum := 0.0
	var pairs_sum := 0.0
	while elapsed < SAMPLE_SECONDS:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - last) / 1_000_000.0
		last = now
		elapsed += delta
		frames += 1
		process_sum += float(Performance.get_monitor(Performance.TIME_PROCESS))
		physics_sum += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		objects_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		pairs_sum += float(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
		if delta > 0.0:
			min_fps = minf(min_fps, 1.0 / delta)
	var total := float(Time.get_ticks_usec() - start) / 1_000_000.0
	var avg := float(frames) / maxf(0.001, total)
	var commons := 0
	var specials := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie) or bool(zombie.get("dead")):
			continue
		var zd: ZombieData = zombie.get("data")
		if zd == null:
			continue
		if zd.is_special:
			specials += 1
		else:
			commons += 1
	var memory_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var peak_mb := float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)
	print("[PERF] frames=%d avg_fps=%.1f min_fps=%.1f commons=%d specials=%d" % [
		frames, avg, min_fps, commons, specials])
	print("[PERF] draw_calls=%d memory=%.1fMB peak=%.1fMB" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		memory_mb, peak_mb])
	var denom := float(maxi(1, frames))
	print("[PERF] process=%.2fms physics=%.2fms objects=%.0f pairs=%.0f" % [
		process_sum / denom * 1000.0, physics_sum / denom * 1000.0,
		objects_sum / denom, pairs_sum / denom])
	var ok := avg >= 60.0 and commons <= 120 and specials <= 4 and peak_mb < 600.0
	print("[PERF] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
