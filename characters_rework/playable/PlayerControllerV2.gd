class_name PlayerControllerV2
extends CharacterBody2D
## ---------------------------------------------------------------------------
## 职责: 可玩角色控制器(重构版)。数据驱动 —— 所有角色差异来自
##       ReworkCharacterData(属性/配色/绘制档案/被动 ID),内部零角色分支。
##       覆盖: 移动(跑/蹲/滑铲/跳/土狼/缓冲)、8 向瞄准、hitscan 射击(散布/
##       穿透/距离衰减/爆头)、换弹、近战、推开、技能(被动组件执行)、
##       倒地/救助/黑白/死亡/复活全流程、状态效果(胆汁/燃烧/减速/被控)。
## 依赖(全部可选,通过 Engine.get_singleton 探测,独立运行时自动降级):
##   EventBus        现有全局信号总线(只 emit 兼容信号,不新增同名信号)
##   GameManager     get_weapon(id: StringName) -> WeaponData
##   AudioManager    play_sfx(id, vol, pitch) / play_sfx_2d(id, pos, radius, pitch)
##   MathUtils       damage_falloff / vec8 / cone_hit (静态,工程内类)
## 伤害输出契约(与现有 ZombieBase 完全一致):
##   target.apply_damage(amount: int, from_dir: Vector2, is_head: bool,
##                       source: StringName, damage_type: StringName)
##   target.hit(amount: int, source: StringName)          # 可破坏物
##   target.is_headshot_point(point: Vector2) -> bool     # 爆头判定(可选)
## 对外接口(供集成方/被动组件调用):
##   take_damage / heal / heal_full / die / revive / respawn_at / apply_bile /
##   apply_burn / enter_control / release_control / inspire / use_skill /
##   add_speed_modifier / add_damage_modifier / add_reload_modifier /
##   add_fire_rate_modifier / add_frontal_guard / grant_iframes / teleport_to /
##   get_effective_speed / attach_passive
## 兼容字段(现有 HUD / LevelRunner 通过 .get() 读取,必须保留):
##   hp max_hp temp_hp downs is_downed is_dead is_controlled black_white
##   bile_timer burn_timer slow_timer inspire_timer shield_wall_timer
##   medkits pills throwables spread_heat character facing aim_dir visual_id
## ---------------------------------------------------------------------------

signal character_state_changed(state: StringName, detail: Dictionary)
signal passive_triggered(passive_id: StringName, payload: Dictionary)
signal shots_fired(weapon_id: StringName, position: Vector2)
signal damage_taken(amount: int, source: StringName)
signal died
signal downed
signal revived

## InputBuffer 缓存按键，用于换弹取消等反馈链路。
var _input_buffer: InputBuffer = null

const FALLBACK_DATA := "res://characters_rework/data/playable/assault.tres"
const FALLBACK_WEAPON_DIR := "res://resources/data/weapons"
const GRAVITY: float = 1500.0
const JUMP_VELOCITY: float = -560.0
const COYOTE_TIME: float = 0.08
const JUMP_BUFFER_TIME: float = 0.10
const SLIDE_TIME: float = 0.35
const SLIDE_IFRAMES: float = 0.15
const SLIDE_CD: float = 1.2
const HIT_IFRAMES: float = 0.5
const BLEEDOUT_TIME: float = 20.0
const REVIVE_TIME: float = 3.0
const CONTROL_IMMUNE_TIME: float = 3.0
const MAX_THROWABLES: int = 3
const ENEMY_RAY_MASK: int = 1 | 8 | 16          # WORLD | COMMON | SPECIAL
const SELF_EXCLUDE_MASK: int = 89               # 与现有 player.tscn 一致
const MUZZLE_LOCAL: Vector2 = Vector2(20, -18)  # 与现有工程一致
const PASSIVE_DIR := "res://characters_rework/playable/passives"

const WEAPON_VISUAL_TYPES: Dictionary = {
	"m9": &"pistol", "smg": &"smg", "ar15": &"rifle", "shotgun": &"shotgun",
	"lmg": &"lmg", "sniper": &"sniper", "katana": &"katana", "axe": &"axe",
	"chainsaw": &"axe",
}

const ACTION_ALIASES: Dictionary = {
	"fire": ["fire", "shoot"],
	"skill": ["skill", "dash"],
	"cmd_formation": ["cmd_formation", "formation_cycle"],
}

@export var character_data: ReworkCharacterData = null
## 独立运行时是否自动挂一个跟随相机(集成到现有场景时保持 false,沿用 Camera 子节点)。
@export var auto_camera: bool = false

## --- 生命/状态(字段名与现有 player.gd 对齐,兼容 HUD 的 .get() 读取) ---
var max_hp: int = 100
var hp: int = 100
var temp_hp: int = 0
var downs: int = 0
var black_white: bool = false
var is_downed: bool = false
var is_dead: bool = false
var is_controlled: bool = false
var control_kind: StringName = &""
var controller: Node = null
var control_immune: float = 0.0
var bleedout: float = BLEEDOUT_TIME
var bile_timer: float = 0.0
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var slow_timer: float = 0.0
var inspire_timer: float = 0.0
var shield_wall_timer: float = 0.0
var iframes: float = 0.0
var medkits: int = 1
var pills: int = 1
var throwables: Dictionary = {"grenade": 1, "molotov": 1, "bile": 1}
var throw_index: int = 0

