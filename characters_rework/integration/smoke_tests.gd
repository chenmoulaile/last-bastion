extends Node
## Characters-rework smoke test. Run:
##   Godot --headless --path . res://characters_rework/integration/smoke_tests.tscn
##
## Validates data integrity, narrative mapping, passive wiring, both actor
## classes and the one-way EventBus bridge. It does not start a level.

const PLAYABLE_DIR := "res://characters_rework/data/playable"
const SOLDIER_DIR := "res://characters_rework/data/soldiers"
const PLAYABLE_IDS: Array[StringName] = [
	&"assault", &"heavy", &"medic", &"scout", &"operative", &"officer",
]
const NARRATIVE_MAP := {
	&"assault": &"",
	&"heavy": &"marcus",
	&"medic": &"victor",
	&"scout": &"lucia",
	&"operative": &"lin_yuan",
	&"officer": &"",
}
const PALETTE_KEYS: Array[String] = [
	"accent", "body_primary", "body_secondary", "gear", "skin", "visor", "weapon",
]

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	print("[CHARREWORK] playable data")
	_test_playable_data()
	print("[CHARREWORK] narrative mapping")
	_test_narrative_mapping()
	print("[CHARREWORK] soldier data")
	_test_soldier_data()
	print("[CHARREWORK] actor scripts")
	await _test_actor_scripts()
	print("[CHARREWORK] bridge signals")
	await _test_event_bus_bridge()
	print("[CHARREWORK] support scripts")
	_test_ui_and_support_scripts()

	print("[CHARREWORK] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[CHARREWORK] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[CHARREWORK] FAIL: " + failure)
		print("[CHARREWORK] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _test_playable_data() -> void:
	var seen: Dictionary = {}
	for id in PLAYABLE_IDS:
		var path := "%s/%s.tres" % [PLAYABLE_DIR, id]
		_check(ResourceLoader.exists(path), "playable exists: " + String(id))
		var data := load(path) as ReworkCharacterData
		_check(data != null, "playable loads: " + String(id))
		if data == null:
			continue
		seen[data.id] = true
		_check(data.display_name != "", "display name: " + String(id))
		_check(data.max_hp > 0 and data.speed > 0.0, "stats valid: " + String(id))
		_check(data.primary_weapon != &"" and data.secondary_weapon != &"",
			"weapons assigned: " + String(id))
		var palette_ok := true
		for key in PALETTE_KEYS:
			if not data.palette.has(key):
				palette_ok = false
		_check(palette_ok, "palette complete: " + String(id))
		var passive_path := "res://characters_rework/playable/passives/passive_%s.gd" % data.passive_ability_id
		_check(ResourceLoader.exists(passive_path), "passive script: " + String(id))
	_check(seen.size() == PLAYABLE_IDS.size(), "six unique playable ids")


func _test_narrative_mapping() -> void:
	for id in PLAYABLE_IDS:
		var data := load("%s/%s.tres" % [PLAYABLE_DIR, id]) as ReworkCharacterData
		if data == null:
			continue
		_check(data.narrative_id == NARRATIVE_MAP[id],
			"narrative map: %s -> %s" % [String(id), String(NARRATIVE_MAP[id])])
		if data.narrative_id == &"":
			continue
		var story := GameManager.get_character(data.narrative_id)
		_check(story != null, "narrative character exists: " + String(data.narrative_id))
		if story != null:
			_check(story.id == data.narrative_id, "narrative id round-trip: " + String(data.narrative_id))


func _test_soldier_data() -> void:
	var ids: Array[StringName] = [&"rifleman", &"mg", &"demolition", &"field_medic"]
	for id in ids:
		var path := "%s/%s.tres" % [SOLDIER_DIR, id]
		_check(ResourceLoader.exists(path), "soldier exists: " + String(id))
		var data := load(path) as ReworkSoldierData
		_check(data != null, "soldier loads: " + String(id))
		if data == null:
			continue
		_check(data.max_hp > 0 and data.speed > 0.0, "soldier stats: " + String(id))
		_check(RoleStrategy.SCRIPT_TABLE.has(data.strategy_id), "soldier strategy: " + String(id))


func _test_actor_scripts() -> void:
	var player_script = load("res://characters_rework/playable/PlayerControllerV2.gd")
	_check(player_script != null, "player controller script loads")
	var soldier_script = load("res://characters_rework/soldiers/SoldierBase.gd")
	_check(soldier_script != null, "soldier base script loads")
	_check(ClassDB.class_exists("CharacterBody2D"), "4.x physics body base")
	_check(not ClassDB.class_exists("KinematicBody2D"), "no Godot 3 body API")

	var player := PlayerControllerV2.new()
	add_child(player)
	await get_tree().process_frame
	_check(player.is_in_group("player"), "player joins player group")
	_check(player.hp == player.max_hp and player.max_hp > 0, "player health initialised")
	_check(player.weapon_slots.size() >= 2, "player weapon slots")
	_check(player.character != null, "player character alias")
	var bridge := EventBusBridge.instance()
	_check(bridge != null, "event bus bridge created")
	if bridge != null:
		_check(bridge.actors().has(player), "bridge registers player")
	player.queue_free()
	await get_tree().process_frame

	var soldier := SoldierBase.new()
	soldier.soldier_data = load("%s/rifleman.tres" % SOLDIER_DIR) as ReworkSoldierData
	add_child(soldier)
	await get_tree().process_frame
	_check(soldier.is_in_group("allies"), "soldier joins allies group")
	_check(soldier.hp == soldier.max_hp and soldier.max_hp > 0, "soldier health initialised")
	_check(soldier.strategy != null, "soldier strategy bound")
	var bridge2 := EventBusBridge.instance()
	if bridge2 != null:
		_check(bridge2.actors().has(soldier), "bridge registers soldier")
	soldier.queue_free()
	await get_tree().process_frame


func _test_event_bus_bridge() -> void:
	var fired := [false]
	var callback := func() -> void: fired[0] = true
	EventBus.player_died.connect(callback)
	var bridge := EventBusBridge.instance()
	_check(bridge != null, "bridge available for signal test")
	if bridge != null:
		bridge.call("_emit_if", &"player_died")
		_check(fired[0], "bridge forwards player_died")
	EventBus.player_died.disconnect(callback)


func _test_ui_and_support_scripts() -> void:
	var paths: Array[String] = [
		"res://characters_rework/ui/CharacterSelectV2.gd",
		"res://characters_rework/rendering/PlayerRenderer.gd",
		"res://characters_rework/rendering/SoldierRenderer.gd",
		"res://characters_rework/soldiers/components/CombatComponent.gd",
		"res://characters_rework/soldiers/components/FormationComponent.gd",
	]
	for path in paths:
		var script = load(path)
		_check(script != null, "support script loads: " + path.get_file())
