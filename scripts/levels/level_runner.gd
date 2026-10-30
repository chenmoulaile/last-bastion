class_name LevelRunner
extends Node2D
## Builds and runs one campaign mission from LevelData: procedural terrain,
## parallax, props, doors, supplies, triggers, AI director spawns, extraction,
## scoring and the result payload.

const PLAYER_SCENE := preload("res://characters_rework/playable/PlayerControllerV2.gd")
const ZOMBIE_BASE_SCRIPT := preload("res://scripts/zombies/zombie_base.gd")
const REWORK_CHAR_DIR := "res://characters_rework/data/playable"
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const WINDOW_RAPPEL := preload("res://scripts/interactables/window_rappel.gd")
const MAX_COMMONS := 120
const MAX_SPECIALS := 4
const ZOMBIE_SCENES := {
	&"common": preload("res://scenes/zombies/zombie_common.tscn"),
	&"hunter": preload("res://scenes/zombies/zombie_hunter.tscn"),
	&"smoker": preload("res://scenes/zombies/zombie_smoker.tscn"),
	&"boomer": preload("res://scenes/zombies/zombie_boomer.tscn"),
	&"charger": preload("res://scenes/zombies/zombie_charger.tscn"),
	&"spitter": preload("res://scenes/zombies/zombie_spitter.tscn"),
	&"jockey": preload("res://scenes/zombies/zombie_jockey.tscn"),
	&"tank": preload("res://scenes/zombies/zombie_tank.tscn"),
	&"witch": preload("res://scenes/zombies/zombie_witch.tscn"),
}

@export var level_data: LevelData

var data: LevelData
var level_width: float = 9000.0
var dark: bool = false
var fx_layer: Node2D
var actors: Node2D
var props: Node2D
var interactables: Node2D
var pickups: Node2D
var player: Node2D
var allies: Array = []
var ground_segments: Array = []
var platforms: Array = []
var hud: CanvasLayer
var formation: StringName = &"wedge"
var archive_pickups: Array[Node] = []
var ai_director: Node = null
var comic_layer: CanvasLayer = null
var decode_active: bool = false
var _decode_left: float = 0.0
var _decode_waves: int = 0
var _final_choice_open: bool = false

var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _progress: float = 0.0
var _events_fired: Dictionary = {}
var _score: int = 0
var _combo: int = 0
var _combo_timer: float = 0.0
var _max_combo: int = 0
var _kills: int = 0
var _headshots: int = 0
var _specials_killed: int = 0
var _tanks_killed: int = 0
var _tank_kill_time: float = 999.0
var _tank_spawn_time: float = 0.0
var _boss_node: Node = null
var _network_spawn_override := false
var _boss_kind: StringName = &""
var _boss_nodes: Array = []
var _boss_phase: int = 1
var _boss_max_hp: int = 0
var _ground_segments: Array = []
var _platforms: Array = []
var use_roguelite: bool = false
var roguelite_map: Dictionary = {}
var roguelite_generator: Node = null
var _horde_active: bool = false
var _horde_alive: Array = []
var _horde_pending: int = 0
var _checkpoint_x: float = 0.0
var _checkpoint_active: bool = true
var _checkpoint_respawn_used: bool = false
var _respawn_pos: Vector2 = Vector2.ZERO
var _extraction_started: bool = false
var _extraction_left: float = 0.0
var _extraction_wave_timer: float = 0.0
var _defense_active: bool = false
var _defense_left: float = 0.0
var _defense_total: float = 0.0
var _defense_count: int = 0
var _defense_waves_left: int = 0
var _defense_wave_timer: float = 0.0
var _finishing: bool = false
var _respawning: bool = false
var _hidden_found: bool = false
var _hidden_rooms: Array = []
var _witch_woken: bool = false
var _defense_downs: int = 0
var _soldiers_start: int = 0
var _soldiers_lost: int = 0
var _soldier_roster: Array = []
var _squad_deaths: int = 0
var _barrel_kills: int = 0
var _molotov_kills: int = 0
var _max_molotov_kills: int = 0
var _fire_chain: int = 0
var _fire_chain_timer: float = 0.0
var _rescue_count: int = 0
var _doors_kicked: int = 0
var _hunter_interrupts: int = 0
var _witch_crowns: int = 0
var _boomer_bursts: int = 0
var _codex: Array = []
var _tips_shown: int = 0
var _objective_timer: float = 0.0
var _director_report_timer: float = 0.0
var _safe_room_timer: float = 0.0
var _started_at: float = 0.0


func _ready() -> void:
	data = level_data
	if data == null:
		data = GameManager.current_level
	if data == null:
		push_error("LevelRunner started without LevelData.")
		return
	GameManager.current_level = data
	# Chapter 3 has two routes through one level slot; the chip decision in 2-3
	# decides which one loads. Deep-copy so the shared .tres stays untouched.
	data = data.duplicate(true)
	_apply_route_variant()
	level_width = data.length
	dark = data.dark
	_rng.seed = GameManager.run_seed ^ hash(String(data.id))
	Fx.reset()
	_build_layers()
	_build_background()
	_build_terrain()
	_build_bounds()
	_build_props()
	_build_doors()
	_build_windows()
	_build_barrels_and_crates()
	_build_supplies()
	_build_checkpoint_visual()
	_build_hidden_room()
	_build_extraction()
	_build_zones()
	_build_archives()
	_build_cover_zones()
	_build_narrative()
	_spawn_player()
	_spawn_allies()
	_build_hud()
	_build_faction_layer()
	_build_comic_layer()
	_connect_events()
	_started_at = Time.get_ticks_msec() / 1000.0
	_respawn_pos = player.global_position
	_checkpoint_x = player.global_position.x
	EventBus.objective_changed.emit("推进至撤离点")
	EventBus.safe_room_entered.emit(true)
	_safe_room_timer = 2.0
	AudioManager.play_ambience(StringName("rain" if data.rain else String(data.theme)))
	AudioManager.set_ambience_reverb_for_theme(String(data.theme))
	if data.tutorial_tips.size() > 0:
		EventBus.level_event.emit(data.tutorial_tips[0])
		_tips_shown = 1
	else:
		EventBus.level_event.emit(data.title + " — " + data.subtitle)
	call_deferred("_intro")
	var net := get_node_or_null("/root/NetworkManager")
	if net != null and bool(net.call("is_multiplayer_active")):
		net.call_deferred("notify_level_ready")


func _intro() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	EventBus.level_event.emit("%s · %s" % [data.chapter_name, data.title])
	EventBus.notify.emit(data.new_threat)


func _build_layers() -> void:
	fx_layer = Node2D.new()
	fx_layer.name = "FX"
	fx_layer.z_index = 20
	add_child(fx_layer)
	props = Node2D.new()
	props.name = "Props"
	props.z_index = 1
	add_child(props)
	interactables = Node2D.new()
	interactables.name = "Interactables"
	interactables.z_index = 3
	add_child(interactables)
	pickups = Node2D.new()
	pickups.name = "Pickups"
	pickups.z_index = 5
	add_child(pickups)
	actors = Node2D.new()
	actors.name = "Actors"
	actors.z_index = 5
	add_child(actors)


func _build_background() -> void:
	var theme := String(data.theme)
	var bg := ParallaxBackground.new()
	bg.name = "Background"
	add_child(bg)
	_add_parallax(bg, "bg_%s_sky" % theme, 0.03, 640.0, false)
	_add_parallax(bg, "bg_%s_far" % theme, 0.14, 960.0, true)
	_add_parallax(bg, "bg_%s_mid" % theme, 0.34, 960.0, true)
	if dark:
		var cm := CanvasModulate.new()
		cm.color = Color(0.17, 0.20, 0.28)
		add_child(cm)
	# A subtle ground-level fog band helps the 360p silhouette read.
	var fog := ColorRect.new()
	fog.color = Color(0.55, 0.6, 0.68, 0.05)
	fog.position = Vector2(0, 230)
	fog.size = Vector2(640, 130)
	fog.z_index = 2
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog)


func _add_parallax(parent: ParallaxBackground, texture_name: String, scale_value: float,
		width: float, mirror: bool) -> void:
	var tex := SpriteLibrary.prop_texture(texture_name)
	if tex == null:
		return
	var layer := ParallaxLayer.new()
	layer.motion_scale = Vector2(scale_value, 1.0)
	if mirror:
		layer.motion_mirroring = Vector2(width, 0)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = Vector2(0, 0)
	layer.add_child(sprite)
	parent.add_child(layer)


func _build_terrain() -> void:
	if use_roguelite:
		_build_roguelite_rooms()
		return
	var built := TerrainBuilder.build(self, String(data.theme), level_width, _rng, dark)
	ground_segments = built.get("segments", [])
	platforms = built.get("platforms", [])


func _build_roguelite_rooms() -> void:
	var gen: RogueliteMapGenerator = RogueliteMapGenerator.instance()
	roguelite_generator = gen
	add_child(gen)
	var seed_val := int(GameManager.run_seed)
	var map_data: Dictionary = gen.generate(seed_val, 10, 10)
	roguelite_map = map_data
	var rooms_array: Array = map_data.get("rooms", [])
	var room_size: float = float(map_data.get("room_size", 420.0))
	# 实例化房间场景
	for room_info in rooms_array:
		var scene: PackedScene = room_info.get("scene", null)
		if scene == null:
			continue
		var instance: Node2D = scene.instantiate()
		instance.position = Vector2(
			float(room_info.get("world_x", 0.0)),
			float(room_info.get("world_y", 0.0))
		)
		instance.name = "Room_" + str(room_info.get("x", 0)) + "_" + str(room_info.get("y", 0))
		add_child(instance)
		# 根据房间类型设置内容
		var rtype := int(room_info.get("type", 0))
		if rtype == 0:  # START
			_setup_start_room(instance)
		elif rtype == 1:  # COMBAT
			_setup_combat_room(instance)
		elif rtype == 2:  # SUPPLY
			_setup_supply_room(instance)
		elif rtype == 4:  # BOSS
			_setup_boss_room(instance)

	# 设置关卡宽度
	level_width = 10.0 * room_size


