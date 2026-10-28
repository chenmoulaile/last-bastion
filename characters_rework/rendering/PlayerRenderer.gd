class_name PlayerRenderer
extends CodeRenderer
## ---------------------------------------------------------------------------
## 职责: 可玩角色(6 名)的程序化绘制器。体型/配色/职业细节全部由
##       ReworkCharacterData 驱动;绘制帧内零分配、零角色分支(职业细节通过
##       setup 时缓存的 Callable 查表分派)。
## 依赖: rendering/CodeRenderer.gd、rendering/shapes.gd、data/CharacterData.gd。
## 对外接口:
##   setup(data: ReworkCharacterData) -> void   # 注入数据并缓存绘制参数
##   set_weapon_visual(kind: StringName, weapon_type: StringName)
##       kind: "gun" / "melee"(近战挥舞由 set_melee_swing 驱动)
##       weapon_type: "rifle"/"smg"/"shotgun"/"lmg"/"sniper"/"pistol"/
##                    "suppressed"/"katana"/"axe"/"baton"
##   其余状态接口继承 CodeRenderer(set_anim_state / set_facing / ...)。
## 图元预算: 阴影1 + 腿4 + 后臂1 + 躯干3 + 头3 + 前臂2 + 武器2~4 +
##           职业细节3~6 + 火光3 + 状态1 ≈ 23~30,满足 ≤40 要求。
## ---------------------------------------------------------------------------

const GEAR_CALLABLES: Dictionary = {
	&"assault": &"_gear_assault",
	&"heavy": &"_gear_heavy",
	&"medic": &"_gear_medic",
	&"scout": &"_gear_scout",
	&"operative": &"_gear_operative",
	&"officer": &"_gear_officer",
}

const HEAD_CALLABLES: Dictionary = {
	&"operative": &"_head_hood",
	&"officer": &"_head_cap",
	&"scout": &"_head_goggles",
}

var character_data: ReworkCharacterData = null
var visual_profile: StringName = &"assault"
var weapon_kind: StringName = &"gun"
var weapon_type: StringName = &"rifle"

var _gear_draw: Callable = Callable()
var _head_extra: Callable = Callable()


func setup(data: ReworkCharacterData) -> void:
	character_data = data
	if data == null:
		return
	visual_profile = data.visual_profile
	width_scale = data.body_width_scale
	height_scale = data.body_height_scale
	var palette: Dictionary = data.palette
	if palette.is_empty():
		palette = ReworkPalettes.for_id(data.id)
	apply_palette(palette)
	# 缓存分派 Callable: 绘制帧只 call(),不查字典、不创建闭包。
	var gear_name: StringName = GEAR_CALLABLES.get(visual_profile, &"")
	if gear_name != &"":
		_gear_draw = get(gear_name)
	var head_name: StringName = HEAD_CALLABLES.get(visual_profile, &"")
	if head_name != &"":
		_head_extra = get(head_name)


func set_weapon_visual(kind: StringName, type_id: StringName) -> void:
	weapon_kind = kind
	weapon_type = type_id


## ------------------------------------------------------------------ 绘制 ----

func _draw_body() -> void:
	# 分层顺序(镜像后的局部系): 后腿→后臂→躯干→头→前臂→武器→职业细节
	draw_legs()
	draw_back_arm()
	if visual_profile == &"heavy":
		_draw_back_shield()
	draw_torso()
	draw_head_base()
	if _head_extra.is_valid():
		_head_extra.call()
	draw_front_arm()
	_draw_weapon()
	if _gear_draw.is_valid():
		_gear_draw.call()


func _draw_weapon() -> void:
	var hand := pose_hand_front
	match weapon_kind:
		&"melee":
			_draw_melee(hand)
		_:
			ReworkShapes.gun(self, hand, pose_aim_local, _gun_length(), pal_weapon,
				pal_gear_dark, pose_flash > 0.0, pose_flash)


