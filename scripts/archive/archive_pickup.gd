class_name ArchivePickup
extends Area2D
## A collectible archive fragment in the world.
##
## Interact key unlocks it if the current survivor has the required expertise.
## In co-op any player who qualifies can unlock it; the fragment is shared.

signal collected(fragment_id: String)

const ICON := "res://assets/sprites/ui/ach_codex.png"

var fragment_id: String = ""
var level: Node = null
var fragment: ArchiveFragment = null
var taken: bool = false

var _sprite: Sprite2D
var _halo: Sprite2D
var _time: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 64
	collision_mask = 0
	monitoring = false
	monitorable = true
	fragment = ArchiveManager.get_fragment(fragment_id)
	_base_y = position.y
	_build_visual()


func _build_visual() -> void:
	var color := Color(0.82, 0.78, 0.62)
	if fragment != null:
		color = fragment.security_color()
	_halo = Sprite2D.new()
	_halo.texture = SpriteLibrary.ui_texture("crosshair")
	_halo.modulate = Color(color.r, color.g, color.b, 0.28)
	_halo.scale = Vector2(2.6, 2.6)
	_halo.z_index = 4
	add_child(_halo)

	_sprite = Sprite2D.new()
	var tex := load(ICON) as Texture2D
	if tex != null:
		_sprite.texture = tex
	_sprite.modulate = color
	_sprite.scale = Vector2(0.85, 0.85)
	_sprite.z_index = 6
	add_child(_sprite)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)


func _process(delta: float) -> void:
	if taken:
		return
	_time += delta
	position.y = _base_y + sin(_time * 2.4) * 2.0
	if _halo != null:
		_halo.modulate.a = 0.20 + 0.14 * sin(_time * 3.1)
	if _sprite != null:
		_sprite.rotation = sin(_time * 1.7) * 0.08


# ------------------------------------------------------------- interact ----
func get_prompt() -> String:
	if taken:
		return ""
	if fragment == null:
		return "E 损坏的档案"
	if ArchiveManager.is_jammed(global_position):
		return "信号干扰 · 档案暂时无法读取"
	if ArchiveManager.is_unlocked(fragment_id):
		return "已收录 · " + fragment.title
	if fragment.is_specialist_gated():
		var who := fragment.required_specialist_name()
		var current := _current_character_id()
		if fragment.required_character != "" and fragment.required_character != current:
			return "需要%s的专业知识" % who
	return "E 查阅档案 · " + fragment.security_label_zh()


func interact(player: Node) -> void:
	if taken or fragment == null:
		return
	var character_id := ""
	var passive_id := ""
	if player != null and is_instance_valid(player):
		var data: Variant = player.get("character")
		if data != null:
			character_id = String(data.cid())
			passive_id = String(data.passive_ability_id)
	var result := ArchiveManager.try_unlock(fragment_id, character_id, passive_id)
	if not bool(result.get("ok", false)):
		var reason := String(result.get("reason", ""))
		if reason == "已收录":
			EventBus.notify.emit("已收录：" + fragment.title)
		else:
			EventBus.notify.emit(reason)
			AudioManager.play_sfx(&"ui_deny")
		return
	taken = true
	collected.emit(fragment_id)
	AudioManager.play_sfx(&"pickup")
	EventBus.toast.emit(fragment.security_name(), fragment.title)
	if level != null and level.has_method("on_archive_collected"):
		level.on_archive_collected(fragment_id)
	_open_viewer()
	queue_free()


func _open_viewer() -> void:
	var packed: PackedScene = load("res://scenes/ui/archive/ArchiveViewer.tscn")
	if packed == null:
		return
	var viewer := packed.instantiate()
	if viewer.has_method("setup"):
		viewer.setup({"fragment_id": fragment_id})
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(viewer)


func _current_character_id() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return ""
	var data: Variant = player.get("character")
	if data == null:
		return ""
	return String(data.cid())
