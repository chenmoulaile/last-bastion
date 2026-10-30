extends Node
## Two-process co-op acceptance probe.
## Run:
##   godot --headless --path . res://tests/coop_probe.tscn -- --role=host
##   godot --headless --path . res://tests/coop_probe.tscn -- --role=client
##
## Covers: room join, synchronized level load, both player bodies, client
## movement replication, host zombie spawn -> client copy, client shot ->
## host-authoritative zombie damage/death, and remote-shot presentation events.

var role: String = "host"
var _fails: int = 0
var _level: Node = null
var _capture: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = _arg("--role", "host")
	_capture = "--capture" in OS.get_cmdline_user_args()
	EventBus.start_level_requested.connect(_on_start_level_requested)
	if role == "host":
		await _run_host()
	else:
		await _run_client()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_fails += 1


func _on_start_level_requested() -> void:
	if _level != null:
		return
	var path := "res://scenes/levels/%s.tscn" % String(GameManager.current_level_id)
	var packed: PackedScene = load(path)
	if packed == null:
		return
	_level = packed.instantiate()
	add_child(_level)
	await get_tree().create_timer(0.9, true, false, true).timeout


func _find_player(peer_id: int) -> Node:
	var root := get_tree().get_current_scene()
	if root == null:
		return null
	return root.find_child("Player_" + str(peer_id), true, false)


func _first_client_id(net: Node) -> int:
	for pid in net.get("players").keys():
		if int(pid) != 1:
			return int(pid)
	return -1


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1, true, false, true).timeout
	return bool(predicate.call())


func _run_host() -> void:
	print("== COOP PROBE: HOST ==")
	var net := get_node("/root/NetworkManager")
	net.host_session()
	net.start_coop_level(&"l01", &"SQUAD", &"NORMAL", &"assault")
	var level_ok: bool = await _wait_until(func() -> bool: return _level != null, 8000)
	_check(level_ok, "host level loaded")
	if not level_ok:
		_finish()
		return
	var client_id := -1
	var got_peer: bool = await _wait_until(
		func() -> bool: return _first_client_id(net) > 0, 12000)
	client_id = _first_client_id(net)
	_check(got_peer and client_id > 0, "client peer registered on host")
	if client_id < 0:
		_finish()
		return
	var client_ready: bool = await _wait_until(
		func() -> bool: return _find_player(client_id) != null, 12000)
	_check(client_ready, "client player body spawned on host (peer %d)" % client_id)
	var host_player: Node = _find_player(1)
	var client_player: Node = _find_player(client_id)
	_check(host_player != null and client_player != null, "host sees both player bodies")
	if host_player == null or client_player == null:
		_finish()
		return
	host_player.set("iframes", 9999.0)
	host_player.set_physics_process(false)
	host_player.global_position = Vector2(220.0, 288.0)
	var hcam: Camera2D = host_player.get("camera")
	if hcam != null:
		hcam.position_smoothing_enabled = false
		if hcam.has_method("reset_smoothing"):
			hcam.call("reset_smoothing")
	await get_tree().create_timer(1.5, true, false, true).timeout
	_check(absf(client_player.global_position.x - 280.0) < 16.0,
		"client movement replicated to host (x=%.1f)" % client_player.global_position.x)

	var target: Node = _level.call("_spawn_zombie", &"common", Vector2(360.0, 288.0), true)
	_check(target != null, "host spawned test zombie")
	var spawn_seen: bool = await _wait_until(
		func() -> bool: return int(net.get("zombie_spawn_events")) > 0, 3000)
	_check(spawn_seen, "host broadcast zombie spawn")
	var shot_seen: bool = await _wait_until(
		func() -> bool: return int(net.get("remote_shot_events")) > 0, 6000)
	_check(shot_seen, "host received remote-shot event from client")
	var target_dead: bool = await _wait_until(
		func() -> bool:
			return target == null or not is_instance_valid(target) or bool(target.get("dead")),
		6000)
	_check(target_dead, "client shot killed host-authoritative zombie")

	var weapon: Resource = host_player.call("_current_weapon")
	if weapon != null:
		host_player.set("facing", 1)
		host_player.set("aim_angle", 0.0)
		host_player.call("_fire_weapon", weapon)
	# A few extra infected so the co-op screenshots show a living battlefield.
	for i in 5:
		var zx := 340.0 + float(i) * 22.0
		_level.call("_spawn_zombie", &"common", Vector2(zx, 288.0), true)
	await get_tree().create_timer(1.2, true, false, true).timeout
	if _capture:
		await _snap("02_host_coop_combat")
	_dump_camera("HOST")
	print("HOST events: zombies=%d remote_shots=%d" % [
		int(net.get("zombie_spawn_events")), int(net.get("remote_shot_events"))])
	print("COOP HOST RESULT: %d failed" % _fails)
	_finish()