func _gun_length() -> float:
	match weapon_type:
		&"pistol":
			return 6.0
		&"smg":
			return 9.0
		&"shotgun":
			return 13.0
		&"lmg":
			return 13.0
		&"sniper":
			return 16.0
		&"suppressed":
			return 15.0
		_:
			return 11.0


func _draw_melee(hand: Vector2) -> void:
	## 近战: 挥舞进度 _melee_swing 0→1 驱动角度从 -100° 扫到 +40°。
	var swing_t: float = clampf(1.0 - _melee_swing, 0.0, 1.0)
	var angle: float = lerp_angle(deg_to_rad(-100.0), deg_to_rad(40.0), swing_t)
	if pose_aim_local != 0.0 and _melee_swing <= 0.0:
		angle = pose_aim_local
	match weapon_type:
		&"katana":
			var dir := Vector2(cos(angle), sin(angle))
			draw_line(hand, hand + dir * 15.0, Color(0.85, 0.88, 0.95), 1.4)
			draw_line(hand - dir * 1.5, hand + dir * 1.5, pal_gear_dark, 2.6)
		&"baton":
			var bdir := Vector2(cos(angle), sin(angle))
			draw_line(hand, hand + bdir * 8.0, pal_gear_dark, 2.0)
			draw_circle(hand + bdir * 8.0, 1.2, pal_accent)
		_: # axe
			var adir := Vector2(cos(angle), sin(angle))
			var perp := Vector2(-adir.y, adir.x)
			draw_line(hand, hand + adir * 11.0, pal_gear_dark, 1.8)
			draw_line(hand + adir * 8.0 - perp * 2.5, hand + adir * 12.0 + perp * 1.0,
				Color(0.8, 0.83, 0.88), 2.6)


func _draw_back_shield() -> void:
	## 重装兵: 背后防弹盾轮廓(2 图元,画在躯干之前=身后)。
	var hs := height_scale
	var top := Vector2(-6.5 * width_scale, (-25.0 + pose_bob) * hs)
	draw_rect(Rect2(top, Vector2(3.0 * width_scale, 19.0 * hs)), pal_gear_dark)
	draw_line(top + Vector2(1.5, 1.0), top + Vector2(1.5, 18.0 * hs), pal_accent, 0.8)


## ------------------------------------------------------------ 职业细节 ----

func _gear_assault() -> void:
	## 突击兵: 胸前斜挎弹链 + 短枪管已在 _gun_length 体现。
	var hs := height_scale
	var chest := Vector2(pose_lean, (-22.0 + pose_bob) * hs)
	draw_line(chest + Vector2(-4.0, 0.0), chest + Vector2(4.0, 6.0 * hs), pal_gear_dark, 1.6)
	draw_circle(chest + Vector2(4.0, 6.0 * hs), 1.0, pal_accent)
	draw_circle(chest + Vector2(0.0, 3.0 * hs), 0.9, pal_accent)


func _gear_heavy() -> void:
	## 重装兵: 肩甲两块 + 胸前橙色条。
	var hs := height_scale
	var ws := width_scale
	var sh := Vector2(pose_lean, (-24.0 + pose_bob) * hs)
	draw_rect(Rect2(sh + Vector2(-6.4 * ws, -0.5), Vector2(3.4 * ws, 3.0)), pal_gear_dark)
	draw_rect(Rect2(sh + Vector2(3.0 * ws, -0.5), Vector2(3.4 * ws, 3.0)), pal_gear_dark)
	draw_line(sh + Vector2(-3.0, 4.0), sh + Vector2(3.0, 4.0), pal_accent, 1.2)


func _gear_medic() -> void:
	## 医疗兵: 袖口红十字 + 腰挂药包。
	var hs := height_scale
	ReworkShapes.crossMark(self, pose_hand_front + Vector2(0.0, -2.2), 1.6, pal_accent)
	var pouch := Vector2(-3.0 * width_scale, (-15.5 + pose_bob * 0.5) * hs)
	draw_rect(Rect2(pouch, Vector2(4.0, 3.4)), pal_gear)
	ReworkShapes.crossMark(self, pouch + Vector2(2.0, 1.7), 1.1, Color(0.92, 0.3, 0.3))


