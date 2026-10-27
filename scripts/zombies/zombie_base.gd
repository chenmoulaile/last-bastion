class_name ZombieBase
extends CharacterBody2D
## Shared infected body: health, hitboxes, stagger, knockback, burning,
## separation, death and the common-infected state machine. Specials override
## _ai_tick() and death effects.

signal died(kind: StringName, pos: Vector2, source: StringName)

const GRAVITY := 1500.0

var data: ZombieData
var level: Node = null
var target: Node2D = null
var health: int = 30
var max_health: int = 30
var facing: int = -1
var dead: bool = false
var alerted: bool = false
var spawn_time: float = 0.0
var last_source: StringName = &"player"
var last_damage_type: StringName = &"bullet"

var stagger_timer: float = 0.0
var attack_cooldown: float = 0.0
var jump_cd: float = 0.0
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var slow_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var flash_timer: float = 0.0
var scream_cd: float = 0.0
var wander_timer: float = 0.0
var wander_dir: int = -1
var voice_timer: float = 3.0
var separation_timer: float = 0.0
var state_name: String = "idle"
var pinning: bool = false
var _retarget_timer: float = 0.0

var sprite: AnimatedSprite2D
var collision: CollisionShape2D
var _base_tint: Color = Color.WHITE
var _visual_prefix: String = ""
var _outline: Sprite2D = null
var _reveal_timer: float = 0.0


func _ready() -> void:
	add_to_group("zombies")
	if data == null:
		data = GameManager.get_zombie(&"common")
	if data == null:
		data = GameManager.get_zombie(&"common")
	_build_body()
	health = data.max_hp
	max_health = data.max_hp
	if data.id == &"tank":
		var diff := GameManager.current_difficulty
		if diff == &"HARD":
			max_health = 4000
		elif diff == &"EXPERT":
			max_health = 5000
		health = max_health
	spawn_time = Time.get_ticks_msec() / 1000.0
	attack_cooldown = randf_range(0.2, 0.8)
	wander_timer = randf_range(1.0, 4.0)
	wander_dir = [-1, 1].pick_random()
	voice_timer = randf_range(2.0, 6.0)
	_base_tint = data.tint
	if data.sprite_prefix.begins_with("common"):
		_visual_prefix = ["common_a", "common_b", "common_c", "common_d"].pick_random()
	else:
		_visual_prefix = data.sprite_prefix
	sprite.sprite_frames = SpriteLibrary.zombie_frames(_visual_prefix, data.sprite_size)
	sprite.play("idle")
	if data.is_special:
		collision_layer = 16
		add_to_group("special_infected")
	else:
		collision_layer = 8
	collision_mask = 1 | 2 | 4 | 64
	floor_snap_length = 8.0


