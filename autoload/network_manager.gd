extends Node
## NetworkManager - Host/Client 架构（运行时初始化）。
## 避免在解析期引用 SceneTree.multiplayer，改为 _ready() 中动态获取。

const MAX_PLAYERS := 4
const PORT := 7777
const SYNC_RATE := 1.0 / 20.0

var is_host: bool = false
var is_client: bool = false
var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var local_peer_id: int = 1
var _sync_tick: float = 0.0
var _mp_api: Object = null

signal peer_connected(peer_id: int, name: String)
signal peer_disconnected(peer_id: int)
signal session_started(is_host: bool)
signal connection_failed(reason: String)
signal session_ended

func _ready() -> void:
	var mp := _get_mp()
	if mp != null:
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected_to_server)
		mp.connection_failed.connect(_on_connection_failed)


func _get_mp() -> Object:
	if _mp_api == null:
		var tree := get_tree()
		if tree != null and tree.has_method("get_multiplayer"):
			_mp_api = tree.call("get_multiplayer")
	return _mp_api

## ---------- Host / Client lifecycle ----------

func host_session() -> void:
	var mp := _get_mp()
	if mp == null:
		connection_failed.emit("MultiplayerAPI 不可用")
		return
	var enet_peer := ENetMultiplayerPeer.new()
	var error := enet_peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		connection_failed.emit("主机创建失败: " + str(error))
		return
	peer = enet_peer
	mp.multiplayer_peer = peer
	is_host = true
	is_client = false
	local_peer_id = 1
	players[1] = {"name": "Host", "character_id": &"assault", "peer_id": 1}
	session_started.emit(true)
	print("[Network] Host session started on port " + str(PORT))


func join_session(ip: String, port: int = PORT) -> void:
	var mp := _get_mp()
	if mp == null:
		connection_failed.emit("MultiplayerAPI 不可用")
		return
	var enet_peer := ENetMultiplayerPeer.new()
	var error := enet_peer.create_client(ip, port)
	if error != OK:
		connection_failed.emit("连接失败: " + str(error))
		return
	peer = enet_peer
	mp.multiplayer_peer = peer
	is_host = false
	is_client = true
	session_started.emit(false)
	print("[Network] Connecting to " + ip + ":" + str(port))


func leave_session() -> void:
	var mp := _get_mp()
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close_connection()
	if mp != null:
		mp.multiplayer_peer = null
	is_host = false
	is_client = false
	players.clear()
	local_peer_id = 1
	session_ended.emit()


## ---------- RPC: player state ----------

@rpc("any_peer", "reliable")
func rpc_player_spawn(peer_id: int, character_id: StringName, spawn_x: float, spawn_y: float) -> void:
	players[peer_id] = {"name": "P" + str(peer_id), "character_id": character_id, "peer_id": peer_id}
	_var_spawn_player(peer_id, character_id, spawn_x, spawn_y)


@rpc("any_peer", "reliable")
func rpc_zombie_dismember(zombie_id: int, pos_x: float, pos_y: float, dir_x: float, dir_y: float, damage_type: StringName) -> void:
	_var_spawn_dismember_effect(zombie_id, pos_x, pos_y, dir_x, dir_y, damage_type)


@rpc("any_peer", "reliable")
func rpc_zombie_hit(zombie_id: int, dmg: int, head: bool) -> void:
	var zombie := _get_zombie_node(zombie_id)
	if zombie != null:
		zombie.call_deferred("net_take_damage", dmg, head)


## ---------- Internal ----------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	players[peer_id] = {"name": "P" + str(peer_id), "character_id": &"assault", "peer_id": peer_id}
	peer_connected.emit(peer_id, "P" + str(peer_id))
	for pid in players.keys():
		rpc_id(peer_id, "rpc_player_spawn", pid, players[pid]["character_id"], 220.0, 288.0)


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	peer_disconnected.emit(peer_id)
	if is_host and peer_id == 1:
		leave_session()


func _on_connected_to_server() -> void:
	var mp := _get_mp()
	if mp != null:
		local_peer_id = mp.get_unique_id()
	print("[Network] Connected as peer " + str(local_peer_id))


func _on_connection_failed(reason: String) -> void:
	connection_failed.emit(reason)
	leave_session()


func _get_zombie_node(zombie_id: int) -> Node:
	var root := get_tree().get_current_scene()
	if root == null:
		return null
	return root.find_child("Zombie_" + str(zombie_id), true, false)


func _find_level(root: Node) -> Node:
	if root.has_method("spawn_network_player"):
		return root
	for child in root.get_children():
		if child.has_method("spawn_network_player"):
			return child
	return null


func _var_spawn_player(peer_id: int, character_id: StringName, x: float, y: float) -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var level := _find_level(root)
	if level == null:
		return
	level.call_deferred("spawn_network_player", peer_id, character_id, x, y)


func _var_spawn_dismember_effect(zombie_id: int, pos_x: float, pos_y: float, dir_x: float, dir_y: float, damage_type: StringName) -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var fx_layer := root.find_child("FXLayer", true, false)
	if fx_layer != null and fx_layer.has_method("spawn_dismember"):
		fx_layer.call_deferred("spawn_dismember", Vector2(pos_x, pos_y), Vector2(dir_x, dir_y), damage_type)


func _process(delta: float) -> void:
	if not is_host:
		return
	_sync_tick += delta
	if _sync_tick < SYNC_RATE:
		return
	_sync_tick = 0.0
	broadcast_zombie_positions()


## ---------- Public API ----------

func spawn_local_player(peer_id: int, character_id: StringName, x: float, y: float) -> void:
	rpc_player_spawn(peer_id, character_id, x, y)


func get_peer_id() -> int:
	return local_peer_id


func is_multiplayer_active() -> bool:
	return is_host or is_client


## RPC: Host 广播僵尸位置给客户端。
@rpc("any_peer", "reliable")
func rpc_zombie_position(zombie_instance_id: int, x: float, y: float, facing: int) -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var zombie := root.find_child("Zombie_" + str(zombie_instance_id), true, false)
	if zombie != null:
		zombie.set("_net_target_x", x)
		zombie.set("_net_target_y", y)
		zombie.set("_net_facing", facing)


## Host 广播所有僵尸位置给客户端（由 _sync_loop 调用）。
func broadcast_zombie_positions() -> void:
	if not is_host:
		return
	var zombies := get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if z is ZombieBase and z._is_network_host:
			var zid := z.get_instance_id()
			var pos: Vector2 = z.global_position
			var facing := int(z.facing)
			rpc_zombie_position(zid, pos.x, pos.y, facing)
