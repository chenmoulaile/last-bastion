extends CharacterBody2D
## Player survivor: movement, 8-way aim, hitscan weapons, melee shove, slide,
## downed/revive, skills, throwables and interactions.

const GRAVITY := 1500.0
const JUMP_VELOCITY := -560.0
const COYOTE_TIME := 0.08
const JUMP_BUFFER_TIME := 0.10
const SLIDE_TIME := 0.35
const SLIDE_IFRAMES := 0.15
const SLIDE_CD := 1.2
const RAPPEL_TIME := 0.34
const HIT_IFRAMES := 0.5
const BLEEDOUT_TIME := 20.0
const REVIVE_TIME := 3.0
const MEDKIT_TIME := 4.0
const MAX_THROWABLES := 3

var level: Node = null
var character: CharacterData
var visual_id: String = "assault"

## --- narrative / stealth layer (2019 RUST FREQUENCY) ----------------------
signal silent_execution(victim: Node)
signal backstab_blocked

var visibility: float = 1.0 # 0 = 完全不可见；感染者用它缩放视野
var is_stealthed: bool = false
var stealth_speed_multiplier: float = 0.6
var is_executing: bool = false
var execute_timer: float = 0.0
var _invisible_timer: float = 0.0
var passive: Node = null
var damage_multipliers: Dictionary = {} # group -> multiplier (维克多)
var passive_block_backstab: bool = false
var passive_block_cooldown: float = 30.0
var backstab_block_cd: float = 0.0
var samples: int = 0

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

var facing: int = 1
var aim_dir: Vector2 = Vector2.RIGHT
var aim_angle: float = 0.0
var mouse_recent: float = 0.0
var using_mouse: bool = false

var run_speed: float = 220.0
var crouch_speed: float = 110.0
var coyote: float = 0.0
var jump_buffer: float = 0.0
var is_crouching: bool = false
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_cd: float = 0.0
var slide_dir: float = 1.0
var roll_timer: float = 0.0
var roll_dir: Vector2 = Vector2.RIGHT
var rappelling: bool = false
var _rappel_from: Vector2 = Vector2.ZERO
var _rappel_to: Vector2 = Vector2.ZERO
var _rappel_t: float = 0.0
var iframes: float = 0.0
var bleedout: float = BLEEDOUT_TIME

var weapon_slots: Array[StringName] = []
var slot_index: int = 0
var ammo: Dictionary = {}
var weapon_cooldown: float = 0.0
var reload_timer: float = 0.0
var reloading: bool = false
var spread_heat: float = 0.0
var last_shot_time: float = -10.0
var shoot_anim_timer: float = 0.0
var melee_anim_timer: float = 0.0
var hurt_anim_timer: float = 0.0
var melee_cooldown: float = 0.0
var scoped: bool = false

var medkits: int = 1
var pills: int = 1
var throwables: Dictionary = {"grenade": 1, "molotov": 1, "bile": 1}
var throw_index: int = 0
var medkit_channel: float = 0.0
var medkit_using: bool = false
var chainsaw_fuel: float = 25.0
var _temp_decay_accum: float = 0.0

var skill_cd: float = 0.0
var skill_active_timer: float = 0.0
var skill_active: bool = false
var inspire_timer: float = 0.0
var assault_rush_timer: float = 0.0
var shield_wall_timer: float = 0.0
var field_medic_flash: float = 0.0

var bile_timer: float = 0.0
var slow_timer: float = 0.0
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var flashlight_on: bool = false
var flashlight: PointLight2D = null
var revive_target: Node = null
var revive_progress: float = 0.0
var interact_target: Node = null
var interact_text: String = ""

var _last_floor: bool = false
var _muzzle_local := Vector2(20, -18)

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision: CollisionShape2D = $Collision
@onready var weapon_sprite: Sprite2D = $WeaponSprite
@onready var muzzle: Marker2D = $Muzzle
@onready var camera: ShakeCamera = $Camera


func _ready() -> void:
	add_to_group("player")
	character = GameManager.get_character(GameManager.selected_character)
	if character == null:
		character = GameManager.get_character(&"assault")
	visual_id = character.animation_id()
	max_hp = character.max_hp
	hp = max_hp
	run_speed = character.speed
	stealth_speed_multiplier = character.stealth_speed_multiplier
	crouch_speed = run_speed * stealth_speed_multiplier
	sprite.sprite_frames = SpriteLibrary.character_frames(visual_id)
	sprite.play("idle")
	_apply_palette()
	_setup_weapons()
	_install_passive()
	_emit_all_state()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if level != null and bool(level.get("dark")):
		_create_flashlight()
	call_deferred("_setup_camera")


## 调色板偏移：不重画像素素材，用 modulate 区分四名角色。
func _apply_palette() -> void:
	if character == null:
		return
	var tint: Color = character.palette_tint
	if tint == Color.WHITE:
		return
	sprite.modulate = tint
	weapon_sprite.modulate = tint.lightened(0.15)


func _install_passive() -> void:
	if character == null or not character.has_passive():
		return
	if not PassiveRegistry.has_passive(character.passive_ability_id):
		push_warning("Unknown passive: " + String(character.passive_ability_id))
		return
	passive = PassiveRegistry.create(character.passive_ability_id, self, character)
	if passive != null:
		add_child(passive)


