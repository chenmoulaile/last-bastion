class_name CodeRenderer
extends Node2D
## ---------------------------------------------------------------------------
## 职责: 代码绘制角色渲染基类。维护动画时钟与 IDLE/WALK/ATTACK 三态混合,
##       每帧把姿态参数预计算进成员变量,_draw() 中零分配(无 Array/Dict/闭包
##       创建;多边形顶点写入预分配的 PackedVector2Array)。
## 依赖: 仅 Godot CanvasItem API。不依赖工程任何现有脚本,可独立运行。
## 对外接口(控制器调用):
##   set_anim_state(state: StringName)   # STATE_IDLE / STATE_WALK / STATE_ATTACK
##   set_facing(dir: int)                # 1 / -1,经 draw_set_transform 镜像,
##                                       #   不使用 scale.x = -1(保护碰撞调试)
##   set_aim_angle(world_angle: float)   # 武器指向(世界弧度)
##   trigger_muzzle_flash()              # 枪口火光 0.08s
##   set_melee_swing(t: float)           # 0..1 近战挥舞进度
##   set_health_ratio(r) / set_downed(b) / set_dead(b)
## 子类契约: 实现 _draw_body() 与 _draw_gear();可覆写 _setup_profile()。
## 坐标系: 原点在脚底中心,身体向 -y 生长,总高约 32px,头身比 1:4。
## 分层顺序: 阴影 → 后腿 → 后臂 → 躯干 → 头 → 前臂 → 武器 → 火光/特效 → 状态。
## ---------------------------------------------------------------------------

const STATE_IDLE: StringName = &"idle"
const STATE_WALK: StringName = &"walk"
const STATE_ATTACK: StringName = &"attack"

const FLASH_TIME: float = 0.08
const ATTACK_HOLD: float = 0.18
const BODY_BLEND: float = 12.0
const LOW_HP_BLINK_HZ: float = 6.0

## 骨架基准(单位 px,未乘体型缩放)
const HEAD_R: float = 4.0
const SHOULDER_Y: float = -24.0
const HIP_Y: float = -15.0
const LEG_LEN: float = 15.0

var anim_time: float = 0.0
var anim_state: StringName = STATE_IDLE
var facing: int = 1
var aim_angle: float = 0.0
var health_ratio: float = 1.0
var is_downed: bool = false
var is_dead: bool = false

var width_scale: float = 1.0
var height_scale: float = 1.0

## --- 每帧预计算的姿态参数(_draw 只读) ---
var w_idle: float = 1.0
var w_walk: float = 0.0
var w_attack: float = 0.0
var pose_bob: float = 0.0
var pose_lean: float = 0.0
var pose_leg_a: float = 0.0
var pose_leg_b: float = 0.0
var pose_arm_back: float = 0.0
var pose_recoil: float = 0.0
var pose_flash: float = 0.0
var pose_aim_local: float = 0.0
var pose_shoulder: Vector2 = Vector2.ZERO
var pose_hand_front: Vector2 = Vector2.ZERO
var pose_hand_back: Vector2 = Vector2.ZERO
var pose_knee_a: Vector2 = Vector2.ZERO
var pose_foot_a: Vector2 = Vector2.ZERO
var pose_knee_b: Vector2 = Vector2.ZERO
var pose_foot_b: Vector2 = Vector2.ZERO
var pose_head_c: Vector2 = Vector2.ZERO
var pose_alpha: float = 1.0

## --- 缓存(禁止在 _draw 中重建) ---
var pal_primary: Color = Color.WHITE
var pal_secondary: Color = Color.WHITE
var pal_skin: Color = Color.WHITE
var pal_weapon: Color = Color.WHITE
var pal_accent: Color = Color.WHITE
var pal_gear: Color = Color.WHITE
var pal_visor: Color = Color.WHITE
var pal_primary_dark: Color = Color.WHITE
var pal_gear_dark: Color = Color.WHITE

var _shadow_pts := PackedVector2Array()
var _shadow_cols := PackedColorArray()
var _poly_pts := PackedVector2Array()
var _poly_cols := PackedColorArray()
var _helmet_pts := PackedVector2Array()
var _flash_timer: float = 0.0
var _attack_timer: float = 0.0
var _melee_swing: float = 0.0


func _ready() -> void:
	_shadow_pts.resize(8)
	_shadow_cols.resize(8)
	_poly_pts.resize(12)
	_poly_cols.resize(12)
	_helmet_pts.resize(12)
	_setup_profile()
	set_process(true)


func _process(delta: float) -> void:
	anim_time += delta
	_flash_timer = maxf(0.0, _flash_timer - delta)
	_melee_swing = maxf(0.0, _melee_swing - delta * 4.0)
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0 and anim_state == STATE_ATTACK:
			anim_state = STATE_IDLE
	_update_pose(delta)
	queue_redraw()


## ------------------------------------------------------------------ API ----

func set_anim_state(state: StringName) -> void:
	if state == anim_state:
		return
	anim_state = state
	if state == STATE_ATTACK:
		_attack_timer = ATTACK_HOLD


