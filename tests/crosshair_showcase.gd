extends Control
## 准星七状态特写：静止/开火扩散/最大扩散/换弹/命中/击杀/爆头。
## 输出 build/screens/crosshair_states.png（640×360 逻辑分辨率，像素 1:1）。

func _ready() -> void:
	# 精确 640×360 渲染，保证 1 逻辑像素 = 1 截图像素（放大后检查锯齿）
	DisplayServer.window_set_size(Vector2i(640, 360))
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11, 1)
	bg.size = Vector2(640, 360)
	add_child(bg)
	_make(Vector2(60, 60), 3, 0, 0, 0.9, "静止")
	_make(Vector2(180, 60), 6, 0, 0, 0.9, "开火扩散", 1)
	_make(Vector2(300, 60), 12, 0, 0, 0.9, "最大扩散")
	_make(Vector2(420, 60), 3, 1, 3, 0.9, "换弹")
	_make(Vector2(540, 60), 3, 0, 0, 0.25, "倒地")
	var hit := PixelHitmarker.new()
	hit.position = Vector2(48, 150)
	hit.size = Vector2(24, 24)
	add_child(hit)
	hit.show_hit(Color(0.95, 0.96, 0.97))
	_label(Vector2(30, 180), "命中")
	var kill := PixelHitmarker.new()
	kill.position = Vector2(168, 150)
	kill.size = Vector2(24, 24)
	add_child(kill)
	kill.show_hit(Color(1.0, 0.32, 0.28))
	_label(Vector2(150, 180), "击杀")
	var head := PixelHitmarker.new()
	head.position = Vector2(288, 150)
	head.size = Vector2(24, 24)
	add_child(head)
	head.show_hit(Color(1.0, 0.62, 0.20))
	_label(Vector2(270, 180), "爆头")
	# 命中标记生命周期 0.12s：截图前重置并冻结计时器（_process 停用），保证可见
	for hm in [hit, kill, head]:
		hm.show_hit(hm._color)
		hm.set_process(false)
		hm.visible = true
	await get_tree().create_timer(0.04).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/screens/crosshair_states.png")
	print("[CROSS] saved")
	get_tree().quit()


func _make(pos: Vector2, spread: int, state: int, phase: int, alpha: float, caption: String,
		press: int = 0) -> void:
	var c := PixelCrosshair.new()
	c.position = pos
	c.spread_px = spread
	c.state = state
	c.press_bonus = press
	c.reload_phase = phase
	c.effective_alpha = alpha
	add_child(c)
	_label(pos + Vector2(-14, 40), caption)


func _label(pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	add_child(l)
