class_name EventBusBridge
extends Node
## ---------------------------------------------------------------------------
## 职责: 新角色系统与现有 EventBus 之间的**单向只读桥接**。新系统内部信号
##       (character_state_changed / passive_triggered / soldier_state_changed /
##       soldier_order_acknowledged)由本桥转发为现有 EventBus 信号;
##       新系统自身绝不直接 emit 现有 EventBus 信号(player.gd 兼容信号除外,
##       见 INTEGRATION_GUIDE §2)。
## 依赖: EventBus autoload(可选;不存在时桥接静默停用,支持独立运行)。
## 对外接口:
##   static attach_for(actor: Node) -> EventBusBridge
##       首个 rework 演员注册时自动实例化并挂到场景树;重复注册幂等。
##   register_player(node) / register_soldier(node)
##   actors() -> Array  (测试用)
## 生命周期: 场景树清空时 _instance 自动失效(引用判空后重建)。
## ---------------------------------------------------------------------------

const NODE_NAME: StringName = &"EventBusBridge"

static var _instance: EventBusBridge = null

var _bus: Node = null
var _players: Array = []
var _soldiers: Array = []


static func attach_for(actor: Node) -> EventBusBridge:
	if _instance == null or not is_instance_valid(_instance) or not _instance.is_inside_tree():
		_instance = EventBusBridge.new()
		_instance.name = NODE_NAME
		actor.get_tree().root.add_child.call_deferred(_instance)
	_instance._register(actor)
	return _instance


static func instance() -> EventBusBridge:
	return _instance if _instance != null and is_instance_valid(_instance) else null


func _resolve_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("EventBus")


func _ready() -> void:
	_bus = _resolve_bus()


func actors() -> Array:
	var result: Array = []
	result.append_array(_players)
	result.append_array(_soldiers)
	return result


func _register(actor: Node) -> void:
	# 桥可能先于 _ready 被调用,_bus 延迟到入树时解析
	if _bus == null:
		_bus = _resolve_bus()
	if actor is PlayerControllerV2:
		if not _players.has(actor):
			_players.append(actor)
			_bind_player(actor)
	elif actor is SoldierBase:
		if not _soldiers.has(actor):
			_soldiers.append(actor)
			_bind_soldier(actor)


## 从玩家注册表中移除（供 PlayerControllerV2._exit_tree 调用）。
func _unregister_player(player: PlayerControllerV2) -> void:
	if _players.has(player):
		_players.erase(player)
	if _bus != null and player.is_connected("character_state_changed", _on_player_state):
		player.character_state_changed.disconnect(_on_player_state)
	if _bus != null and player.is_connected("downed", _emit_if.bind(&"player_downed")):
		player.downed.disconnect(_emit_if.bind(&"player_downed"))
	if _bus != null and player.is_connected("died", _emit_if.bind(&"player_died")):
		player.died.disconnect(_emit_if.bind(&"player_died"))
	if _bus != null and player.is_connected("revived", _emit_if.bind(&"player_rescued")):
		player.revived.disconnect(_emit_if.bind(&"player_rescued"))
	if _bus != null and player.is_connected("damage_taken", _on_player_damaged):
		player.damage_taken.disconnect(_on_player_damaged)
	if _bus != null and player.is_connected("passive_triggered", _on_passive_triggered):
		player.passive_triggered.disconnect(_on_passive_triggered)


## ------------------------------------------------------------ 玩家转发 ----

func _bind_player(player: PlayerControllerV2) -> void:
	if _bus == null:
		return
	player.character_state_changed.connect(_on_player_state)
	player.downed.connect(_emit_if.bind(&"player_downed"))
	player.died.connect(_emit_if.bind(&"player_died"))
	player.revived.connect(_emit_if.bind(&"player_rescued"))
	player.damage_taken.connect(_on_player_damaged)
	player.passive_triggered.connect(_on_passive_triggered)


func _on_player_state(state: StringName, _detail: Dictionary) -> void:
	if _bus == null:
		return
	match state:
		&"hurt", &"healed", &"downed", &"revived", &"dead", &"respawn", &"fire":
			_push_health()
		&"controlled":
			_push_health()
		&"spawn":
			_push_health()
			_push_ammo()


func _on_player_damaged(_amount: int, _source: StringName) -> void:
	if _bus != null and _bus.has_signal("damage_flash"):
		_bus.damage_flash.emit()


func _on_passive_triggered(passive_id: StringName, payload: Dictionary) -> void:
	if _bus != null and _bus.has_signal("notify"):
		var text: String = String(payload.get("notify_text", passive_id))
		_bus.notify.emit(text)


func _push_health() -> void:
	if _bus == null or not _bus.has_signal("health_changed"):
		return
	for actor in _players:
		if is_instance_valid(actor):
			_bus.health_changed.emit(int(actor.hp), int(actor.temp_hp), int(actor.max_hp))
			return


func _push_ammo() -> void:
	if _bus == null or not _bus.has_signal("ammo_changed"):
		return
	for actor in _players:
		if not is_instance_valid(actor):
			continue
		var weapon: Variant = actor._current_weapon()
		if weapon == null:
			return
		var wid: StringName = actor._wname(weapon, "id")
		var state: Dictionary = actor.ammo.get(wid, {"mag": 0, "reserve": 0})
		_bus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))
		return


## ------------------------------------------------------------ 士兵转发 ----

func _bind_soldier(soldier: SoldierBase) -> void:
	if _bus == null:
		return
	soldier.soldier_state_changed.connect(_on_soldier_state.bind(soldier))
	soldier.soldier_order_acknowledged.connect(_on_soldier_order_ack)


func _on_soldier_state(state: StringName, _detail: Dictionary, soldier: SoldierBase) -> void:
	if _bus == null:
		return
	match state:
		&"dead":
			if _bus.has_signal("teammate_status_changed"):
				_bus.teammate_status_changed.emit()
		&"downed", &"revived", &"respawn":
			if _bus.has_signal("teammate_status_changed"):
				_bus.teammate_status_changed.emit()
		&"healing":
			if _bus.has_signal("notify"):
				_bus.notify.emit("战地医疗兵正在治疗伤兵")


func _on_soldier_order_ack(cmd: StringName, _state: Dictionary) -> void:
	if _bus != null and _bus.has_signal("teammate_status_changed"):
		_bus.teammate_status_changed.emit()
	if _bus != null and _bus.has_signal("notify"):
		var labels := {"follow": "指令：跟随", "advance": "指令：推进",
			"hold": "指令：防守", "focus": "指令：集火"}
		_bus.notify.emit(String(labels.get(String(cmd), "指令下达")))


## ------------------------------------------------------------ 工具 ----

func _emit_if(signal_name: StringName) -> void:
	if _bus != null and _bus.has_signal(signal_name):
		_bus.emit_signal(signal_name)
