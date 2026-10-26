class_name AllyAgent
extends CharacterBody2D
## Squad member / command-mode soldier. A small behaviour tree selects between
## rescuing a downed teammate, engaging infected, and obeying the current order.
## Balance values come from CharacterData and WeaponData resources.

const GRAVITY := 1500.0
const JUMP_VELOCITY := -540.0
const BLEEDOUT_TIME := 20.0

var data: CharacterData
var level: Node = null
var visual_id: String = "assault"
var accent: Color = Color.WHITE
var ally_index: int = 0
var is_soldier: bool = false

var max_hp: int = 100
var hp: int = 100
var downs: int = 0
var is_downed: bool = false
var is_dead: bool = false
var is_controlled: bool = false
var is_pinned: bool = false
var control_kind: StringName = &""
var controller: Node = null
var control_immune: float = 0.0
var bleedout: float = BLEEDOUT_TIME

var facing: int = 1
var aim_dir: Vector2 = Vector2.RIGHT
var move_speed: float = 210.0
var command: StringName = &"follow"
var formation: StringName = &"wedge"
var hold_position: Vector2 = Vector2.ZERO
var focus_point: Vector2 = Vector2.ZERO
var state_text: String = "跟随"

var weapon: WeaponData
var fire_cooldown: float = 0.0
var shoot_anim_timer: float = 0.0
var hurt_anim_timer: float = 0.0
var melee_timer: float = 0.0
var scan_timer: float = 0.0
var enemy: Node2D = null
var revive_target: Node = null
var revive_progress: float = 0.0
var heal_cooldown: float = 0.0
var brace_timer: float = 0.0
var grenade_cd: float = 0.0
var grenade_count: int = 0
var stuck_timer: float = 0.0
var inspire_timer: float = 0.0
var iframes: float = 0.0
var jump_cd: float = 0.0
var bile_timer: float = 0.0
var _bt: BT.BTNode = null
var _last_ground_y: float = 0.0
var _delta: float = 0.016

var sprite: AnimatedSprite2D
var collision: CollisionShape2D
var weapon_sprite: Sprite2D


func _ready() -> void:
	if data == null:
		data = GameManager.get_character(&"rifleman")
	if data == null:
		data = GameManager.get_character(&"assault")
	visual_id = data.portrait
	accent = data.accent
	max_hp = data.max_hp
	hp = max_hp
	move_speed = data.speed
	weapon = GameManager.get_weapon(data.primary_weapon)
	if weapon == null:
		weapon = GameManager.get_weapon(&"m9")
	if data.soldier_role == &"demolisher":
		grenade_count = 2
	add_to_group("allies")
	collision_layer = 4
	collision_mask = 1 | 8 | 16 | 64
	floor_snap_length = 8.0
	_build_body()
	_build_tree()
	hold_position = global_position
	focus_point = global_position + Vector2(200, 0)
	_last_ground_y = global_position.y
	EventBus.command_issued.connect(_on_command_issued)
	EventBus.formation_changed.connect(_on_formation_changed)


func _build_body() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteLibrary.character_frames(visual_id)
	sprite.position = Vector2(0, -16)
	sprite.z_index = 4
	add_child(sprite)
	sprite.play("idle")
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 28)
	collision.shape = shape
	collision.position = Vector2(0, -14)
	add_child(collision)
	weapon_sprite = Sprite2D.new()
	weapon_sprite.texture = SpriteLibrary.weapon_texture(weapon.sprite if weapon else "m9")
	weapon_sprite.position = Vector2(9, -18)
	weapon_sprite.z_index = 5
	add_child(weapon_sprite)


