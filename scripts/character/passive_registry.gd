class_name PassiveRegistry
extends RefCounted
## Maps CharacterData.passive_ability_id -> passive script. Keeping the table
## here means new survivors are a data change, not a PlayerController change.

const SCRIPTS := {
	&"passive_lin_yuan": "res://scripts/character/passives/passive_lin_yuan.gd",
	&"passive_marcus": "res://scripts/character/passives/passive_marcus.gd",
	&"passive_lucia": "res://scripts/character/passives/passive_lucia.gd",
	&"passive_victor": "res://scripts/character/passives/passive_victor.gd",
}


static func has_passive(id: StringName) -> bool:
	return SCRIPTS.has(id)


static func create(id: StringName, owner_player: Node, character: CharacterData) -> Node:
	if not SCRIPTS.has(id):
		return null
	var script: GDScript = load(SCRIPTS[id])
	if script == null:
		push_warning("Passive script missing: " + String(id))
		return null
	var node: Node = script.new()
	node.set("player", owner_player)
	node.set("data", character)
	node.name = "Passive_" + String(id)
	return node
