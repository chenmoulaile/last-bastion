extends Node
## wp3-interior-visuals 定向截图：室内专用调色板 / 深色底板挡视差 /
## 家具与碰撞 / 出口楼梯贴片 + 返回街道提示 / 暖色 modulate。
## 真实窗口运行：Godot --path . --resolution 1280x720 res://tests/wp3_interior_shot.tscn
## 输出 build/screens/wp3_interior_*.png，并打印数值证据。

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
	var buildings: Array = scene.get("_buildings")
	var target: Dictionary = {}
	for b in buildings:
		if bool(b.get("enterable", false)):
			target = b
			break
	print("[WP3] player=%s buildings=%d target_door_x=%s" % [
		str(player != null), buildings.size(), str(target.get("door_x", -1.0))])
	if target.is_empty() or player == null:
		get_tree().quit()
		return
	# 走真实进门路径：先打破门（门离开 doors 组）→ 走入门洞 → Area2D 触发 _try_enter_interior
	for d in get_tree().get_nodes_in_group("doors"):
		if absf(d.global_position.x - float(target["door_x"])) < 24.0:
			d.call("hit", 999)
			break
	player.global_position = Vector2(float(target["door_x"]), float(target["ground_y"]) - 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.5, true, false, true).timeout
	var room: Dictionary = target.get("interior", {})
	var in_interior: bool = scene.get("_in_interior")
	print("[WP3] door_broken_interior_triggered in_interior=%s player_at=%s entry=%s" % [
		str(in_interior), str(player.global_position.round()), str(room.get("entry", Vector2.ZERO))])
	# 走到房间中部，自建相机室内居中构图（zoom=4，规格要求；玩家相机有拖拽偏移不宜依赖）
	# 注意：视口 640x360，zoom=4 的世界视野是 160x90——对准家具+地板带，玩家作比例参照
	var rect2: Rect2 = room["rect"] as Rect2
	player.global_position = Vector2(rect2.get_center().x, 284.0)
	var shot_cam := Camera2D.new()
	shot_cam.zoom = Vector2(4, 4)
	scene.add_child(shot_cam)
	shot_cam.global_position = Vector2(rect2.get_center().x, 262.0)
	shot_cam.make_current()
	await get_tree().create_timer(1.2, true, false, true).timeout
	print("[WP3] shot_cam_center=%s zoom=%s player=%s" % [
		str(shot_cam.get_screen_center_position().round()), str(shot_cam.zoom),
		str(player.global_position.round())])
	# ① 暖角证据：玩家根 modulate 应为暖色
	print("[WP3] player_modulate=%s allies_pickups_tinted=%s" % [
		str(player.modulate), str(_count_tinted())])
	await _snap("wp3_interior_center")
	# ② 全屋概览（zoom=2，视野 320x180，可见天花板/墙纸/平台/家具/楼梯/提示）
	shot_cam.zoom = Vector2(2, 2)
	shot_cam.global_position = rect2.get_center() + Vector2(0, -8)
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _snap("wp3_interior_overview")
	# ② 家具与底板数量（房间根现在是 InteriorRoot1/2 唯一名）
	var furn := 0
	var backdrops := 0
	var roots := 0
	for c in scene.get_children():
		if c is Node2D and String(c.name).begins_with("InteriorRoot"):
			roots += 1
			for cc in (c as Node2D).get_children():
				if cc is StaticBody2D:
					furn += 1
				if cc is Polygon2D:
					backdrops += 1
	print("[WP3] interior_roots=%d furniture_bodies=%d backdrop_polygons=%d furniture_expected=6-10(2房x3-5)" % [roots, furn, backdrops])
	print("[WP3] done")
	get_tree().quit()


func _count_tinted() -> int:
	var n := 0
	for g in ["allies", "pickups"]:
		for p in get_tree().get_nodes_in_group(g):
			if p is CanvasItem and (p as CanvasItem).modulate.is_equal_approx(Color(1.0, 0.92, 0.82)):
				n += 1
	return n


func _snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + shot + ".png"))
	print("[WP3] %s saved" % shot)