## --- 移动/瞄准 ---
var facing: int = 1
var aim_dir: Vector2 = Vector2.RIGHT
var aim_angle: float = 0.0
var run_speed: float = 220.0
var crouch_speed: float = 110.0
var is_crouching: bool = false
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_cd: float = 0.0
var slide_dir: float = 1.0
var coyote: float = 0.0
var jump_buffer: float = 0.0
var mouse_recent: float = 0.0
var using_mouse: bool = false

## --- 武器 ---
var weapon_slots: Array[StringName] = []
var slot_index: int = 0
var ammo: Dictionary = {}
var weapon_cooldown: float = 0.0
var reload_timer: float = 0.0
var reloading: bool = false
var _reload_total: float = 0.0
var spread_heat: float = 0.0
var level: Node = null
var stealth_speed_multiplier: float = 1.0
var visibility: float = 1.0
var melee_cooldown: float = 0.0
var melee_anim_timer: float = 0.0
var shove_cooldown: float = 0.0
var skill_cd: float = 0.0
var attack_anim_timer: float = 0.0

## --- 被动修正器(键为来源 id,乘法叠加) ---
var _speed_mods: Dictionary = {}
var _damage_mods: Dictionary = {}
var _reload_mods: Dictionary = {}
var _fire_rate_mods: Dictionary = {}
var _frontal_guards: Dictionary = {}

var _renderer: PlayerRenderer = null
var _passives: Array[Node] = []
var _action_cache: Dictionary = {}
var _skill_payload: Dictionary = {"handled": false}
var _prompt_payload: Dictionary = {"text": ""}
var _last_prompt: String = ""
var _interact_target: Node = null
var _cached_gun_visual: StringName = &"rifle"
var _bus: Node = null
var _audio: Node = null
var _game: Node = null
var _item_component: Node = null

## 兼容别名: 现有 HUD 读取 player.get("character")(类型 CharacterData)。
## 返回 CharacterDataCompat，内部将 ReworkCharacterData 映射为旧结构。
var character: Resource:
	get:
		if _character_compat == null:
			_character_compat = (load("res://scripts/data/character_data_compat.gd") as GDScript).new(character_data)
		return _character_compat

var _character_compat: Resource = null


func _ready() -> void:
	add_to_group("player")
	add_to_group("rework_actors")
	if character_data == null:
		character_data = load(FALLBACK_DATA) as ReworkCharacterData
	max_hp = character_data.max_hp
	hp = max_hp
	run_speed = character_data.speed
	crouch_speed = run_speed * 0.5
	stealth_speed_multiplier = 1.0
	collision_layer = 2
	collision_mask = 1 | 8 | 16 | 64
	floor_snap_length = 8.0
	_bus = _autoload(&"EventBus")
	_audio = _autoload(&"AudioManager")
	_game = _autoload(&"GameManager")
	_input_buffer = _autoload(&"InputBuffer")
	_setup_renderer()
	_setup_weapons()
	_attach_passive(character_data.passive_ability_id)
	_setup_item_component()
	if auto_camera:
		_build_camera()
	EventBusBridge.attach_for(self)
	_sync_weapon_visual(true)
	_emit_state(&"spawn")


func _exit_tree() -> void:
	# 从 EventBusBridge 注册表中移除，避免 Autoload 持有失效引用。
	var bridge := EventBusBridge.instance()
	if bridge != null and bridge.has_method("_unregister_player"):
		bridge.call("_unregister_player", self)
	_renderer = null
	_item_component = null
	_passives.clear()


## ------------------------------------------------------------ 主循器 ----

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	if is_downed:
		_tick_downed(delta)
		_apply_gravity(delta)
		move_and_slide()
		_sync_visuals()
		return
	if is_controlled:
		velocity.x = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_sync_visuals()
		return
	_read_aim(delta)
	_tick_movement(delta)
	_tick_actions(delta)
	_tick_interaction()
	move_and_slide()
	_sync_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_recent = 0.4
		using_mouse = true