func _gear_scout() -> void:
	## 侦察兵: 背后短刀(刀柄露出右肩后)。
	var hs := height_scale
	var back := Vector2(-4.5 * width_scale, (-23.0 + pose_bob) * hs)
	draw_line(back, back + Vector2(-2.0, -5.0), pal_gear_dark, 1.6)
	draw_circle(back + Vector2(-2.0, -5.0), 0.9, pal_accent)


func _gear_operative() -> void:
	## 特勤: 胸前战术挂带 + 腰间飞刀。
	var hs := height_scale
	var chest := Vector2(pose_lean, (-21.0 + pose_bob) * hs)
	draw_line(chest + Vector2(-3.5, -1.0), chest + Vector2(3.5, 5.0 * hs), Color(0.35, 0.3, 0.45), 1.4)
	draw_rect(Rect2(chest + Vector2(3.6 * width_scale, 4.0), Vector2(1.2, 3.2)), Color(0.8, 0.82, 0.9))


func _gear_officer() -> void:
	## 军官: 双肩章金星 + 皮手套强调色。
	var hs := height_scale
	var ws := width_scale
	var sh := Vector2(pose_lean, (-24.5 + pose_bob) * hs)
	ReworkShapes.starMark(self, sh + Vector2(-4.6 * ws, 0.4), 2.2, pal_accent)
	ReworkShapes.starMark(self, sh + Vector2(4.6 * ws, 0.4), 2.2, pal_accent)
	draw_circle(pose_hand_front, 1.7 * ws, pal_gear_dark)


## ---------------------------------------------------------- 头部变体 ----

func _head_hood() -> void:
	## 特勤兜帽: 覆盖头盔的尖顶多边形(写入预分配缓存)+ 面罩反光条。
	var r := HEAD_R * minf(width_scale, height_scale) + 1.4
	var c := pose_head_c
	_poly_pts[0] = c + Vector2(-r, 1.2)
	_poly_pts[1] = c + Vector2(-r * 0.7, -r * 0.9)
	_poly_pts[2] = c + Vector2(-r * 0.1, -r * 1.5)
	_poly_pts[3] = c + Vector2(r * 0.75, -r * 0.8)
	_poly_pts[4] = c + Vector2(r, 1.2)
	_poly_pts[5] = c + Vector2(r * 0.3, 0.2)
	for i in range(6, 12):
		_poly_pts[i] = _poly_pts[5]
	for i in 12:
		_poly_cols[i] = pal_secondary
	draw_polygon(_poly_pts, _poly_cols)
	draw_rect(Rect2(c + Vector2(-0.5, -1.2), Vector2(4.0, 1.3)), pal_visor)


func _head_cap() -> void:
	## 军官大檐帽: 帽檐前伸 + 帽墙金线。
	var r := HEAD_R * minf(width_scale, height_scale)
	var c := pose_head_c
	draw_rect(Rect2(c + Vector2(-r - 0.5, -r * 0.55), Vector2(r * 2.0 + 3.5, 1.8)), pal_gear_dark)
	draw_line(c + Vector2(-r, -r * 0.55 - 0.6), c + Vector2(r + 2.6, -r * 0.55 - 0.6), pal_accent, 0.8)


func _head_goggles() -> void:
	## 侦察兵护目镜高光: 推到额头的镜片 + 反光点。
	var r := HEAD_R * minf(width_scale, height_scale)
	var c := pose_head_c
	draw_rect(Rect2(c + Vector2(-r * 0.4, -r - 1.6), Vector2(r * 1.5, 2.0)), pal_visor * 0.8)
	draw_circle(c + Vector2(r * 0.5, -r - 0.6), 0.7, Color(1, 1, 1, 0.85))
