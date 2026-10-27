class_name NarrativeTrigger
extends Area2D
## A world-space story beat. Walking into it can:
##   conversation  -> DialogueManager.play_conversation(id)
##   archive       -> ArchiveManager.force_unlock(id)
##   hostility     -> FactionManager.set_hostility(faction, value)
##   faction_event -> level.spawn_faction_event(event_id)
##   final_choice  -> open FinalChoiceUI
##   memory        -> Lin Yuan monologue (character-gated)
##   flag          -> SaveSystem story flag
##
## Triggers are built by LevelRunner from LevelData.narrative, so level design
## stays data-driven.

var trigger_id: String = ""
var kind: String = "conversation"
var payload: Dictionary = {}
var requires_character: String = ""
var radius: float = 46.0
var once: bool = true
var level: Node = null

var _fired: bool = false
var _visual: Node2D = null


func configure(config: Dictionary) -> void:
	payload = config.duplicate()
	trigger_id = String(config.get("id", config.get("trigger_id", "")))
	kind = String(config.get("type", "conversation"))
	requires_character = String(config.get("character", ""))
	radius = float(config.get("radius", 46.0))
	once = bool(config.get("once", true))


func _ready() -> void:
	add_to_group("narrative_triggers")
	collision_layer = 0
	collision_mask = 2 # PLAYER
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_build_visual()


func _build_visual() -> void:
	if kind == "final_choice":
		return
	_visual = Node2D.new()
	_visual.z_index = 2
	add_child(_visual)
	var mark := Sprite2D.new()
	mark.texture = SpriteLibrary.ui_texture("crosshair")
	mark.modulate = Color(0.86, 0.74, 0.42, 0.18)
	mark.scale = Vector2(1.6, 1.6)
	_visual.add_child(mark)


func _process(delta: float) -> void:
	if _visual == null or _fired:
		return
	_visual.position.y = sin(Time.get_ticks_msec() * 0.002) * 2.0
	_visual.rotation += delta * 0.2


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	fire(body)


func fire(player: Node = null) -> bool:
	if _fired and once:
		return false
	if requires_character != "":
		var current := ""
		if player != null and is_instance_valid(player):
			var data: Variant = player.get("character")
			if data != null:
				current = String(data.cid())
		if current != requires_character:
			return false
	_fired = true
	EventBus.narrative_triggered.emit(trigger_id if trigger_id != "" else kind)
	match kind:
		"conversation":
			DialogueManager.play_conversation(String(payload.get("conversation", payload.get("id", ""))))
		"memory":
			DialogueManager.play_conversation(String(payload.get("conversation", payload.get("id", ""))))
		"archive":
			var fragment_id := String(payload.get("fragment", payload.get("id", "")))
			ArchiveManager.force_unlock(fragment_id)
			EventBus.notify.emit("剧情档案已收录")
		"hostility":
			FactionManager.set_hostility(String(payload.get("faction", "horizon")), float(payload.get("value", 0.8)))
			EventBus.notify.emit("%s 的敌意发生变化" % FactionManager.display_name(String(payload.get("faction", ""))))
		"faction_event":
			if level != null and level.has_method("spawn_faction_event"):
				level.spawn_faction_event(String(payload.get("event", "")), player)
		"flag":
			SaveSystem.set_flag(StringName(String(payload.get("flag", trigger_id))))
		"final_choice":
			if level != null and level.has_method("open_final_choice"):
				level.open_final_choice()
		"choice":
			if level != null and level.has_method("open_story_choice"):
				level.open_story_choice(String(payload.get("choice", payload.get("id", ""))))
		"tip":
			EventBus.level_event.emit(String(payload.get("text", "")))
	if once and _visual != null:
		_visual.queue_free()
		_visual = null
	return true