func _setup_camera() -> void:
	if level == null:
		return
	camera.limit_left = 0
	camera.limit_right = int(level.get("level_width"))
	camera.limit_top = 0
	camera.limit_bottom = 360
	camera.limit_smoothed = true
	camera.position = Vector2(0, -80)


func _setup_weapons() -> void:
	weapon_slots = [character.primary_weapon, character.secondary_weapon, character.melee_weapon]
	for id in weapon_slots:
		var data := GameManager.get_weapon(id)
		if data == null:
			continue
		if data.category in [&"primary", &"secondary"]:
			ammo[id] = {"mag": data.mag_size, "reserve": data.reserve_ammo}
	slot_index = 0
	_update_weapon_visual()


func _create_flashlight() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.94, 0.72, 0.85))
	gradient.set_color(1, Color(0.8, 0.75, 0.55, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	flashlight = PointLight2D.new()
	flashlight.texture = tex
	flashlight.energy = 1.1
	flashlight.texture_scale = 1.7
	flashlight.color = Color(1.0, 0.93, 0.72)
	flashlight.position = Vector2(0, -20)
	flashlight.enabled = false
	add_child(flashlight)


func _input(event: InputEvent) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if event is InputEventMouseMotion:
		mouse_recent = 2.0
		using_mouse = true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if is_dead:
		return
	_tick_timers(delta)
	if rappelling:
		_tick_rappel(delta)
		return
	if is_controlled:
		velocity = Vector2.ZERO
		if sprite.animation != "hurt":
			sprite.play("hurt")
		return
	if is_executing:
		velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		sprite.play("melee")
		return
	if is_downed:
		_tick_downed(delta)
		return
	_update_aim(delta)
	_tick_actions(delta)
	_tick_movement(delta)
	_update_animation()
	_update_weapon_visual()


func _tick_timers(delta: float) -> void:
	iframes = maxf(0.0, iframes - delta)
	control_immune = maxf(0.0, control_immune - delta)
	slide_cd = maxf(0.0, slide_cd - delta)
	weapon_cooldown = maxf(0.0, weapon_cooldown - delta)
	melee_cooldown = maxf(0.0, melee_cooldown - delta)
	shoot_anim_timer = maxf(0.0, shoot_anim_timer - delta)
	melee_anim_timer = maxf(0.0, melee_anim_timer - delta)
	hurt_anim_timer = maxf(0.0, hurt_anim_timer - delta)
	mouse_recent = maxf(0.0, mouse_recent - delta)
	bile_timer = maxf(0.0, bile_timer - delta)
	slow_timer = maxf(0.0, slow_timer - delta)
	inspire_timer = maxf(0.0, inspire_timer - delta)
	assault_rush_timer = maxf(0.0, assault_rush_timer - delta)
	shield_wall_timer = maxf(0.0, shield_wall_timer - delta)
	field_medic_flash = maxf(0.0, field_medic_flash - delta)
	skill_active_timer = maxf(0.0, skill_active_timer - delta)
	skill_active = skill_active_timer > 0.0
	if skill_cd > 0.0:
		skill_cd = maxf(0.0, skill_cd - delta)
		EventBus.skill_state_changed.emit(1.0 - skill_cd / maxf(0.01, character.skill_cd), skill_active)
	if reloading:
		var data := _current_weapon()
		var reload_speed := 2.0 if assault_rush_timer > 0.0 else 1.0
		reload_timer -= delta * reload_speed
		if reload_timer <= 0.0:
			_finish_reload()
	if temp_hp > 0:
		_temp_decay_accum += delta
		if _temp_decay_accum >= 1.0:
			_temp_decay_accum -= 1.0
			temp_hp = maxi(0, temp_hp - 1)
			EventBus.health_changed.emit(hp, temp_hp, max_hp)
	if burn_timer > 0.0:
		burn_timer -= delta
		_apply_direct_damage(burn_dps * delta, Vector2.ZERO, &"fire", &"fire")
	if medkit_using:
		medkit_channel -= delta
		if medkit_channel <= 0.0:
			_finish_medkit()
	execute_timer = maxf(0.0, execute_timer - delta)
	if execute_timer <= 0.0:
		is_executing = false
	backstab_block_cd = maxf(0.0, backstab_block_cd - delta)
	if _invisible_timer > 0.0:
		_invisible_timer = maxf(0.0, _invisible_timer - delta)
	visibility = 0.0 if _invisible_timer > 0.0 else (0.45 if is_stealthed else 1.0)


## 处决/潜行让玩家进入“不可见”窗口，由被动脚本调用。
func set_stealth_invisible(duration: float) -> void:
	_invisible_timer = maxf(_invisible_timer, duration)
	visibility = 0.0


func _update_stealth() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var quiet := now - last_shot_time > 1.2
	is_stealthed = is_crouching and not is_sliding and not flashlight_on and quiet \
		and not is_dead and not is_downed and not is_controlled


func _tick_movement(delta: float) -> void:
	if roll_timer > 0.0:
		roll_timer -= delta
		velocity = roll_dir * 800.0
		move_and_slide()
		return
	var input_x := Input.get_axis("move_left", "move_right")
	if absf(input_x) > 0.1:
		if not using_mouse or mouse_recent <= 0.0:
			facing = 1 if input_x > 0.0 else -1
	var on_floor := is_on_floor()
	if on_floor:
		coyote = COYOTE_TIME
	else:
		coyote = maxf(0.0, coyote - delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER_TIME
	else:
		jump_buffer = maxf(0.0, jump_buffer - delta)

	var crouch_pressed := Input.is_action_pressed("crouch") and on_floor
	if Input.is_action_just_pressed("crouch") and crouch_pressed and absf(input_x) > 0.4 and slide_cd <= 0.0 and not is_sliding:
		_start_slide(input_x)
	if is_sliding:
		slide_timer -= delta
		velocity.x = slide_dir * run_speed * 1.15
		if slide_timer <= 0.0:
			is_sliding = false
		is_crouching = false
	else:
		is_crouching = crouch_pressed
		var speed := crouch_speed if is_crouching else run_speed
		if assault_rush_timer > 0.0:
			speed *= 1.2
		if bile_timer > 0.0:
			speed *= 0.85
		if slow_timer > 0.0:
			speed *= 0.85
		if is_downed:
			speed = 45.0
		var target_x := input_x * speed
		var accel := 1800.0 if on_floor else 900.0
		velocity.x = move_toward(velocity.x, target_x, accel * delta)
	_update_stealth()

	# Crouch + jump drops through one-way platforms.
	if jump_buffer > 0.0 and Input.is_action_pressed("crouch") and on_floor:
		position.y += 3.0
		jump_buffer = 0.0
	elif jump_buffer > 0.0 and coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer = 0.0
		coyote = 0.0
		is_crouching = false
		AudioManager.play_sfx(&"jump")

	if not on_floor:
		velocity.y += GRAVITY * delta
		if velocity.y > 700.0:
			velocity.y = 700.0
	_step_up(input_x)
	move_and_slide()
	if global_position.y > 460.0:
		take_damage(999, Vector2.DOWN, &"pit", &"fall")
	camera.set_look_ahead(facing * 40.0)
	_last_floor = is_on_floor()


func _step_up(input_x: float) -> void:
	if absf(input_x) < 0.2 or not is_on_floor():
		return
	var dir := signf(input_x)
	var forward := Vector2(dir * 7.0, 0)
	if not test_move(global_transform, forward):
		return
	for height in [4.0, 8.0, 12.0, 16.0]:
		var lifted := global_transform.translated(Vector2(0, -height))
		if not test_move(lifted, Vector2.ZERO) and not test_move(lifted, forward):
			global_position.y -= height
			return


func _start_slide(input_x: float) -> void:
	is_sliding = true
	slide_timer = SLIDE_TIME
	slide_cd = SLIDE_CD
	slide_dir = 1.0 if input_x > 0.0 else -1.0
	iframes = maxf(iframes, SLIDE_IFRAMES)
	velocity.x = slide_dir * run_speed * 1.2
	AudioManager.play_sfx(&"slide")


func start_rappel(target_y: float) -> bool:
	if is_dead or is_downed or is_controlled or rappelling:
		return false
	if target_y <= global_position.y + 8.0:
		return false
	rappelling = true
	_rappel_from = global_position
	_rappel_to = Vector2(global_position.x, target_y)
	_rappel_t = 0.0
	velocity = Vector2.ZERO
	is_sliding = false
	is_crouching = false
	iframes = maxf(iframes, 0.7)
	sprite.play("jump")
	AudioManager.play_sfx(&"slide")
	return true


func _tick_rappel(delta: float) -> void:
	_rappel_t = minf(1.0, _rappel_t + delta / RAPPEL_TIME)
	global_position = _rappel_from.lerp(_rappel_to, ease(_rappel_t, 0.6))
	velocity = Vector2.ZERO
	if _rappel_t >= 1.0:
		rappelling = false
		global_position = _rappel_to
		iframes = maxf(iframes, 0.3)
		AudioManager.play_sfx(&"zombie_land")
		EventBus.shake(0.8)


func _update_aim(delta: float) -> void:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if stick.length() > 0.35:
		aim_dir = stick.normalized()
		using_mouse = false
	elif mouse_recent > 0.0:
		var to_mouse := get_global_mouse_position() - (global_position + Vector2(0, -16))
		if to_mouse.length() > 12.0:
			aim_dir = to_mouse.normalized()
			using_mouse = true
	if mouse_recent <= 0.0:
		using_mouse = false
	if not using_mouse:
		var ax := float(facing)
		var ay := 0.0
		if Input.is_action_pressed("aim_up"):
			ay = -1.0
		elif Input.is_action_pressed("aim_down") and not is_crouching:
			ay = 1.0
		aim_dir = Vector2(ax, ay).normalized()
	if aim_dir.length_squared() < 0.01:
		aim_dir = Vector2(float(facing), 0.0)
	aim_angle = aim_dir.angle()
	if aim_dir.x > 0.25:
		facing = 1
	elif aim_dir.x < -0.25:
		facing = -1
	sprite.flip_h = facing < 0
	weapon_sprite.flip_h = facing < 0
	weapon_sprite.flip_v = absf(aim_angle) > PI * 0.5
	weapon_sprite.rotation = aim_angle
	var hand := Vector2(facing * 8.0, -18.0)
	weapon_sprite.position = hand + aim_dir * 4.0
	weapon_sprite.z_index = 6 if facing > 0 else 4
	_muzzle_local = hand + aim_dir * 14.0
	muzzle.position = _muzzle_local


func _tick_actions(delta: float) -> void:
	var weapon := _current_weapon()
	if weapon == null:
		return
	if Input.is_action_just_pressed("switch_weapon"):
		_cycle_weapon(1)
	if Input.is_action_just_pressed("reload"):
		_start_reload()
	if Input.is_action_just_pressed("melee"):
		if not _try_execution():
			_shove()
	if Input.is_action_just_pressed("skill"):
		_use_skill()
	if Input.is_action_just_pressed("throw"):
		_throw_current()
	if Input.is_action_just_pressed("throw_cycle"):
		_cycle_throwable()
	if Input.is_action_just_pressed("medkit"):
		_start_medkit()
	if Input.is_action_just_pressed("pills"):
		_use_pills()
	if Input.is_action_just_pressed("flashlight") and flashlight != null:
		flashlight_on = not flashlight_on
		flashlight.enabled = flashlight_on
		AudioManager.play_sfx(&"ui_click")

	if weapon.category == &"melee":
		if Input.is_action_pressed("fire") and weapon_cooldown <= 0.0:
			if weapon.id == &"chainsaw":
				if chainsaw_fuel <= 0.0:
					_cycle_weapon(1)
					return
				chainsaw_fuel = maxf(0.0, chainsaw_fuel - delta)
				EventBus.ammo_changed.emit(int(ceil(chainsaw_fuel)), 25)
			_swing_melee(weapon)
	elif Input.is_action_pressed("fire"):
		_try_fire(weapon)
	if Input.is_action_pressed("fire") and weapon.id == &"sniper" and Input.is_action_pressed("crouch"):
		scoped = true
	else:
		scoped = false
	if reloading and Input.is_action_just_pressed("fire"):
		return
	_tick_interaction(delta)


func _tick_interaction(delta: float) -> void:
	var downed: Node = level.get_downed_ally_near(global_position) if level else null
	var pinned: Node = level.get_pinned_ally_near(global_position) if level else null
	revive_target = pinned if pinned != null else downed
	if revive_target != null and is_instance_valid(revive_target):
		interact_text = "E 救助"
		EventBus.interact_prompt.emit(interact_text)
		if Input.is_action_pressed("interact"):
			revive_progress += delta
			if revive_progress >= REVIVE_TIME:
				level.revive_ally(revive_target, self)
				revive_target = null
				revive_progress = 0.0
		else:
			revive_progress = 0.0
		return
	revive_progress = 0.0
	interact_target = level.get_nearby_interactable(global_position) if level else null
	if interact_target != null and is_instance_valid(interact_target):
		interact_text = interact_target.get_prompt() if interact_target.has_method("get_prompt") else "E 互动"
		EventBus.interact_prompt.emit(interact_text)
		if Input.is_action_just_pressed("interact"):
			interact_target.interact(self)
	else:
		EventBus.interact_prompt.emit("")


func _try_fire(weapon: WeaponData) -> void:
	if reloading or weapon_cooldown > 0.0:
		return
	if not weapon.automatic and not Input.is_action_just_pressed("fire"):
		return
	var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
	if int(state["mag"]) <= 0:
		AudioManager.play_sfx(&"empty")
		_start_reload()
		return
	if weapon.category == &"throwable":
		return
	_fire_weapon(weapon)


func _fire_weapon(weapon: WeaponData) -> void:
	var state: Dictionary = ammo.get(weapon.id, {"mag": 1, "reserve": 0})
	state["mag"] = int(state["mag"]) - 1
	ammo[weapon.id] = state
	weapon_cooldown = 60.0 / maxf(1.0, weapon.rpm)
	var spread := weapon.spread
	if scoped and weapon.scoped_spread >= 0.0:
		spread = weapon.scoped_spread
	if absf(velocity.x) > 30.0:
		spread += 1.2
	if not is_on_floor():
		spread += 2.0
	if weapon.automatic:
		spread_heat = minf(6.0, spread_heat + 0.3)
	else:
		spread_heat = 0.0
	spread += spread_heat
	var origin := global_position + _muzzle_local
	var end_point := origin + aim_dir * weapon.effective_range
	for pellet in weapon.pellets:
		var shot_angle := aim_angle + deg_to_rad(randf_range(-spread, spread) * 0.5)
		var dir := Vector2(cos(shot_angle), sin(shot_angle))
		var hits := _ray_hits(origin, dir, weapon.effective_range, weapon.pierce)
		for hit in hits:
			_apply_hit(weapon, hit, dir)
		if hits.is_empty():
			Fx.tracer(level.fx_layer, origin, origin + dir * weapon.effective_range)
	Fx.muzzle(level.fx_layer, origin, aim_angle)
	Fx.shell(level.fx_layer, global_position + Vector2(facing * 4.0, -16.0), -facing)
	AudioManager.play_sfx(weapon.id)
	AudioManager.play_sfx(&"gunshot", 1.0, -8.0)
	EventBus.gunshot.emit(global_position, 900.0)
	EventBus.shake(0.8 if weapon.id != &"shotgun" else 1.6)
	shoot_anim_timer = 0.16
	last_shot_time = Time.get_ticks_msec() / 1000.0
	EventBus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))
	if int(state["mag"]) <= 0:
		_start_reload()


func _ray_hits(origin: Vector2, dir: Vector2, range_px: float, pierce: int) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var space := get_world_2d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	var from := origin
	var remaining := range_px
	var max_hits := 1 + maxi(0, pierce)
	for i in max_hits:
		var query := PhysicsRayQueryParameters2D.create(from, from + dir * remaining, 89, exclude)
		query.collide_with_areas = false
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		hits.append(result)
		var collider: Object = result["collider"]
		exclude.append(result["rid"])
		from = result["position"] + dir * 2.0
		remaining = range_px - origin.distance_to(from)
		if remaining <= 2.0:
			break
		if not (collider.has_method("apply_damage") or collider.has_method("hit")):
			break
	return hits


func _apply_hit(weapon: WeaponData, hit: Dictionary, dir: Vector2) -> void:
	var collider: Object = hit["collider"]
	var point: Vector2 = hit["position"]
	var distance := global_position.distance_to(point)
	var damage := float(weapon.damage) * MathUtils.damage_falloff(distance, weapon.effective_range)
	damage *= _damage_scale(collider)
	var is_head := false
	if collider.has_method("is_headshot_point"):
		is_head = bool(collider.is_headshot_point(point))
	if collider.has_method("apply_damage"):
		var dmg_type: StringName = &"shotgun" if weapon.id == &"shotgun" else &"bullet"
		collider.apply_damage(int(round(damage)), -dir, is_head, &"player", dmg_type)
		Fx.blood(level.fx_layer, point, dir, 1.2 if is_head else 0.9)
		if is_head:
			EventBus.hitstop.emit(0.03)
			EventBus.shake(1.4)
		else:
			EventBus.shake(0.5)
	elif collider.has_method("hit"):
		collider.hit(int(round(damage)), &"player")
		Fx.spark(level.fx_layer, point)
	else:
		Fx.spark(level.fx_layer, point)
	Fx.tracer(level.fx_layer, global_position + _muzzle_local, point)


func _start_reload() -> void:
	var weapon := _current_weapon()
	if weapon == null or weapon.category == &"melee" or reloading:
		return
	var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
	if int(state["mag"]) >= weapon.mag_size:
		return
	if int(state["reserve"]) == 0:
		return
	reloading = true
	reload_timer = weapon.reload_time
	AudioManager.play_sfx(&"reload")
	EventBus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))


