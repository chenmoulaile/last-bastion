class_name RoleStrategy
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 士兵兵种策略抽象基类 + 工厂。兵种差异全部由子类承担,
##       SoldierBase 与各组件中禁止出现 `if soldier_type == ...` 分支。
## 依赖: 宿主 SoldierBase(duck-typed,推荐类型标注 SoldierBase)。
## 对外接口(组件调用,子类按需覆写):
##   static create(strategy_id: StringName) -> RoleStrategy   # 工厂
##   on_attached(host) / think(delta) / physics_tick(delta)
##   movement_speed_mult() -> float          # 基础移速倍率
##   can_move() -> bool                      # false = 定身(如机枪手开火)
##   can_fire() -> bool                      # false = 禁火(如未架枪)
##   wants_to_fire(enemy) -> bool            # 是否主动开火
##   fire_interval_mult() -> float           # 射击间隔倍率
##   damage_multiplier(target) -> float      # 对目标伤害倍率
##   burst_length() -> int                   # 点射长度(≤0 = 持续全自动)
##   burst_pause() -> float                  # 点射间歇
##   prefer_target(candidates) -> Node2D     # 目标选择偏好
##   try_special_action(delta) -> void       # 特殊行为(投手雷/治疗)
##   support_tick(delta) -> void             # 每帧支援逻辑(治疗扫描)
## ---------------------------------------------------------------------------

const SCRIPT_TABLE: Dictionary = {
	&"demolition": preload("res://characters_rework/soldiers/strategies/DemolitionStrategy.gd"),
	&"mg": preload("res://characters_rework/soldiers/strategies/MGStrategy.gd"),
	&"rifleman": preload("res://characters_rework/soldiers/strategies/RiflemanStrategy.gd"),
	&"field_medic": preload("res://characters_rework/soldiers/strategies/FieldMedicStrategy.gd"),
}

var host: Node = null
var data: ReworkSoldierData = null


static func create(strategy_id: StringName) -> RoleStrategy:
	var script: Script = SCRIPT_TABLE.get(strategy_id, SCRIPT_TABLE[&"rifleman"])
	return script.new()


func on_attached(attached_host: Node) -> void:
	host = attached_host
	data = attached_host.get("soldier_data")


func think(_delta: float) -> void:
	pass


func physics_tick(_delta: float) -> void:
	pass


func movement_speed_mult() -> float:
	return 1.0


func can_move() -> bool:
	return true


func can_fire() -> bool:
	return true


func wants_to_fire(_enemy: Node2D) -> bool:
	return true


func fire_interval_mult() -> float:
	return 1.0


func damage_multiplier(_target: Node2D) -> float:
	return 1.0


func burst_length() -> int:
	return 0


func burst_pause() -> float:
	return 0.0


func prefer_target(candidates: Array) -> Node2D:
	if candidates.is_empty():
		return null
	return candidates[0]


func try_special_action(_delta: float) -> void:
	pass


func support_tick(_delta: float) -> void:
	pass


## ---------------------------------------------------------------- 工具 ----

func zombie_list() -> Array:
	if host == null:
		return []
	return host.get_tree().get_nodes_in_group("zombies")


func alive_enemies() -> Array:
	var result: Array = []
	for zombie in zombie_list():
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("dead")) or bool(node.get("is_dead")):
			continue
		result.append(node)
	return result


func bus() -> Node:
	if host == null:
		return null
	var event_bus: Variant = host.get("_bus")
	return event_bus if event_bus is Node else null
