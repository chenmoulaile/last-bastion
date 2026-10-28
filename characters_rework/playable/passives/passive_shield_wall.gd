extends PassiveBase
## ---------------------------------------------------------------------------
## 职责: 重装兵「盾墙」—— 激活后 5 秒内正面减伤 70%、近战伤害 ×2。
##       正面判定由控制器 take_damage 的 frontal_guard 修正器完成
##       (攻击方向与面朝相反时取最小 guard 系数)。
## 依赖: PlayerControllerV2.add_frontal_guard / add_damage_modifier。
## 对外接口: 无(事件驱动,监听 "skill_used")。
## ---------------------------------------------------------------------------

const DURATION: float = 5.0
const FRONTAL_DAMAGE_MULT: float = 0.3
const MELEE_DAMAGE_MULT: float = 2.0


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
	controller.add_frontal_guard(passive_id, FRONTAL_DAMAGE_MULT)
	controller.add_damage_modifier(passive_id, MELEE_DAMAGE_MULT)
	controller.set("shield_wall_timer", DURATION) # 兼容 HUD 的盾墙计时显示
	get_tree().create_timer(DURATION).timeout.connect(_deactivate)


func _deactivate() -> void:
	if controller == null or not is_instance_valid(controller):
		return
	controller.remove_frontal_guard(passive_id)
	controller.remove_damage_modifier(passive_id)
