class_name ReworkOrderComponent
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 指令状态机 —— 跟随(follow)/推进(advance)/防守(hold)/集火(focus)。
##       集成模式下订阅现有 EventBus.command_issued(cmd: StringName);
##       独立运行时由 SoldierBase.issue_command() 直接驱动。
##       信号名与现有系统保持一致(cmd 取值 follow/advance/hold/focus)。
## 依赖: EventBus(可选,存在才订阅)。
## 对外接口:
##   issue(cmd: StringName, point: Vector2) -> void
##   order -> StringName / hold_position / focus_point
##   set_leader(node) / set_anchor_provider(callable)
##   acknowledged 信号: soldier_order_acknowledged(cmd, state)
## ---------------------------------------------------------------------------

signal soldier_order_acknowledged(cmd: StringName, state: Dictionary)

const ORDERS: Array[StringName] = [&"follow", &"advance", &"hold", &"focus"]

var order: StringName = &"follow"
var hold_position: Vector2 = Vector2.ZERO
var focus_point: Vector2 = Vector2.ZERO
var leader: Node2D = null
var anchor_x: float = 0.0
var facing_dir: float = 1.0

var _host: Node = null
var _bus: Node = null


func attach(host: Node) -> void:
	_host = host
	_bus = host.get("_bus")
	if _bus != null and _bus.has_signal("command_issued"):
		_bus.command_issued.connect(_on_bus_command)
	hold_position = host.global_position
	focus_point = host.global_position + Vector2(240, 0)


func detach() -> void:
	if _bus != null and _bus.has_signal("command_issued") \
			and _bus.command_issued.is_connected(_on_bus_command):
		_bus.command_issued.disconnect(_on_bus_command)
	_bus = null
	_host = null


func issue(cmd: StringName, point: Vector2 = Vector2.ZERO) -> void:
	if not ORDERS.has(cmd):
		return
	if cmd == &"hold" and order == &"hold" and _host != null:
		hold_position = _host.global_position # 二次 HOLD = 就地重新固守
	order = cmd
	if cmd == &"hold" and _host != null:
		hold_position = _host.global_position
	if cmd == &"focus":
		focus_point = point if point != Vector2.ZERO else _default_focus()
	soldier_order_acknowledged.emit(cmd, order_state())


func order_state() -> Dictionary:
	return {
		"order": order,
		"hold_position": hold_position,
		"focus_point": focus_point,
	}


func set_leader(node: Node2D) -> void:
	leader = node


func _default_focus() -> Vector2:
	if _host == null:
		return focus_point
	# 集火点: 优先取玩家准星方向 260px(与现有 AllyAgent 行为一致)
	var player: Node = _host.get("aim_focus_source")
	if player == null:
		for candidate in _host.get_tree().get_nodes_in_group("player"):
			player = candidate
			break
	if player != null and is_instance_valid(player):
		var aim: Variant = player.get("aim_dir")
		if aim is Vector2:
			return player.global_position + aim * 260.0
		return player.global_position + Vector2(240, 0)
	return _host.global_position + Vector2(240, 0)


func _on_bus_command(cmd: StringName) -> void:
	issue(cmd)
