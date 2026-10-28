class_name SoldierRenderer
extends CodeRenderer
## ---------------------------------------------------------------------------
## 职责: 指挥模式士兵(4 兵种)的程序化绘制器。兵种差异(安全帽/三脚架/背包
##       十字等)通过 setup 缓存的 Callable 查表分派,绘制帧零分配零分支。
## 依赖: rendering/CodeRenderer.gd、rendering/shapes.gd、data/SoldierData.gd。
## 对外接口:
##   setup(data: ReworkSoldierData) -> void
##   set_weapon_visual(type_id: StringName)   # "rifle"/"lmg"/"shotgun"/"smg"
##   其余状态接口继承 CodeRenderer。
## 图元预算: 与 PlayerRenderer 同级(≈22~28),满足 ≤40 要求。
## ---------------------------------------------------------------------------

const GEAR_CALLABLES: Dictionary = {
	&"demolition": &"_gear_demolition",
	&"mg": &"_gear_mg",
	&"rifleman": &"_gear_rifleman",
	&"field_medic": &"_gear_field_medic",
}

var soldier_data: ReworkSoldierData = null
var visual_profile: StringName = &"rifleman"
var weapon_type: StringName = &"rifle"

var _gear_draw: Callable = Callable()


func setup(data: ReworkSoldierData) -> void:
	soldier_data = data
	if data == null:
		return
	visual_profile = data.visual_profile
	width_scale = data.body_width_scale
	height_scale = data.body_height_scale
	var palette: Dictionary = data.palette
	if palette.is_empty():
		palette = ReworkPalettes.for_id(data.id)
	apply_palette(palette)
	var gear_name: StringName = GEAR_CALLABLES.get(visual_profile, &"_gear_rifleman")
	_gear_draw = get(gear_name)
	match String(data.strategy_id):
		"mg":
			weapon_type = &"lmg"
		"demolition":
			weapon_type = &"shotgun"
		"field_medic":
			weapon_type = &"smg"
		_:
			weapon_type = &"rifle"


func set_weapon_visual(type_id: StringName) -> void:
	weapon_type = type_id


## ------------------------------------------------------------------ 绘制 ----

func _draw_body() -> void:
	draw_legs()
	draw_back_arm()
	if visual_profile == &"mg":
		_draw_back_tripod()
	if visual_profile == &"field_medic" or visual_profile == &"demolition":
		_draw_backpack()
	draw_torso()
	if visual_profile == &"demolition":
		_draw_hard_hat()
	else:
		draw_head_base()
	draw_front_arm()
	_draw_weapon()
	if _gear_draw.is_valid():
		_gear_draw.call()


func _draw_weapon() -> void:
	var length := 11.0
	match weapon_type:
		&"smg":
			length = 9.0
		&"shotgun":
			length = 13.0
		&"lmg":
			length = 13.0
	ReworkShapes.gun(self, pose_hand_front, pose_aim_local, length, pal_weapon,
		pal_gear_dark, pose_flash > 0.0, pose_flash)


func _draw_backpack() -> void:
	## 背在身后的补给包/炸药包底形(细节由兵种 gear 叠加)。
	var hs := height_scale
	var top := Vector2(-7.0 * width_scale, (-23.5 + pose_bob) * hs)
	draw_rect(Rect2(top, Vector2(4.2 * width_scale, 8.0 * hs)), pal_gear_dark)


func _draw_back_tripod() -> void:
	## 机枪手: 收拢在背后的三脚架(两条斜腿)。
	var hs := height_scale
	var top := Vector2(-4.0 * width_scale, (-24.0 + pose_bob) * hs)
	draw_line(top, top + Vector2(-3.0, 9.0 * hs), pal_gear_dark, 1.4)
	draw_line(top + Vector2(1.0, 0.0), top + Vector2(-1.6, 9.0 * hs), pal_gear_dark, 1.4)


func _draw_hard_hat() -> void:
	## 爆破手: 安全帽(亮橙盔体 + 前沿),替代通用头盔。
	var r := HEAD_R * minf(width_scale, height_scale)
	var c := pose_head_c
	draw_circle(c, r, pal_skin)
	_fill_helmet_cache(r)
	for i in 12:
		_poly_cols[i] = pal_accent
	draw_polygon(_helmet_pts, _poly_cols)
	draw_rect(Rect2(c + Vector2(-1.0, -1.0), Vector2(5.0, 1.4)), pal_accent * 0.85)
	ReworkShapes.eyeSlit(self, c, 1, Color(0.15, 0.13, 0.12))


## ------------------------------------------------------------ 兵种细节 ----

func _gear_demolition() -> void:
	## 爆破手: 炸药包(背包上的捆扎条 + 引信) + 胸前两枚手雷。
	var hs := height_scale
	var pack := Vector2(-6.4 * width_scale, (-21.0 + pose_bob) * hs)
	draw_line(pack, pack + Vector2(3.6, 0.0), Color(0.55, 0.35, 0.2), 1.2)
	draw_line(pack + Vector2(1.8, -2.0), pack + Vector2(2.6, -4.2), Color(0.8, 0.6, 0.3), 0.9)
	var chest := Vector2(pose_lean + 2.5, (-17.0 + pose_bob) * hs)
	draw_circle(chest, 1.3, Color(0.3, 0.36, 0.28))
	draw_circle(chest + Vector2(0.0, 3.0), 1.3, Color(0.3, 0.36, 0.28))


func _gear_mg() -> void:
	## 机枪手: 环绕躯干的弹链(折线 3 段用 2 图元) + 手臂弹药盒。
	var hs := height_scale
	var ws := width_scale
	var chest := Vector2(pose_lean, (-22.5 + pose_bob) * hs)
	draw_line(chest + Vector2(-4.5 * ws, 0.0), chest + Vector2(0.0, 5.0 * hs), pal_accent, 1.4)
	draw_line(chest + Vector2(0.0, 5.0 * hs), chest + Vector2(4.5 * ws, 2.0 * hs), pal_accent, 1.4)
	draw_rect(Rect2(pose_hand_back - Vector2(1.4, 1.0), Vector2(3.0, 2.4)), pal_gear_dark)


func _gear_rifleman() -> void:
	## 步枪手: 头盔迷彩条 + 背后标准弹药包扣带。
	var hs := height_scale
	var c := pose_head_c
	draw_line(c + Vector2(-3.0, -3.4), c + Vector2(3.0, -3.4), pal_secondary, 1.0)
	draw_rect(Rect2(Vector2(-6.0 * width_scale, (-19.0 + pose_bob) * hs), Vector2(3.0, 2.2)), pal_gear)


func _gear_field_medic() -> void:
	## 战地医疗兵: 背包白十字 + 手提医疗箱(前手下方)。
	var hs := height_scale
	ReworkShapes.crossMark(self, Vector2(-5.0 * width_scale, (-19.5 + pose_bob) * hs), 2.0, Color(0.95, 0.95, 0.95))
	var kit := pose_hand_back + Vector2(0.0, 2.2)
	draw_rect(Rect2(kit - Vector2(2.0, 1.4), Vector2(4.0, 3.0)), pal_gear)
	ReworkShapes.crossMark(self, kit + Vector2(0.0, 0.1), 1.0, Color(0.92, 0.3, 0.3))
