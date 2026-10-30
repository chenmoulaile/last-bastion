extends Node
## Two-process ENet probe for player state replication (task 1b).
## Run:
##   godot --headless --path . res://tests/net_sync_probe.tscn -- --role=host
##   godot --headless --path . res://tests/net_sync_probe.tscn -- --role=client
##
## Order matters: SceneCacheInterface permanently drops packets for node paths
## that do not exist yet, so the host only starts its synchronizer after the
## client confirms the RPC-spawned body exists.

const PORT := 7777
const TARGET_POS := Vector2(900.0, 240.0)
const TARGET_HP := 77
const TARGET_TEMP_HP := 5
const TARGET_FACING := -1
const TARGET_STATE := "walk"
const CONTROL_VALUE := 42

var role: String = "host"
var _client_peer: int = 0
var _client_ready: bool = false
var _client_has_player: bool = false
var _fails: int = 0
var _control: Node2D = null


class ControlNode extends Node2D:
	var value: int = 0


func _ready() -> void:
	role = _arg("--role", "host")
	if role == "host":
		await _run_host()
	else:
		await _run_client()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


## A node that exists on both peers before the session is established, used to
## prove the synchronizer itself works independently of player spawning.
func _make_control() -> void:
	_control = ControlNode.new()
	_control.name = "Control"
	add_child(_control)
	var cfg := SceneReplicationConfig.new()
	for prop in ["position", "value"]:
		var path := NodePath(".:" + prop)
		cfg.add_property(path)
		cfg.property_set_sync(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.root_path = NodePath("..")
	sync.replication_config = cfg
	sync.set_multiplayer_authority(1)
	_control.add_child(sync)


func _load_level() -> Node:
	var empty_squad: Array[StringName] = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL", &"assault", empty_squad)
	var packed: PackedScene = load("res://scenes/levels/l01.tscn")
	var level: Node = packed.instantiate()
	level.name = "LevelRunner"
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	return level


## The level's own single-player body would share a path on both peers. It is
## not the subject of this probe; remove only its network components.
func _strip_local_sync(level: Node) -> void:
	var local: Node = level.get_player()
	if local == null:
		return
	for node_name in ["PlayerSync", "PlayerNetworkSync"]:
		var node: Node = local.get_node_or_null(node_name)
		if node != null:
			node.free()


func _find_player(level: Node) -> Node:
	return level.find_child("Player_1", true, false)


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	return bool(predicate.call())


func _run_host() -> void:
	print("== net sync probe: HOST ==")
	var net := get_node("/root/NetworkManager")
	net.connection_failed.connect(func(reason: String) -> void: print("HOST CONNECTION_FAILED: " + reason))
	net.peer_connected.connect(func(id: int, _name: String) -> void: _client_peer = id)
	_make_control()
	net.host_session()
	await get_tree().create_timer(0.4).timeout
	var level: Node = await _load_level()
	_strip_local_sync(level)

	var ready_ok: bool = await _wait_until(func() -> bool: return _client_ready, 6000)
	_check(ready_ok, "client reported level ready (peer %d)" % _client_peer)
	if not ready_ok or _client_peer == 0:
		_finish()
		return

	net.rpc_id(_client_peer, "rpc_player_spawn", 1, &"assault", 220.0, 288.0)
	var spawn_ok: bool = await _wait_until(func() -> bool: return _client_has_player, 4000)
	_check(spawn_ok, "client confirmed RPC-spawned Player_1")
	if not spawn_ok:
		_finish()
		return

	# The client's node now exists, so the host synchronizer can register without
	# the SceneCache permanently poisoning unknown paths.
	level.call("spawn_network_player", 1, &"assault", 220.0, 288.0)
	var player: Node = _find_player(level)
	_check(player != null, "host Player_1 spawned")
	if player == null:
		_finish()
		return
	var host_sync: Node = player.get_node_or_null("PlayerSync")
	_check(host_sync != null, "host MultiplayerSynchronizer exists")
	if host_sync != null:
		var cfg: SceneReplicationConfig = host_sync.get("replication_config")
		print("HOST SYNC props=%s authority=%d is_auth=%s" % [
			str(cfg.get_properties() if cfg != null else []),
			host_sync.get_multiplayer_authority(),
			str(host_sync.is_multiplayer_authority())])

	await get_tree().create_timer(0.5).timeout
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = TARGET_POS
	player.set("hp", TARGET_HP)
	player.set("temp_hp", TARGET_TEMP_HP)
	player.set("facing", TARGET_FACING)
	player.set("state", TARGET_STATE)
	player.set("aim_angle", 1.25)
	if _control != null:
		_control.value = CONTROL_VALUE
	print("HOST STATE pos=%s hp=%d facing=%d state=%s control=%d" % [
		str(TARGET_POS), TARGET_HP, TARGET_FACING, TARGET_STATE, CONTROL_VALUE])
	await get_tree().create_timer(2.5).timeout
	print("HOST RESULT: %d failed" % _fails)
	_finish()


func _run_client() -> void:
	print("== net sync probe: CLIENT ==")
	var net := get_node("/root/NetworkManager")
	_make_control()
	net.join_session("127.0.0.1", PORT)
	var connected: bool = await _wait_until(
		func() -> bool: return int(net.local_peer_id) > 1, 6000)
	_check(connected, "client connected as peer %d" % int(net.local_peer_id))
	if not connected:
		_finish()
		return
	var level: Node = await _load_level()
	_strip_local_sync(level)
	await get_tree().create_timer(0.2).timeout
	rpc_id(1, "rpc_client_ready")

	var player: Node = null
	var spawn_ok: bool = await _wait_until(
		func() -> bool: return _find_player(level) != null, 6000)
	player = _find_player(level)
	_check(spawn_ok and player != null, "remote Player_1 spawned on client via RPC")
	if player == null:
		_finish()
		return
	player.set_physics_process(false)
	player.set_process(false)
	rpc_id(1, "rpc_client_has_player")

	await get_tree().create_timer(2.2).timeout
	if _control != null:
		_check(int(_control.value) == CONTROL_VALUE,
			"control node value replicated (got %d)" % int(_control.value))
	var pos: Vector2 = player.global_position
	_check(pos.distance_to(TARGET_POS) < 8.0, "position replicated (%s)" % str(pos))
	_check(int(player.get("hp")) == TARGET_HP, "hp replicated (got %s)" % str(player.get("hp")))
	_check(int(player.get("temp_hp")) == TARGET_TEMP_HP, "temp_hp replicated (got %s)" % str(player.get("temp_hp")))
	_check(int(player.get("facing")) == TARGET_FACING, "facing replicated (got %s)" % str(player.get("facing")))
	_check(String(player.get("state")) == TARGET_STATE, "state replicated (got %s)" % str(player.get("state")))
	_check(absf(float(player.get("aim_angle")) - 1.25) < 0.01, "aim_angle replicated (got %s)" % str(player.get("aim_angle")))
	var helper: Node = player.get_node_or_null("PlayerNetworkSync")
	_check(helper != null, "PlayerNetworkSync attached")
	if helper != null:
		var snap: Dictionary = helper.call("snapshot")
		_check(int(snap.get("peer_id", 0)) == 1, "sync peer_id == 1 (got %s)" % str(snap.get("peer_id")))
		_check(not bool(snap.get("is_local", true)), "remote body is not local")
		print("CLIENT SNAPSHOT " + str(snap))
	print("CLIENT RESULT: %d failed" % _fails)
	_finish()


@rpc("any_peer", "reliable")
func rpc_client_ready() -> void:
	_client_ready = true


@rpc("any_peer", "reliable")
func rpc_client_has_player() -> void:
	_client_has_player = true


func _finish() -> void:
	print("NET PROBE DONE: %d failed" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