func _setup_start_room(room: Node2D) -> void:
	var spawn := room.get_node_or_null("SpawnPoint")
	if spawn != null:
		var player := get_node_or_null("Player")
		if player == null:
			# 玩家由 _spawn_player 创建，这里记录出生点
			pass

func _setup_combat_room(room: Node2D) -> void:
	# 在战斗房间生成敌人
	var spawn1 := room.get_node_or_null("EnemySpawn1")
	var spawn2 := room.get_node_or_null("EnemySpawn2")
	if spawn1 != null:
		_spawn_zombie(&"common", spawn1.global_position, false)
	if spawn2 != null:
		_spawn_zombie(&"common", spawn2.global_position, false)

func _setup_supply_room(room: Node2D) -> void:
	var drop1 := room.get_node_or_null("SupplyDrop1")
	var drop2 := room.get_node_or_null("SupplyDrop2")
	# 补给物品由道具系统生成

func _setup_boss_room(room: Node2D) -> void:
	var boss_spawn := room.get_node_or_null("BossSpawn")
	if boss_spawn != null:
		spawn_boss(&"tank", 1)


## 获取 roguelite 模式下的地图宽度。
func get_roguelite_width() -> float:
	return level_width


## 获取 roguelite 地图数据。
func get_roguelite_map() -> Dictionary:
	return roguelite_map


func _build_bounds() -> void:
	for x in [-24.0, level_width + 24.0]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector2(x, 150)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32, 420)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)


func _build_props() -> void:
	var x := 180.0
	while x < level_width - 180.0:
		x += _rng.randf_range(130.0, 260.0)
		var gy := get_ground_y(x)
		if gy < 0.0:
			continue
		var tex_name := _pick_prop()
		var tex := SpriteLibrary.prop_texture(tex_name)
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.position = Vector2(x, gy - tex.get_height())
		sprite.z_index = 1
		sprite.flip_h = _rng.randf() < 0.5
		props.add_child(sprite)


func _pick_prop() -> String:
	var pool: Array = ["barrel", "crate", "sign", "sandbags", "dumpster", "car"]
	match String(data.theme):
		"city":
			pool = ["car", "dumpster", "sign", "streetlight", "generator", "sandbags"]
		"subway":
			pool = ["barrel", "crate", "generator", "sandbags", "sign"]
		"military":
			pool = ["sandbags", "generator", "car", "barrel", "barbed_wire", "sign"]
		"bridge":
			pool = ["car", "sandbags", "barbed_wire", "barrel", "sign"]
	return pool.pick_random()


func _build_doors() -> void:
	var door_kind := "wood"
	if String(data.theme) in ["city", "military", "bridge"]:
		door_kind = "metal"
	if String(data.theme) == "subway":
		door_kind = "metal"
	for frac in [0.16, 0.36, 0.56, 0.76]:
		var x := _nearest_ground_x(level_width * frac)
		if x < 0.0:
			continue
		var door := LevelDoor.new()
		door.level = self
		door.kind = door_kind if _rng.randf() < 0.7 else "glass"
		door.position = Vector2(x, get_ground_y(x))
		interactables.add_child(door)


func _build_windows() -> void:
	var placed := 0
	for platform in platforms:
		if float(platform["y"]) > 180.0:
			continue
		if float(platform["x1"]) < 420.0:
			continue
		if placed > 0 and _rng.randf() < 0.45:
			continue
		var x := float(platform["x0"]) + 14.0
		if _rng.randf() < 0.5:
			x = float(platform["x1"]) - 14.0
		if get_ground_y(x) < 0.0:
			continue
		var window = WINDOW_RAPPEL.new()
		window.level = self
		window.position = Vector2(x, float(platform["y"]))
		interactables.add_child(window)
		placed += 1
		if placed >= 4:
			break


func _build_barrels_and_crates() -> void:
	var bx := 420.0
	while bx < level_width - 300.0:
		bx += _rng.randf_range(480.0, 820.0)
		var x := _nearest_ground_x(bx)
		if x < 0.0:
			continue
		var barrel := ExplosiveBarrel.new()
		barrel.level = self
		barrel.position = Vector2(x, get_ground_y(x))
		interactables.add_child(barrel)
	var cx := 560.0
	while cx < level_width - 300.0:
		cx += _rng.randf_range(540.0, 900.0)
		var x := _nearest_ground_x(cx)
		if x < 0.0:
			continue
		var crate := BreakableCrate.new()
		crate.level = self
		crate.position = Vector2(x, get_ground_y(x))
		interactables.add_child(crate)


func _build_supplies() -> void:
	var ammo_count := maxi(2, data.ammo_crates)
	for i in ammo_count:
		var frac := 0.12 + 0.70 * float(i) / float(maxi(1, ammo_count - 1))
		_spawn_pickup("ammo", _ground_pos(level_width * frac + _rng.randf_range(-40, 40)), 90)
	for i in maxi(1, data.medkits):
		var frac := 0.28 + 0.52 * float(i) / float(maxi(1, data.medkits))
		_spawn_pickup("medkit", _ground_pos(level_width * frac + _rng.randf_range(-50, 50)), 1)
	_spawn_pickup("pills", _ground_pos(level_width * 0.46), 1)
	_spawn_pickup("pills", _ground_pos(level_width * 0.80), 1)
	_spawn_pickup("grenade", _ground_pos(level_width * 0.34), 1)
	_spawn_pickup("molotov", _ground_pos(level_width * 0.64), 1)
	_spawn_pickup("bile", _ground_pos(level_width * 0.88), 1)
	for i in data.player_weapons.size():
		var wid := String(data.player_weapons[i])
		if wid == "":
			continue
		var frac := 0.40 + 0.20 * float(i)
		_spawn_pickup("weapon", _ground_pos(level_width * frac), 1, wid)
	for i in 3:
		_spawn_pickup("gold", _ground_pos(level_width * (0.2 + i * 0.27)), 400)


func _build_checkpoint_visual() -> void:
	var x := _nearest_ground_x(level_width * data.checkpoint_at)
	if x < 0.0:
		return
	var sign_sprite := Sprite2D.new()
	sign_sprite.texture = SpriteLibrary.prop_texture("sign")
	sign_sprite.centered = false
	sign_sprite.position = Vector2(x, get_ground_y(x) - 28)
	sign_sprite.z_index = 2
	props.add_child(sign_sprite)
	var gen := Sprite2D.new()
	gen.texture = SpriteLibrary.prop_texture("generator")
	gen.centered = false
	gen.position = Vector2(x + 28, get_ground_y(x) - 24)
	gen.z_index = 2
	props.add_child(gen)


func _build_hidden_room() -> void:
	var x := _nearest_ground_x(level_width * data.hidden_room_at)
	if x < 0.0:
		return
	var platform_y := 200.0
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(x, platform_y)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(104, 8)
	shape.shape = rect
	shape.one_way_collision = true
	body.add_child(shape)
	interactables.add_child(body)
	var visual := Sprite2D.new()
	visual.texture = SpriteLibrary.prop_texture("sandbags")
	visual.centered = false
	visual.scale = Vector2(2.6, 1.0)
	visual.position = Vector2(x - 52, platform_y - 18)
	visual.z_index = 2
	props.add_child(visual)
	var sign_sprite := Sprite2D.new()
	sign_sprite.texture = SpriteLibrary.prop_texture("sign")
	sign_sprite.centered = false
	sign_sprite.position = Vector2(x - 20, platform_y - 50)
	sign_sprite.z_index = 2
	props.add_child(sign_sprite)
	_spawn_pickup("gold", Vector2(x - 34, platform_y - 20), 900)
	_spawn_pickup("gold", Vector2(x, platform_y - 20), 900)
	_spawn_pickup("gold", Vector2(x + 34, platform_y - 20), 900)
	_spawn_pickup("medkit", Vector2(x + 18, platform_y - 20), 1)
	var weapon := "sniper"
	if data.id == &"l08":
		weapon = "chainsaw"
	elif data.id in [&"l10", &"l11"]:
		weapon = "lmg"
	_spawn_pickup("weapon", Vector2(x - 8, platform_y - 20), 1, weapon)
	# Trigger sits above the stash.
	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.position = Vector2(x, platform_y - 52)
	var cshape := CollisionShape2D.new()
	var crect := RectangleShape2D.new()
	crect.size = Vector2(120, 110)
	cshape.shape = crect
	trigger.add_child(cshape)
	trigger.body_entered.connect(_on_hidden_trigger)
	add_child(trigger)


func _build_extraction() -> void:
	var x := _nearest_ground_x(level_width - 150.0)
	if x < 0.0:
		return
	var tex_name := "sign"
	match data.extraction:
		"helicopter":
			tex_name = "helicopter"
		"apc":
			tex_name = "apc"
		_:
			tex_name = "door_metal"
	var tex := SpriteLibrary.prop_texture(tex_name)
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.position = Vector2(x - tex.get_width() * 0.5, get_ground_y(x) - tex.get_height())
		sprite.z_index = 2
		props.add_child(sprite)
	var sand := SpriteLibrary.prop_texture("sandbags")
	if sand:
		for i in 3:
			var sb := Sprite2D.new()
			sb.texture = sand
			sb.centered = false
			sb.position = Vector2(x - 70 + i * 42, get_ground_y(x) - 18)
			sb.z_index = 2
			props.add_child(sb)
	if data.escort_vehicle:
		var apc := SpriteLibrary.prop_texture("apc")
		if apc:
			var apc_sprite := Sprite2D.new()
			apc_sprite.texture = apc
			apc_sprite.centered = false
			apc_sprite.position = Vector2(x - 220, get_ground_y(x) - 52)
			apc_sprite.z_index = 2
			props.add_child(apc_sprite)


