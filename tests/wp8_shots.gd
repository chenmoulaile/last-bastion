extends Node
## wp8-tests-ci 定向截图：手臂三角度（上45°/水平/下45°）+ 街道/室内同门对比。
## 真实窗口运行：Godot --path . --resolution 1280x720 res://tests/wp8_shots.tscn
## 输出 build/screens/wp8_arms_{up45,horizontal,down45}.png 与
## build/screens/wp8_street.png / wp8_interior.png（同一可进入建筑的前后对比），
## 并打印 aim_angle / weapon_sprite.rotation / in_interior 数值证据。

const OUT := "res://build/screens"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().process_frame
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(1.1, true, false, true).timeout
	var player: Node2D = scene.get_player()
	var target: Dictionary = {}
	for b in scene.get("_buildings"):
		if bool(b.get("enterable", false)):
			target = b
			break
	if target.is_empty() or player == null:
		print("[WP8] no enterable building / no player, abort")
		get_tree().quit()
		return
	var door_x := float(target["door_x"])
	var ground_y := float(target["ground_y"])
	# 隐藏 HUD 层，避免遮挡角色
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	# —— 街道对比照：玩家站在 enterable 门前，镜头贴身放大
	player.global_position = Vector2(door_x - 60.0, ground_y - 2.0)
	player.velocity = Vector2.ZERO
	var cam: Camera2D = player.get_node("Camera")
	cam.zoom = Vector2(4, 4)
	cam.position = Vector2(0, -24)
	cam.limit_smoothed = false
	cam.reset_smoothing()
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _snap("wp8_street")

	# —— 手臂三角度（与 wp3_arms_shot 同规格：屏蔽鼠标瞄准，走键盘 aim 分支）
	player.set("using_mouse", false)
	player.set("mouse_recent", 0.0)
	await _snap_arms("wp8_arms_horizontal", player)
	Input.action_press("aim_up")
	player.set("mouse_recent", 0.0)
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _snap_arms("wp8_arms_up45", player)
	Input.action_release("aim_up")
	Input.action_press("aim_down")
	player.set("mouse_recent", 0.0)
	await get_tree().create_timer(0.35, true, false, true).timeout
	await _snap_arms("wp8_arms_down45", player)
	Input.action_release("aim_down")

	# —— 室内对比照：破门 → 走入门洞 → 房间中央 zoom=2 概览（与街道照同门）
	for d in get_tree().get_nodes_in_group("doors"):
		if absf(d.global_position.x - door_x) < 24.0:
			d.call("hit", 999)
			break
	player.global_position = Vector2(door_x, ground_y - 2.0)
	for _i in 4:
		await get_tree().physics_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	var room: Dictionary = target.get("interior", {})
	if room.is_empty():
		print("[WP8] no interior room, abort")
		get_tree().quit()
		return
	var rect2: Rect2 = room["rect"] as Rect2
	player.global_position = Vector2(rect2.get_center().x, 284.0)
	var shot_cam := Camera2D.new()
	shot_cam.zoom = Vector2(2, 2)
	scene.add_child(shot_cam)
	shot_cam.global_position = rect2.get_center() + Vector2(0, -8)
	shot_cam.make_current()
	await get_tree().create_timer(1.0, true, false, true).timeout
	await _snap("wp8_interior")
	print("[WP8] in_interior=%s street_return=%s door_x=%.0f" % [
		str(scene.get("_in_interior")), str(scene.get("_street_return")), door_x])
	print("[WP8] done")
	get_tree().quit()


func _snap_arms(shot: String, player: Node2D) -> void:
	player.set("using_mouse", false)
	player.set("mouse_recent", 0.0)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + shot + ".png"))
	print("[WP8] %s aim_angle=%.3f ws_rot=%.3f facing=%d" % [
		shot, player.aim_angle, player.weapon_sprite.rotation, player.facing])


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
	print("[WP8] saved " + name)
