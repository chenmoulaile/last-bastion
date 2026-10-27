class_name FactionUnit
extends ZombieBase
## A human faction combatant: Horizon / Signal Bureau / Rust Gang / Remnants.
##
## Extends ZombieBase so it inherits hitboxes, stagger, knockback, burning,
## separation and the death pipeline; only targeting + shooting are replaced.
## Visuals reuse character sprite strips with a palette tint.

var faction_id: String = "horizon"
var unit_kind: String = "rust_enforcer"
var spec: Dictionary = {}
var provoked: bool = false
var jam_timer: float = 0.0

var _retarget: float = 0.0
var _shoot_cd: float = 0.0
var _target_node: Node2D = null
var _archive_target: Node2D = null
var _visual: String = "assault"
var _tint: Color = Color.WHITE


func _ready() -> void:
	spec = FactionRoster.spec(unit_kind)
	_visual = String(spec.get("visual", "assault"))
	_tint = spec.get("tint", Color.WHITE)
	data = _make_data()
	super()
	add_to_group("faction_units")
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8 | 16
	sprite.sprite_frames = SpriteLibrary.character_frames(_visual)
	sprite.modulate = _tint
	sprite.play("idle")
	_base_tint = _tint
	z_index = 4
	EventBus.faction_unit_spawned.emit(faction_id, unit_kind)


func _make_data() -> ZombieData:
	var unit := ZombieData.new()
	unit.id = StringName(unit_kind)
	unit.display_name = FactionRoster.display_name(unit_kind)
	unit.max_hp = int(spec.get("hp", 120))
	unit.walk_speed_min = float(spec.get("speed", 130)) * 0.7
	unit.walk_speed_max = float(spec.get("speed", 130))
	unit.attack_damage = int(spec.get("damage", 10))
	unit.attack_interval = float(spec.get("interval", 1.0))
	unit.score_value = int(spec.get("score", 400))
	unit.is_special = true # keeps horde counters from counting humans
	unit.sprite_prefix = "common_a"
	unit.sprite_size = Vector2i(28, 36)
	unit.collision_size = Vector2(14, 30)
	unit.sight_range = 420.0
	unit.attack_range = float(spec.get("range", 40.0))
	unit.tint = Color.WHITE
	unit.voice_id = &"zombie_growl"
	return unit


func is_neutral() -> bool:
	return bool(spec.get("neutral", false)) and not provoked


# -------------------------------------------------------------------- AI ----
func _ai_tick(delta: float) -> void:
	_retarget -= delta
	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	if _retarget <= 0.0:
		_retarget = randf_range(0.9, 1.6)
		_target_node = _pick_target()
	if bool(spec.get("jammer", false)):
		_tick_jammer(delta)
	if is_neutral():
		_wander(delta)
		return
	if bool(spec.get("burn_archives", false)) and _archive_target == null:
		_archive_target = _find_archive_target()
	if _archive_target != null and is_instance_valid(_archive_target):
		_move_to(_archive_target.global_position, delta)
		if global_position.distance_to(_archive_target.global_position) < 34.0:
			_burn_archive()
		return
	if _target_node == null or not is_instance_valid(_target_node):
		_wander(delta)
		return
	var distance := global_position.distance_to(_target_node.global_position)
	var range_px := float(spec.get("range", 40.0))
	if distance > range_px:
		_move_to(_target_node.global_position, delta)
	else:
		stop_horizontal(delta)
		face_toward(_target_node)
		if _shoot_cd <= 0.0:
			_attack(_target_node)
	_play_anim("run" if absf(velocity.x) > 8.0 else "idle")


func _move_to(target_pos: Vector2, delta: float) -> void:
	var dir := signf(target_pos.x - global_position.x)
	if dir == 0.0:
		dir = 1.0
	facing = int(dir)
	if sprite != null:
		sprite.flip_h = facing < 0
	var speed := float(spec.get("speed", 130))
	velocity.x = move_toward(velocity.x, dir * speed, 900.0 * delta)
	_try_jump_for_target(target_pos - global_position)