func _run_client() -> void:
	print("== COOP PROBE: CLIENT ==")
	var net := get_node("/root/NetworkManager")
	net.join_session("127.0.0.1")
	var connected: bool = await _wait_until(
		func() -> bool: return int(net.local_peer_id) > 1, 8000)
	_check(connected, "client connected (peer %d)" % int(net.local_peer_id))
	if not connected:
		_finish()
		return
	var level_ok: bool = await _wait_until(func() -> bool: return _level != null, 12000)
	_check(level_ok, "client received synchronized level")
	if not level_ok:
		_finish()
		return
	var my_id := int(net.local_peer_id)
	var local_ok: bool = await _wait_until(
		func() -> bool: return _find_player(my_id) != null, 8000)
	var host_ok: bool = await _wait_until(
		func() -> bool: return _find_player(1) != null, 8000)
	_check(local_ok, "client local Player_%d exists" % my_id)
	_check(host_ok, "client sees remote Player_1")
	if not local_ok or not host_ok:
		_finish()
		return
	var local_player: Node = _find_player(my_id)
	# Move on the client; the host asserts the replicated position. Freeze after
	# moving so an accidental keyboard focus cannot walk the body off-camera.
	local_player.set("iframes", 9999.0)
	local_player.global_position = Vector2(280.0, 288.0)
	local_player.set_physics_process(false)
	var ccam: Camera2D = local_player.get("camera")
	if ccam != null:
		ccam.position_smoothing_enabled = false
		if ccam.has_method("reset_smoothing"):
			ccam.call("reset_smoothing")

	var zombie_ok: bool = await _wait_until(
		func() -> bool: return get_tree().get_nodes_in_group("zombies").size() > 0, 6000)
	_check(zombie_ok, "client received zombie spawn")
	if zombie_ok:
		var weapon: Resource = local_player.call("_current_weapon")
		local_player.set("facing", 1)
		local_player.set("aim_angle", 0.0)
		if weapon != null:
			for i in 5:
				local_player.call("_fire_weapon", weapon)
				await get_tree().create_timer(0.12, true, false, true).timeout
		var remote_shot: bool = await _wait_until(
			func() -> bool: return int(net.get("remote_shot_events")) > 0, 6000)
		_check(remote_shot, "client received host remote-shot presentation")
		await get_tree().create_timer(1.2, true, false, true).timeout
		if _capture:
			await _snap("03_client_coop_combat")
		_dump_camera("CLIENT")
		print("CLIENT events: remote_shots=%d zombies_alive=%d" % [
			int(net.get("remote_shot_events")),
			get_tree().get_nodes_in_group("zombies").size()])
	else:
		_check(false, "client could not fire without a synced zombie")
	print("COOP CLIENT RESULT: %d failed" % _fails)
	_finish()


func _finish() -> void:
	print("COOP PROBE DONE: %d failed" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := "res://docs/evidence/v3.2.0"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := ProjectSettings.globalize_path(dir + "/" + name + ".png")
	image.save_png(path)
	print("[COOP SHOT] %s %dx%d at %s" % [name, image.get_width(), image.get_height(), path])


func _dump_camera(label: String) -> void:
	var cam := get_viewport().get_camera_2d()
	var cine := get_node_or_null("/root/CinematicCamera")
	print("%s CAMERA cam=%s cine_cam=%s cine_target=%s cine_ref=%s" % [
		label,
		str(cam.global_position) if cam != null else "none",
		str(cine.get("camera_2d")) if cine != null else "none",
		str(cine.get("_target_node")) if cine != null else "none",
		str(cine.get("_player_ref")) if cine != null else "none"])