func _build_tree() -> void:
	_bt = BT.selector([
		BT.sequence([
			BT.cond(func(a: AllyAgent) -> bool: return a._should_rescue()),
			BT.action(func(_a: Node, d: float) -> bool: return _bt_rescue(d)),
		]),
		BT.sequence([
			BT.cond(func(a: AllyAgent) -> bool: return a._has_enemy()),
			BT.action(func(_a: Node, d: float) -> bool: return _bt_fight(d)),
		]),
		BT.action(func(_a: Node, d: float) -> bool: return _bt_move(d)),
	])


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or is_dead:
		return
	_delta = delta
	_tick_timers(delta)
	if is_controlled:
		velocity = Vector2.ZERO
		if sprite.animation != "hurt":
			sprite.play("hurt")
		return
	if is_downed:
		_tick_downed(delta)
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if velocity.y > 720.0:
			velocity.y = 720.0
	_bt.tick(self, delta)
	move_and_slide()
	_update_animation()
	_update_weapon_visual()
	_catch_up_if_lost(delta)
	if global_position.y > 460.0:
		global_position = Vector2(maxf(40.0, global_position.x - 100.0), 260.0)
		take_damage(20, Vector2.UP, &"zombie", &"fall")


func _tick_timers(delta: float) -> void:
	iframes = maxf(0.0, iframes - delta)
	control_immune = maxf(0.0, control_immune - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	shoot_anim_timer = maxf(0.0, shoot_anim_timer - delta)
	hurt_anim_timer = maxf(0.0, hurt_anim_timer - delta)
	melee_timer = maxf(0.0, melee_timer - delta)
	scan_timer = maxf(0.0, scan_timer - delta)
	heal_cooldown = maxf(0.0, heal_cooldown - delta)
	brace_timer = 0.0 if absf(velocity.x) > 10.0 else brace_timer
	grenade_cd = maxf(0.0, grenade_cd - delta)
	inspire_timer = maxf(0.0, inspire_timer - delta)
	jump_cd = maxf(0.0, jump_cd - delta)
	bile_timer = maxf(0.0, bile_timer - delta)
	if bile_timer > 0.0:
		sprite.modulate = Color(0.8, 1.15, 0.7, 1.0)
	else:
		sprite.modulate = Color.WHITE


# --------------------------------------------------------------- behaviour ----
func _should_rescue() -> bool:
	if is_soldier:
		revive_target = level.find_downed_ally_near(global_position, 220.0, self, true) if level else null
		if revive_target == null and level:
			revive_target = level.find_pinned_ally_near(global_position, 220.0, self)
		if revive_target == null:
			return false
		# Do not run into a horde to revive; fight first.
		return level.get_zombies_near(revive_target.global_position, 150.0).is_empty()
	revive_target = level.find_downed_ally_near(global_position, 170.0, self, true) if level else null
	if revive_target == null and level:
		revive_target = level.find_pinned_ally_near(global_position, 170.0, self)
	if revive_target == null:
		return false
	return level.get_zombies_near(revive_target.global_position, 130.0).is_empty()


func _has_enemy() -> bool:
	if enemy != null and is_instance_valid(enemy) and not bool(enemy.get("dead")):
		if global_position.distance_to(enemy.global_position) < 560.0:
			return true
		enemy = null
	if scan_timer > 0.0:
		return enemy != null
	scan_timer = 0.2
	enemy = _find_enemy()
	return enemy != null


func _find_enemy() -> Node2D:
	if level == null:
		return null
	# Free a controlled teammate first.
	var player: Node = level.get_player()
	if player and is_instance_valid(player) and bool(player.get("is_controlled")):
		var controller: Node = player.get("controller")
		if controller and is_instance_valid(controller) and controller.has_method("apply_damage"):
			return controller
	for mate in level.get_allies():
		if mate == self or mate == null or not is_instance_valid(mate):
			continue
		if bool(mate.get("is_controlled")):
			var c: Node = mate.get("controller")
			if c and is_instance_valid(c) and c.has_method("apply_damage"):
				return c
	var best: Node2D = null
	var best_dist := 560.0
	for z in level.get_zombies_near(global_position, 560.0):
		if z == null or not is_instance_valid(z) or bool(z.get("dead")):
			continue
		var d := global_position.distance_to(z.global_position)
		if d < best_dist and _line_of_sight(z):
			best = z
			best_dist = d
	return best


func _line_of_sight(z: Node2D) -> bool:
	var from := global_position + Vector2(0, -20)
	var to := z.global_position + Vector2(0, -18)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _bt_rescue(delta: float) -> bool:
	if revive_target == null or not is_instance_valid(revive_target):
		return false
	var target_pos: Vector2 = revive_target.global_position
	var dist := absf(target_pos.x - global_position.x)
	facing = 1 if target_pos.x > global_position.x else -1
	if dist > 30.0:
		_move_toward_x(target_pos.x, 0.95)
		state_text = "救援"
		_play_anim("run")
		return true
	stop_x()
	revive_progress += delta
	state_text = "救援中"
	_play_anim("crouch")
	if revive_progress >= 2.2:
		revive_progress = 0.0
		if revive_target.has_method("revive"):
			revive_target.revive(self)
		if level:
			level.add_rescue(self)
		AudioManager.play_sfx(&"revive")
		revive_target = null
	return true


func _bt_fight(delta: float) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var to_enemy := enemy.global_position - global_position
	facing = 1 if to_enemy.x > 0.0 else -1
	aim_dir = to_enemy.normalized()
	var dist := to_enemy.length()
	if dist < 44.0 and melee_timer <= 0.0:
		melee_timer = 1.0
		if enemy.has_method("apply_damage"):
			enemy.apply_damage(9, -aim_dir, false, &"friendly", &"melee")
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(aim_dir * 90.0)
		if enemy.has_method("apply_stagger"):
			enemy.apply_stagger(0.5)
		shoot_anim_timer = 0.15
		AudioManager.play_sfx_2d(&"melee_hit", global_position, 500.0, -14.0)
	if dist > 230.0:
		_move_toward_x(enemy.global_position.x, 0.9)
	elif dist < 120.0:
		_move_toward_x(enemy.global_position.x - float(facing) * 130.0, 0.7)
	else:
		stop_x()
	# Gunner must brace for 0.8s before the LMG can fire.
	var can_fire := true
	if data.soldier_role == &"gunner":
		if absf(velocity.x) < 10.0:
			brace_timer = minf(0.8, brace_timer + delta)
		else:
			brace_timer = 0.0
		can_fire = brace_timer >= 0.8
	elif data.soldier_role == &"demolisher":
		_try_grenade()
	if _line_of_sight(enemy) and fire_cooldown <= 0.0 and can_fire:
		_fire(enemy)
	state_text = "架枪" if data.soldier_role == &"gunner" and not can_fire else "交战"
	if absf(velocity.x) > 10.0 and shoot_anim_timer <= 0.0:
		_play_anim("run")
	return true


func _bt_move(delta: float) -> bool:
	if level == null:
		return true
	var player: Node = level.get_player()
	if player == null or not is_instance_valid(player):
		return true
	var ppos: Vector2 = player.global_position
	var dir := 1.0 if int(player.get("facing")) >= 0 else -1.0
	var slot := _formation_offset(dir)
	var desired := ppos + slot
	match command:
		&"advance":
			desired = ppos + slot + Vector2(dir * 150.0, 0)
			state_text = "推进"
		&"hold":
			desired = hold_position
			state_text = "防守"
		&"focus":
			desired = focus_point
			if absf(desired.x - global_position.x) < 260.0:
				desired = global_position
			state_text = "集火"
		_:
			state_text = "跟随"
	if absf(desired.x - global_position.x) > 28.0:
		_move_toward_x(desired.x, 1.0)
		_play_anim("run")
	else:
		stop_x()
		_play_anim("idle")
	# Face the player's aim direction when idle.
	if enemy == null:
		facing = 1 if ppos.x > global_position.x else -1
	# Medic support pulse.
	if heal_cooldown <= 0.0 and (data.soldier_role == &"medic" or data.skill_id == &"field_medic"):
		_try_heal()
	return true


func _formation_offset(dir: float) -> Vector2:
	# Side-view formations differ in spacing and stagger. Allies stay on the
	# ground; the slot only changes the X target so pathing stays robust.
	match formation:
		&"line":
			return Vector2(-dir * (44.0 + float(ally_index) * 26.0), 0.0)
		&"column":
			return Vector2(-dir * (38.0 + float(ally_index / 2) * 26.0), 0.0)
		_:
			var row := float(ally_index / 2)
			var stagger := 8.0 if ally_index % 2 == 0 else -8.0
			return Vector2(-dir * (34.0 + row * 22.0) + stagger, 0.0)


func _move_toward_x(target_x: float, speed_mult: float) -> void:
	var dx := target_x - global_position.x
	if absf(dx) < 4.0:
		stop_x()
		return
	var dir := signf(dx)
	var speed := move_speed * speed_mult
	if inspire_timer > 0.0:
		speed *= 1.15
	velocity.x = move_toward(velocity.x, dir * speed, 1500.0 * _delta)
	facing = 1 if dir > 0.0 else -1
	_try_jump_gap(dir)


func stop_x() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 1700.0 * _delta)


