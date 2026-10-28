extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 医疗兵「战地医疗」—— 半径 150px 内友军回 35HP、自己回 20HP。
##       友军识别: group "allies"(现有 AllyAgent)与 "rework_soldiers"
##       (本重构士兵),duck-typed 调用 heal(amount)。
## 依赖: PlayerControllerV2.heal / get_tree()。
## 对外接口: 无(事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const RADIUS: float = 150.0
const ALLY_HEAL: int = 35
const SELF_HEAL: int = 20


func _on_event(event_name: StringName, payload: Dictionary) -> void:
	if event_name != &"skill_used":
		return
	if payload.get("handled", false):
		return
	_activate()
	consume_skill(payload)


func _activate() -> void:
	if controller == null:
		return
	var origin: Vector2 = controller.global_position
	for group_name in ["allies", "rework_soldiers"]:
		for member in get_tree().get_nodes_in_group(group_name):
			var node := member as Node2D
			if node == null or not is_instance_valid(node):
				continue
			if bool(node.get("is_dead")):
				continue
			if origin.distance_to(node.global_position) > RADIUS:
				continue
			if node.has_method("heal"):
				node.heal(ALLY_HEAL)
	controller.heal(SELF_HEAL)
	var bus := controller_bus()
	if bus != null and bus.has_signal("notify"):
		bus.notify.emit("战地医疗：周围队友恢复 35 HP")
