class_name PlayerNetworkSync
extends Node2D
## Owns the player's MultiplayerSynchronizer.
##
## The previous implementation ran a second movement loop over RPC and read
## `facing`/`state` from this helper node instead of the player body, while
## NetworkManager wrote its interpolation targets to the body. Both sides were
## disconnected. Replication is now single-source: the synchronizer below
## mirrors the player body's transform, facing, state and health to every peer.

const REPLICATED_PROPERTIES := [
	"position", "facing", "aim_angle", "state",
	"hp", "temp_hp", "is_downed", "is_dead",
	"black_white", "bleedout", "downs", "medkits", "pills", "visual_id",
]

var peer_id: int = 1
var is_local: bool = true


func _ready() -> void:
	add_to_group("player_network_sync")
	var net := get_node_or_null("/root/NetworkManager")
	if net == null or not bool(net.call("is_multiplayer_active")):
		return
	var body := get_parent()
	if body == null:
		return
	peer_id = body.get_multiplayer_authority()
	is_local = peer_id == multiplayer.get_unique_id()


## Replication is a two-phase handshake: both peers must already own every
## player node before the first synchronizer packet is sent, otherwise Godot's
## SceneCache permanently caches the missing node path.
func enable_replication() -> void:
	var body := get_parent()
	if body == null:
		return
	_build_synchronizer(body, peer_id)
	set_replication_enabled(true)


func set_replication_enabled(enabled: bool) -> void:
	var body := get_parent()
	if body == null:
		return
	var sync := body.get_node_or_null("PlayerSync")
	if sync != null:
		sync.set_process(enabled)
		sync.set_physics_process(enabled)


func _build_synchronizer(body: Node, owner_id: int) -> void:
	if body.get_node_or_null("PlayerSync") != null:
		return
	var config := SceneReplicationConfig.new()
	for prop in REPLICATED_PROPERTIES:
		if not (prop in body):
			continue
		var path := NodePath(".:" + prop)
		config.add_property(path)
		config.property_set_sync(path, true)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(
			path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PlayerSync"
	sync.root_path = NodePath("..")
	sync.replication_config = config
	sync.set_multiplayer_authority(owner_id)
	body.add_child(sync)


func snapshot() -> Dictionary:
	var body := get_parent()
	if body == null:
		return {}
	return {
		"peer_id": peer_id,
		"is_local": is_local,
		"hp": int(body.get("hp")),
		"facing": int(body.get("facing")),
		"state": String(body.get("state")),
	}
