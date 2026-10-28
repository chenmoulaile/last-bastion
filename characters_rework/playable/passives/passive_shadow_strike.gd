extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 特勤「影袭」—— 瞬步至 250px 内最近普通感染者背后并重击;
##       目标剩余血量 ≤30 时直接处决(秒杀)。
## 依赖: group "zombies"(现有 ZombieBase 加入该组)、apply_damage 契约、
##       PlayerControllerV2.teleport_to / grant_iframes。
## 对外接口: 无(事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const RANGE: float = 250.0
const STRIKE_DAMAGE: int = 120
const EXECUTE_THRESHOLD: int = 30
const IFRAMES: float = 0.3


func _on_event(event_name: StringName, payload: Dictionary) -> void:
	if event_name != &"skill_used":
		return
	if payload.get("handled", false):
		return
	var target := _find_nearest_target()
	if target == null:
		return # 无目标: 不消费技能、不进冷却
	_strike(target)
	consume_skill(payload)


func _find_nearest_target() -> Node2D:
	if controller == null:
		return null
	var origin: Vector2 = controller.global_position
	var best: Node2D = null
	var best_dist := RANGE
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("dead")) or bool(node.get("is_dead")):
			continue
		var data: Variant = node.get("data")
		if data != null and bool(data.get("is_boss")):
			continue # Tank/Witch 免疫影袭处决,保持 Boss 威胁定位
		var dist := origin.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func _strike(target: Node2D) -> void:
	if controller == null:
		return
	var behind := Vector2(target.global_position.x - 26.0 * _side_to(target),
		target.global_position.y)
	controller.teleport_to(behind)
	controller.grant_iframes(IFRAMES, passive_id)
	controller.set("facing", _side_to(target))
	var remaining: int = int(target.get("hp"))
	var damage: int = 9999 if remaining <= EXECUTE_THRESHOLD else STRIKE_DAMAGE
	if target.has_method("apply_damage"):
		target.apply_damage(damage, Vector2(float(_side_to(target)), 0.0), false,
			&"player", &"melee")
	var bus := controller_bus()
	if bus != null and bus.has_signal("notify"):
		bus.notify.emit("影袭！" if remaining > EXECUTE_THRESHOLD else "影袭 · 处决！")


func _side_to(target: Node2D) -> int:
	var dx: float = target.global_position.x - controller.global_position.x
	return 1 if dx >= 0.0 else -1