func set_facing(dir: int) -> void:
	facing = 1 if dir >= 0 else -1


func set_aim_angle(world_angle: float) -> void:
	aim_angle = world_angle


func trigger_muzzle_flash() -> void:
	_flash_timer = FLASH_TIME
	set_anim_state(STATE_ATTACK)


func set_melee_swing(t: float) -> void:
	_melee_swing = clampf(t, 0.0, 1.0)


func set_health_ratio(ratio: float) -> void:
	health_ratio = clampf(ratio, 0.0, 1.0)


func set_downed(value: bool) -> void:
	is_downed = value


func set_dead(value: bool) -> void:
	is_dead = value


func apply_palette(palette: Dictionary) -> void:
	pal_primary = _color_of(palette, "body_primary", Color(0.3, 0.35, 0.3))
	pal_secondary = _color_of(palette, "body_secondary", Color(0.2, 0.23, 0.2))
	pal_skin = _color_of(palette, "skin", Color(0.76, 0.58, 0.44))
	pal_weapon = _color_of(palette, "weapon", Color(0.18, 0.19, 0.22))
	pal_accent = _color_of(palette, "accent", Color(0.8, 0.8, 0.8))
	pal_gear = _color_of(palette, "gear", Color(0.26, 0.28, 0.26))
	pal_visor = _color_of(palette, "visor", Color(0.6, 0.75, 0.85))
	pal_primary_dark = pal_primary * 0.72
	pal_primary_dark.a = 1.0
	pal_gear_dark = pal_gear * 0.72
	pal_gear_dark.a = 1.0


## -------------------------------------------------------------- 姿态计算 ----

func _update_pose(delta: float) -> void:
	var t_idle := 1.0 if anim_state == STATE_IDLE else 0.0
	var t_walk := 1.0 if anim_state == STATE_WALK else 0.0
	var t_attack := 1.0 if anim_state == STATE_ATTACK else 0.0
	w_idle = lerpf(w_idle, t_idle, minf(1.0, BODY_BLEND * delta))
	w_walk = lerpf(w_walk, t_walk, minf(1.0, BODY_BLEND * delta))
	w_attack = lerpf(w_attack, t_attack, minf(1.0, BODY_BLEND * delta))

	var phase := anim_time * 9.0
	var leg_swing: float = sin(phase) * 5.0 * w_walk
	pose_leg_a = leg_swing
	pose_leg_b = -leg_swing
	pose_arm_back = -sin(phase) * 4.0 * w_walk
	pose_bob = sin(anim_time * 2.2) * 0.5 * w_idle + absf(sin(phase)) * 1.0 * w_walk
	pose_lean = 1.2 * w_walk + 2.0 * w_attack
	pose_recoil = -2.5 * w_attack
	pose_flash = _flash_timer / FLASH_TIME
	pose_aim_local = aim_angle if facing > 0 else atan2(sin(aim_angle), -cos(aim_angle))

	var hs := height_scale
	var ws := width_scale
	pose_shoulder = Vector2(pose_lean * facing, SHOULDER_Y * hs + pose_bob)
	# 前臂手位: 空闲垂放 → 攻击/瞄准时伸向 aim_local
	var rest_hand := Vector2(facing * 4.0 * ws, HIP_Y * hs - 1.0)
	var aim_vec := Vector2(cos(pose_aim_local), sin(pose_aim_local))
	var aim_hand := Vector2(0, SHOULDER_Y * hs + 2.0 + pose_bob) + aim_vec * (11.0 * ws) + Vector2(pose_recoil, 0)
	var aim_blend: float = 0.35 if anim_state == STATE_WALK else 0.0
	pose_hand_front = rest_hand.lerp(aim_hand, clampf(w_attack + aim_blend, 0.0, 1.0))
	pose_hand_back = Vector2(-facing * 2.0 * ws + pose_arm_back, HIP_Y * hs - 1.0 + pose_bob * 0.5)

	var hip := Vector2(0.0, HIP_Y * hs + pose_bob * 0.5)
	_solve_leg(hip, pose_leg_a, true)
	_solve_leg(hip, pose_leg_b, false)
	pose_head_c = Vector2(pose_lean * 0.6 * facing, (-28.0 + pose_bob * 0.5) * hs)
	pose_alpha = 0.25 if is_dead else 1.0


func _solve_leg(hip: Vector2, swing_deg: float, front: bool) -> void:
	var hs := height_scale
	var knee: Vector2 = hip + Vector2(swing_deg * 0.55 * facing, 7.5 * hs)
	var foot: Vector2 = knee + Vector2(swing_deg * 0.75 * facing, (LEG_LEN - 7.5) * hs)
	foot.y = minf(foot.y, -0.5) # 脚不陷入地面
	if front:
		pose_knee_a = knee
		pose_foot_a = foot
	else:
		pose_knee_b = knee
		pose_foot_b = foot


## ---------------------------------------------------------------- 绘制 ----