func _finish_reload() -> void:
	reloading = false
	var weapon := _current_weapon()
	if weapon == null:
		return
	var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
	var need := weapon.mag_size - int(state["mag"])
	if int(state["reserve"]) < 0:
		state["mag"] = weapon.mag_size
	else:
		var load := mini(need, int(state["reserve"]))
		state["mag"] = int(state["mag"]) + load
		state["reserve"] = int(state["reserve"]) - load
	ammo[weapon.id] = state
	EventBus.ammo_changed.emit(int(state["mag"]), int(state["reserve"]))
	AudioManager.play_sfx(&"reload_done")


func _swing_melee(weapon: WeaponData) -> void:
	weapon_cooldown = 60.0 / maxf(1.0, weapon.rpm)
	melee_anim_timer = 0.22
	var origin := global_position + Vector2(0, -14)
	var count := 0
	for zombie in level.get_zombies_in_cone(origin, facing, weapon.melee_range, weapon.melee_arc):
		count += 1
		var dir: Vector2 = (zombie.global_position - origin).normalized()
		zombie.apply_damage(int(round(float(weapon.damage) * _damage_scale(zombie))), -dir, false, &"player", &"melee")
		zombie.apply_knockback(dir * weapon.knockback)
		zombie.apply_stagger(0.5)
		Fx.blood(level.fx_layer, zombie.global_position + Vector2(0, -14), dir, 1.1)
	for barrel in level.get_interactables_in_cone(origin, facing, weapon.melee_range, weapon.melee_arc):
		if barrel.has_method("hit"):
			barrel.hit(weapon.damage, &"player")
	AudioManager.play_sfx(weapon.id)
	EventBus.shake(2.0 if count > 0 else 0.5)
	if count > 0:
		EventBus.hitstop.emit(0.04)