func _try_jump_gap(dir: float) -> void:
	if not is_on_floor() or jump_cd > 0.0 or level == null:
		return
	var ahead_x := global_position.x + dir * 24.0
	var ground: float = level.get_ground_y(ahead_x)
	if ground < 0.0:
		velocity.y = JUMP_VELOCITY
		jump_cd = 1.1
		return
	if ground < global_position.y - 34.0:
		velocity.y = JUMP_VELOCITY
		jump_cd = 1.1


func _catch_up_if_lost(delta: float) -> void:
	if level == null:
		return
	var player: Node = level.get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > 760.0 and command != &"hold":
		var ground: float = level.get_ground_y(player.global_position.x - 60.0)
		global_position = Vector2(player.global_position.x - 60.0, ground if ground > 0.0 else player.global_position.y)
		velocity = Vector2.ZERO
		return
	if absf(velocity.x) < 5.0 and dist > 220.0:
		stuck_timer += delta
		if stuck_timer > 3.5:
			stuck_timer = 0.0
			velocity.y = JUMP_VELOCITY
			jump_cd = 0.8
	else:
		stuck_timer = 0.0


func _fire(zombie: Node2D) -> void:
	if weapon == null:
		return
	var rpm := maxf(120.0, weapon.rpm)
	fire_cooldown = maxf(0.16, 60.0 / rpm * 1.55)
	var origin := global_position + Vector2(facing * 10.0, -18.0)
	var target := zombie.global_position + Vector2(0, -16)
	var spread := deg_to_rad(randf_range(-2.6, 2.6))
	var dir := (target - origin).normalized().rotated(spread)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * 520.0, 1 | 8 | 16, [get_rid()])
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	var end := origin + dir * 520.0
	if not result.is_empty():
		end = result["position"]
		var collider: Object = result["collider"]
		if collider.has_method("apply_damage"):
			var damage := int(round(float(weapon.damage) * 0.62))
			collider.apply_damage(damage, -dir, false, &"friendly", &"bullet")
			Fx.blood(level.fx_layer, end, dir, 0.8)
		else:
			Fx.spark(level.fx_layer, end)
	Fx.tracer(level.fx_layer, origin, end, Color(0.85, 0.9, 0.65, 0.7))
	Fx.muzzle(level.fx_layer, origin, dir.angle())
	AudioManager.play_sfx_2d(StringName(weapon.id), origin, 600.0, -17.0)
	shoot_anim_timer = 0.14
	aim_dir = dir