func _tick_timers(delta: float) -> void:
	if iframes > 0.0:
		iframes -= delta
	if control_immune > 0.0:
		control_immune -= delta
	if bile_timer > 0.0:
		bile_timer -= delta
		if bile_timer <= 0.0:
			_emit_state(&"bile_end")
	if burn_timer > 0.0:
		burn_timer -= delta
		take_damage(int(maxf(1.0, burn_dps * delta)), Vector2.ZERO, &"fire", &"fire")
	if slow_timer > 0.0:
		slow_timer -= delta
	if inspire_timer > 0.0:
		inspire_timer -= delta
	if shield_wall_timer > 0.0:
		shield_wall_timer -= delta
	if melee_cooldown > 0.0:
		melee_cooldown -= delta
	if shove_cooldown > 0.0:
		shove_cooldown -= delta
	if slide_cd > 0.0:
		slide_cd -= delta
	if weapon_cooldown > 0.0:
		weapon_cooldown -= delta
	if melee_anim_timer > 0.0:
		melee_anim_timer -= delta
	if attack_anim_timer > 0.0:
		attack_anim_timer -= delta
	if mouse_recent > 0.0:
		mouse_recent -= delta
		if mouse_recent <= 0.0:
			using_mouse = false
	if skill_cd > 0.0:
		skill_cd -= delta
	if reloading:
		reload_timer -= delta * get_reload_speed_mult()
		# InputBuffer 换弹取消: 进度 >= 70% 时按射击可取消换弹并立即开火。
		if _input_buffer != null and _input_buffer.consume(&"fire", 0.3) \
				and _reload_total > 0.0 \
				and reload_timer <= _reload_total * 0.3:
			reloading = false
			reload_timer = 0.0
			var weapon := _current_weapon()
			if weapon != null:
				_try_fire(weapon)
		elif reload_timer <= 0.0:
			_finish_reload()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, 1400.0)
	else:
		coyote = COYOTE_TIME


## ------------------------------------------------------------ 移动 ----

func _tick_movement(delta: float) -> void:
	var input_x := Input.get_axis(_act(&"move_left"), _act(&"move_right"))
	var want_crouch := _pressed(&"crouch")
	if is_sliding:
		slide_timer -= delta
		velocity.x = slide_dir * run_speed * 1.45 * maxf(0.25, slide_timer / SLIDE_TIME)
		if slide_timer <= 0.0 or not is_on_floor():
			is_sliding = false
	elif want_crouch and is_on_floor() and absf(input_x) > 0.5 \
			and not _was_crouching and slide_cd <= 0.0 and absf(velocity.x) > run_speed * 0.65:
		_start_slide(signf(velocity.x))
	elif want_crouch and is_on_floor():
		is_crouching = true
		velocity.x = move_toward(velocity.x, input_x * crouch_speed, 1400.0 * delta)
	else:
		is_crouching = false
		var target_speed: float = input_x * get_effective_speed()
		if slow_timer > 0.0:
			target_speed *= 0.6
		velocity.x = move_toward(velocity.x, target_speed, 1800.0 * delta)
	_was_crouching = want_crouch
	if _just_pressed(&"jump"):
		jump_buffer = JUMP_BUFFER_TIME
	if jump_buffer > 0.0:
		jump_buffer -= delta
		if is_on_floor() or coyote > 0.0:
			velocity.y = JUMP_VELOCITY
			jump_buffer = 0.0
			coyote = 0.0
			is_sliding = false
	if coyote > 0.0 and not is_on_floor():
		coyote -= delta
	if input_x != 0.0 and not using_mouse:
		facing = 1 if input_x > 0.0 else -1


var _was_crouching: bool = false


func _start_slide(dir: float) -> void:
	is_sliding = true
	slide_timer = SLIDE_TIME
	slide_cd = SLIDE_CD
	slide_dir = dir
	grant_iframes(SLIDE_IFRAMES, &"slide")


## ------------------------------------------------------------ 瞄准 ----

func _read_aim(delta: float) -> void:
	if using_mouse:
		var mouse_pos := get_global_mouse_position()
		var to_mouse := mouse_pos - global_position
		if to_mouse.length_squared() > 36.0:
			aim_dir = to_mouse.normalized()
			facing = 1 if to_mouse.x >= 0.0 else -1
	else:
		var kx := Input.get_axis(_act(&"move_left"), _act(&"move_right"))
		var ky := Input.get_axis("aim_up", "aim_down")
		var vec := Vector2(kx, ky)
		if vec.length_squared() > 0.04:
			aim_dir = _vec8(vec)
			if kx != 0.0:
				facing = 1 if kx > 0.0 else -1
		else:
			aim_dir = Vector2(float(facing), 0.0)
	aim_angle = aim_dir.angle()


static func _vec8(direction: Vector2) -> Vector2:
	var angle := direction.angle()
	var step := TAU / 8.0
	var snapped := roundi(angle / step) * step
	return Vector2(cos(snapped), sin(snapped))


## ------------------------------------------------------------ 动作 ----

func _tick_actions(delta: float) -> void:
	var weapon := _current_weapon()
	if _held(&"fire") and weapon != null:
		var auto := _wbool(weapon, "automatic")
		if auto or _just_pressed(&"fire"):
			_try_fire(weapon)
	if _just_pressed(&"reload"):
		start_reload()
	if _just_pressed(&"melee"):
		if weapon != null and _wname(weapon, "category") == &"melee":
			_swing_melee(weapon)
		else:
			_shove()
	if _just_pressed(&"switch_weapon"):
		cycle_weapon(1)
	if _just_pressed(&"skill"):
		use_skill()
	if _just_pressed(&"throw"):
		_throw_stub()
	if _just_pressed(&"medkit"):
		_medkit_stub()
	if _just_pressed(&"pills"):
		_pills_stub()