func _shove() -> void:
	if melee_cooldown > 0.0:
		return
	melee_cooldown = 0.45
	melee_anim_timer = 0.18
	var origin := global_position + Vector2(0, -14)
	var hit_any := false
	for zombie in level.get_zombies_in_cone(origin, facing, 46.0, 120.0):
		hit_any = true
		var dir: Vector2 = (zombie.global_position - origin).normalized()
		zombie.apply_damage(int(round(15.0 * _damage_scale(zombie))), -dir, false, &"player", &"melee")
		zombie.apply_knockback(dir * 120.0)
		zombie.apply_stagger(0.8)
		if zombie.has_method("on_melee_interrupt"):
			if zombie.on_melee_interrupt():
				level.register_hunter_interrupt()
		Fx.blood(level.fx_layer, zombie.global_position + Vector2(0, -14), dir, 1.0)
	if hit_any:
		EventBus.hitstop.emit(0.04)
		EventBus.shake(2.2)
		AudioManager.play_sfx(&"melee_hit")
	else:
		AudioManager.play_sfx(&"melee_swing")


# ------------------------------------------------------- stealth execute ----
## 潜行状态下从背后处决：不触发尸潮警觉，并让林远的被动接管感知抑制。
func _try_execution() -> bool:
	if not is_stealthed or is_executing:
		return false
	var target := _find_execution_target()
	if target == null:
		return false
	_execute(target)
	return true


