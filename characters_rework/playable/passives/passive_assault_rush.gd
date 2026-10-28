extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 突击兵「突击冲锋」—— 激活后 4 秒内换弹速度 ×2、移速 +20%。
## 依赖: PlayerControllerV2 的修正器 API(add_speed_modifier 等)。
## 对外接口: 无(纯事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const DURATION: float = 4.0
const SPEED_MULT: float = 1.2
const RELOAD_MULT: float = 2.0


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
	controller.add_speed_modifier(passive_id, SPEED_MULT)
	controller.add_reload_modifier(passive_id, RELOAD_MULT)
	get_tree().create_timer(DURATION).timeout.connect(_deactivate)


func _deactivate() -> void:
	if controller == null or not is_instance_valid(controller):
		return
	controller.remove_speed_modifier(passive_id)
	controller.remove_reload_modifier(passive_id)
