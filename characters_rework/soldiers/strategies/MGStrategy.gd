extends RoleStrategy
## ---------------------------------------------------------------------------
## 职责: 机枪手策略 —— 持续压制射击;基础移速 ×0.6;需 0.8s 架枪才能开火,
##       开火期间不可移动(定身);对被压制(suppressed)目标伤害 ×1.2。
##       压制状态记录在目标节点的 "rework_suppressed" 元数据上(带时间戳)。
## 依赖: SoldierBase / RoleStrategy 钩子。
## 对外接口: 覆写 movement_speed_mult / can_move / can_fire / think /
##           fire_interval_mult / damage_multiplier。
## ---------------------------------------------------------------------------

const SETUP_TIME: float = 0.8
const SUPPRESS_WINDOW: float = 2.0
const SUPPRESS_DAMAGE_MULT: float = 1.2
const MOVE_EPSILON: float = 6.0

var deployed: bool = false
var setup_progress: float = 0.0
var firing: bool = false
var last_target: Node2D = null


func movement_speed_mult() -> float:
	return 0.6


func can_move() -> bool:
	## 规格: 开火时不可移动;架枪完成后同样定身(收枪需要停止移动 0.3s)。
	return not (deployed or firing)


func can_fire() -> bool:
	return deployed


func fire_interval_mult() -> float:
	return 1.0


func damage_multiplier(target: Node2D) -> float:
	if target == null:
		return 1.0
	return SUPPRESS_DAMAGE_MULT if is_suppressed(target) else 1.0


func think(delta: float) -> void:
	if host == null:
		return
	var moving: bool = absf(float(host.velocity.x)) > MOVE_EPSILON
	if deployed:
		if moving:
			# 移动即收枪
			deployed = false
			setup_progress = 0.0
		else:
			setup_progress = SETUP_TIME
	else:
		if moving:
			setup_progress = maxf(0.0, setup_progress - delta * 2.0)
		else:
			setup_progress += delta
			if setup_progress >= SETUP_TIME:
				deployed = true
				if host.has_signal("soldier_state_changed"):
					host.soldier_state_changed.emit(&"mg_deployed", {})
	if firing and last_target != null and is_instance_valid(last_target):
		_mark_suppressed(last_target)


func note_firing(target: Node2D) -> void:
	## CombatComponent 开火时调用,记录压制目标。
	firing = target != null
	last_target = target
	if target != null and is_instance_valid(target):
		_mark_suppressed(target)


static func is_suppressed(target: Node2D) -> bool:
	if not target.has_meta("rework_suppressed"):
		return false
	var until: float = float(target.get_meta("rework_suppressed"))
	return Time.get_ticks_msec() / 1000.0 < until


static func _mark_suppressed(target: Node2D) -> void:
	target.set_meta("rework_suppressed", Time.get_ticks_msec() / 1000.0 + SUPPRESS_WINDOW)