func _try_grenade() -> void:
	if grenade_count <= 0 or grenade_cd > 0.0 or level == null or enemy == null:
		return
	if not is_instance_valid(enemy) or bool(enemy.get("dead")):
		return
	var cluster: Array = level.get_zombies_near(enemy.global_position, 110.0)
	if cluster.size() < 3:
		return
	grenade_count -= 1
	grenade_cd = 60.0
	var target := Vector2.ZERO
	for z in cluster:
		target += z.global_position
	target /= float(cluster.size())
	var marker := Sprite2D.new()
	marker.texture = SpriteLibrary.prop_texture("pickup_grenade")
	marker.scale = Vector2(0.8, 0.8)
	marker.z_index = 18
	var parent: Node = level.fx_layer if level.fx_layer != null else level
	parent.add_child(marker)
	marker.global_position = global_position + Vector2(float(facing) * 12.0, -22.0)
	var start := marker.global_position
	var tween := marker.create_tween()
	tween.tween_method(_move_grenade.bind(marker, start, target), 0.0, 1.0, 0.55)
	tween.tween_callback(_detonate_grenade.bind(marker, target))
	state_text = "投雷"


func _move_grenade(t: float, marker: Sprite2D, start: Vector2, target: Vector2) -> void:
	if is_instance_valid(marker):
		marker.global_position = start.lerp(target, t) + Vector2(0, -sin(t * PI) * 42.0)