func _draw() -> void:
	# 世界系: 地面阴影
	_draw_shadow()
	# 局部系: 镜像(禁用 scale.x=-1,只用绘制变换) + 倒地旋转
	var mirror_scale := Vector2(float(facing), 1.0)
	if is_downed:
		# 顺时针 90° 后镜像: 旋转 +90° 再以 (1, facing) 缩放等价于 mirror * prone。
		draw_set_transform(Vector2(10.0 * facing, 0.0), PI * 0.5, Vector2(1.0, float(facing)))
	else:
		draw_set_transform(Vector2.ZERO, 0.0, mirror_scale)
	_draw_body()
	_draw_status_overlay()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_shadow() -> void:
	if is_dead:
		return
	var radius := Vector2(9.0 * width_scale, 2.6)
	var alpha := 0.22 if not is_downed else 0.14
	for i in 8:
		var a := TAU * float(i) / 8.0
		_shadow_pts[i] = Vector2(cos(a) * radius.x, -0.5 + sin(a) * radius.y)
		_shadow_cols[i] = Color(0.0, 0.0, 0.0, alpha)
	draw_polygon(_shadow_pts, _shadow_cols)


func _draw_status_overlay() -> void:
	## 状态图标层: 低血量红闪 / 死亡淡出。绘制在局部系顶层。
	if is_dead:
		return
	if health_ratio < 0.3:
		var blink := 0.5 + 0.5 * sin(anim_time * TAU * LOW_HP_BLINK_HZ)
		var tint := Color(1.0, 0.15, 0.1, 0.16 + 0.14 * blink)
		var hs := height_scale
		draw_rect(Rect2(Vector2(-7.0 * width_scale, -33.0 * hs), Vector2(14.0 * width_scale, 33.0 * hs)), tint)


## ------------------------------------------------------- 子类共享图元 ----

func draw_legs() -> void:
	# 后腿(暗) → 靴 → 前腿(亮) → 靴,共 6 图元
	ReworkShapes.capsuleLimb(self, Vector2(0, HIP_Y * height_scale), pose_knee_b, 3.2 * width_scale, pal_primary_dark)
	ReworkShapes.capsuleLimb(self, pose_knee_b, pose_foot_b, 2.8 * width_scale, pal_gear_dark)
	ReworkShapes.capsuleLimb(self, Vector2(0, HIP_Y * height_scale + pose_bob * 0.5), pose_knee_a, 3.4 * width_scale, pal_secondary)
	ReworkShapes.capsuleLimb(self, pose_knee_a, pose_foot_a, 3.0 * width_scale, pal_gear)


func draw_torso() -> void:
	var hs := height_scale
	var ws := width_scale
	var top := Vector2(pose_lean, SHOULDER_Y * hs + pose_bob)
	var torso_h: float = (HIP_Y - SHOULDER_Y + 1.0) * hs
	ReworkShapes.torso(self, top, 5.0 * ws, torso_h, pal_primary, pal_secondary)
	# 腰带
	draw_rect(Rect2(top + Vector2(-5.0 * ws, torso_h - 1.6), Vector2(10.0 * ws, 1.6)), pal_gear_dark)


func draw_head_base() -> void:
	## 通用头部: 皮肤 + 头盔弧(缓存多边形) + 眼睛缝,3 图元。
	var r := HEAD_R * minf(width_scale, height_scale)
	draw_circle(pose_head_c, r, pal_skin)
	_fill_helmet_cache(r)
	draw_polygon(_helmet_pts, _poly_cols)
	ReworkShapes.eyeSlit(self, pose_head_c, 1, pal_visor)


func draw_front_arm() -> void:
	ReworkShapes.capsuleLimb(self, pose_shoulder + Vector2(1.5, 1.0), pose_hand_front, 2.8 * width_scale, pal_primary)
	draw_circle(pose_hand_front, 1.5 * width_scale, pal_skin)


func draw_back_arm() -> void:
	ReworkShapes.capsuleLimb(self, pose_shoulder + Vector2(-2.0, 1.0), pose_hand_back, 2.6 * width_scale, pal_primary_dark)


func _fill_helmet_cache(radius: float) -> void:
	## 把头盔弧多边形写入预分配缓存(12 点上限),避免 _draw 分配。
	var n: int = 0
	_helmet_pts[n] = pose_head_c + Vector2(-radius - 0.5, 0.6)
	n += 1
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		_helmet_pts[n] = pose_head_c + Vector2(cos(a), sin(a)) * (radius + 0.7)
		n += 1
	_helmet_pts[n] = pose_head_c + Vector2(radius + 0.5, 0.6)
	n += 1
	for i in range(n, 12):
		_helmet_pts[i] = _helmet_pts[n - 1]
	_poly_cols[0] = pal_gear
	for i in range(1, 12):
		_poly_cols[i] = _poly_cols[0]
	_poly_pts = _helmet_pts # 语义别名,便于子类复用


func _color_of(palette: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = palette.get(key, fallback)
	if value is Color:
		return value
	return fallback


## ------------------------------------------------------------- 子类契约 ----

func _setup_profile() -> void:
	pass


func _draw_body() -> void:
	pass


func _draw_gear() -> void:
	pass