func face_toward(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	facing = 1 if node.global_position.x > global_position.x else -1
	if sprite != null:
		sprite.flip_h = facing < 0


func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	var hostile_to_player := FactionManager.is_hostile(faction_id) or provoked
	if hostile_to_player:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and not bool(player.get("is_dead")):
			var vis := 1.0
			var value: Variant = player.get("visibility")
			if value != null:
				vis = clampf(float(value), 0.0, 1.0)
			if vis > 0.05:
				best = player
				best_score = global_position.distance_to(player.global_position) * 0.8
	# Other factions: relationship drives aggression.
	for other in get_tree().get_nodes_in_group("faction_units"):
		if other == self or not is_instance_valid(other):
			continue
		var other_faction := String(other.get("faction_id"))
		if other_faction == faction_id:
			continue
		var hostility := FactionManager.relationship(faction_id, other_faction)
		if hostility < 0.4 and not provoked:
			continue
		var score := global_position.distance_to(other.global_position) * (1.0 - hostility * 0.5)
		if score < best_score:
			best_score = score
			best = other
	# Infected: everyone but the Rust Gang shoots them first.
	if FactionManager.hostility_to_zombies(faction_id) >= 0.5:
		for zombie in get_tree().get_nodes_in_group("zombies"):
			if zombie == self or not is_instance_valid(zombie) or bool(zombie.get("dead")):
				continue
			if zombie.is_in_group("faction_units"):
				continue
			if zombie.get("level") != level:
				continue
			var bonus := 0.0
			if bool(spec.get("hunt_specials", false)) and zombie.is_in_group("special_infected"):
				bonus = -260.0
			var score := global_position.distance_to(zombie.global_position) * (1.6 - FactionManager.hostility_to_zombies(faction_id)) + bonus
			if score < best_score:
				best_score = score
				best = zombie
	return best


func _attack(target: Node2D) -> void:
	_shoot_cd = float(spec.get("interval", 1.0))
	_play_anim("shoot")
	var damage := int(spec.get("damage", 10))
	var range_px := maxf(60.0, float(spec.get("range", 40.0)) + 20.0)
	var origin := global_position + Vector2(0, -20)
	var dir := (target.global_position + Vector2(0, -16) - origin).normalized()
	if range_px <= 70.0:
		# Melee / shield bash.
		if target.has_method("take_damage"):
			target.take_damage(damage, dir, &"faction", &"melee")
		elif target.has_method("apply_damage"):
			target.apply_damage(damage, -dir, false, &"faction", &"melee")
		AudioManager.play_sfx_2d(&"melee_hit", global_position, 420.0, -10.0)
		return
	# Hitscan with a little spread.
	var spread := 0.04
	var shot_dir := dir.rotated(randf_range(-spread, spread))
	var query := PhysicsRayQueryParameters2D.create(origin, origin + shot_dir * range_px, 89, [get_rid()])
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	var end := origin + shot_dir * range_px
	if not result.is_empty():
		end = result["position"]
		var collider: Object = result["collider"]
		if collider != self:
			if collider.has_method("take_damage"):
				collider.take_damage(damage, shot_dir, &"faction", &"bullet")
			elif collider.has_method("apply_damage"):
				collider.apply_damage(damage, -shot_dir, false, &"faction", &"bullet")
	if level != null and level.has_method("fx_layer") and level.fx_layer != null:
		Fx.tracer(level.fx_layer, origin, end)
		Fx.muzzle(level.fx_layer, origin, shot_dir.angle())
	if not bool(spec.get("silenced", false)):
		AudioManager.play_sfx_2d(&"gunshot", global_position, 700.0, -12.0)
		EventBus.gunshot.emit(global_position, 500.0)


# ---------------------------------------------------------------- special ----
func _tick_jammer(delta: float) -> void:
	jam_timer -= delta
	if jam_timer > 0.0:
		return
	jam_timer = 5.0
	if ArchiveManager.has_method("jam_zone"):
		ArchiveManager.jam_zone(global_position, 240.0, 6.0)
	EventBus.notify.emit("信号干扰 · 档案无法读取")


func _find_archive_target() -> Node2D:
	if level == null or not level.has_method("get_archive_pickups"):
		return null
	var best: Node2D = null
	var best_dist := 1400.0
	for pickup in level.get_archive_pickups():
		if pickup == null or not is_instance_valid(pickup) or bool(pickup.get("taken")):
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pickup
	return best


func _burn_archive() -> void:
	if _archive_target == null or not is_instance_valid(_archive_target):
		return
	if level != null and level.has_method("burn_archive_pickup"):
		level.burn_archive_pickup(_archive_target)
	_archive_target = null


# ----------------------------------------------------------------- damage ----
func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if dead:
		return
	provoked = true
	# Riot-shield style frontal mitigation for enforcers / patrols.
	if bool(spec.get("shield", false)) and damage_type == &"bullet" and from_dir.length() > 0.01:
		if from_dir.normalized().dot(Vector2(float(facing), 0.0)) > 0.2:
			amount = int(ceil(float(amount) * 0.35))
			Fx.spark(level.fx_layer if level else get_parent(), global_position + Vector2(0, -18))
	super(amount, from_dir, is_head, source, damage_type)


func _die(source: StringName, is_head: bool = false) -> void:
	if dead:
		return
	if source == &"player":
		FactionManager.register_kill(faction_id)
		if level != null and level.has_method("drop_scavenger_loot"):
			level.drop_scavenger_loot(global_position)
	super(source, is_head)


func _on_death_effect() -> void:
	if faction_id == "signal_bureau" and unit_kind == "signal_jammer":
		EventBus.notify.emit("干扰器已摧毁")