func _detonate_grenade(marker: Node, target: Vector2) -> void:
	if is_instance_valid(marker):
		marker.queue_free()
	if level == null or not is_instance_valid(level):
		return
	Fx.explosion(level.fx_layer, target, 1.15)
	AudioManager.play_sfx_2d(&"explosion", target, 900.0)
	for z in level.get_zombies_near(target, 92.0):
		if z != null and is_instance_valid(z) and z.has_method("apply_damage"):
			var dir: Vector2 = z.global_position - target
			if dir.length_squared() < 0.01:
				dir = Vector2.UP
			z.apply_damage(85, dir.normalized(), false, &"friendly", &"explosion")


func _try_heal() -> void:
	if level == null:
		return
	var best: Node = null
	var best_missing := 0
	var player: Node = level.get_player()
	if player and is_instance_valid(player) and not bool(player.get("is_dead")):
		var missing: int = int(player.get("max_hp")) - int(player.get("hp"))
		if missing > best_missing and player.global_position.distance_to(global_position) < 160.0:
			best = player
			best_missing = missing
	for mate in level.get_allies():
		if mate == self or mate == null or not is_instance_valid(mate) or bool(mate.get("is_dead")):
			continue
		var missing: int = int(mate.get("max_hp")) - int(mate.get("hp"))
		if missing > best_missing and mate.global_position.distance_to(global_position) < 150.0:
			best = mate
			best_missing = missing
	if best == null or best_missing < 24:
		return
	heal_cooldown = 9.0
	if best.has_method("heal"):
		best.heal(18)
	Fx.acid(level.fx_layer, best.global_position + Vector2(0, -14))
	AudioManager.play_sfx_2d(&"heal", best.global_position, 500.0, -8.0)


func _tick_downed(delta: float) -> void:
	bleedout -= delta
	var player: Node = level.get_player() if level else null
	if player and is_instance_valid(player):
		facing = 1 if player.global_position.x > global_position.x else -1
	velocity.x = move_toward(velocity.x, float(facing) * 18.0, 120.0 * delta)
	velocity.y += GRAVITY * delta
	move_and_slide()
	_play_anim("crouch")
	sprite.flip_h = facing < 0
	if bleedout <= 0.0:
		die()


func take_damage(amount: int, source_dir: Vector2 = Vector2.ZERO, source: StringName = &"zombie",
		damage_type: StringName = &"melee") -> void:
	if is_dead or iframes > 0.0 or GameManager.state != GameManager.State.PLAYING:
		return
	if is_downed:
		bleedout -= float(amount) * 0.35
		if bleedout <= 0.0:
			die()
		return
	var final_amount := float(amount) * GameManager.enemy_damage_mult()
	if source == &"friendly":
		final_amount *= 0.35
	var total := int(ceil(final_amount))
	hp -= total
	iframes = 0.35
	hurt_anim_timer = 0.22
	EventBus.teammate_status_changed.emit()
	if hp <= 0:
		_go_down()


func _go_down() -> void:
	if is_downed or is_dead:
		return
	downs += 1
	hp = 0
	if downs >= 3:
		die()
		return
	is_downed = true
	is_pinned = false
	bleedout = BLEEDOUT_TIME
	velocity = Vector2.ZERO
	state_text = "倒地"
	EventBus.ally_downed.emit(self)
	EventBus.teammate_status_changed.emit()
	AudioManager.play_sfx_2d(&"ally_downed", global_position, 700.0)
	if level:
		level.on_ally_downed(self)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_downed = false
	is_controlled = false
	hp = 0
	collision_layer = 0
	collision_mask = 0
	sprite.play("die")
	state_text = "阵亡"
	EventBus.ally_died.emit(self)
	EventBus.teammate_status_changed.emit()
	if level:
		level.on_ally_died(self)