func _find_execution_target() -> Node:
	if level == null:
		return null
	var origin := global_position + Vector2(0, -14)
	var best: Node = null
	var best_dist := 54.0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie == null or not is_instance_valid(zombie):
			continue
		if bool(zombie.get("dead")):
			continue
		var zdata: Variant = zombie.get("data")
		if zdata != null and bool(zdata.get("is_boss")):
			continue
		var dist: float = origin.distance_to(zombie.global_position)
		if dist > best_dist:
			continue
		var dx: float = zombie.global_position.x - global_position.x
		if signf(dx) != float(facing):
			continue
		var zombie_facing := int(zombie.get("facing"))
		if zombie_facing == 0:
			zombie_facing = -facing
		# Player stands behind the infected when both face the same way.
		if signf(dx) != float(zombie_facing):
			continue
		best = zombie
		best_dist = dist
	return best


func _execute(target: Node) -> void:
	is_executing = true
	execute_timer = 0.55
	velocity = Vector2.ZERO
	melee_anim_timer = 0.34
	reloading = false
	var dir: Vector2 = (target.global_position - global_position).normalized()
	if dir.length() < 0.1:
		dir = Vector2(float(facing), 0.0)
	# Suppress the room before the damage lands, otherwise the corpse screams.
	EnemyPerception.suppress_noise(target.global_position, 420.0, 3.0)
	var damage := character.melee_damage * 6.0 * _damage_scale(target)
	if target.has_method("apply_damage"):
		target.apply_damage(int(round(damage)), -dir, true, &"player", &"execution")
	if target.has_method("apply_stagger"):
		target.apply_stagger(1.2)
	Fx.blood(level.fx_layer if level else get_parent(),
		target.global_position + Vector2(0, -16), dir, 1.7)
	AudioManager.play_sfx(&"melee_hit")
	EventBus.shake(3.4)
	EventBus.hitstop.emit(0.06)
	EventBus.gore_event.emit(1.0)
	silent_execution.emit(target)


