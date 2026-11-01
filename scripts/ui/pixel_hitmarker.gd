class_name PixelHitmarker
extends Control
## P1-7 命中标记：4 条 45° 斜向 1px 刻线组成的 X（像素坐标表，无旋转）。
## 三色：普通命中白 / 击杀红 / 爆头橙；显示 120ms，两档大小，淡出只改 alpha。

const LIFETIME := 0.12

var _color := Color(1, 1, 1)
var _scale_big := true
var _timer := 0.0
var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(24, 24)
	z_index = 51
	visible = false


func show_hit(color: Color) -> void:
	_color = color
	_timer = LIFETIME
	_shown = true
	_scale_big = true
	visible = true
	queue_redraw()
	# 收到小一档（阶梯，无插值）
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		_scale_big = false
		if is_instance_valid(self):
			queue_redraw())


func _process(delta: float) -> void:
	if not _shown:
		return
	_timer -= delta
	if _timer <= 0.0:
		_shown = false
		visible = false
		return
	queue_redraw()


func _draw() -> void:
	if not _shown:
		return
	var c := Vector2i(int(size.x * 0.5), int(size.y * 0.5))
	var arm := 3 if _scale_big else 2
	var a := clampf(_timer / LIFETIME, 0.0, 1.0)
	var color := Color(_color.r, _color.g, _color.b, a)
	var shadow := Color(0, 0, 0, a * 0.5)
	# 45° 斜线像素表：x+y=-arm..arm 的对角点
	for i in range(-arm, arm + 1):
		if i == 0:
			continue
		draw_rect(Rect2(c.x + i + 1, c.y + i + 1, 1, 1), shadow)
		draw_rect(Rect2(c.x + i, c.y + i, 1, 1), color)
		draw_rect(Rect2(c.x + i + 1, c.y - i + 1, 1, 1), shadow)
		draw_rect(Rect2(c.x + i, c.y - i, 1, 1), color)
