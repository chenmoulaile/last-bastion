extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 侦察兵「战术翻滚」—— 0.25 秒无敌 + 向输入方向位移约 200px
##       (实现为 800px/s × 0.25s 的速度脉冲,由控制器物理积分完成位移)。
## 依赖: PlayerControllerV2.grant_iframes / velocity / facing。
## 对外接口: 无(事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const IFRAMES: float = 0.25
const DASH_SPEED: float = 800.0


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
	var direction := Vector2.RIGHT
	if InputMap.has_action("move_left") and Input.is_action_pressed("move_left"):
		direction = Vector2.LEFT
	elif InputMap.has_action("move_right") and Input.is_action_pressed("move_right"):
		direction = Vector2.RIGHT
	else:
		direction = Vector2(float(int(controller.get("facing"))), 0.0)
	controller.grant_iframes(IFRAMES, passive_id)
	var vel: Vector2 = controller.get("velocity")
	controller.set("velocity", Vector2(direction.x * DASH_SPEED, minf(vel.y, -120.0)))
	controller.set("is_sliding", false)