## Group-based damage multipliers (维克多 vs 特殊感染者).
func _damage_scale(target: Object) -> float:
	var scale := 1.0
	if damage_multipliers.is_empty() or not (target is Node):
		return scale
	var node := target as Node
	for group in damage_multipliers.keys():
		if node.is_in_group(String(group)):
			scale *= float(damage_multipliers[group])
	return scale


func _cycle_weapon(direction: int) -> void:
	if reloading:
		reloading = false
		reload_timer = 0.0
	slot_index = posmod(slot_index + direction, weapon_slots.size())
	_update_weapon_visual()
	EventBus.weapon_changed.emit(_current_weapon().id, _current_weapon().display_name)
	var weapon := _current_weapon()
	var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
	EventBus.ammo_changed.emit(int(state.get("mag", 0)), int(state.get("reserve", 0)))


func _update_weapon_visual() -> void:
	var weapon := _current_weapon()
	if weapon == null:
		weapon_sprite.visible = false
		return
	weapon_sprite.visible = true
	weapon_sprite.texture = SpriteLibrary.weapon_texture(weapon.sprite)


func _current_weapon() -> WeaponData:
	if weapon_slots.is_empty():
		return null
	return GameManager.get_weapon(weapon_slots[slot_index])


func _throw_current() -> void:
	var keys := ["grenade", "molotov", "bile"]
	var kind: String = keys[throw_index]
	if int(throwables.get(kind, 0)) <= 0:
		_cycle_throwable()
		kind = keys[throw_index]
		if int(throwables.get(kind, 0)) <= 0:
			EventBus.notify.emit("没有投掷物")
			return
	throwables[kind] = int(throwables[kind]) - 1
	level.spawn_throwable(kind, global_position + Vector2(facing * 10.0, -22.0), aim_dir)
	AudioManager.play_sfx(&"throw")
	EventBus.ammo_changed.emit(int(ammo.get(_current_weapon().id, {}).get("mag", 0)),
		int(ammo.get(_current_weapon().id, {}).get("reserve", 0)))


func _cycle_throwable() -> void:
	throw_index = (throw_index + 1) % 3
	var keys := ["grenade", "molotov", "bile"]
	EventBus.notify.emit("投掷物：" + {"grenade": "手雷", "molotov": "燃烧瓶", "bile": "胆汁瓶"}[keys[throw_index]])


func _start_medkit() -> void:
	if medkits <= 0 or medkit_using:
		return
	if not black_white and hp >= max_hp and temp_hp >= 50:
		return
	medkit_using = true
	medkit_channel = MEDKIT_TIME
	AudioManager.play_sfx(&"medkit_use")


func _finish_medkit() -> void:
	medkit_using = false
	medkits -= 1
	if black_white:
		black_white = false
		max_hp = character.max_hp
	var missing := max_hp - hp
	var heal := int(ceil(missing * 0.8))
	hp = mini(max_hp, hp + heal)
	temp_hp = 0
	EventBus.health_changed.emit(hp, temp_hp, max_hp)
	EventBus.notify.emit("使用医疗包")
	AudioManager.play_sfx(&"heal")


func _use_pills() -> void:
	if pills <= 0:
		return
	pills -= 1
	temp_hp = mini(100, temp_hp + 50)
	EventBus.health_changed.emit(hp, temp_hp, max_hp)
	AudioManager.play_sfx(&"pills")
	EventBus.notify.emit("使用药丸 +50 临时生命")