func _try_fire(weapon: Resource) -> void:
	if reloading or weapon_cooldown > 0.0:
		return
	var wid := _wname(weapon, "id")
	var state: Dictionary = ammo.get(wid, {"mag": 0, "reserve": 0})
	if int(state["mag"]) <= 0:
		if _audio:
			_audio.play_sfx(&"empty")
		start_reload()
		return
	var category := _wname(weapon, "category")
	if category == &"melee":
		_swing_melee(weapon)
		return
	if category == &"throwable":
		return
	_fire_weapon(weapon)


func _fire_weapon(weapon: Resource) -> void:
	var wid := _wname(weapon, "id")
	var state: Dictionary = ammo.get(wid, {"mag": 1, "reserve": 0})
	state["mag"] = int(state["mag"]) - 1
	ammo[wid] = state
	var rpm := _wfloat(weapon, "rpm", 400.0)
	weapon_cooldown = 60.0 / maxf(1.0, rpm * get_fire_rate_mult())
	var spread := _wfloat(weapon, "spread", 2.0)
	if absf(velocity.x) > 30.0:
		spread += 1.2
	if not is_on_floor():
		spread += 2.0
	if _wbool(weapon, "automatic"):
		spread_heat = minf(6.0, spread_heat + 0.3)
	else:
		spread_heat = 0.0
	spread += spread_heat
	var origin: Vector2 = global_position + MUZZLE_LOCAL
	var range_px := _wfloat(weapon, "effective_range", 400.0)
	var pellets: int = maxi(1, int(_wint(weapon, "pellets", 1)))
	var pierce: int = maxi(0, int(_wint(weapon, "pierce", 0)))
	var base_damage := float(_wint(weapon, "damage", 10)) * get_damage_mult()
	for i in pellets:
		var shot_angle := aim_angle + deg_to_rad(randf_range(-spread, spread) * 0.5)
		var dir := Vector2(cos(shot_angle), sin(shot_angle))
		_hitscan(origin, dir, range_px, pierce, base_damage, wid)
	if _renderer:
		_renderer.trigger_muzzle_flash()
	attack_anim_timer = 0.16
	if _audio:
		_audio.play_sfx(wid)
	if _bus:
		_bus.gunshot.emit(global_position, 900.0)
	shots_fired.emit(wid, global_position)
	_emit_state(&"fire")
	if _bus:
		_bus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))
	if int(state["mag"]) <= 0:
		start_reload()


func _hitscan(origin: Vector2, dir: Vector2, range_px: float, pierce: int,
		damage: float, weapon_id: StringName) -> void:
	## 与现有 player.gd 相同的穿透逻辑: 命中后前移 2px 继续查询,
	## 打到无 apply_damage/hit 方法的物体(墙)即停止。
	var space := get_world_2d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var from := origin
	var remaining := range_px
	for i in 1 + pierce:
		var query := PhysicsRayQueryParameters2D.create(from, from + dir * remaining,
			ENEMY_RAY_MASK, exclude)
		query.collide_with_areas = false
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		exclude.append(result["rid"])
		var collider: Object = result["collider"]
		var point: Vector2 = result["position"]
		_apply_hit(collider, point, dir, damage, weapon_id)
		from = point + dir * 2.0
		remaining = range_px - origin.distance_to(from)
		if remaining <= 2.0:
			break
		if not (collider.has_method("apply_damage") or collider.has_method("hit")):
			break


func _apply_hit(collider: Object, point: Vector2, dir: Vector2, damage: float,
		weapon_id: StringName) -> void:
	var distance := global_position.distance_to(point)
	var current := _current_weapon()
	var effective: float = 400.0
	if current != null:
		effective = _wfloat(current, "effective_range", 400.0)
	var falloff := _falloff(distance, effective)
	var amount := int(round(damage * falloff))
	var damage_type: StringName = &"shotgun" if weapon_id == &"shotgun" else &"bullet"
	var is_head := false
	if collider.has_method("apply_damage"):
		if collider.has_method("is_headshot_point"):
			is_head = bool(collider.is_headshot_point(point))
		if is_head:
			amount *= 2
		collider.apply_damage(amount, -dir, is_head, &"player", damage_type)
	elif collider.has_method("hit"):
		collider.hit(amount, &"player")
	if _bus and is_head:
		_bus.hitstop.emit(0.03)


func _falloff(distance: float, effective_range: float) -> float:
	## 与现有 MathUtils.damage_falloff 相同: 射程外每 100px -15%,下限 40%。
	if distance <= effective_range:
		return 1.0
	return maxf(0.4, 1.0 - (distance - effective_range) / 100.0 * 0.15)


func start_reload() -> void:
	var weapon := _current_weapon()
	if weapon == null or reloading:
		return
	if _wname(weapon, "category") == &"melee":
		return
	var wid := _wname(weapon, "id")
	var state: Dictionary = ammo.get(wid, {"mag": 0, "reserve": 0})
	var mag_size := _wint(weapon, "mag_size", 10)
	if int(state["mag"]) >= mag_size:
		return
	if int(state["reserve"]) == 0 and _wint(weapon, "reserve_ammo", -1) != -1:
		return
	reloading = true
	reload_timer = _wfloat(weapon, "reload_time", 1.5)
	_reload_total = reload_timer
	_emit_state(&"reload_start")


