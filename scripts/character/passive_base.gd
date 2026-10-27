class_name PassiveAbility
extends Node
## Base class for the four survivor passives.
##
## Lifecycle contract (mirrors the design spec):
##   player -> creates the node -> assigns `player` / `data` -> add_child()
##   -> _ready() -> _on_activate()
##   -> queue_free() / level exit -> _exit_tree() -> _on_deactivate()
##
## Subclasses must disconnect every signal they connected inside _on_deactivate()
## so a retry / level reload never leaves a dangling Callable on a freed player.

var player: Node = null
var data: CharacterData = null


func _ready() -> void:
	set_process(true)
	_on_activate()


func _exit_tree() -> void:
	_on_deactivate()
	player = null


## Called once the node is inside the tree and `player` is valid.
func _on_activate() -> void:
	pass


## Called on removal; subclasses disconnect their signals here.
func _on_deactivate() -> void:
	pass


func character_id() -> String:
	return data.cid() if data != null else ""


## Convenience: fetch the level runner the player belongs to.
func level() -> Node:
	if player == null or not is_instance_valid(player):
		return null
	return player.get("level")
