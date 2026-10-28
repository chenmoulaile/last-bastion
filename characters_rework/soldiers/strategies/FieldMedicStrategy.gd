extends RoleStrategy
## ---------------------------------------------------------------------------
## 职责: 战地医疗兵策略 —— 不主动开火(除非敌人近身 ≤60px 自卫);
##       优先治疗 110px 内血量最低的友军(每 1.5s 脉冲 25HP,duck-typed
##       调用 heal());基础移速 ×1.1。
## 依赖: group "allies" / "rework_soldiers" / "player" 的 heal(amount) 方法。
## 对外接口: 覆写 movement_speed_mult / wants_to_fire / support_tick。
## ---------------------------------------------------------------------------

const SELF_DEFENSE_RANGE: float = 60.0
const HEAL_RANGE: float = 110.0
const HEAL_AMOUNT: int = 25
const HEAL_INTERVAL: float = 1.5
const HEAL_THRESHOLD: float = 0.999

var heal_cd: float = 0.0
var last_heal_target: Node = null


func movement_speed_mult() -> float:
	return 1.1


func wants_to_fire(enemy: Node2D) -> bool:
	## 仅在敌人近身时自卫开火。
	if enemy == null or host == null or not is_instance_valid(enemy):
		return false
	return host.global_position.distance_to(enemy.global_position) <= SELF_DEFENSE_RANGE


func support_tick(delta: float) -> void:
	heal_cd = maxf(0.0, heal_cd - delta)
	if heal_cd > 0.0:
		return
	var target := _lowest_ally()
	if target == null:
		return
	heal_cd = HEAL_INTERVAL
	last_heal_target = target
	if target.has_method("heal"):
		target.heal(HEAL_AMOUNT)
	if host != null and host.has_signal("soldier_state_changed"):
		host.soldier_state_changed.emit(&"healing", {"target": target})


func _lowest_ally() -> Node2D:
	if host == null:
		return null
	var origin: Vector2 = host.global_position
	var best: Node2D = null
	var best_ratio := HEAL_THRESHOLD
	# 友军: 现有 AllyAgent(allies 组)+ 本重构士兵 + 玩家
	var candidates: Array = []
	candidates.append_array(host.get_tree().get_nodes_in_group("allies"))
	candidates.append_array(host.get_tree().get_nodes_in_group("rework_soldiers"))
	candidates.append_array(host.get_tree().get_nodes_in_group("player"))
	for member in candidates:
		var node := member as Node2D
		if node == null or not is_instance_valid(node) or node == host:
			continue
		if bool(node.get("is_dead")) or bool(node.get("is_downed")):
			continue
		if origin.distance_to(node.global_position) > HEAL_RANGE:
			continue
		var hp_value := float(node.get("hp"))
		var max_value := maxf(1.0, float(node.get("max_hp")))
		var ratio := hp_value / max_value
		if ratio < best_ratio:
			best_ratio = ratio
			best = node
	return best