func _finish_reload() -> void:
	reloading = false
	var weapon := _current_weapon()
	if weapon == null:
		return
	var wid := _wname(weapon, "id")
	var state: Dictionary = ammo.get(wid, {"mag": 0, "reserve": 0})
	var mag_size := _wint(weapon, "mag_size", 10)
	var need: int = mag_size - int(state["mag"])
	var reserve: int = int(state["reserve"])
	if reserve < 0:
		state["mag"] = mag_size
	else:
		var take: int = mini(need, reserve)
		state["mag"] = int(state["mag"]) + take
		state["reserve"] = reserve - take
	ammo[wid] = state
	if _bus:
		_bus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))
	_emit_state(&"reload_end")


func cycle_weapon(direction: int) -> void:
	if weapon_slots.size() < 2:
		return
	slot_index = posmod(slot_index + direction, weapon_slots.size())
	reloading = false
	weapon_cooldown = maxf(weapon_cooldown, 0.25)
	_sync_weapon_visual(true)
	if _bus:
		var w := _current_weapon()
		if w != null:
			_bus.weapon_changed.emit(_wname(w, "id"), String(_wstr(w, "display_name", "")))
	_emit_state(&"weapon_switch")


func _swing_melee(weapon: Resource) -> void:
	if melee_cooldown > 0.0:
		return
	melee_cooldown = 0.55
	melee_anim_timer = 0.25
	if _renderer:
		_renderer.set_melee_swing(1.0)
	var arc := _wfloat(weapon, "melee_arc", 120.0)
	var reach := _wfloat(weapon, "melee_range", 60.0)
	var damage := float(_wint(weapon, "damage", 30)) * get_damage_mult()
	var knock := _wfloat(weapon, "knockback", 120.0)
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var to := node.global_position - global_position
		if to.length() > reach:
			continue
		var facing_vec := Vector2(float(facing), 0.0)
		if absf(rad_to_deg(facing_vec.angle_to(to))) > arc * 0.5:
			continue
		if node.has_method("apply_damage"):
			node.apply_damage(int(round(damage)), -to.normalized(), false, &"player", &"melee")
		if node.has_method("apply_knockback"):
			node.apply_knockback(to.normalized() * knock)
	shots_fired.emit(_wname(weapon, "id"), global_position)
	_emit_state(&"melee")


func _shove() -> void:
	if shove_cooldown > 0.0:
		return
	shove_cooldown = 0.9
	if _renderer:
		_renderer.set_melee_swing(1.0)
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var to := node.global_position - global_position
		if to.length() > 44.0:
			continue
		if absf(Vector2(float(facing), 0.0).angle_to(to.normalized())) > deg_to_rad(60.0):
			continue
		if node.has_method("apply_stagger"):
			node.apply_stagger(0.8)
		if node.has_method("apply_knockback"):
			node.apply_knockback(to.normalized() * 200.0)
		if node.has_method("on_melee_interrupt"):
			node.on_melee_interrupt()
	_emit_state(&"shove")


## ---------------------------------------------------------- 技能/被动 ----

func use_skill() -> void:
	if skill_cd > 0.0 or is_downed or is_dead or is_controlled:
		return
	_skill_payload["handled"] = false
	_emit_passive_event(&"skill_used", _skill_payload)
	if not bool(_skill_payload["handled"]):
		skill_cd = maxf(1.0, character_data.skill_cd)
		passive_triggered.emit(character_data.passive_ability_id, {"result": &"generic_flash"})
		if _bus:
			_bus.skill_state_changed.emit(0.0, true)


func _attach_passive(passive_id: StringName) -> void:
	if passive_id == &"":
		return
	var path := "%s/passive_%s.gd" % [PASSIVE_DIR, passive_id]
	if not ResourceLoader.exists(path):
		push_warning("PlayerControllerV2: passive script not found: " + path)
		return
	var script: Script = load(path)
	var node := Node.new()
	node.set_script(script)
	node.name = "Passive_%s" % passive_id
	add_child(node)
	_passives.append(node)


func attach_passive(passive_id: StringName) -> void:
	_attach_passive(passive_id)


func _emit_passive_event(event_name: StringName, payload: Dictionary) -> void:
	for passive in _passives:
		if is_instance_valid(passive) and passive.has_method("_on_event"):
			passive._on_event(event_name, payload)


func add_speed_modifier(source_id: StringName, mult: float) -> void:
	_speed_mods[source_id] = mult


func remove_speed_modifier(source_id: StringName) -> void:
	_speed_mods.erase(source_id)


func add_damage_modifier(source_id: StringName, mult: float) -> void:
	_damage_mods[source_id] = mult


func remove_damage_modifier(source_id: StringName) -> void:
	_damage_mods.erase(source_id)


func add_reload_modifier(source_id: StringName, mult: float) -> void:
	_reload_mods[source_id] = mult


func remove_reload_modifier(source_id: StringName) -> void:
	_reload_mods.erase(source_id)


func add_fire_rate_modifier(source_id: StringName, mult: float) -> void:
	_fire_rate_mods[source_id] = mult


func remove_fire_rate_modifier(source_id: StringName) -> void:
	_fire_rate_mods.erase(source_id)