func _build_zones() -> void:
	var cx := _nearest_ground_x(level_width * data.checkpoint_at)
	if cx > 0.0:
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = Vector2(cx, get_ground_y(cx) - 40)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(90, 110)
		shape.shape = rect
		area.add_child(shape)
		area.body_entered.connect(_on_checkpoint_trigger)
		add_child(area)
	var ex := _nearest_ground_x(level_width - 140.0)
	if ex > 0.0:
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = Vector2(ex, get_ground_y(ex) - 50)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(150, 140)
		shape.shape = rect
		area.add_child(shape)
		area.body_entered.connect(_on_extraction_trigger)
		add_child(area)


func _spawn_player() -> void:
	var p: Node2D = PlayerControllerV2.new()
	p.level = self
	p.auto_camera = true
	p.position = Vector2(220, get_ground_y(220))
	# 解析选中的角色数据：优先用 GameManager.selected_character，回退到关卡默认武器对应的角色。
	var char_id := GameManager.selected_character
	var rework_data: ReworkCharacterData = null
	if char_id != &"":
		var path := "%s/%s.tres" % [REWORK_CHAR_DIR, String(char_id)]
		if ResourceLoader.exists(path):
			rework_data = load(path) as ReworkCharacterData
	if rework_data == null:
		var fallback_id := &"assault"
		var fb_path := "%s/%s.tres" % [REWORK_CHAR_DIR, String(fallback_id)]
		if ResourceLoader.exists(fb_path):
			rework_data = load(fb_path) as ReworkCharacterData
	p.character_data = rework_data
	var net := get_node_or_null("/root/NetworkManager")
	if net != null and bool(net.call("is_multiplayer_active")):
		var pid := int(net.call("get_peer_id"))
		p.name = "Player_" + str(pid)
		p.set_multiplayer_authority(pid)
	actors.add_child(p)
	player = p
	for wid in data.player_weapons:
		var id := StringName(wid)
		if id != &"":
			p.give_weapon(id)
	# Tutorial loadout: one throwable of each type, as the design doc specifies.
	if player.get("throwables") is Dictionary:
		var th: Dictionary = player.get("throwables")
		th["grenade"] = 1
		th["molotov"] = 1
		th["bile"] = 1


func spawn_network_player(peer_id: int, character_id: StringName, x: float, y: float) -> void:
	var p: Node2D = PlayerControllerV2.new()
	p.level = self
	# Remote bodies must never create a Camera2D: the last camera made current
	# would steal the view from the local player on this peer.
	p.auto_camera = false
	p.is_remote_player = true
	p.position = Vector2(x, y)
	p.name = "Player_" + str(peer_id)
	p.set_multiplayer_authority(peer_id)
	var path := "%s/%s.tres" % [REWORK_CHAR_DIR, String(character_id)]
	var rework_data: ReworkCharacterData = null
	if ResourceLoader.exists(path):
		rework_data = load(path) as ReworkCharacterData
	if rework_data == null:
		var fb_path := "%s/%s.tres" % [REWORK_CHAR_DIR, "assault"]
		if ResourceLoader.exists(fb_path):
			rework_data = load(fb_path) as ReworkCharacterData
	p.character_data = rework_data
	actors.add_child(p)
	for wid in data.player_weapons:
		var id := StringName(wid)
		if id != &"":
			p.give_weapon(id)
	if p.get("throwables") is Dictionary:
		var th: Dictionary = p.get("throwables")
		th["grenade"] = 1
		th["molotov"] = 1
		th["bile"] = 1


func _spawn_allies() -> void:
	var ids: Array = []
	if GameManager.current_mode == &"COMMAND":
		ids = GameManager.selected_soldiers.duplicate()
		_soldiers_start = ids.size()
	else:
		ids = GameManager.selected_squad.duplicate()
		if ids.is_empty():
			ids = [&"medic", &"heavy", &"scout"]
	_soldier_roster = ids.duplicate()
	for i in mini(ids.size(), 8):
		var char_data := GameManager.get_character(StringName(ids[i]))
		if char_data == null:
			char_data = GameManager.get_character(&"rifleman")
		if char_data == null:
			continue
		var ally := AllyAgent.new()
		ally.level = self
		ally.data = char_data
		ally.ally_index = i
		ally.is_soldier = GameManager.current_mode == &"COMMAND"
		ally.formation = formation
		var px := player.position.x - 34.0 - i * 24.0
		var gy := get_ground_y(px)
		if gy < 0.0:
			px = player.position.x
			gy = player.position.y
		ally.position = Vector2(px, gy)
		actors.add_child(ally)
		allies.append(ally)


func _build_hud() -> void:
	hud = HUD_SCENE.instantiate()
	hud.level = self
	add_child(hud)


func _connect_events() -> void:
	EventBus.director_request_special.connect(_on_director_special)
	EventBus.director_request_horde.connect(_on_director_horde)
	EventBus.director_request_supply.connect(_on_director_supply)
	EventBus.director_request_boss.connect(_on_director_boss)
	EventBus.gunshot.connect(_on_gunshot)
	EventBus.door_kicked.connect(_on_door_kicked)
	EventBus.player_died.connect(on_player_died)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or _finishing:
		return
	_elapsed += delta
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0 and _combo > 0:
			_combo = 0
			EventBus.combo_changed.emit(0, 1.0)
	if _fire_chain_timer > 0.0:
		_fire_chain_timer -= delta
		if _fire_chain_timer <= 0.0:
			_fire_chain = 0
	if _safe_room_timer > 0.0:
		_safe_room_timer -= delta
		if _safe_room_timer <= 0.0:
			EventBus.safe_room_entered.emit(false)
	if player == null or not is_instance_valid(player):
		return
	_progress = clampf(player.global_position.x / level_width, 0.0, 1.0)
	_fire_due_events()
	_show_tips()
	_tick_defense(delta)
	_tick_extraction(delta)
	_check_horde()
	_director_report_timer += delta
	if _director_report_timer >= 0.5:
		_director_report_timer = 0.0
		_report_party()
		_tick_boss_phases(delta)
	_objective_timer += delta
	if _objective_timer >= 1.0:
		_objective_timer = 0.0
		if not _extraction_started and not _defense_active:
			EventBus.objective_changed.emit("推进至撤离点 · %d%%" % int(_progress * 100.0))
	# The player can also walk past the extraction zone without triggering it.
	if not _extraction_started and player.global_position.x > level_width - 120.0:
		_on_extraction_trigger(player)


func _fire_due_events() -> void:
	for i in data.events.size():
		var key := "ev_%d" % i
		if _events_fired.has(key):
			continue
		var ev: Dictionary = data.events[i]
		if float(ev.get("at", 0.0)) <= _progress:
			_events_fired[key] = true
			_fire_event(ev)


func _fire_event(ev: Dictionary) -> void:
	var kind := String(ev.get("type", ""))
	match kind:
		"tip":
			EventBus.level_event.emit(String(ev.get("text", "")))
		"horde":
			start_horde(int(ev.get("count", 16)), bool(ev.get("alarm", false)))
		"special":
			spawn_special(StringName(ev.get("kind", "hunter")))
		"supply":
			_spawn_director_supply(StringName(ev.get("kind", "ammo")))
		"defense":
			start_defense(float(ev.get("seconds", 40.0)), int(ev.get("waves", 2)), int(ev.get("count", 18)))
		"boss":
			spawn_boss(StringName(ev.get("kind", "tank")), int(ev.get("count", 1)))
		"witch":
			var wx := _nearest_ground_x(level_width * _progress + float(ev.get("x_offset", 0.0)))
			if wx > 0.0:
				_spawn_zombie(&"witch", Vector2(wx, get_ground_y(wx)), false)
		"elevator":
			EventBus.level_event.emit("电梯警报响起——守住这层楼！")
			start_horde(14, true)
		"faction":
			spawn_faction_event(String(ev.get("event", "")), player)
		"narrative":
			DialogueManager.play_conversation(String(ev.get("conversation", "")))
		"final_choice":
			open_final_choice()
		_:
			EventBus.level_event.emit(String(ev.get("text", "")))


func _show_tips() -> void:
	if _tips_shown >= data.tutorial_tips.size():
		return
	var thresholds := [0.10, 0.22, 0.34, 0.48]
	var index := _tips_shown - 1
	if index >= 0 and index < thresholds.size() and _progress >= thresholds[index]:
		EventBus.level_event.emit(data.tutorial_tips[_tips_shown])
		_tips_shown += 1


func _report_party() -> void:
	if player == null:
		return
	var total_hp := float(player.get("hp")) / maxf(1.0, float(player.get("max_hp")))
	var count := 1
	var alive := 1
	for ally in allies:
		if ally == null or not is_instance_valid(ally):
			continue
		if bool(ally.get("is_dead")):
			continue
		alive += 1
		total_hp += float(ally.get("hp")) / maxf(1.0, float(ally.get("max_hp")))
		count += 1
	var avg_hp := total_hp / float(maxi(1, count))
	DirectorSystem.report_party(avg_hp, 0.8, player.global_position.x)
	DirectorSystem.set_boss_active(_boss_node != null and is_instance_valid(_boss_node))


# ---------------------------------------------------- narrative / factions ----


# ---------------------------------------------------- narrative / factions ----
func _level_number() -> int:
	var digits := ""
	for i in String(data.id).length():
		var ch := String(data.id)[i]
		if ch >= "0" and ch <= "9":
			digits += ch
	return int(digits) if digits != "" else 1


