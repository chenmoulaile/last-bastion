class_name PlayerNetworkSync
extends Node2D
## PlayerNetworkSync - 挂载于 PlayerControllerV2，仅负责网络状态同步。
## 不修改任何战斗逻辑，只读取/广播位置、朝向、状态。
## 单机模式下自动禁用，零开销。

var peer_id: int = 1
var is_local: bool = true
var net_target_x: float = 0.0
var net_target_y: float = 0.0
var net_facing: int = 1
var net_state: String = "idle"
var _lerp_speed: float = 12.0
var _last_input_time: float = 0.0

var _network: Node = null

func _ready() -> void:
	_network = get_node_or_null("/root/NetworkManager")
	if _network == null or not _network.is_multiplayer_active():
		set_process(false)
		return
	set_process(true)
	# 重命名节点便于查找
	name = "Player_" + str(peer_id)


func _process(delta: float) -> void:
	if _network == null:
		return
	if is_local:
		_emit_local_state()
	else:
		_apply_remote_interpolation(delta)


func _emit_local_state() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_input_time < 0.05:
		return
	_last_input_time = now
	var pos := global_position
	var facing := int(get("facing", 1))
	var state := String(get("state", "idle"))
	_network.sync_player_move(peer_id, pos.x, pos.y, facing, state)


func _apply_remote_interpolation(delta: float) -> void:
	var cur_x := global_position.x
	var cur_y := global_position.y
	var new_x := lerpf(cur_x, net_target_x, _lerp_speed * delta)
	var new_y := lerpf(cur_y, net_target_y, _lerp_speed * delta)
	global_position = Vector2(new_x, new_y)
	set("facing", net_facing)
	set("state", net_state)


## RPC 触发点（由 PlayerControllerV2 调用）
func net_fire(weapon_id: StringName, x: float, y: float, dir_x: float, dir_y: float) -> void:
	pass  # 由 PlayerControllerV2 处理实际开火，此处仅占位


func net_reload(weapon_id: StringName) -> void:
	pass


func net_swap_weapon(weapon_id: StringName) -> void:
	pass


func net_downed() -> void:
	set("is_downed", true)


func net_revived() -> void:
	set("is_downed", false)