func _use_skill() -> void:
	if skill_cd > 0.0 or character == null:
		return
	skill_cd = character.skill_cd
	skill_active_timer = 0.2
	match character.skill_id:
		&"assault_rush":
			assault_rush_timer = 4.0
			skill_active_timer = 4.0
			EventBus.notify.emit("突击冲锋！")
		&"field_medic":
			heal(20)
			level.heal_allies_near(global_position, 150.0, 35)
			field_medic_flash = 0.4
			EventBus.notify.emit("战地医疗")
		&"shield_wall":
			shield_wall_timer = 5.0
			skill_active_timer = 5.0
			EventBus.notify.emit("盾墙展开")
		&"tactical_roll":
			roll_timer = 0.25
			roll_dir = aim_dir if aim_dir.length() > 0.1 else Vector2(facing, 0)
			iframes = maxf(iframes, 0.25)
			EventBus.notify.emit("战术翻滚")
		&"shadow_strike":
			var target: Node = level.find_nearest_zombie(global_position, 250.0, true)
			if target != null:
				var behind: Vector2 = target.global_position - Vector2(target.facing * 24.0, 0)
				global_position = behind
				target.apply_damage(999, Vector2.RIGHT, true, &"player", &"melee")
				Fx.blood(level.fx_layer, target.global_position, Vector2.UP, 1.5)
				EventBus.shake(3.0)
				EventBus.notify.emit("影袭")
			else:
				skill_cd = 0.0
		&"inspire":
			inspire_timer = 8.0
			skill_active_timer = 8.0
			level.inspire_allies(8.0)
			EventBus.notify.emit("全队——进攻！")
	AudioManager.play_sfx(&"skill")
	EventBus.skill_state_changed.emit(0.0, true)


func _update_animation() -> void:
	if is_dead:
		return
	var anim := "idle"
	if is_downed:
		anim = "crouch"
	elif is_sliding:
		anim = "slide"
	elif not is_on_floor():
		anim = "jump"
	elif is_crouching:
		anim = "crouch"
	elif melee_anim_timer > 0.0:
		anim = "melee"
	elif shoot_anim_timer > 0.0:
		anim = "shoot"
	elif hurt_anim_timer > 0.0:
		anim = "hurt"
	elif absf(velocity.x) > 12.0:
		anim = "run"
	if sprite.animation != anim:
		sprite.play(anim)


func _tick_downed(delta: float) -> void:
	bleedout -= delta
	var input_x := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, input_x * 45.0, 500.0 * delta)
	velocity.y += GRAVITY * delta
	move_and_slide()
	if absf(input_x) > 0.1:
		facing = 1 if input_x > 0.0 else -1
	sprite.flip_h = facing < 0
	sprite.play("crouch")
	_update_aim(delta)
	if Input.is_action_pressed("fire") and weapon_cooldown <= 0.0:
		weapon_cooldown = 0.35
		var origin := global_position + _muzzle_local
		var query := PhysicsRayQueryParameters2D.create(origin, origin + aim_dir * 400.0, 89, [get_rid()])
		var result := get_world_2d().direct_space_state.intersect_ray(query)
		var end := origin + aim_dir * 400.0
		if not result.is_empty():
			end = result["position"]
			var collider: Object = result["collider"]
			if collider.has_method("apply_damage"):
				collider.apply_damage(18, -aim_dir, false, &"player", &"bullet")
				Fx.blood(level.fx_layer, end, aim_dir)
		Fx.tracer(level.fx_layer, origin, end)
		Fx.muzzle(level.fx_layer, origin, aim_angle)
		AudioManager.play_sfx(&"m9")
	if bleedout <= 0.0:
		die()


func take_damage(amount: int, source_dir: Vector2 = Vector2.ZERO, source: StringName = &"zombie",
		damage_type: StringName = &"melee") -> void:
	if is_dead or iframes > 0.0 or GameManager.state != GameManager.State.PLAYING:
		return
	if medkit_using:
		medkit_using = false
		medkit_channel = 0.0
		reloading = false
	var final_amount := float(amount) * GameManager.enemy_damage_mult()
	if is_downed:
		bleedout -= final_amount * 0.4
		if bleedout <= 0.0:
			die()
		return
	if shield_wall_timer > 0.0 and source_dir.length() > 0.1:
		var facing_vec := Vector2(float(facing), 0.0)
		if facing_vec.dot(source_dir.normalized()) > 0.15:
			final_amount *= 0.3
	# 马库斯「老兵直觉」：伤害来自背后 120° 扇形时完全格挡。
	if passive_block_backstab and backstab_block_cd <= 0.0 and source_dir.length() > 0.1 \
			and final_amount > 0.0 and source != &"friendly":
		var behind := Vector2(float(facing), 0.0).dot(source_dir.normalized())
		if behind > 0.5:
			backstab_block_cd = passive_block_cooldown
			iframes = maxf(iframes, 0.25)
			hurt_anim_timer = 0.12
			AudioManager.play_sfx(&"ricochet")
			EventBus.shake(1.6)
			backstab_blocked.emit()
			return
	if source == &"friendly" and not GameManager.friendly_fire_enabled():
		return
	if source == &"friendly":
		final_amount *= 0.5
	var total := int(ceil(final_amount))
	if temp_hp > 0:
		var absorbed := mini(temp_hp, total)
		temp_hp -= absorbed
		total -= absorbed
	hp -= total
	iframes = HIT_IFRAMES
	hurt_anim_timer = 0.22
	EventBus.player_hit.emit(int(ceil(final_amount)))
	EventBus.damage_flash.emit()
	EventBus.shake(2.5)
	EventBus.health_changed.emit(maxi(0, hp), temp_hp, max_hp)
	AudioManager.play_sfx(&"player_hurt")
	if hp <= 0:
		_go_down()


