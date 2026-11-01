extends Node
## wp6-signal-agent-ai 定向截图：信号局特工干扰视觉（准星抖动 / 静电噪点层）
## 与特工招式（受击瞬移 / 诱导尸群 / 死亡反制爆发）。
## 真实窗口运行：Godot --path . --resolution 1280x720 res://tests/wp6_signal_shot.tscn
## 输出 build/screens/wp6_signal_*.png，并打印数值证据。

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
	var hud = scene.get("hud")
	var player: Node2D = scene.get_player()
	var agent: Node = scene.call("_spawn_humans", &"signal_bureau", &"agent", 1, 0.5)
	print("[WP6] agent=%s hud=%s" % [str(agent != null), str(hud != null)])
	if agent != null:
		agent.global_position = player.global_position + Vector2(120, 0)
	# 镜头贴身放大，让特工与准星区域都可见
	var cam: Camera2D = player.get_node("Camera")
	cam.zoom = Vector2(3, 3)
	cam.reset_smoothing()
	get_viewport().warp_mouse(Vector2(320, 180))  # 准星移到画面中心，抖动可目测
	await get_tree().create_timer(0.4, true, false, true).timeout

	# ① 基线（无干扰）
	await _snap("wp6_signal_baseline")
	print("[WP6] baseline interference_active=%s static_visible=%s" % [
		str(hud.get("_interference_active")), str(hud.get("_static_rect").visible)])

	# ② 干扰生效：准星抖动（采样多帧）+ 静电噪点层
	EventBus.signal_interference.emit(true)
	await get_tree().create_timer(0.15, true, false, true).timeout
	var cross: Control = hud.get("_crosshair")
	var samples: Array[String] = []
	for i in 6:
		await get_tree().process_frame
		samples.append("(%d,%d)" % [int(cross.position.x), int(cross.position.y)])
	var static_rect: TextureRect = hud.get("_static_rect")
	print("[WP6] interference interference_active=%s static_visible=%s static_a=%.3f cross_pos_samples=%s" % [
		str(hud.get("_interference_active")), str(static_rect.visible),
		static_rect.modulate.a, " ".join(samples)])
	await _snap("wp6_signal_interference")
	EventBus.signal_interference.emit(false)
	await get_tree().process_frame

	# ③ 受击瞬移换位：记录前后位置
	if agent != null:
		var before: Vector2 = agent.global_position
		agent.call("apply_damage", 10, Vector2.RIGHT, false, &"player", &"bullet")
		await get_tree().create_timer(0.2, true, false, true).timeout
		print("[WP6] blink before=%s after=%s moved=%.0f blink_cd=%.1f" % [
			str(before.round()), str(agent.global_position.round()),
			absf(agent.global_position.x - before.x), float(agent.get("_blink_cd"))])

	# ④ 诱导尸群
	if agent != null:
		var zombies_before := get_tree().get_nodes_in_group("zombies").size()
		agent.set("_summon_cd", 0.05)
		await get_tree().create_timer(0.4, true, false, true).timeout
		var delta := get_tree().get_nodes_in_group("zombies").size() - zombies_before
		print("[WP6] summon delta=+%d (expect 1-2)" % delta)

	# ⑤ 死亡反制爆发：击杀特工 → 大范围干扰
	EventBus.signal_interference.emit(true)  # 先模拟脉冲在途
	await get_tree().create_timer(0.1, true, false, true).timeout
	if agent != null:
		agent.call("apply_damage", 9999, Vector2.RIGHT, false, &"player", &"bullet")
	await get_tree().create_timer(0.3, true, false, true).timeout
	print("[WP6] death_burst level_interference=%.1f hud_active=%s agent_dead=%s" % [
		float(scene.get("_interference")), str(hud.get("_interference_active")),
		str(bool(agent.get("dead")) if agent != null else false)])
	await _snap("wp6_signal_death_burst")

	print("[WP6] done")
	get_tree().quit()


func _snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "/" + shot + ".png"))
	print("[WP6] %s saved" % shot)
