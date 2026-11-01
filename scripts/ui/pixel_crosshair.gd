class_name PixelCrosshair
extends Control
## P1-7 像素准星：全部 _draw() 程序化绘制，1px 刻线，扩散只改间距。
## 状态：0 常态 / 1 装填（4 点环形按 6FPS 步进旋转）。
## 绘制坐标全部取整，2x 窗口缩放下保持像素颗粒感，无位图放大模糊。

var spread_px: int = 3        # 刻线内端到中心的距离（3..12）
var press_bonus: int = 0      # 开火瞬间的额外间距（0/1）
var state: int = 0            # 0 常态 / 1 装填
var reload_phase: int = 0     # 0..7，45° 步进
var effective_alpha: float = 0.9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(32, 32)
	z_index = 50


func _draw() -> void:
	var c := Vector2i(int(size.x * 0.5), int(size.y * 0.5))
	var a := effective_alpha
	if state == 1:
		_draw_reload_ring(c, a)
		return
	var gap := spread_px + press_bonus
	var color := Color(0.91, 0.925, 0.937, a)
	if gap >= 11:
		color = Color(1.0, 0.35, 0.24, a)  # 最大扩散警示色
	var shadow := Color(0.0, 0.0, 0.0, a * 0.5)
	# 4 条 1px×4px 刻线（上下左右）+ 右下 1px 阴影
	for i in 4:
		var arm := _arm_rect(c, gap, i)
		draw_rect(Rect2(arm.position + Vector2(1, 1), arm.size), shadow)
		draw_rect(arm, color)
	# 中心 1px 点
	draw_rect(Rect2(c.x, c.y, 1, 1), color)
	if state == 0 and gap <= 4:
		pass


## 第 i 条刻线（0 上 1 下 2 左 3 右）的 1px 线矩形。
func _arm_rect(c: Vector2i, gap: int, i: int) -> Rect2:
	match i:
		0: return Rect2(c.x, c.y - gap - 4, 1, 4)
		1: return Rect2(c.x, c.y + gap, 1, 4)
		2: return Rect2(c.x - gap - 4, c.y, 4, 1)
		_: return Rect2(c.x + gap, c.y, 4, 1)


## 换弹：4 个 1px 点组成的环，按 phase 步进旋转（非平滑）。
func _draw_reload_ring(c: Vector2i, a: float) -> void:
	var color := Color(0.91, 0.925, 0.937, a)
	var shadow := Color(0.0, 0.0, 0.0, a * 0.5)
	var radius := 5
	var base := reload_phase * 3  # 每档 3° 的整数像素表由角度表近似
	var angles := [0, 90, 180, 270]
	for i in 4:
		var deg := (int(angles[i]) + base * 8) % 360
		var rad := deg_to_rad(float(deg))
		var px := c.x + int(round(cos(rad) * radius))
		var py := c.y + int(round(sin(rad) * radius))
		draw_rect(Rect2(px + 1, py + 1, 1, 1), shadow)
		draw_rect(Rect2(px, py, 1, 1), color)
