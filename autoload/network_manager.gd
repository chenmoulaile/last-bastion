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
var _level_params: Dictionary = {}
var _level_ready: bool = false
var _ready_peers: Dictionary = {}
var _start_sent: Dictionary = {}
var _spawn_sent: Dictionary = {}
var _rep_acks: Dictionary = {}
var remote_shot_events: int = 0
var zombie_spawn_events: int = 0

signal peer_connected(peer_id: int, name: String)
signal peer_disconnected(peer_id: int)
signal session_started(is_host: bool)
signal connection_failed(reason: String)
signal session_ended
signal level_synced(level_id: StringName)

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
	_level_params.clear()
	_level_ready = false
	_ready_peers.clear()
	_start_sent.clear()
	_spawn_sent.clear()
	_rep_acks.clear()
	session_ended.emit()


## ---------- RPC: player state ----------

@rpc("any_peer", "reliable")
func rpc_player_spawn(peer_id: int, character_id: StringName, spawn_x: float, spawn_y: float) -> void:
	players[peer_id] = {"name": "P" + str(peer_id), "character_id": character_id, "peer_id": peer_id}
	_var_spawn_player(peer_id, character_id, spawn_x, spawn_y)


## ---------- Co-op session lifecycle ----------

## Host: start a level locally and tell every current/future client to load it.
func start_coop_level(level_id: StringName, mode: StringName, difficulty: StringName,
		character_id: StringName) -> void:
	if not is_host:
		return
	_level_params = {
		"level_id": level_id, "mode": mode, "difficulty": difficulty,
		"character_id": character_id,
	}
	_level_ready = false
	_ready_peers.clear()
	_start_sent.clear()
	_spawn_sent.clear()
	_rep_acks.clear()
	GameManager.selected_character = character_id
	GameManager.start_level(level_id, mode, difficulty, character_id)
	EventBus.start_level_requested.emit()
	for pid in players.keys():
		if int(pid) != 1:
			_send_level_start(int(pid))
	level_synced.emit(level_id)


@rpc("authority", "reliable")
func rpc_start_level(level_id: StringName, mode: StringName, difficulty: StringName,
		character_id: StringName) -> void:
	if is_host:
		return
	_level_params = {
		"level_id": level_id, "mode": mode, "difficulty": difficulty,
		"character_id": character_id,
	}
	_level_ready = false
	GameManager.selected_character = character_id
	GameManager.start_level(level_id, mode, difficulty, character_id)
	EventBus.start_level_requested.emit()
	level_synced.emit(level_id)


## Called by LevelRunner once its local player/HUD exist.
func notify_level_ready() -> void:
	if not is_multiplayer_active():
		return
	_level_ready = true
	if is_client:
		rpc_id(1, "rpc_client_level_ready", local_peer_id)
	else:
		for pid in players.keys():
			if int(pid) != 1:
				_send_level_start(int(pid))
		_spawn_remote_players()


func _send_level_start(pid: int) -> void:
	if not is_host or _start_sent.has(pid) or _level_params.is_empty():
		return
	_start_sent[pid] = true
	rpc_id(pid, "rpc_start_level",
		_level_params["level_id"], _level_params["mode"],
		_level_params["difficulty"], _level_params["character_id"])


@rpc("any_peer", "reliable")
func rpc_client_level_ready(peer_id: int) -> void:
	if not is_host:
		return
	_ready_peers[peer_id] = true
	_spawn_remote_players()


func _spawn_remote_players() -> void:
	if not is_host or not _level_ready:
		return
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var level := _find_level(root)
	if level == null:
		return
	for pid in players.keys():
		if int(pid) == 1 or not _ready_peers.has(pid):
			continue
		if _spawn_sent.has(pid):
			continue
		_spawn_sent[pid] = true
		var char_id: StringName = players[pid].get("character_id", &"assault")
		var spawn_x := 244.0 + float(int(pid) % 4) * 28.0
		if level.find_child("Player_" + str(pid), true, false) == null:
			level.call("spawn_network_player", pid, char_id, spawn_x, 288.0)
		# The joining client needs the host body and every other ready client.
		rpc_id(pid, "rpc_player_spawn", 1, &"assault", 220.0, 288.0)
		for other in players.keys():
			if int(other) == 1 or int(other) == int(pid) or not _ready_peers.has(other):
				continue
			var other_char: StringName = players[other].get("character_id", &"assault")
			rpc_id(pid, "rpc_player_spawn", other, other_char,
				244.0 + float(int(other) % 4) * 28.0, 288.0)
	_request_replication_enable()


## Enable synchronizers only after every peer owns every player node. The host
## asks ready clients to enable theirs (and ack), then enables its own.
func _request_replication_enable() -> void:
	if not is_host:
		return
	var targets: Array = []
	for pid in _ready_peers.keys():
		targets.append(pid)
	if targets.is_empty():
		return
	_rep_acks.clear()
	for pid in targets:
		rpc_id(pid, "rpc_enable_replication")


@rpc("authority", "reliable")
func rpc_enable_replication() -> void:
	if is_host:
		return
	_set_all_replication(true)
	rpc_id(1, "rpc_replication_ack", local_peer_id)