func _build_body() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.position = Vector2(0, -data.sprite_size.y * 0.5)
	sprite.centered = true
	sprite.z_index = 3 if not data.is_special else 4
	add_child(sprite)
	collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = data.collision_size
	collision.shape = shape
	collision.position = Vector2(0, -data.collision_size.y * 0.5)
	add_child(collision)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or dead:
		return
	spawn_time += 0.0
	stagger_timer = maxf(0.0, stagger_timer - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	jump_cd = maxf(0.0, jump_cd - delta)
	scream_cd = maxf(0.0, scream_cd - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	voice_timer -= delta
	slow_timer = maxf(0.0, slow_timer - delta)
	if flash_timer <= 0.0 and sprite:
		sprite.modulate = _base_tint
	if burn_timer > 0.0:
		burn_timer -= delta
		_take_raw_damage(burn_dps * delta, &"fire", &"fire", false)
		if dead:
			return
	if knockback_velocity.length() > 1.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		velocity += knockback_velocity * delta * 8.0
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		if velocity.y > 750.0:
			velocity.y = 750.0
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 and not pinning:
		_retarget_timer = randf_range(1.4, 2.4)
		_acquire_target()
	if target == null or not is_instance_valid(target):
		target = level.get_player() if level else null
	if stagger_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
		if sprite.animation != "hurt":
			sprite.play("hurt")
		move_and_slide()
		return
	_ai_tick(delta)
	_apply_separation(delta)
	move_and_slide()
	if global_position.y > 470.0:
		_despawn_fall()
	if voice_timer <= 0.0:
		voice_timer = randf_range(5.0, 11.0)
		if randf() < 0.35:
			AudioManager.play_sfx_2d(data.voice_id, global_position, 800.0, -12.0)
	_tick_outline(delta)


# ------------------------------------------------------------- perception ----
## 穿墙轮廓：露西亚的「街头直觉」把感染者标记 3 秒，轮廓画在所有墙体之上。
func reveal_through_walls(duration: float) -> void:
	_reveal_timer = maxf(_reveal_timer, duration)
	if _outline == null:
		_build_outline()


func _build_outline() -> void:
	_outline = Sprite2D.new()
	_outline.name = "Outline"
	_outline.z_index = 60
	_outline.centered = true
	_outline.modulate = Color(1.0, 0.36, 0.30, 0.55)
	_outline.scale = Vector2(1.14, 1.14)
	add_child(_outline)


func _tick_outline(delta: float) -> void:
	if _reveal_timer <= 0.0:
		if _outline != null and _outline.visible:
			_outline.visible = false
		return
	_reveal_timer -= delta
	if _outline == null:
		return
	_outline.visible = true
	if sprite != null and sprite.sprite_frames != null \
			and sprite.sprite_frames.has_animation(sprite.animation):
		_outline.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_outline.flip_h = sprite.flip_h if sprite != null else false
	_outline.position = sprite.position if sprite != null else Vector2.ZERO
	_outline.modulate.a = 0.40 + 0.18 * sin(Time.get_ticks_msec() * 0.012)


## Player visibility for this infected: 0 = cannot be perceived at all.
func _target_visibility(target_node: Node2D) -> float:
	if target_node == null or not is_instance_valid(target_node):
		return 0.0
	if EnemyPerception.is_ignored(target_node):
		return 0.0
	var value: Variant = target_node.get("visibility")
	if value == null:
		return 1.0
	return clampf(float(value), 0.0, 1.0)


func _ai_tick(delta: float) -> void:
	# Common infected state machine: wander -> alert -> chase -> attack.
	if target == null:
		_wander(delta)
		return
	var to_target := target.global_position - global_position
	var dist_x := absf(to_target.x)
	var dist_y := absf(to_target.y)
	if not alerted:
		var sight := data.sight_range * maxf(0.15, _target_visibility(target))
		if dist_x < sight and dist_y < 120.0:
			if _can_see_target():
				_alert()
	if not alerted:
		_wander(delta)
		return
	if dist_x < 26.0 and dist_y < 40.0:
		state_name = "attack"
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if attack_cooldown <= 0.0:
			_attack_target()
		_play_anim("attack")
		return
	state_name = "chase"
	facing = 1 if to_target.x > 0.0 else -1
	var speed := data.walk_speed_max
	if randf() < 0.15:
		speed = 220.0
	if slow_timer > 0.0:
		speed *= 0.7
	velocity.x = move_toward(velocity.x, speed * float(facing), 900.0 * delta)
	_try_jump_for_target(to_target)
	_try_attack_door()
	_play_anim("run")
	if scream_cd <= 0.0 and randf() < 0.005:
		_scream()


func _wander(delta: float) -> void:
	state_name = "idle"
	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = randf_range(2.5, 6.5)
		wander_dir = [-1, 1].pick_random()
		velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
		if randf() < 0.4:
			_play_anim("idle")
			return
	velocity.x = move_toward(velocity.x, wander_dir * data.walk_speed_min * 0.45, 400.0 * delta)
	facing = wander_dir
	_play_anim("run" if absf(velocity.x) > 8.0 else "idle")
	if level and level.get_ground_y(global_position.x + float(wander_dir) * 28.0) < 0.0:
		wander_dir *= -1
		velocity.x = 0.0


func _try_jump_for_target(to_target: Vector2) -> void:
	if not is_on_floor() or jump_cd > 0.0:
		return
	var ground_ahead: float = level.get_ground_y(global_position.x + float(facing) * 26.0) if level else 0.0
	var needs_jump := to_target.y < -38.0
	if ground_ahead < 0.0 and absf(to_target.x) < 260.0:
		needs_jump = true
	if is_on_wall() and absf(to_target.x) < 160.0:
		needs_jump = true
	if needs_jump:
		velocity.y = -500.0
		jump_cd = 1.2


func _try_attack_door() -> void:
	if not is_on_floor():
		return
	var from := global_position + Vector2(0, -18)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(facing * 26.0, 0), 64, [get_rid()])
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider: Object = result["collider"]
		if collider.has_method("zombie_scratch"):
			collider.zombie_scratch(self)
			velocity.x = 0.0
			_play_anim("attack")


func _attack_target() -> void:
	attack_cooldown = data.attack_interval
	_play_anim("attack")
	if target != null and target.has_method("take_damage"):
		var dir := (target.global_position - global_position).normalized()
		target.take_damage(data.attack_damage, dir, &"zombie", &"melee")
	AudioManager.play_sfx_2d(&"zombie_attack", global_position, 500.0, -8.0)


func _can_see_target() -> bool:
	if target == null:
		return false
	if _target_visibility(target) <= 0.02:
		return false
	var from := global_position + Vector2(0, -20)
	var to := target.global_position + Vector2(0, -18)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	return result.is_empty()


func _alert() -> void:
	alerted = true
	_scream()
	if level and not EnemyPerception.is_noise_suppressed(global_position):
		level.alert_commons_near(global_position, 80.0)


func _scream() -> void:
	if scream_cd > 0.0:
		return
	scream_cd = 4.0
	AudioManager.play_sfx_2d(&"zombie_scream", global_position, 900.0, -4.0)
	EventBus.zombie_scream.emit(global_position, 80.0)
	if level:
		level.alert_commons_near(global_position, 80.0)


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if dead:
		return
	if data.fire_immune and damage_type == &"fire":
		return
	if data.front_immune and damage_type == &"bullet" and from_dir.length() > 0.01:
		if from_dir.normalized().dot(Vector2(float(facing), 0.0)) > 0.15:
			Fx.spark(level.fx_layer if level else get_parent(), global_position + Vector2(0, -16))
			AudioManager.play_sfx_2d(&"ricochet", global_position, 500.0)
			alerted = true
			return
	var final_amount := float(amount)
	if is_head and data.head_hittable and not data.head_immune:
		final_amount *= 2.0
	_take_raw_damage(final_amount, source, damage_type, is_head)
	flash_timer = 0.08
	if sprite:
		sprite.modulate = Color(2.2, 2.2, 2.2, 1.0)
	if not data.is_boss:
		var force := 0.0
		if damage_type == &"melee":
			force = 140.0
		elif damage_type == &"shotgun":
			force = 110.0
		elif is_head:
			force = 50.0
		if force > 0.0 and from_dir.length() > 0.01:
			apply_knockback(from_dir.normalized() * force)
		if damage_type == &"melee" or damage_type == &"shotgun":
			apply_stagger(0.8)
		elif not data.is_special:
			apply_stagger(0.25)
	if not dead:
		alerted = true
		if source == &"player" and level and not EnemyPerception.is_noise_suppressed(global_position):
			level.alert_commons_near(global_position, 80.0)


func _take_raw_damage(amount: float, source: StringName, damage_type: StringName, is_head: bool) -> void:
	if dead:
		return
	last_source = source
	last_damage_type = damage_type
	health -= int(ceil(amount))
	if health <= 0:
		_die(source, is_head)


func apply_stagger(duration: float) -> void:
	if data.is_boss:
		return
	stagger_timer = maxf(stagger_timer, duration)


func apply_knockback(force: Vector2) -> void:
	if data.is_boss:
		return
	knockback_velocity += force


func is_headshot_point(point: Vector2) -> bool:
	if not data.head_hittable or data.head_immune:
		return false
	return point.y < global_position.y - data.collision_size.y * 0.62


func _die(source: StringName, is_head: bool = false) -> void:
	if dead:
		return
	release_controlled_target()
	dead = true
	health = 0
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	if sprite:
		sprite.play("die")
		sprite.modulate = _base_tint
	remove_from_group("zombies")
	Fx.blood(level.fx_layer if level else get_parent(), global_position + Vector2(0, -14), Vector2.UP, 1.4)
	Fx.blood_decal(level.fx_layer if level else get_parent(), global_position + Vector2(0, -2))
	AudioManager.play_sfx_2d(&"zombie_die", global_position, 700.0)
	_on_death_effect()
	died.emit(data.id, global_position, source)
	if level:
		level.on_zombie_died(self, source, is_head)
	await get_tree().create_timer(2.6, true, false, true).timeout
	if is_instance_valid(self):
		queue_free()


func _on_death_effect() -> void:
	if data.id == &"clown" and level:
		level.spawn_horde_at(global_position, 15, true)
	elif data.id == &"scavenger" and level:
		level.drop_scavenger_loot(global_position)
	elif data.id == &"mud":
		EventBus.bile_splashed.emit(2.5)
		EventBus.notify.emit("泥浆糊住了视野")


func _despawn_fall() -> void:
	dead = true
	remove_from_group("zombies")
	if level:
		level.on_zombie_fell(self)
	queue_free()


func _apply_separation(delta: float) -> void:
	separation_timer -= delta
	if separation_timer > 0.0 or level == null:
		return
	separation_timer = 0.12
	var nearby: Array = level.get_zombies_near(global_position, 18.0)
	var push := 0.0
	for other in nearby:
		if other == self:
			continue
		var dx: float = global_position.x - other.global_position.x
		if absf(dx) < 0.1:
			dx = randf_range(-1.0, 1.0)
		push += signf(dx) * 6.0
	if push != 0.0:
		velocity.x += clampf(push, -30.0, 30.0)


func _play_anim(anim: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var resolved := anim
	if not sprite.sprite_frames.has_animation(resolved):
		if sprite.sprite_frames.has_animation("run"):
			resolved = "run"
		elif sprite.sprite_frames.has_animation("idle"):
			resolved = "idle"
		else:
			return
	if sprite.animation != resolved:
		sprite.play(resolved)


# ------------------------------------------------------------- shared AI ----
func _acquire_target() -> void:
	if level == null:
		return
	var player: Node2D = level.get_player()
	var best: Node2D = null
	var best_score := INF
	if player != null and is_instance_valid(player):
		if not bool(player.get("is_dead")) and _target_visibility(player) > 0.05:
			best = player
			# The player is the protagonist: allies must be clearly closer to
			# pull aggro away, which keeps squads from feeling invisible.
			# Low visibility also makes the player a less attractive target.
			var vis := maxf(0.25, _target_visibility(player))
			best_score = global_position.distance_to(player.global_position) * 0.72 / vis
	var allies: Array = level.get_allies()
	for ally in allies:
		if ally == null or not is_instance_valid(ally):
			continue
		if bool(ally.get("is_dead")):
			continue
		var score := global_position.distance_to(ally.global_position)
		if score < best_score:
			best_score = score
			best = ally
	if best != null:
		target = best


func face_toward_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	facing = 1 if target.global_position.x > global_position.x else -1
	if sprite:
		sprite.flip_h = facing < 0


func distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return 9999.0
	return global_position.distance_to(target.global_position)


func distance_x_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return 9999.0
	return absf(target.global_position.x - global_position.x)


func has_line_of_sight_to_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var from := global_position + Vector2(0, -18)
	var to := target.global_position + Vector2(0, -18)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func chase_target(delta: float, speed_mult: float = 1.0, anim: String = "run") -> void:
	if target == null or not is_instance_valid(target):
		return
	face_toward_target()
	var speed := data.walk_speed_max * speed_mult
	if slow_timer > 0.0:
		speed *= 0.7
	velocity.x = move_toward(velocity.x, speed * float(facing), 900.0 * delta)
	_try_jump_for_target(target.global_position - global_position)
	_try_attack_door()
	_play_anim(anim)


func stop_horizontal(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)


func jump_toward_target(power: float = 500.0) -> void:
	if is_on_floor() and jump_cd <= 0.0:
		velocity.y = -power
		jump_cd = 1.2


func target_is_controlled_by_me() -> bool:
	return target != null and is_instance_valid(target) \
		and bool(target.get("is_controlled")) and target.get("controller") == self


func release_controlled_target() -> void:
	if target_is_controlled_by_me():
		target.release_control()
	pinning = false


func get_target() -> Node2D:
	return target


func enter_control(control_target: Node2D) -> void:
	target = control_target


func release_control() -> void:
	pass


func get_data() -> ZombieData:
	return data


func on_melee_interrupt() -> bool:
	return false


func is_pounce_active() -> bool:
	return false


func _set_facing_from_target() -> void:
	if target:
		facing = 1 if target.global_position.x > global_position.x else -1
	if sprite:
		sprite.flip_h = facing < 0