func _apply_direct_damage(amount: float, source_dir: Vector2, source: StringName, damage_type: StringName) -> void:
	if is_dead or iframes > 0.0:
		return
	var total := int(ceil(amount * GameManager.enemy_damage_mult()))
	if temp_hp > 0:
		var absorbed := mini(temp_hp, total)
		temp_hp -= absorbed
		total -= absorbed
	hp -= total
	EventBus.player_hit.emit(total)
	EventBus.health_changed.emit(maxi(0, hp), temp_hp, max_hp)
	if hp <= 0:
		_go_down()


func _go_down() -> void:
	if is_downed or is_dead:
		return
	downs += 1
	hp = 0
	if downs >= GameManager.max_downs():
		die()
		return
	is_downed = true
	bleedout = BLEEDOUT_TIME
	velocity = Vector2.ZERO
	reloading = false
	medkit_using = false
	EventBus.player_downed.emit()
	AudioManager.play_sfx(&"downed")
	if level:
		level.on_player_downed()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_downed = false
	hp = 0
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	sprite.play("die")
	EventBus.player_died.emit()
	AudioManager.play_sfx(&"player_die")
	if level:
		level.on_player_died()


func revive(healer: Node) -> void:
	if not is_downed:
		return
	is_downed = false
	bleedout = BLEEDOUT_TIME
	iframes = 2.0
	if downs >= 2:
		black_white = true
		max_hp = 1
		hp = 1
	else:
		black_white = false
		max_hp = character.max_hp
		hp = maxi(1, int(max_hp * 0.35))
	temp_hp = 30
	EventBus.player_rescued.emit()
	EventBus.health_changed.emit(hp, temp_hp, max_hp)
	AudioManager.play_sfx(&"revive")
	if level:
		level.add_rescue(healer)


func heal(amount: int) -> void:
	if is_dead:
		return
	if black_white:
		hp = 1
	else:
		hp = mini(max_hp, hp + amount)
	EventBus.health_changed.emit(hp, temp_hp, max_hp)


func heal_full() -> void:
	is_dead = false
	is_downed = false
	downs = 0
	black_white = false
	max_hp = character.max_hp
	hp = max_hp
	temp_hp = 0
	bleedout = BLEEDOUT_TIME
	iframes = 2.0
	collision_layer = 2
	collision_mask = 89
	sprite.play("idle")
	EventBus.health_changed.emit(hp, temp_hp, max_hp)


func respawn_at(pos: Vector2) -> void:
	global_position = pos
	heal_full()
	velocity = Vector2.ZERO
	reloading = false
	weapon_cooldown = 0.0
	EventBus.interact_prompt.emit("")


func apply_bile(duration: float) -> void:
	bile_timer = duration
	EventBus.bile_splashed.emit(4.0)
	AudioManager.play_sfx(&"bile_splash")
	if level:
		level.on_player_biled()


func apply_burn(dps: float, duration: float) -> void:
	burn_dps = dps
	burn_timer = maxf(burn_timer, duration)


func enter_control(kind: StringName, source: Node) -> void:
	if control_immune > 0.0 or is_dead or is_downed:
		return
	is_controlled = true
	control_kind = kind
	controller = source
	velocity = Vector2.ZERO
	reloading = false
	medkit_using = false
	AudioManager.play_sfx(&"grabbed")


func release_control() -> void:
	is_controlled = false
	control_kind = &""
	controller = null
	control_immune = 3.0
	iframes = maxf(iframes, 0.5)
	EventBus.notify.emit("挣脱控制")


func add_medkit(amount: int = 1) -> void:
	medkits += amount


func add_pills(amount: int = 1) -> void:
	pills += amount


func add_throwable(kind: String, amount: int = 1) -> void:
	throwables[kind] = int(throwables.get(kind, 0)) + amount


func add_ammo(amount: int = 9999) -> void:
	for id in weapon_slots:
		var data := GameManager.get_weapon(id)
		if data == null or data.category == &"melee":
			continue
		var state: Dictionary = ammo.get(id, {"mag": 0, "reserve": 0})
		if int(state["reserve"]) >= 0:
			state["reserve"] = mini(data.reserve_ammo, int(state["reserve"]) + amount)
			ammo[id] = state
	var weapon := _current_weapon()
	if weapon:
		var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
		EventBus.ammo_changed.emit(int(state.get("mag", 0)), int(state.get("reserve", 0)))


func give_weapon(id: StringName) -> void:
	var data := GameManager.get_weapon(id)
	if data == null:
		return
	if data.category == &"primary":
		weapon_slots[0] = id
		if data.category == &"primary" and data.fire_mode != &"melee":
			ammo[id] = {"mag": data.mag_size, "reserve": data.reserve_ammo}
		slot_index = 0
	elif data.category == &"melee":
		weapon_slots[2] = id
		slot_index = 2
	_update_weapon_visual()
	EventBus.notify.emit("获得 " + data.display_name)
	EventBus.weapon_changed.emit(data.id, data.display_name)


func _emit_all_state() -> void:
	EventBus.health_changed.emit(hp, temp_hp, max_hp)
	var weapon := _current_weapon()
	if weapon:
		EventBus.weapon_changed.emit(weapon.id, weapon.display_name)
		var state: Dictionary = ammo.get(weapon.id, {"mag": 0, "reserve": 0})
		EventBus.ammo_changed.emit(int(state.get("mag", 0)), int(state.get("reserve", 0)))
	EventBus.skill_state_changed.emit(1.0, false)
	EventBus.interact_prompt.emit("")
