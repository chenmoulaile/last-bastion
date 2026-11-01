extends Node
## wp3-arms-aim-rotate 定向截图：手臂随瞄准角旋转三连。
## 水平 / aim_up 按住 / aim_down 按住各截一张（build/screens/wp3_arms_*.png），
## 同时打印 aim_angle 与 WeaponSprite 旋转角供程序化比对。
## 真实窗口运行：Godot --path . --resolution 1280x720 res://tests/wp3_arms_shot.tscn

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
	# 传送到空地并把镜头贴身放大，让手臂/枪身像素级可见
	var gx := 220.0
	player.global_position = Vector2(gx, scene.call("get_ground_y", gx) - 4.0)
	player.velocity = Vector2.ZERO
	var cam: Camera2D = player.get_node("Camera")
	cam.zoom = Vector2(5, 5)
	cam.position = Vector2(0, -24)
	cam.limit_smoothed = false
	cam.reset_smoothing()
	# 隐藏 HUD 层，避免遮挡角色
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	await get_tree().create_timer(0.35, true, false, true).timeout

	# ① 水平瞄准（默认朝向）
	_force_keyboard_aim(player)
	await _snap_arms("wp3_arms_horizontal", player)

	# ② aim_up 按住（-45°）
	Input.action_press("aim_up")
	await _settle(player)
	await _snap_arms("wp3_arms_up", player)
	Input.action_release("aim_up")

	# ③ aim_down 按住（+45°）
	Input.action_press("aim_down")
	await _settle(player)
	await _snap_arms("wp3_arms_down", player)
	Input.action_release("aim_down")

	# ④ 队友手臂（velocity/facing 推角）——队友奔跑中、镜头对准队友截
	Input.action_press("move_right")
	await get_tree().create_timer(0.8, true, false, true).timeout
	_force_keyboard_aim(player)
	await _snap_allies("wp3_arms_allies", scene)
	Input.action_release("move_right")

	print("[WP3] done")
	get_tree().quit()


## 屏蔽鼠标瞄准干扰，强制走键盘 aim 分支
func _force_keyboard_aim(player: Node) -> void:
	player.set("using_mouse", false)
	player.set("mouse_recent", 0.0)


func _settle(player: Node) -> void:
	_force_keyboard_aim(player)
	await get_tree().create_timer(0.35, true, false, true).timeout


func _snap_arms(shot: String, player: Node2D) -> void:
	_force_keyboard_aim(player)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + shot + ".png"))
	print("[WP3] %s aim_angle=%.3f ws_rot=%.3f ws_pos=(%.1f, %.1f) facing=%d cat=%s pos=%s" % [
		shot, player.aim_angle, player.weapon_sprite.rotation,
		player.weapon_sprite.position.x, player.weapon_sprite.position.y,
		player.facing, player.arm_category, str(player.global_position.round())])


## 队友手臂合影：镜头对准第一个还在移动的队友，打印各队友手臂角与枪身角
func _snap_allies(shot: String, scene: Node) -> void:
	var player: Node2D = scene.get_player()
	var allies: Array = scene.get_allies() if scene.has_method("get_allies") else []
	var target: Node2D = null
	for a in allies:
		if a == null or not is_instance_valid(a) or bool(a.get("is_dead")):
			continue
		print("[WP3] ally %s arm_angle=%.3f ws_rot=%.3f facing=%d vel=%.0f" % [
			a.get("data").id if a.get("data") != null else "?",
			a.get("_arm_angle"), a.weapon_sprite.rotation, a.facing, a.velocity.length()])
		if target == null and a.velocity.length_squared() > 100.0:
			target = a
	if target == null:
		target = player
	var cam: Camera2D = player.get_node("Camera")
	cam.zoom = Vector2(4, 4)
	cam.position = target.global_position - player.global_position + Vector2(0, -24)
	cam.reset_smoothing()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + shot + ".png"))
	print("[WP3] %s saved, allies=%d target_vel=%.0f" % [shot, allies.size(), target.velocity.length()])