## 3-1A / 3-1B share level slot l07; the route is chosen by the chapter 2 chip.
func _apply_route_variant() -> void:
	if String(data.id) != "l07":
		return
	if GameManager.route_variant() == &"sewer":
		data.title = "排水系统"
		data.subtitle = "绕后路线。下面全是失败品。"
		data.theme = &"subway"
		data.music_theme = &"subway"
		data.dark = true
		data.rain = false
		data.route_label = "3-1A · 绕后"
	else:
		data.title = "净化区正门"
		data.subtitle = "硬闯路线。防御塔已经上电。"
		data.theme = &"military"
		data.music_theme = &"military"
		data.dark = false
		data.rain = false
		data.route_label = "3-1B · 正门"


## Terrain is procedural, so a fixed ratio can land in a pit. Probe outwards for
## the nearest walkable column before placing story props.
func _ground_point_near(x: float) -> Vector2:
	for offset in [0.0, 40.0, -40.0, 80.0, -80.0, 140.0, -140.0, 220.0, -220.0, 320.0, -320.0]:
		var probe := clampf(x + offset, 80.0, level_width - 80.0)
		var gy := get_ground_y(probe)
		if gy > 0.0:
			return Vector2(probe, gy)
	return Vector2.ZERO


## Places archive fragments. When the previous chapter's quota is unmet, extra
## spawn points are added so the player can catch up (design 2.3).
func _build_archives() -> void:
	if data.archive_slots <= 0:
		return
	var chapter := data.chapter
	var slots := data.archive_slots + ArchiveManager.extra_spawn_slots(chapter - 1)
	var ids := ArchiveManager.plan_for_level(chapter, _level_number(), slots)
	var ratios := [0.22, 0.38, 0.52, 0.66, 0.78, 0.88]
	for i in ids.size():
		var ratio: float = ratios[i % ratios.size()]
		var point := _ground_point_near(level_width * ratio)
		if point == Vector2.ZERO:
			continue
		var pickup := ArchivePickup.new()
		pickup.fragment_id = ids[i]
		pickup.level = self
		pickup.position = point - Vector2(0, 24.0)
		pickups.add_child(pickup)
		archive_pickups.append(pickup)
	if not ids.is_empty():
		EventBus.level_event.emit("检测到 %d 份档案信号" % ids.size())


## Cover volumes feed Lucia's passive. They are gameplay areas, not colliders.
func _build_cover_zones() -> void:
	for ratio in [0.28, 0.44, 0.61, 0.75, 0.9]:
		var point := _ground_point_near(level_width * float(ratio))
		if point == Vector2.ZERO:
			continue
		var area := Area2D.new()
		area.name = "Cover"
		area.add_to_group("cover")
		area.collision_layer = 64
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(56, 34)
		shape.shape = rect
		shape.position = Vector2(0, -17)
		area.add_child(shape)
		var sprite := Sprite2D.new()
		sprite.texture = SpriteLibrary.prop_texture("sandbags")
		if sprite.texture != null:
			sprite.centered = false
			sprite.position = Vector2(-28, -32)
			sprite.z_index = 1
			area.add_child(sprite)
		area.position = point
		props.add_child(area)


## Story beats are Area2D triggers built from LevelData.narrative.
func _build_narrative() -> void:
	for row in data.narrative:
		if not (row is Dictionary):
			continue
		var config: Dictionary = row
		var trigger := NarrativeTrigger.new()
		trigger.level = self
		trigger.configure(config)
		var at := float(config.get("at", 0.5))
		var point := _ground_point_near(level_width * at)
		if point == Vector2.ZERO:
			continue
		trigger.position = point - Vector2(0, 24.0)
		add_child(trigger)


func _build_faction_layer() -> void:
	ai_director = AIDirector.new()
	ai_director.name = "AIDirector"
	ai_director.level = self
	add_child(ai_director)


func _build_comic_layer() -> void:
	comic_layer = CanvasLayer.new()
	comic_layer.name = "ComicPostProcess"
	comic_layer.set_script(load("res://scripts/fx/comic_post_process.gd"))
	add_child(comic_layer)


# ------------------------------------------------------------- spawn hooks ----
func spawn_faction_unit(faction_id: String, unit_kind: String, pos: Vector2) -> Node:
	var unit := FactionUnit.new()
	unit.faction_id = faction_id
	unit.unit_kind = unit_kind
	unit.level = self
	var gy := get_ground_y(pos.x)
	unit.position = Vector2(pos.x, gy if gy > 0.0 else pos.y)
	actors.add_child(unit)
	return unit


func spawn_faction_event(event_id: String, player_node: Node = null) -> void:
	var origin: Vector2 = player_node.global_position if player_node != null else Vector2.ZERO
	match event_id:
		"rust_ambush":
			for i in 3:
				spawn_faction_unit("rust", "rust_enforcer", origin + Vector2(-260.0 - i * 40.0, 0))
			EventBus.level_event.emit("锈帮伏击！")
		"remnant_support":
			for i in 2:
				spawn_faction_unit("remnants", "remnant_patrol", origin + Vector2(-120.0 + i * 50.0, 0))
			EventBus.level_event.emit("残警火力支援抵达")
		"horizon_sweep":
			for i in 3:
				spawn_faction_unit("horizon", "horizon_enforcer", origin + Vector2(300.0 + i * 40.0, 0))
			EventBus.level_event.emit("地平线清扫队正在接近")
		"signal_jam":
			spawn_faction_unit("signal_bureau", "signal_jammer", origin + Vector2(260.0, 0))
			EventBus.level_event.emit("信号局部署干扰器")
		_:
			EventBus.level_event.emit("派系活动：" + event_id)


## Victor's passive drops these; they convert into supplies at the next crate.
func spawn_sample(pos: Vector2) -> void:
	var sample := Pickup.new()
	sample.kind = "ammo"
	sample.amount = 30
	sample.level = self
	sample.position = Vector2(pos.x, pos.y - 10.0)
	pickups.add_child(sample)
	add_score(150)


func on_archive_collected(fragment_id: String) -> void:
	add_score(5000)
	var fragment := ArchiveManager.get_fragment(fragment_id)
	var title := fragment.title if fragment != null else fragment_id
	EventBus.level_event.emit("档案收录：" + title)
	EventBus.objective_changed.emit("档案 %d/%d" % [ArchiveManager.unlocked_count(), ArchiveManager.total_count()])
	if ArchiveManager.chapter_quota_met(data.chapter):
		EventBus.notify.emit("本章档案进度已达标")


func get_archive_pickups() -> Array[Node]:
	var out: Array[Node] = []
	for pickup in archive_pickups:
		if pickup != null and is_instance_valid(pickup) and not bool(pickup.get("taken")):
			out.append(pickup)
	return out