func add_frontal_guard(source_id: StringName, mult: float) -> void:
	## mult = 正面受击伤害系数(盾墙 0.3 = 减伤 70%)。
	_frontal_guards[source_id] = mult


func remove_frontal_guard(source_id: StringName) -> void:
	_frontal_guards.erase(source_id)


func get_speed_mult() -> float:
	return _product(_speed_mods)


func get_damage_mult() -> float:
	return _product(_damage_mods)


func get_reload_speed_mult() -> float:
	return _product(_reload_mods)


func get_fire_rate_mult() -> float:
	return _product(_fire_rate_mods)


func get_effective_speed() -> float:
	return run_speed * get_speed_mult()


func grant_iframes(seconds: float, _source: StringName = &"") -> void:
	iframes = maxf(iframes, seconds)


func teleport_to(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO


static func _product(table: Dictionary) -> float:
	var result := 1.0
	for key in table:
		result *= float(table[key])
	return result


## ---------------------------------------------------------- 生命流程 ----

func take_damage(amount: int, source_dir: Vector2 = Vector2.ZERO,
		source: StringName = &"zombie", damage_type: StringName = &"melee") -> void:
	if is_dead or iframes > 0.0 or amount <= 0:
		return
	if is_downed:
		bleedout -= 2.0
		return
	var dmg := float(amount)
	if source_dir != Vector2.ZERO and not _frontal_guards.is_empty():
		var from_side: float = signf(source_dir.x)
		if from_side == 0.0:
			from_side = -float(facing)
		if int(from_side) != facing: # 攻击来自面朝方向
			dmg *= _min_frontal_guard()
	if shield_wall_timer > 0.0 and source_dir != Vector2.ZERO:
		pass # 盾墙减伤已通过 frontal_guard 修正器生效,此处不重复计算
	hp -= int(round(dmg))
	iframes = HIT_IFRAMES
	damage_taken.emit(int(round(dmg)), source)
	_emit_passive_event(&"damaged", {"amount": dmg, "source": source, "type": damage_type})
	if _bus:
		_bus.player_hit.emit(int(round(dmg)))
		_bus.damage_flash.emit()
	if hp <= 0:
		_go_down()
	else:
		_emit_state(&"hurt")


func _min_frontal_guard() -> float:
	var result := 1.0
	for key in _frontal_guards:
		result = minf(result, float(_frontal_guards[key]))
	return result


func _go_down() -> void:
	hp = 0
	downs += 1
	if downs > _max_downs():
		die()
		return
	is_downed = true
	bleedout = BLEEDOUT_TIME
	velocity = Vector2.ZERO
	if _renderer:
		_renderer.set_downed(true)
	downed.emit()
	if _bus:
		_bus.player_downed.emit()
	_emit_state(&"downed")


func _tick_downed(delta: float) -> void:
	bleedout -= delta
	if _just_pressed(&"medkit") and medkits > 0:
		medkits -= 1
		revive(self)
		return
	if bleedout <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_downed = false
	is_controlled = false
	hp = 0
	velocity = Vector2.ZERO
	if _renderer:
		_renderer.set_dead(true)
		_renderer.set_anim_state(CodeRenderer.STATE_IDLE)
	died.emit()
	if _bus:
		_bus.player_died.emit()
	_emit_state(&"dead")


func revive(_healer: Node) -> void:
	if is_dead or not is_downed:
		return
	is_downed = false
	black_white = downs >= _max_downs()
	hp = 30
	temp_hp = 30 if black_white else 0
	bleedout = BLEEDOUT_TIME
	control_immune = CONTROL_IMMUNE_TIME
	iframes = 1.0
	if _renderer:
		_renderer.set_downed(false)
	revived.emit()
	if _bus:
		_bus.player_rescued.emit()
	_emit_state(&"revived")


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	hp = mini(hp + amount, max_hp)
	if _bus:
		_bus.player_healed.emit(amount)
	_emit_state(&"healed")


func heal_full() -> void:
	if is_dead:
		return
	hp = max_hp
	temp_hp = 0
	black_white = false


func set_stealth_invisible(duration: float) -> void:
	visibility = 0.01
	downs = 0
	_emit_state(&"healed")


func respawn_at(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	is_dead = false
	is_downed = false
	is_controlled = false
	hp = max_hp
	downs = 0
	black_white = false
	bleedout = BLEEDOUT_TIME
	iframes = 2.0
	if _renderer:
		_renderer.set_dead(false)
		_renderer.set_downed(false)
	_emit_state(&"respawn")


func apply_bile(duration: float) -> void:
	bile_timer = maxf(bile_timer, duration)
	if _bus:
		_bus.bile_splashed.emit(duration)
	_emit_state(&"bile")


func apply_burn(dps: float, duration: float) -> void:
	burn_timer = maxf(burn_timer, duration)
	burn_dps = maxf(burn_dps, dps)
	_emit_state(&"burn")


func enter_control(kind: StringName, source: Node) -> void:
	if is_dead or control_immune > 0.0 or is_controlled:
		return
	is_controlled = true
	control_kind = kind
	controller = source
	velocity = Vector2.ZERO
	if _bus:
		_bus.player_hit.emit(0)
	_emit_state(&"controlled")


func release_control() -> void:
	if not is_controlled:
		return
	is_controlled = false
	control_kind = &""
	controller = null
	control_immune = CONTROL_IMMUNE_TIME
	_emit_state(&"control_released")


func inspire(duration: float) -> void:
	var had_active: bool = inspire_timer > 0.0
	inspire_timer = maxf(inspire_timer, duration)
	add_fire_rate_modifier(&"inspire", 1.3)
	if not had_active:
		# 到期移除由一次性计时器处理,避免每帧轮询修正器字典。
		get_tree().create_timer(duration).timeout.connect(
			func() -> void: remove_fire_rate_modifier(&"inspire"))
	_emit_state(&"inspired")


func _max_downs() -> int:
	if _game != null and _game.has_method("max_downs"):
		return int(_game.max_downs())
	return 3


## ---------------------------------------------------------- 武器装配 ----

func _setup_weapons() -> void:
	weapon_slots.clear()
	for id in [character_data.primary_weapon, character_data.secondary_weapon,
			character_data.melee_weapon]:
		if id != &"" and not weapon_slots.has(id):
			weapon_slots.append(id)
	slot_index = 0
	for id in weapon_slots:
		var w := _load_weapon(id)
		if w == null:
			continue
		var reserve: int = _wint(w, "reserve_ammo", -1)
		if _wname(w, "category") == &"melee":
			reserve = 0
		ammo[id] = {"mag": _wint(w, "mag_size", 0), "reserve": reserve}
	_sync_weapon_visual(true)


func _load_weapon(id: StringName) -> Resource:
	if _game != null and _game.has_method("get_weapon"):
		var w: Variant = _game.get_weapon(id)
		if w != null:
			return w
	var path := "%s/weapon_%s.tres" % [FALLBACK_WEAPON_DIR, id]
	if ResourceLoader.exists(path):
		return load(path)
	return _make_fallback_weapon(id)


static func _make_fallback_weapon(id: StringName) -> Resource:
	## 独立运行且无武器资源时的最小占位武器(duck-typed 字段)。
	var res := Resource.new()
	res.set("id", id)
	res.set("display_name", String(id))
	res.set("category", &"primary")
	res.set("damage", 12)
	res.set("pellets", 1)
	res.set("rpm", 300.0)
	res.set("mag_size", 12)
	res.set("reserve_ammo", 96)
	res.set("reload_time", 1.4)
	res.set("spread", 2.0)
	res.set("effective_range", 380.0)
	res.set("automatic", false)
	res.set("pierce", 0)
	res.set("knockback", 40.0)
	res.set("sprite", String(id))
	return res


func _current_weapon() -> Resource:
	if weapon_slots.is_empty():
		return null
	return _load_weapon(weapon_slots[slot_index])


func give_weapon(id: StringName) -> void:
	if not weapon_slots.has(id):
		weapon_slots.append(id)
	var w := _load_weapon(id)
	if w != null:
		ammo[id] = {"mag": _wint(w, "mag_size", 0),
			"reserve": _wint(w, "reserve_ammo", -1)}


func add_ammo(amount: int = 9999) -> void:
	for id in ammo.keys():
		var state: Dictionary = ammo[id]
		if int(state["reserve"]) >= 0:
			state["reserve"] = int(state["reserve"]) + amount
		ammo[id] = state


func _setup_item_component() -> void:
	_item_component = (load("res://scripts/items/ItemComponent.gd") as GDScript).new()
	_item_component.name = "ItemComponent"
	_item_component._owner_ref = self
	add_child(_item_component)


func _setup_renderer() -> void:
	var existing := get_node_or_null("Renderer")
	if existing is PlayerRenderer:
		_renderer = existing
	else:
		_renderer = PlayerRenderer.new()
		_renderer.name = "Renderer"
		_renderer.z_index = 5
		add_child(_renderer)
	var muzzle := get_node_or_null("MuzzlePoint")
	if muzzle == null:
		var marker := Marker2D.new()
		marker.name = "MuzzlePoint"
		marker.position = MUZZLE_LOCAL
		add_child(marker)
	_renderer.setup(character_data)


func _sync_weapon_visual(force: bool = false) -> void:
	if _renderer == null:
		return
	var w := _current_weapon()
	if w == null:
		return
	var kind := &"gun"
	var visual: StringName = &"rifle"
	if _wname(w, "category") == &"melee":
		kind = &"melee"
		visual = WEAPON_VISUAL_TYPES.get(_wname(w, "id"), &"axe")
	else:
		var sprite_key := _wstr(w, "sprite", String(_wname(w, "id")))
		visual = WEAPON_VISUAL_TYPES.get(sprite_key, &"rifle")
		if character_data.visual_profile == &"operative" and kind == &"gun" \
				and visual == &"rifle":
			visual = &"suppressed"
	if force or visual != _cached_gun_visual:
		_cached_gun_visual = visual
		_renderer.set_weapon_visual(kind, visual)


func _build_camera() -> void:
	if get_node_or_null("Camera") != null:
		return
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(0, -80)
	camera.limit_top = 0
	camera.limit_bottom = 360
	camera.position_smoothing_enabled = true
	add_child(camera)
	camera.make_current()


## ---------------------------------------------------------- 交互 ----

func _tick_interaction() -> void:
	_interact_target = null
	var prompt := ""
	var best := 1e9
	for candidate in get_tree().get_nodes_in_group("interactable"):
		var node := candidate as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist > 40.0 or dist > best:
			continue
		if node.has_method("can_interact") and not bool(node.can_interact(self)):
			continue
		best = dist
		_interact_target = node
		prompt = str(node.get("interact_text")) if node.get("interact_text") != null else "互动"
	if prompt != _last_prompt:
		_last_prompt = prompt
		if _bus:
			_bus.interact_prompt.emit(prompt)
	if _interact_target != null and _just_pressed(&"interact"):
		if _interact_target.has_method("interact"):
			_interact_target.interact(self)
		_emit_state(&"interact")


## ------------------------------------------------------- 物品代理 ----

func _throw_stub() -> void:
	if _item_component != null:
		_item_component.throw(throw_index)
	else:
		_emit_passive_event(&"throw_requested", {})
	_emit_state(&"throw")


func _medkit_stub() -> void:
	if _item_component != null:
		_item_component.use_medkit()
	else:
		if medkits <= 0 or is_dead:
			return
		medkits -= 1
		heal(int(70.0 * _medkit_mult()))
		black_white = false
	_emit_state(&"medkit")


func _pills_stub() -> void:
	if _item_component != null:
		_item_component.use_pills()
	else:
		if pills <= 0 or is_dead:
			return
		pills -= 1
		temp_hp += 50
	_emit_state(&"pills")


func get_status_text() -> String:
	var statuses: Array[String] = []
	if bool(is_downed):
		statuses.append("倒地")
	elif bool(black_white):
		statuses.append("黑血")
	if bool(is_controlled):
		statuses.append("受控")
	if bile_timer > 0.0:
		statuses.append("胆汁")
	if burn_timer > 0.0:
		statuses.append("燃烧")
	if slow_timer > 0.0:
		statuses.append("减速")
	if inspire_timer > 0.0:
		statuses.append("鼓舞")
	if shield_wall_timer > 0.0:
		statuses.append("盾墙")
	if statuses.is_empty():
		return "状态正常"
	return " · ".join(statuses)


func _medkit_mult() -> float:
	if _game != null and _game.has_method("medkit_mult"):
		return float(_game.medkit_mult())
	return 1.0


## ------------------------------------------------------- 视觉同步 ----

func _sync_visuals() -> void:
	if _renderer == null:
		return
	var state := CodeRenderer.STATE_IDLE
	if is_downed or is_dead:
		state = CodeRenderer.STATE_IDLE
	elif _attack_anim_active():
		state = CodeRenderer.STATE_ATTACK
	elif absf(velocity.x) > 24.0 and is_on_floor():
		state = CodeRenderer.STATE_WALK
	_renderer.set_anim_state(state)
	_renderer.set_facing(facing)
	_renderer.set_aim_angle(aim_angle)
	_renderer.set_health_ratio(float(hp) / float(maxi(1, max_hp)))
	_renderer.set_downed(is_downed)
	_renderer.set_dead(is_dead)


func _attack_anim_active() -> bool:
	return attack_anim_timer > 0.0 or melee_anim_timer > 0.0


## ------------------------------------------------------- 事件/工具 ----

func _emit_state(state: StringName, detail: Dictionary = {}) -> void:
	character_state_changed.emit(state, detail)


func _autoload(what: StringName) -> Node:
	return get_node_or_null("/root/" + String(what))


var _resolved_actions: Dictionary = {}


func _act(action: String) -> String:
	var cached: Variant = _resolved_actions.get(action, null)
	if cached != null:
		return cached
	var aliases: Array = ACTION_ALIASES.get(action, [action])
	for alias in aliases:
		if InputMap.has_action(alias):
			_resolved_actions[action] = alias
			return alias
	_resolved_actions[action] = action
	return action


func _pressed(action: String) -> bool:
	var resolved := _act(action)
	return InputMap.has_action(resolved) and Input.is_action_pressed(resolved)


func _just_pressed(action: String) -> bool:
	var resolved := _act(action)
	return InputMap.has_action(resolved) and Input.is_action_just_pressed(resolved)


func _held(action: String) -> bool:
	return _pressed(action)


static func _wint(w: Resource, field: String, fallback: int) -> int:
	var value: Variant = w.get(field)
	return fallback if value == null else int(value)


static func _wfloat(w: Resource, field: String, fallback: float) -> float:
	var value: Variant = w.get(field)
	return fallback if value == null else float(value)


static func _wbool(w: Resource, field: String) -> bool:
	var value: Variant = w.get(field)
	return false if value == null else bool(value)


static func _wname(w: Resource, field: String) -> StringName:
	var value: Variant = w.get(field)
	return &"" if value == null else value


static func _wstr(w: Resource, field: String, fallback: String) -> String:
	var value: Variant = w.get(field)
	return fallback if value == null else String(value)
