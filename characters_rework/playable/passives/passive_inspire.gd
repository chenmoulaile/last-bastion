extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 军官「鼓舞」—— 8 秒内全队(现有 AllyAgent / 本重构士兵)射速 +30%,
##       自身射速同步提升;恐惧免疫以控制免疫窗口近似(3s)。
## 依赖: group "allies" / "rework_soldiers" 的 inspire(duration) 方法
##       (与现有 LevelRunner 对 AllyAgent 的调用方式一致);
##       PlayerControllerV2.inspire / control_immune。
## 对外接口: 无(事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const DURATION: float = 8.0


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
	controller.inspire(DURATION)
	controller.set("control_immune", maxf(float(controller.get("control_immune")), 3.0))
	for group_name in ["allies", "rework_soldiers"]:
		for member in get_tree().get_nodes_in_group(group_name):
			var node := member as Node
			if node == null or not is_instance_valid(node):
				continue
			if bool(node.get("is_dead")):
				continue
			if node.has_method("inspire"):
				node.inspire(DURATION)
	var bus := controller_bus()
	if bus != null and bus.has_signal("notify"):
		bus.notify.emit("鼓舞：全队射速 +30%（8 秒）")