func nearest_archive_position(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_dist := INF
	for pickup in get_archive_pickups():
		var dist := from.distance_to(pickup.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pickup.global_position
	return best


func burn_archive_pickup(pickup: Node) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	var fragment_id := String(pickup.get("fragment_id"))
	archive_pickups.erase(pickup)
	Fx.explosion(fx_layer, pickup.global_position, 1.4)
	AudioManager.play_sfx(&"barrel_explode")
	EventBus.notify.emit("档案被销毁：" + fragment_id)
	EventBus.level_event.emit("证据销毁小队烧毁了一份档案")
	pickup.queue_free()


func clamp_spawn_x(x: float) -> float:
	return clampf(x, 80.0, level_width - 80.0)


# ------------------------------------------------------------- final choice ----
func open_final_choice() -> void:
	var packed: PackedScene = load("res://scenes/ui/narrative/FinalChoiceUI.tscn")
	if packed == null:
		return
	var ui := packed.instantiate()
	ui.set("level", self)
	add_child(ui)


func open_story_choice(choice_id: String) -> void:
	if not StoryChoices.has(choice_id):
		return
	var packed: PackedScene = load("res://scenes/ui/narrative/StoryChoiceUI.tscn")
	if packed == null:
		return
	var ui := packed.instantiate()
	ui.set("level", self)
	ui.set("choice_id", choice_id)
	add_child(ui)


func play_destroy_ending() -> void:
	EventBus.level_event.emit("信号已终止")
	EventBus.objective_changed.emit("信号已终止")
	AudioManager.play_sfx(&"explosion")
	Fx.explosion(fx_layer, player.global_position + Vector2(0, -20), 4.0)
	AudioLayerManager.play_explosion_layer()
	AudioManager.duck_music(30.0, 0.8)
	if PostProcess != null:
		PostProcess.pulse_blood_distortion(0.8, 0.4)
	EventBus.shake(6.0)
	EventBus.gore_event.emit(1.4)
	await get_tree().create_timer(1.0, true, false, true).timeout
	DialogueManager.play_conversation("ending_destroy")
	await get_tree().create_timer(7.5, true, false, true).timeout
	if is_instance_valid(self):
		_finish_level()


func start_decode_defense(seconds: float, waves: int) -> void:
	decode_active = true
	_decode_left = seconds
	_decode_waves = waves
	EventBus.level_event.emit("解码开始——守住设备 90 秒")
	EventBus.objective_changed.emit("解码防守 %ds" % int(seconds))
	start_defense(seconds, waves, 22)
	if ArchiveManager.highest_security_level_collected() >= 4:
		# 信号核心防御协议：额外两波敌人
		_decode_waves += 2
		EventBus.level_event.emit("信号核心防御协议启动")


func _finish_decode() -> void:
	decode_active = false
	SaveSystem.set_flag(&"lin_yuan_epilogue")
	EventBus.level_event.emit("解码完成 · 坐标与名单已解析")
	DialogueManager.play_conversation("ending_decode")
	await get_tree().create_timer(8.0, true, false, true).timeout
	if is_instance_valid(self):
		_finish_level()


# ------------------------------------------------------------------ events ----
func start_horde(count: int, _alarm: bool = true) -> void:
	if _finishing:
		return
	_horde_active = true
	_horde_pending = 0
	EventBus.horde_started.emit(count)
	AudioManager.set_intensity(0.9)
	EventBus.notify.emit("尸潮来袭！")
	EventBus.level_event.emit("尸潮")
	_spawn_horde_around(player.global_position, count, true)


func spawn_horde_at(pos: Vector2, count: int, alert: bool = true) -> void:
	if _finishing:
		return
	_horde_active = true
	_horde_pending = 0
	EventBus.horde_started.emit(count)
	AudioManager.set_intensity(0.95)
	_spawn_horde_around(pos, count, alert)


func _spawn_horde_around(pos: Vector2, count: int, alert: bool) -> void:
	var room := MAX_COMMONS - _alive_common_count()
	count = mini(count, room)
	if count <= 0:
		return
	for i in count:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var x := pos.x + side * _rng.randf_range(260.0, 620.0)
		x = clampf(x, 80.0, level_width - 80.0)
		var kind := _pick_common_kind()
		var z := _spawn_zombie(StringName(kind), _ground_pos(x), alert)
		if z != null:
			_horde_alive.append(z)


func _pick_common_kind() -> String:
	if not data.uncommon_weights.is_empty() and _rng.randf() < 0.16:
		var pick := MathUtils.weighted_pick(data.uncommon_weights, _rng)
		if pick != "":
			return pick
	return "common"


func _check_horde() -> void:
	if not _horde_active:
		return
	for i in range(_horde_alive.size() - 1, -1, -1):
		var z = _horde_alive[i]
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			_horde_alive.remove_at(i)
	if _horde_pending <= 0 and _horde_alive.is_empty():
		_horde_active = false
		EventBus.horde_ended.emit()
		AudioManager.set_intensity(0.35)


func _alive_common_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		if node == null or not is_instance_valid(node) or bool(node.get("dead")):
			continue
		if node.get("level") != self:
			continue
		if node.is_in_group("faction_units"):
			continue
		var zd: ZombieData = node.get("data")
		if zd != null and not zd.is_special:
			count += 1
	return count


func _alive_special_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		if node == null or not is_instance_valid(node) or bool(node.get("dead")):
			continue
		if node.get("level") != self:
			continue
		if node.is_in_group("faction_units"):
			continue
		var zd: ZombieData = node.get("data")
		if zd != null and zd.is_special and zd.id != &"witch":
			count += 1
	return count


func spawn_special(kind: StringName) -> void:
	if _finishing or player == null:
		return
	if _alive_special_count() >= MAX_SPECIALS:
		return
	var dir := 1.0 if _rng.randf() < 0.65 else -1.0
	var x := player.global_position.x + dir * _rng.randf_range(360.0, 620.0)
	x = clampf(x, 100.0, level_width - 100.0)
	var z := _spawn_zombie(kind, _ground_pos(x), true)
	if z != null:
		EventBus.notify.emit("特殊感染者：%s" % _zombie_name(kind))
		AudioManager.play_sfx(&"special_sting")


func spawn_boss(kind: StringName, count: int = 1) -> void:
	for i in count:
		var x := player.global_position.x + 420.0 + i * 90.0
		x = clampf(x, 120.0, level_width - 120.0)
		var z := _spawn_zombie(kind, _ground_pos(x), true)
		if z != null and i == 0:
			EventBus.level_event.emit("%s 出现" % _zombie_name(kind))


func _on_director_special(kind: StringName) -> void:
	if GameManager.state == GameManager.State.PLAYING and not _finishing:
		spawn_special(kind)


func _on_director_horde(count: int) -> void:
	if GameManager.state == GameManager.State.PLAYING and not _finishing:
		start_horde(count, true)


func _on_director_supply(kind: StringName) -> void:
	_spawn_director_supply(kind)


func _on_director_boss(kind: StringName) -> void:
	if GameManager.state == GameManager.State.PLAYING and not _finishing:
		spawn_boss(kind, 1)
		EventBus.notify.emit("Boss 波次来袭！")


func _spawn_director_supply(kind: StringName) -> void:
	var x := player.global_position.x + 180.0
	x = clampf(x, 80.0, level_width - 80.0)
	var pos := _ground_pos(x)
	if kind == &"medkit":
		_spawn_pickup("medkit", pos, 1)
	else:
		_spawn_pickup("ammo", pos, 90)
	EventBus.supply_spawned.emit(kind, pos)
	EventBus.notify.emit("补给已投放")


func start_defense(seconds: float, waves: int, count: int) -> void:
	if _defense_active or _finishing:
		return
	_defense_active = true
	_defense_left = seconds
	_defense_total = seconds
	_defense_count = count
	_defense_waves_left = maxi(1, waves)
	_defense_wave_timer = 0.5
	EventBus.level_event.emit("防守 %.0f 秒——顶住！" % seconds)
	EventBus.objective_changed.emit("防守 %ds" % int(seconds))
	EventBus.safe_room_entered.emit(false)


func _tick_defense(delta: float) -> void:
	if not _defense_active:
		return
	_defense_left -= delta
	_defense_wave_timer -= delta
	if _defense_wave_timer <= 0.0 and _defense_waves_left > 0:
		_defense_wave_timer = maxf(4.0, _defense_total / float(maxi(1, _defense_waves_left + 1)))
		_defense_waves_left -= 1
		start_horde(maxi(6, _defense_count / 2), true)
	if _defense_left <= 0.0:
		_defense_active = false
		add_score(3000)
		if decode_active:
			_finish_decode()
			return
		EventBus.objective_changed.emit("推进至撤离点")
		EventBus.level_event.emit("防线守住了")
		EventBus.notify.emit("防守成功 +3000")


func _tick_extraction(delta: float) -> void:
	if not _extraction_started:
		return
	if data.extraction_defense <= 0.0:
		return
	_extraction_left -= delta
	_extraction_wave_timer -= delta
	if _extraction_wave_timer <= 0.0:
		_extraction_wave_timer = 9.0
		start_horde(randi_range(10, 16), true)
	EventBus.objective_changed.emit("撤离倒计时 %ds" % int(maxf(0.0, _extraction_left)))
	if _extraction_left <= 0.0:
		_extraction_started = false
		EventBus.extraction_arrived.emit()
		EventBus.notify.emit("撤离成功")
		_finish_level()


func _on_checkpoint_trigger(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var x: float = body.global_position.x
	if absf(x - _checkpoint_x) < 20.0 and _checkpoint_respawn_used == false and _checkpoint_x > 0.0:
		# A second entry still refreshes supplies but not the respawn token.
		pass
	_checkpoint_x = x
	_respawn_pos = Vector2(x, body.global_position.y)
	_checkpoint_active = true
	_checkpoint_respawn_used = false
	EventBus.checkpoint_reached.emit(_respawn_pos)
	EventBus.notify.emit("检查点已激活")
	EventBus.level_event.emit("检查点：队伍状态已记录")
	if player and player.has_method("heal"):
		player.heal(25)
	heal_allies_near(_respawn_pos, 180.0, 25)
	_reinforce_squad()
	_spawn_pickup("ammo", _ground_pos(x + 60.0), 60)
	_spawn_pickup("medkit", _ground_pos(x - 60.0), 1)
	_safe_room_timer = 2.0
	EventBus.safe_room_entered.emit(true)
	AudioManager.play_sfx(&"checkpoint")


func _reinforce_squad() -> void:
	# Command mode: the checkpoint is also a reinforcement room. Replace dead
	# soldiers up to the level's roster, keeping their original slot/role.
	if GameManager.current_mode != &"COMMAND" or _soldier_roster.is_empty():
		return
	var spawned := 0
	for i in mini(_soldier_roster.size(), 8):
		var existing: Node = allies[i] if i < allies.size() else null
		if existing != null and is_instance_valid(existing) and not bool(existing.get("is_dead")):
			continue
		var char_data := GameManager.get_character(StringName(_soldier_roster[i]))
		if char_data == null:
			continue
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		var ally := AllyAgent.new()
		ally.level = self
		ally.data = char_data
		ally.ally_index = i
		ally.is_soldier = true
		ally.formation = formation
		var px := _respawn_pos.x - 38.0 - float(i) * 22.0
		var gy := get_ground_y(px)
		if gy < 0.0:
			px = _respawn_pos.x
			gy = _respawn_pos.y
		ally.position = Vector2(px, gy)
		actors.add_child(ally)
		if i < allies.size():
			allies[i] = ally
		else:
			allies.append(ally)
		spawned += 1
	if spawned > 0:
		EventBus.notify.emit("援军抵达：补充 %d 名士兵" % spawned)
		EventBus.level_event.emit("援军房——编制已补满")


func _on_hidden_trigger(body: Node) -> void:
	if not body.is_in_group("player") or _hidden_found:
		return
	_hidden_found = true
	_hidden_rooms.append(String(data.id) + "_hidden")
	add_score(5000)
	EventBus.notify.emit("发现隐藏补给点 +5000")
	EventBus.level_event.emit("隐藏房间已发现")
	AudioManager.play_sfx(&"secret")
	SaveSystem.register_hidden_room(data.id)


func _on_extraction_trigger(body: Node) -> void:
	if not body.is_in_group("player") or _extraction_started or _finishing:
		return
	if player.global_position.x < level_width - 240.0:
		return
	if data.extraction_defense > 0.0:
		_extraction_started = true
		_extraction_left = data.extraction_defense
		_extraction_wave_timer = 0.5
		EventBus.extraction_started.emit(_extraction_left)
		EventBus.level_event.emit("撤离点已到达——坚持 %.0f 秒！" % _extraction_left)
		EventBus.safe_room_entered.emit(false)
		start_horde(12, true)
	else:
		EventBus.extraction_arrived.emit()
		EventBus.notify.emit("撤离成功")
		_finish_level()


func _finish_level() -> void:
	if _finishing:
		return
	_finishing = true
	EventBus.objective_changed.emit("任务完成")
	AudioManager.stop_level_music()
	await get_tree().create_timer(1.4, true, false, true).timeout
	if not is_instance_valid(self):
		return
	var overtime := maxf(0.0, _elapsed - data.time_target)
	var time_bonus := maxi(0, int((data.time_target - _elapsed) * 220.0))
	var time_penalty := int(ceil(overtime / 10.0)) * 2000
	var clean_bonus := 0 if _defense_downs > 0 else 18000
	var rescue_bonus := _rescue_count * 400
	var total_score := data.base_score + _score + time_bonus - time_penalty + clean_bonus + rescue_bonus
	var alive := 1
	for ally in allies:
		if ally != null and is_instance_valid(ally) and not bool(ally.get("is_dead")):
			alive += 1
	var result := {
		"failed": false,
		"score": total_score,
		"base_score": data.base_score,
		"time_bonus": time_bonus,
		"time_penalty": time_penalty,
		"clean_bonus": clean_bonus,
		"rescue_bonus": rescue_bonus,
		"time": _elapsed,
		"kills": _kills,
		"headshots": _headshots,
		"specials": _specials_killed,
		"rescues": _rescue_count,
		"max_combo": _max_combo,
		"soldiers_start": _soldiers_start,
		"soldiers_lost": _soldiers_lost,
		"squad_alive": alive,
		"doors_kicked": _doors_kicked,
		"hunter_interrupts": _hunter_interrupts,
		"witch_crowns": _witch_crowns,
		"barrel_kills": _barrel_kills,
		"molotov_kills": _molotov_kills,
		"max_molotov_kills": _max_molotov_kills,
		"tanks_killed": _tanks_killed,
		"tank_kill_time": _tank_kill_time,
		"witch_woken": _witch_woken,
		"defense_downs": _defense_downs,
		"hidden_rooms": _hidden_rooms.duplicate(),
		"codex": _codex.duplicate(),
		"boomer_bursts": _boomer_bursts,
	}
	GameManager.complete_level(result)


# ------------------------------------------------------------------ combat ----
func _spawn_zombie(kind: StringName, pos: Vector2, alert: bool = false) -> Node:
	var net := get_node_or_null("/root/NetworkManager")
	var net_active := net != null and bool(net.call("is_multiplayer_active"))
	if net_active and not bool(net.get("is_host")) and not _network_spawn_override:
		return null
	var zd := GameManager.get_zombie(kind)
	if zd == null:
		zd = GameManager.get_zombie(&"common")
	var scene: PackedScene = ZOMBIE_SCENES.get(kind, ZOMBIE_SCENES[&"common"])
	var z = scene.instantiate()
	z.data = zd
	z.level = self
	z.position = pos
	actors.add_child(z)
	if int(z.net_id) == 0:
		z.net_id = z.get_instance_id()
	if net_active and bool(net.get("is_host")):
		net.call_deferred("broadcast_zombie_spawn", kind, z.net_id, pos.x, pos.y)
	if alert:
		z.alerted = true
		z.target = player
	if zd.is_special:
		EventBus.special_spawned.emit(zd.id)
	if kind == &"tank" or (kind == &"charger" and data.id == &"l08"):
		_register_boss(z, kind)
	return z


## Client-side visual spawn driven by NetworkManager.rpc_zombie_spawn. The
## zombie is AI-disabled by ZombieBase because _is_network_host is false.
func spawn_network_zombie(kind: StringName, net_id: int, pos: Vector2) -> Node:
	_network_spawn_override = true
	var z = _spawn_zombie(kind, pos, false)
	_network_spawn_override = false
	if z != null:
		z.net_id = net_id
		z.name = "Zombie_" + str(net_id)
	return z


func _register_boss(z: Node, kind: StringName) -> void:
	_boss_nodes.append(z)
	if _boss_node != null and is_instance_valid(_boss_node) and not bool(_boss_node.get("dead")):
		return
	_boss_node = z
	_boss_kind = kind
	_tank_spawn_time = _elapsed
	_boss_phase = 1
	_boss_max_hp = int(z.get("max_health"))
	EventBus.boss_spawned.emit(kind)
	EventBus.boss_health_changed.emit(int(z.get("health")), int(z.get("max_health")))
	DirectorSystem.set_boss_active(true)
	if kind == &"tank":
		AudioManager.set_tank_active(true)
		EventBus.notify.emit("TANK！")
		EventBus.level_event.emit("TANK 出现")
	elif kind == &"hive_mother":
		AudioManager.set_tank_active(true)
		EventBus.notify.emit("巢穴母体！")
		EventBus.level_event.emit("巢穴母体 出现")


func on_zombie_died(zombie: Node, source: StringName, is_head: bool, killer_peer_id: int = 1) -> void:
	if zombie == null or not is_instance_valid(zombie):
		return
	var zd: ZombieData = zombie.get_data()
	if zd == null:
		return
	_kills += 1
	if is_head:
		_headshots += 1
	# 多人对局：记录击杀归属。
	if killer_peer_id != 1:
		GameManager.record_player_kill(killer_peer_id, is_head, zd.is_special)
	_combo += 1
	_combo_timer = 4.0
	_max_combo = maxi(_max_combo, _combo)
	var mult := get_combo_mult()
	var points := int(float(zd.score_value) * mult)
	if is_head:
		points += int(zd.score_value * 0.5)
	if source == &"barrel":
		_barrel_kills += 1
	if zombie.last_damage_type == &"fire" and zombie.last_source == &"player":
		_molotov_kills += 1
		_fire_chain += 1
		_fire_chain_timer = 2.0
		_max_molotov_kills = maxi(_max_molotov_kills, _fire_chain)
	if zd.is_special:
		_specials_killed += 1
	if String(zd.id) not in _codex:
		_codex.append(String(zd.id))
	_horde_alive.erase(zombie)
	_score += points
	EventBus.score_changed.emit(_score)
	# 敌人掉落货币：普通感染者 1-3 废铁，特殊感染者 5-10，Boss 20-30。
	var drop := 0
	if zd.is_boss:
		drop = randi_range(20, 30)
	elif zd.is_special:
		drop = randi_range(5, 10)
	else:
		drop = randi_range(1, 3)
	if drop > 0:
		GameManager.add_currency(drop)
	EventBus.combo_changed.emit(_combo, mult)
	EventBus.enemy_died.emit(zd.id, zombie.global_position, points)
	EventBus.enemy_killed.emit(zd.id, source, zombie.global_position)
	if zombie in _boss_nodes:
		_boss_nodes.erase(zombie)
		if zombie == _boss_node:
			if zd.id == &"tank":
				_tanks_killed += 1
				_tank_kill_time = minf(_tank_kill_time, _elapsed - _tank_spawn_time)
			EventBus.boss_killed.emit(zd.id)
			EventBus.boss_health_changed.emit(0, int(zd.max_hp))
			DirectorSystem.set_boss_active(false)
			AudioManager.set_tank_active(false)
			if CinematicCamera != null and CinematicCamera.has_method("trigger_killcam"):
				CinematicCamera.trigger_killcam(zombie, 0.8, 0.5)
			_boss_node = null
			if not _boss_nodes.is_empty():
				for candidate in _boss_nodes:
					if candidate != null and is_instance_valid(candidate) and not bool(candidate.get("dead")):
						_boss_node = candidate
						EventBus.boss_health_changed.emit(int(candidate.get("health")), int(candidate.get("max_health")))
						break
			# Final chapter: the signal core's death opens the binary ending.
			if data.final_choice and _boss_nodes.is_empty() and not _final_choice_open:
				_final_choice_open = true
				await get_tree().create_timer(2.2, true, false, true).timeout
				if is_instance_valid(self) and not _finishing and not ArchiveManager.has_final_choice():
					open_final_choice()
	if zd.id == &"witch" and zombie.alerted == false:
		pass


func on_zombie_fell(zombie: Node) -> void:
	_horde_alive.erase(zombie)
	if zombie in _boss_nodes:
		_boss_nodes.erase(zombie)
		if zombie == _boss_node:
			_boss_node = null
			EventBus.boss_health_changed.emit(0, 100)


func barrel_exploded(_barrel: Node, pos: Vector2, radius: float, damage: int) -> void:
	Fx.explosion(fx_layer, pos, 1.5)
	Fx.smoke(fx_layer, pos + Vector2(0, -10), 1.2)
	AudioManager.play_sfx_2d(&"explosion", pos, 1200.0)
	AudioManager.duck_music(24.0, 0.5)
	AudioLayerManager.play_explosion_layer()
	if PostProcess != null:
		PostProcess.pulse_damage_vignette(0.45, 0.3)
	if CinematicCamera != null and CinematicCamera.has_method("add_trauma_directional"):
		CinematicCamera.add_trauma_directional(0.6, Vector2.UP)
	EventBus.barrel_exploded.emit(pos)
	EventBus.shake(5.0)
	for z in get_zombies_near(pos, radius):
		var dist: float = z.global_position.distance_to(pos)
		var falloff := clampf(1.0 - dist / (radius * 1.3), 0.35, 1.0)
		if z.has_method("apply_damage"):
			z.apply_damage(int(float(damage) * falloff), (z.global_position - pos).normalized(), false, &"barrel", &"explosion")
		if z.has_method("apply_knockback"):
			z.apply_knockback((z.global_position - pos).normalized() * 240.0)
	for body in get_damageable_near(pos, radius * 0.9):
		if body.has_method("take_damage"):
			body.take_damage(int(damage * 0.16), (body.global_position - pos).normalized(), &"barrel", &"explosion")
	for other in get_tree().get_nodes_in_group("barrels"):
		if other != _barrel and is_instance_valid(other) and other.global_position.distance_to(pos) < radius * 0.8:
			if other.has_method("explode"):
				other.explode()


func explode_at(pos: Vector2, radius: float, damage: int, source: StringName, player_owned: bool) -> void:
	Fx.explosion(fx_layer, pos, 1.3)
	Fx.smoke(fx_layer, pos + Vector2(0, -8), 1.0)
	AudioManager.play_sfx_2d(&"explosion", pos, 1200.0)
	AudioManager.duck_music(22.0, 0.45)
	AudioLayerManager.play_explosion_layer()
	if PostProcess != null:
		PostProcess.pulse_damage_vignette(0.4, 0.3)
	if CinematicCamera != null and CinematicCamera.has_method("add_trauma_directional"):
		CinematicCamera.add_trauma_directional(0.5, Vector2.UP)
	EventBus.explosion.emit(pos, radius)
	EventBus.shake(4.5)
	for z in get_zombies_near(pos, radius):
		var dist: float = z.global_position.distance_to(pos)
		var falloff := clampf(1.0 - dist / (radius * 1.4), 0.35, 1.0)
		if z.has_method("apply_damage"):
			z.apply_damage(int(float(damage) * falloff), (z.global_position - pos).normalized(), false, source, &"explosion")
		if z.has_method("apply_knockback"):
			z.apply_knockback((z.global_position - pos).normalized() * 220.0)
	if player_owned:
		for body in get_damageable_near(pos, radius * 0.8):
			if body.has_method("take_damage"):
				body.take_damage(14, (body.global_position - pos).normalized(), &"friendly", &"explosion")
	for other in get_tree().get_nodes_in_group("barrels"):
		if is_instance_valid(other) and other.global_position.distance_to(pos) < radius * 0.8:
			if other.has_method("explode"):
				other.explode()


func spawn_fire_zone(pos: Vector2, radius: float, duration: float, player_owned: bool) -> void:
	var zone := HazardZone.new()
	zone.kind = "fire"
	zone.radius = radius
	zone.duration = duration
	zone.dps = 26.0
	zone.source = &"fire"
	zone.player_owned = player_owned
	zone.level = self
	zone.position = pos
	interactables.add_child(zone)


func spawn_acid_zone(pos: Vector2, radius: float, duration: float, _dps: float) -> void:
	var zone := HazardZone.new()
	zone.kind = "acid"
	zone.radius = radius
	zone.duration = duration
	zone.dps = 18.0
	zone.source = &"acid"
	zone.level = self
	zone.position = pos
	interactables.add_child(zone)


func spawn_acid_glob(from: Vector2, to: Vector2) -> void:
	var tex := load("res://assets/sprites/fx/acid_splash.png")
	if tex == null:
		spawn_acid_zone(to, 50.0, 3.0, 18.0)
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 0, 32, 24)
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.position = from
	sprite.z_index = 22
	fx_layer.add_child(sprite)
	var tween := create_tween()
	tween.tween_property(sprite, "position", to, 0.55).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		spawn_acid_zone(to, 52.0, 3.5, 18.0)
		Fx.acid(fx_layer, to)
		AudioManager.play_sfx_2d(&"acid_splash", to, 800.0)
		sprite.queue_free()
	)


func spawn_tank_rock(from: Vector2, to: Vector2) -> void:
	var tex := SpriteLibrary.prop_texture("crate")
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = from
	sprite.scale = Vector2(0.8, 0.8)
	sprite.modulate = Color(0.55, 0.55, 0.58)
	sprite.z_index = 22
	fx_layer.add_child(sprite)
	var mid := Vector2((from.x + to.x) * 0.5, minf(from.y, to.y) - 95.0)
	var tween := create_tween()
	tween.tween_property(sprite, "position", mid, 0.38)
	tween.tween_property(sprite, "position", to, 0.36)
	tween.tween_callback(func() -> void:
		explode_at(to, 72.0, 36, &"zombie", false)
		sprite.queue_free()
	)


func spawn_throwable(kind: String, pos: Vector2, aim_dir: Vector2) -> void:
	var p := ThrowableProjectile.new()
	p.kind = kind
	p.level = self
	p.position = pos
	p.velocity = aim_dir * 430.0 + Vector2(0, -130.0)
	actors.add_child(p)


func bile_explosion(pos: Vector2, _player_owned: bool) -> void:
	Fx.bile(fx_layer, pos)
	EventBus.bile_splashed.emit(4.0)
	AudioManager.play_sfx_2d(&"bile_splash", pos, 1000.0)
	EventBus.notify.emit("胆汁四溅，尸潮被吸引！")
	spawn_horde_at(pos, 14, true)
	if player and is_instance_valid(player) and player.global_position.distance_to(pos) < 150.0:
		if player.has_method("apply_bile"):
			player.apply_bile(4.0)


func record_boomer_burst() -> void:
	_boomer_bursts += 1


func record_witch_woken() -> void:
	_witch_woken = true


func _spawn_pickup(kind: String, pos: Vector2, amount: int = 1, weapon_id: String = "") -> void:
	var pickup := Pickup.new()
	pickup.kind = kind
	pickup.amount = amount
	pickup.weapon_id = weapon_id
	pickup.level = self
	pickup.position = pos
	pickups.add_child(pickup)


func drop_random_pickup(pos: Vector2) -> void:
	var pool := ["ammo", "pills", "grenade", "gold", "medkit"]
	var kind: String = pool.pick_random()
	if kind == "gold":
		_spawn_pickup(kind, pos, 250)
	else:
		_spawn_pickup(kind, pos, 1)


func drop_scavenger_loot(pos: Vector2) -> void:
	_spawn_pickup("gold", pos + Vector2(-10, -8), 300)
	_spawn_pickup("ammo", pos + Vector2(12, -8), 45)


func drop_boss_loot(pos: Vector2) -> void:
	_spawn_pickup("medkit", pos + Vector2(-24, -10), 1)
	_spawn_pickup("ammo", pos + Vector2(0, -10), 120)
	_spawn_pickup("grenade", pos + Vector2(24, -10), 1)
	_spawn_pickup("gold", pos + Vector2(0, -24), 1200)


# ----------------------------------------------------------------- queries ----
func get_player() -> Node2D:
	return player


func get_allies() -> Array:
	return allies


func get_ground_y(x: float) -> float:
	for seg in ground_segments:
		if x >= float(seg["x0"]) and x <= float(seg["x1"]):
			return float(seg["y"])
	return -1.0


func _nearest_ground_x(x: float) -> float:
	x = clampf(x, 40.0, level_width - 40.0)
	if get_ground_y(x) > 0.0:
		return x
	for offset in range(16, 600, 16):
		if get_ground_y(x - offset) > 0.0:
			return x - offset
		if get_ground_y(x + offset) > 0.0:
			return x + offset
	return -1.0


func _ground_pos(x: float) -> Vector2:
	var gx := _nearest_ground_x(x)
	if gx < 0.0:
		return Vector2(x, 288.0)
	return Vector2(gx, get_ground_y(gx))


func get_zombies_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			continue
		if z.global_position.distance_to(pos) <= radius:
			out.append(z)
	return out


func get_zombies_in_cone(origin: Vector2, facing: int, radius: float, arc: float) -> Array:
	var out: Array = []
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			continue
		if MathUtils.cone_hit(origin, facing, z.global_position, radius, arc):
			out.append(z)
	return out


func get_interactables_in_cone(origin: Vector2, facing: int, radius: float, arc: float) -> Array:
	var out: Array = []
	for obj in get_tree().get_nodes_in_group("melee_targets"):
		if obj == null or not is_instance_valid(obj):
			continue
		if not obj.has_method("hit"):
			continue
		if MathUtils.cone_hit(origin, facing, obj.global_position, radius, arc):
			out.append(obj)
	return out


func get_nearby_interactable(pos: Vector2) -> Node:
	var best: Node = null
	var best_dist := 55.0
	for obj in get_tree().get_nodes_in_group("interactables"):
		if obj == null or not is_instance_valid(obj) or not obj.has_method("get_prompt"):
			continue
		var dist: float = pos.distance_to(obj.global_position)
		if dist < best_dist:
			best = obj
			best_dist = dist
	return best


func get_damageable_near(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	if player and is_instance_valid(player) and not bool(player.get("is_dead")) \
			and player.global_position.distance_to(pos) <= radius:
		out.append(player)
	for ally in allies:
		if ally != null and is_instance_valid(ally) and not bool(ally.get("is_dead")) \
				and ally.global_position.distance_to(pos) <= radius:
			out.append(ally)
	return out


func get_downed_ally_near(pos: Vector2, radius: float = 52.0, exclude: Node = null,
		include_player: bool = false) -> Node:
	var best: Node = null
	var best_dist := radius
	if include_player and player and is_instance_valid(player) and player != exclude:
		if bool(player.get("is_downed")) and not bool(player.get("is_dead")):
			var d := pos.distance_to(player.global_position)
			if d < best_dist:
				best = player
				best_dist = d
	for ally in allies:
		if ally == null or not is_instance_valid(ally) or ally == exclude:
			continue
		if bool(ally.get("is_dead")) or not bool(ally.get("is_downed")):
			continue
		var d := pos.distance_to(ally.global_position)
		if d < best_dist:
			best = ally
			best_dist = d
	return best


func find_downed_ally_near(pos: Vector2, radius: float = 220.0, exclude: Node = null,
		include_player: bool = false) -> Node:
	return get_downed_ally_near(pos, radius, exclude, include_player)


func get_pinned_ally_near(pos: Vector2, radius: float = 52.0, exclude: Node = null) -> Node:
	var best: Node = null
	var best_dist := radius
	for ally in allies:
		if ally == null or not is_instance_valid(ally) or ally == exclude:
			continue
		if bool(ally.get("is_dead")) or not bool(ally.get("is_pinned")):
			continue
		var d := pos.distance_to(ally.global_position)
		if d < best_dist:
			best = ally
			best_dist = d
	return best


func find_pinned_ally_near(pos: Vector2, radius: float = 220.0, exclude: Node = null) -> Node:
	return get_pinned_ally_near(pos, radius, exclude)


func revive_ally(target: Node, healer: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("revive"):
		target.revive(healer)
	if healer == player:
		add_rescue(healer)


func find_nearest_zombie(pos: Vector2, radius: float, special_only: bool = false) -> Node:
	var best: Node = null
	var best_dist := radius
	for z in get_tree().get_nodes_in_group("zombies"):
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			continue
		var zd: ZombieData = z.get_data() if z.has_method("get_data") else null
		if special_only and (zd == null or not zd.is_special):
			continue
		var d := pos.distance_to(z.global_position)
		if d < best_dist:
			best = z
			best_dist = d
	return best


func alert_commons_near(pos: Vector2, radius: float) -> void:
	for z in get_zombies_near(pos, radius):
		if z.has_method("apply_stagger"):
			pass
		z.alerted = true
		if z.target == null or not is_instance_valid(z.target):
			z.target = player


func stun_zombies_near(pos: Vector2, radius: float, duration: float) -> void:
	for z in get_zombies_near(pos, radius):
		if z.has_method("apply_stagger"):
			z.apply_stagger(duration)


func heal_allies_near(_pos: Vector2, radius: float, amount: int) -> void:
	if player and is_instance_valid(player) and player.global_position.distance_to(_pos) <= radius:
		if player.has_method("heal"):
			player.heal(amount)
	for ally in allies:
		if ally != null and is_instance_valid(ally) and not bool(ally.get("is_dead")):
			if ally.global_position.distance_to(_pos) <= radius and ally.has_method("heal"):
				ally.heal(amount)


func inspire_allies(duration: float) -> void:
	for ally in allies:
		if ally != null and is_instance_valid(ally) and ally.has_method("inspire"):
			ally.inspire(duration)


func register_hunter_interrupt() -> void:
	_hunter_interrupts += 1
	SaveSystem.register_counter("hunter_interrupts", 1)


func add_rescue(healer: Node) -> void:
	if healer != player:
		return
	_rescue_count += 1
	EventBus.notify.emit("救助队友 +400")


func add_score(points: int) -> void:
	_score += maxi(0, points)
	EventBus.score_changed.emit(_score)


func on_player_downed() -> void:
	if _defense_active or _extraction_started:
		_defense_downs += 1
	EventBus.notify.emit("你被击倒了——等待队友救援")


func on_player_died() -> void:
	if _finishing or _respawning:
		return
	# Command mode has no last-stand revival: the commander is the squad.
	if GameManager.current_mode == &"COMMAND":
		_finishing = true
		EventBus.notify.emit("指挥官阵亡——全队溃败")
		await get_tree().create_timer(1.8, true, false, true).timeout
		if is_instance_valid(self):
			GameManager.fail_level("指挥官阵亡")
		return
	if _checkpoint_active and not _checkpoint_respawn_used:
		_checkpoint_respawn_used = true
		_respawning = true
		EventBus.notify.emit("小队在检查点重整……")
		await get_tree().create_timer(2.4, true, false, true).timeout
		_respawning = false
		if not is_instance_valid(self) or GameManager.state != GameManager.State.PLAYING:
			return
		if player and is_instance_valid(player):
			player.respawn_at(_respawn_pos)
			for ally in allies:
				if ally != null and is_instance_valid(ally) and not bool(ally.get("is_dead")):
					ally.respawn_at(_respawn_pos + Vector2(_rng.randf_range(-50, 50), 0))
			heal_allies_near(_respawn_pos, 260.0, 30)
			EventBus.notify.emit("检查点重整完成")
			EventBus.level_event.emit("队伍在检查点重新集结")
		return
	_finishing = true
	EventBus.notify.emit("小队全灭")
	await get_tree().create_timer(1.8, true, false, true).timeout
	if is_instance_valid(self):
		GameManager.fail_level("小队全灭")


func on_ally_downed(_ally: Node) -> void:
	if _defense_active or _extraction_started:
		_defense_downs += 1


func on_ally_died(_ally: Node) -> void:
	if GameManager.current_mode == &"COMMAND":
		_soldiers_lost += 1
	else:
		_squad_deaths += 1


func on_player_biled() -> void:
	EventBus.notify.emit("胆汁引来了尸潮！")
	call_deferred("_delayed_bile_horde")


func _delayed_bile_horde() -> void:
	await get_tree().create_timer(0.8, true, false, true).timeout
	if is_instance_valid(self) and not _finishing and player:
		spawn_horde_at(player.global_position, 12, true)


func _on_gunshot(pos: Vector2, loudness: float) -> void:
	alert_commons_near(pos, loudness)


func _on_door_kicked(_pos: Vector2) -> void:
	_doors_kicked += 1


func _zombie_name(kind: StringName) -> String:
	var zd := GameManager.get_zombie(kind)
	return zd.display_name if zd else String(kind)


# ------------------------------------------------------------------- input ----
func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and GameManager.state == GameManager.State.PLAYING \
			and event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_F7:
					EventBus.debug_vision_toggled.emit()
					return
				KEY_F8:
					_debug_spawn_special()
					return
				KEY_F9:
					_debug_cycle_time_scale()
					return
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.current_mode != &"COMMAND":
		return
	if event.is_action_pressed("cmd_formation"):
		_cycle_formation()
		return
	var cmd: StringName = &""
	if event.is_action_pressed("cmd_follow"):
		cmd = &"follow"
	elif event.is_action_pressed("cmd_advance"):
		cmd = &"advance"
	elif event.is_action_pressed("cmd_hold"):
		cmd = &"hold"
	elif event.is_action_pressed("cmd_focus"):
		cmd = &"focus"
	if cmd == &"":
		return
	EventBus.command_issued.emit(cmd)
	var labels := {"follow": "跟随", "advance": "推进", "hold": "防守", "focus": "集火"}
	EventBus.notify.emit("指令：" + String(labels.get(String(cmd), "跟随")))
	AudioManager.play_sfx(&"ui_click")


func _cycle_formation() -> void:
	var order := [&"wedge", &"line", &"column"]
	var index := order.find(formation)
	formation = order[(index + 1) % order.size()]
	var labels := {&"wedge": "楔形", &"line": "横列", &"column": "纵队"}
	EventBus.formation_changed.emit(formation)
	EventBus.notify.emit("阵型：" + String(labels.get(formation, "楔形")))
	AudioManager.play_sfx(&"ui_click")


func _debug_cycle_time_scale() -> void:
	var steps := [0.25, 1.0, 2.0]
	var current := Engine.time_scale
	var index := steps.find(current)
	Engine.time_scale = steps[(index + 1) % steps.size()] if index >= 0 else 1.0
	EventBus.notify.emit("调试时间缩放：%.2fx" % Engine.time_scale)


func _debug_spawn_special() -> void:
	var kinds: Array[StringName] = [&"hunter", &"smoker", &"boomer", &"charger",
		&"spitter", &"jockey", &"tank", &"witch"]
	var kind: StringName = kinds.pick_random()
	var x := get_global_mouse_position().x
	x = clampf(x, 100.0, level_width - 100.0)
	_spawn_zombie(kind, _ground_pos(x), true)
	EventBus.notify.emit("调试生成：" + _zombie_name(kind))


# ------------------------------------------------------------------- HUD API --
func get_score() -> int:
	return _score


func get_combo() -> int:
	return _combo


func get_combo_mult() -> float:
	return minf(1.0 + float(_combo) * 0.25, 5.0)


func get_elapsed() -> float:
	return _elapsed


func get_progress() -> float:
	return _progress


func is_extraction_active() -> bool:
	return _extraction_started


func get_extraction_left() -> float:
	return _extraction_left


func is_defense_active() -> bool:
	return _defense_active


func get_defense_left() -> float:
	return _defense_left


func get_boss_node() -> Node:
	return _boss_node


func _exit_tree() -> void:
	## State reset: guarantee zero leaked nodes/resources between level
	## transitions (start_level → _ready → _exit_tree → next _ready).
	Fx.reset()
	ScreenShake.reset()
	_ground_segments.clear()
	_platforms.clear()
	_horde_alive.clear()
	_horde_pending = 0
	_boss_node = null
	_boss_nodes.clear()
	player = null
	hud = null
	fx_layer = null
	props = null
	interactables = null
	pickups = null
	archive_pickups.clear()
	_codex.clear()


func _tick_boss_phases(delta: float) -> void:
	var boss := _boss_node
	if boss == null or not is_instance_valid(boss):
		return
	var hp := int(boss.get("health"))
	var max_hp := int(boss.get("max_health"))
	var pct := float(hp) / maxf(1.0, float(max_hp))
	# Tank phases: 100-60% MG sweep, 60-20% tear gas + shield soldiers, 20-0% rear fuel tank weak point.
	if _boss_kind == &"tank" and _boss_phase < 3:
		var new_phase := 3
		if pct > 0.60:
			new_phase = 1
		elif pct > 0.20:
			new_phase = 2
		if new_phase != _boss_phase:
			_boss_phase = new_phase
			if _boss_phase == 2:
				EventBus.notify.emit("装甲车第2阶段：催泪瓦斯 + 盾兵")
				start_horde(8, true)
			elif _boss_phase == 3:
				EventBus.notify.emit("装甲车第3阶段：尾部油箱弱点暴露")
				boss.set("damage_taken_mult", 2.0)
	# Hive Mother phases: destroy 4 energy nodes across 3 phases.
	elif _boss_kind == &"hive_mother" and _boss_phase < 3:
		var new_phase := 3
		if pct > 0.70:
			new_phase = 1
		elif pct > 0.35:
			new_phase = 2
		if new_phase != _boss_phase:
			_boss_phase = new_phase
			if _boss_phase == 2:
				EventBus.notify.emit("巢穴母体第2阶段：触手激活")
				start_horde(10, true)
			elif _boss_phase == 3:
				EventBus.notify.emit("巢穴母体第3阶段：毒气充满战场")
				boss.set("burn_aura", true)

