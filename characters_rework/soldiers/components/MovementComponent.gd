class_name ReworkMovementComponent
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 士兵移动 —— 重力、走向槽位 X、卡住检测与跳跃脱困、朝向管理。
##       槽位 X 由当前指令 + FormationComponent 偏移合成;速度受
##       RoleStrategy.movement_speed_mult() 与 can_move() 约束。
## 依赖: 宿主 SoldierBase(CharacterBody2D)、ReworkOrderComponent、
##       ReworkFormationComponent、RoleStrategy。
## 对外接口:
##   attach(host) / tick(delta) / target_x / is_moving()
## ---------------------------------------------------------------------------

const GRAVITY: float = 1500.0
const JUMP_VELOCITY: float = -540.0
const ACCEL: float = 1600.0
const ARRIVE_EPSILON: float = 6.0
const STUCK_TIME: float = 0.55
const ADVANCE_PUSH: float = 90.0

var target_x: float = 0.0
var moving: bool = false

var _host: Node = null
var _orders: ReworkOrderComponent = null
var _formation: ReworkFormationComponent = null
var _strategy: RoleStrategy = null
var _stuck_timer: float = 0.0
var _last_x: float = 0.0
var _jump_cd: float = 0.0


func attach(host: Node, orders: ReworkOrderComponent,
		formation: ReworkFormationComponent, strategy: RoleStrategy) -> void:
	_host = host
	_orders = orders
	_formation = formation
	_strategy = strategy
	_last_x = host.global_position.x
	target_x = host.global_position.x


func tick(delta: float) -> void:
	if _host == null:
		return
	_jump_cd = maxf(0.0, _jump_cd - delta)
	# 重力
	if not _host.is_on_floor():
		_host.velocity.y = minf(_host.velocity.y + GRAVITY * delta, 1400.0)
	# 槽位目标
	target_x = _compute_target_x()
	var base_speed: float = float(_host.get("base_speed"))
	var speed: float = base_speed * _strategy.movement_speed_mult()
	if not _strategy.can_move():
		speed = 0.0
	var dx: float = target_x - _host.global_position.x
	moving = absf(dx) > ARRIVE_EPSILON and speed > 0.0
	var desired: float = 0.0
	if moving:
		desired = signf(dx) * speed
		if absf(dx) < 16.0:
			desired *= absf(dx) / 16.0
	_host.velocity.x = move_toward(_host.velocity.x, desired, ACCEL * delta)
	# 朝向: 移动方向优先,否则面向锁定敌人
	var facing := int(_host.get("facing"))
	if absf(_host.velocity.x) > 12.0:
		facing = 1 if _host.velocity.x > 0.0 else -1
	elif _host.get("enemy") != null and is_instance_valid(_host.get("enemy")):
		var enemy: Node2D = _host.get("enemy")
		facing = 1 if enemy.global_position.x >= _host.global_position.x else -1
	_host.set("facing", facing)
	# 卡住检测: 想动却动不了 → 尝试跳跃脱困
	if moving and _host.is_on_floor():
		if absf(_host.global_position.x - _last_x) < 2.0 * delta * 60.0:
			_stuck_timer += delta
			if _stuck_timer >= STUCK_TIME and _jump_cd <= 0.0:
				_host.velocity.y = JUMP_VELOCITY
				_jump_cd = 0.9
				_stuck_timer = 0.0
		else:
			_stuck_timer = 0.0
	_last_x = _host.global_position.x


func is_moving() -> bool:
	return moving


func _compute_target_x() -> float:
	var dir: float = _orders.facing_dir
	var slot: Vector2 = _formation.offset_for(int(_host.get("slot_index")), dir)
	var anchor: float = _orders.anchor_x
	match _orders.order:
		&"follow":
			if _orders.leader != null and is_instance_valid(_orders.leader):
				anchor = _orders.leader.global_position.x
			return anchor + slot.x
		&"advance":
			if _orders.leader != null and is_instance_valid(_orders.leader):
				anchor = _orders.leader.global_position.x
			return anchor + ADVANCE_PUSH * dir + slot.x * 0.5
		&"hold":
			return _orders.hold_position.x + slot.x * 0.5
		&"focus":
			return _orders.focus_point.x + slot.x * 0.5
		_:
			return anchor + slot.x
