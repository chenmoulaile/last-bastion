class_name PassiveBase
extends Node
## ---------------------------------------------------------------------------
## 职责: 角色被动/技能组件抽象基类。每个被动是独立 Node,由
##       PlayerControllerV2 按 character_data.passive_ability_id 动态挂载。
## 依赖: 宿主控制器(duck-typed,推荐类型 PlayerControllerV2)。
## 对外接口:
##   enable() / disable()                       # 生命周期(挂树/移除时调用)
##   _on_event(event_name, payload) -> void     # 控制器事件分发入口
## 控制器事件名约定:
##   "skill_used"      payload: {"handled": bool}  设置 handled=true 表示本
##                     被动消费了技能(控制器将启动冷却并发 passive_triggered)
##   "damaged"         payload: {"amount", "source", "type"}
##   "melee"           payload: {}
##   "fire"            payload: {}
##   "throw_requested" payload: {}
## 被动通过控制器公开 API 施加效果(修正器字典,乘法叠加):
##   add_speed_modifier / add_damage_modifier / add_reload_modifier /
##   add_fire_rate_modifier / add_frontal_guard / grant_iframes /
##   teleport_to / take_damage / heal / get_tree()
## ---------------------------------------------------------------------------

@export var passive_id: StringName = &""
@export var cooldown_override: float = -1.0

var controller: Node = null


func _ready() -> void:
	controller = get_parent()
	if passive_id == &"":
		passive_id = StringName(name)
	enable()


func _exit_tree() -> void:
	disable()


func enable() -> void:
	pass


func disable() -> void:
	pass


func _on_event(_event_name: StringName, _payload: Dictionary) -> void:
	pass


## ---------------------------------------------------------------- 工具 ----

func consume_skill(payload: Dictionary) -> void:
	## 标记技能已被本被动消费,并让控制器进入冷却。
	payload["handled"] = true
	if controller == null:
		return
	var cd: float = cooldown_override
	if cd < 0.0:
		var data: Variant = controller.get("character_data")
		cd = 25.0 if data == null else float(data.skill_cd)
	controller.set("skill_cd", cd)
	if controller.has_signal("passive_triggered"):
		controller.passive_triggered.emit(passive_id, {"result": passive_id})


func controller_bus() -> Node:
	## 只读获取 EventBus(存在才返回),供被动发通知类信号。
	if controller == null:
		return null
	var bus: Variant = controller.get("_bus")
	return bus if bus is Node else null