@rpc("any_peer", "reliable")
func rpc_replication_ack(peer_id: int) -> void:
	if not is_host:
		return
	_rep_acks[peer_id] = true
	for pid in _ready_peers.keys():
		if not _rep_acks.has(pid):
			return
	_set_all_replication(true)


func _set_all_replication(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("player_network_sync"):
		if node != null and is_instance_valid(node) and node.has_method("set_replication_enabled"):
			if enabled and node.has_method("enable_replication"):
				node.call("enable_replication")
			else:
				node.call("set_replication_enabled", enabled)


@rpc("authority", "reliable")
func rpc_player_despawn(peer_id: int) -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var node := root.find_child("Player_" + str(peer_id), true, false)
	if node != null:
		node.queue_free()


@rpc("any_peer", "reliable")
func rpc_zombie_dismember(zombie_id: int, pos_x: float, pos_y: float, dir_x: float, dir_y: float, damage_type: StringName) -> void:
	_var_spawn_dismember_effect(zombie_id, pos_x, pos_y, dir_x, dir_y, damage_type)


@rpc("any_peer", "reliable")
func rpc_zombie_hit(zombie_id: int, dmg: int, head: bool) -> void:
	var zombie := _get_zombie_node(zombie_id)
	if zombie != null:
		zombie.call_deferred("net_take_damage", dmg, head)


## ---------- Zombie replication ----------

func broadcast_zombie_spawn(kind: StringName, net_id: int, x: float, y: float) -> void:
	if not is_host:
		return
	zombie_spawn_events += 1
	rpc("rpc_zombie_spawn", kind, net_id, x, y)


@rpc("authority", "reliable")
func rpc_zombie_spawn(kind: StringName, net_id: int, x: float, y: float) -> void:
	var root := get_tree().get_current_scene()
	if root == null:
		return
	if root.find_child("Zombie_" + str(net_id), true, false) != null:
		return
	var level := _find_level(root)
	if level == null:
		return
	level.call("spawn_network_zombie", kind, net_id, Vector2(x, y))


func broadcast_zombie_death(net_id: int) -> void:
	if not is_host:
		return
	rpc("rpc_zombie_death", net_id)


@rpc("authority", "reliable")
func rpc_zombie_death(net_id: int) -> void:
	var zombie := _get_zombie_node(net_id)
	if zombie != null:
		zombie.queue_free()


## Client -> host damage arbitration. The host owns the authoritative zombie HP
## and broadcasts death/dismember once it resolves the hit.
@rpc("any_peer", "reliable")
func rpc_zombie_damage(net_id: int, amount: int, head: bool,
		dir_x: float, dir_y: float, damage_type: StringName) -> void:
	if not is_host:
		return
	var zombie := _get_zombie_node(net_id)
	if zombie == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if zombie.has_method("set_killer_peer_id"):
		zombie.call("set_killer_peer_id", sender)
	zombie.call("apply_damage", amount, Vector2(dir_x, dir_y), head, &"player", damage_type)


## ---------- Remote player presentation ----------

func broadcast_player_shot(peer_id: int, weapon_id: StringName, origin: Vector2,
		dir: Vector2, hit_pos: Vector2) -> void:
	rpc("rpc_player_shot", peer_id, weapon_id, origin, dir, hit_pos)


@rpc("any_peer", "reliable")
func rpc_player_shot(peer_id: int, weapon_id: StringName, origin: Vector2,
		dir: Vector2, hit_pos: Vector2) -> void:
	if peer_id == local_peer_id:
		return
	var root := get_tree().get_current_scene()
	if root == null:
		return
	var shooter := root.find_child("Player_" + str(peer_id), true, false)
	if shooter != null and shooter.has_method("play_remote_shot"):
		shooter.call("play_remote_shot", weapon_id, origin, dir, hit_pos)
	remote_shot_events += 1


## ---------- Internal ----------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	players[peer_id] = {"name": "P" + str(peer_id), "character_id": &"assault", "peer_id": peer_id}
	peer_connected.emit(peer_id, "P" + str(peer_id))
	# A new peer has none of the player nodes yet: stop existing synchronizers
	# until the spawn + ready handshake completes.
	_set_all_replication(false)
	if _level_ready and not _level_params.is_empty():
		rpc_id(peer_id, "rpc_start_level",
			_level_params["level_id"], _level_params["mode"],
			_level_params["difficulty"], _level_params["character_id"])


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	_ready_peers.erase(peer_id)
	_start_sent.erase(peer_id)
	peer_disconnected.emit(peer_id)
	if is_host:
		rpc("rpc_player_despawn", peer_id)
	if peer_id == 1:
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
	level.call("spawn_network_player", peer_id, character_id, x, y)


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


## Host 广播所有僵尸位置给客户端（由 _process 调用）。
func broadcast_zombie_positions() -> void:
	if not is_host:
		return
	var zombies := get_tree().get_nodes_in_group("zombies")
	for z in zombies:
		if z is ZombieBase and z._is_network_host:
			var zid: int = z.net_id if z.net_id != 0 else z.get_instance_id()
			var pos: Vector2 = z.global_position
			var facing := int(z.facing)
			rpc_zombie_position(zid, pos.x, pos.y, facing)
