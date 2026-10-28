class_name ReworkShapes
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 静态绘制工具库 —— 所有代码绘制角色共用的图元函数(头/四肢/躯干/
##       武器/枪口火光/阴影)。供 PlayerRenderer 与 SoldierRenderer 复用。
## 依赖: 仅 CanvasItem draw_* API。所有函数接收 CanvasItem,不持有状态。
## 对外接口(全部 static):
##   shadowEllipse / capsuleLimb / head / torso / gun / muzzleFlash /
##   crossMark / starMark / eyeSlit
## 约定: 坐标单位为像素,角色绘制原点在脚底中心,身体向 -y 方向生长,
##       总高约 32px,头身比 1:4(头 r≈4)。调用方已通过 draw_set_transform
##       处理朝向镜像,本库不做镜像。
## ---------------------------------------------------------------------------

const OUTLINE: Color = Color(0.06, 0.07, 0.10, 0.55)


## 说明: 地面阴影为 8 顶点椭圆多边形,顶点数组由 CodeRenderer 预分配并每帧
## 原位写入(_draw 零分配),故不在本库提供 shadow 函数 —— 见 CodeRenderer._draw_shadow。


static func capsuleLimb(ci: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	## 肢体 = 粗线段 + 端点圆,视觉上等价胶囊,2 个图元。
	ci.draw_line(from, to, color, width)
	ci.draw_circle(from, width * 0.5, color)
	ci.draw_circle(to, width * 0.5, color)


static func head(ci: CanvasItem, center: Vector2, radius: float, skin_color: Color,
		helmet_color: Color, facing_local: int = 1) -> void:
	## 头: 皮肤圆 + 上半头盔弧 + 描边,3 个图元。
	ci.draw_circle(center, radius, skin_color)
	ci.draw_colored_polygon(_helmet_arc(center, radius, facing_local), helmet_color)
	ci.draw_arc(center, radius + 0.4, PI * 0.15, PI * 1.35, 8, OUTLINE, 0.8)


static func helmetArcPoints(center: Vector2, radius: float, facing_local: int) -> PackedVector2Array:
	return _helmet_arc(center, radius, facing_local)


static func eyeSlit(ci: CanvasItem, center: Vector2, facing_local: int, color: Color) -> void:
	## 面部朝向侧的眼睛/面罩缝,1 个图元。
	var offset := Vector2(facing_local * 1.6, -0.4)
	ci.draw_rect(Rect2(center + offset - Vector2(1.4, 0.7), Vector2(2.8, 1.4)), color)


static func torso(ci: CanvasItem, top_center: Vector2, half_width: float, height: float,
		primary: Color, secondary: Color) -> void:
	## 躯干 = 主色矩形 + 辅色背心条,2 个图元。
	ci.draw_rect(Rect2(top_center - Vector2(half_width, 0), Vector2(half_width * 2.0, height)), primary)
	ci.draw_rect(Rect2(top_center - Vector2(half_width, height * 0.18),
		Vector2(half_width * 2.0, height * 0.42)), secondary)


static func gun(ci: CanvasItem, origin: Vector2, angle: float, length: float, color: Color,
		stock_color: Color, muzzle_flash: bool, flash_alpha: float = 1.0) -> void:
	## 武器: 沿 angle 方向的枪身 + 枪托 + 可选枪口火光。3~6 个图元。
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var body_from: Vector2 = origin - dir * 3.0
	var body_to: Vector2 = origin + dir * length
	ci.draw_line(body_from + perp * 0.8, body_to + perp * 0.8, color, 2.2)
	ci.draw_line(body_from - perp * 0.8, body_from - dir * 3.0 - perp * 0.8, stock_color, 2.0)
	if muzzle_flash and flash_alpha > 0.01:
		muzzleFlash(ci, body_to + dir * 1.5, angle, flash_alpha)


static func muzzleFlash(ci: CanvasItem, at: Vector2, angle: float, alpha: float) -> void:
	## 枪口火光: 亮心圆 + 两条放射线,3 个图元,持续 0.08s 由调用方计时。
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var hot := Color(1.0, 0.92, 0.55, alpha)
	var warm := Color(1.0, 0.65, 0.20, alpha * 0.8)
	ci.draw_circle(at, 2.2, hot)
	ci.draw_line(at, at + dir * 5.0, warm, 1.6)
	ci.draw_line(at - perp * 2.0, at + perp * 2.0, warm, 1.2)


static func crossMark(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	## 医疗十字,2 个图元。
	ci.draw_rect(Rect2(center - Vector2(size, size * 0.34), Vector2(size * 2.0, size * 0.68)), color)
	ci.draw_rect(Rect2(center - Vector2(size * 0.34, size), Vector2(size * 0.68, size * 2.0)), color)


static func starMark(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	## 军官肩章星/金色小矩形,1 个图元。
	ci.draw_rect(Rect2(center - Vector2(size * 0.5, size * 0.3), Vector2(size, size * 0.6)), color)


static func _helmet_arc(center: Vector2, radius: float, facing_local: int) -> PackedVector2Array:
	## 头盔 = 上半圆多边形(9 点)。仅在 setup 时构建缓存,绘制帧不重复调用。
	var pts := PackedVector2Array()
	pts.append(center + Vector2(-radius - 0.5, 0.6))
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * (radius + 0.7))
	pts.append(center + Vector2(radius + 0.5, 0.6))
	if facing_local < 0:
		pts.append(center + Vector2(radius * 0.2, 1.4))
	return pts