func revive(healer: Node) -> void:
	if is_controlled:
		release_control()
		return
	if not is_downed:
		return
	is_downed = false
	bleedout = BLEEDOUT_TIME
	iframes = 1.5
	hp = maxi(1, int(max_hp * 0.4))
	state_text = "跟随"
	EventBus.ally_revived.emit(self)
	EventBus.teammate_status_changed.emit()
	AudioManager.play_sfx_2d(&"revive", global_position, 700.0)


func heal(amount: int) -> void:
	if is_dead or is_downed:
		return
	hp = mini(max_hp, hp + amount)
	EventBus.teammate_status_changed.emit()


func heal_full() -> void:
	is_dead = false
	is_downed = false
	downs = 0
	hp = max_hp
	bleedout = BLEEDOUT_TIME
	collision_layer = 4
	collision_mask = 1 | 8 | 16 | 64
	sprite.play("idle")
	EventBus.teammate_status_changed.emit()


func respawn_at(pos: Vector2) -> void:
	global_position = pos
	heal_full()
	velocity = Vector2.ZERO


func enter_control(kind: StringName, source: Node) -> void:
	if control_immune > 0.0 or is_dead or is_downed:
		return
	is_controlled = true
	is_pinned = true
	control_kind = kind
	controller = source
	velocity = Vector2.ZERO
	state_text = "被控制"
	EventBus.teammate_status_changed.emit()
	AudioManager.play_sfx_2d(&"grabbed", global_position, 600.0, -4.0)


func release_control() -> void:
	is_controlled = false
	is_pinned = false
	control_kind = &""
	controller = null
	control_immune = 3.0
	iframes = maxf(iframes, 0.5)
	state_text = "挣脱"
	EventBus.ally_unpinned.emit(self)
	EventBus.teammate_status_changed.emit()


func apply_bile(duration: float) -> void:
	bile_timer = duration
	EventBus.bile_splashed.emit(2.0)


func apply_burn(_dps: float, _duration: float) -> void:
	pass


func issue_command(cmd: StringName, point: Vector2 = Vector2.ZERO) -> void:
	command = cmd
	if cmd == &"hold":
		hold_position = global_position
	if cmd == &"focus":
		focus_point = point if point != Vector2.ZERO else global_position + Vector2(240, 0)
	if cmd == &"follow" or cmd == &"advance":
		revive_progress = 0.0
	EventBus.teammate_status_changed.emit()


func inspire(duration: float) -> void:
	inspire_timer = maxf(inspire_timer, duration)


func _on_command_issued(cmd: StringName) -> void:
	if is_dead:
		return
	if cmd == &"hold" and command == &"hold":
		hold_position = global_position
	command = cmd
	if cmd == &"focus":
		var player: Node = level.get_player() if level else null
		if player and is_instance_valid(player):
			var aim: Vector2 = player.get("aim_dir")
			focus_point = player.global_position + aim * 260.0
	state_text = {"follow": "跟随", "advance": "推进", "hold": "防守", "focus": "集火"}.get(String(cmd), "跟随")


func _on_formation_changed(value: StringName) -> void:
	formation = value


func _update_animation() -> void:
	var anim := "idle"
	if is_downed:
		anim = "crouch"
	elif not is_on_floor():
		anim = "jump"
	elif melee_timer > 0.6:
		anim = "melee"
	elif shoot_anim_timer > 0.0:
		anim = "shoot"
	elif hurt_anim_timer > 0.0:
		anim = "hurt"
	elif absf(velocity.x) > 10.0:
		anim = "run"
	_play_anim(anim)
	sprite.flip_h = facing < 0


func _update_weapon_visual() -> void:
	if weapon_sprite == null:
		return
	weapon_sprite.visible = not is_downed
	weapon_sprite.flip_h = facing < 0
	weapon_sprite.flip_v = absf(aim_dir.angle()) > PI * 0.5
	weapon_sprite.rotation = aim_dir.angle()
	weapon_sprite.position = Vector2(facing * 8.0, -18.0) + aim_dir * 4.0
	weapon_sprite.z_index = 5 if facing > 0 else 3


func _play_anim(anim: String) -> void:
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)


func get_status_text() -> String:
	if is_dead:
		return "阵亡"
	if is_downed:
		return "倒地"
	if is_controlled:
		return "被控制"
	return state_text


func get_health_ratio() -> float:
	return clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
