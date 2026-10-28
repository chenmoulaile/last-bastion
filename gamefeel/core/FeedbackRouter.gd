class_name GameFeelFeedbackRouter
extends Node
## FeedbackRouter - one place that turns semantic combat events into feedback.
##
## The bridge owns event subscriptions and target polling; this router owns the
## mapping from "a shotgun hit a special infected in the head" to concrete
## feedback calls. Every call is guarded by GameFeelConfig, so a module can be
## switched off independently without touching combat code.

const HEAVY_WEAPONS: Array[StringName] = [&"shotgun", &"lmg", &"sniper"]
const MELEE_WEAPONS: Array[StringName] = [&"katana", &"axe", &"chainsaw"]
const SHELL_WEAPONS: Array[StringName] = [&"m9", &"smg", &"ar15", &"shotgun", &"lmg", &"sniper"]

var damage_numbers: GameFeelDamageNumbers = null
var hit_flash: GameFeelHitFlash = null
var knockback: GameFeelKnockback = null
var muzzle_flash: GameFeelMuzzleFlash = null
var impact_particles: GameFeelImpactParticles = null
var shell_eject: GameFeelShellEject = null
var death_ragdoll: GameFeelDeathRagdoll = null
var hit_direction: GameFeelHitDirection = null
var kill_streak: GameFeelKillStreak = null


func setup(numbers: GameFeelDamageNumbers, flash: GameFeelHitFlash, knock: GameFeelKnockback,
		muzzle: GameFeelMuzzleFlash, impacts: GameFeelImpactParticles,
		shells: GameFeelShellEject, ragdoll: GameFeelDeathRagdoll,
		directions: GameFeelHitDirection, streaks: GameFeelKillStreak) -> void:
	damage_numbers = numbers
	hit_flash = flash
	knockback = knock
	muzzle_flash = muzzle
	impact_particles = impacts
	shell_eject = shells
	death_ragdoll = ragdoll
	hit_direction = directions
	kill_streak = streaks


func is_heavy(weapon_id: StringName) -> bool:
	return weapon_id in HEAVY_WEAPONS


func is_melee(weapon_id: StringName) -> bool:
	return weapon_id in MELEE_WEAPONS


# ------------------------------------------------------------------- shots ---
func on_shot(weapon_id: StringName, muzzle_pos: Vector2, direction: Vector2,
		target_kind: StringName = &"") -> void:
	if not GameFeelConfig.enabled:
		return
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var heavy := is_heavy(weapon_id)
	if GameFeelConfig.is_module_enabled(&"muzzle_flash"):
		if muzzle_flash != null:
			muzzle_flash.flash(muzzle_pos, dir, weapon_id, heavy)
	if GameFeelConfig.is_module_enabled(&"camera_punch"):
		CameraPunch.punch(dir, weapon_id)
	if GameFeelConfig.is_module_enabled(&"screenshake"):
		ScreenShake.add_shot(heavy, dir)
	RecoilController.kick(weapon_id)
	if GameFeelConfig.is_module_enabled(&"shell_eject") and shell_eject != null:
		if weapon_id in SHELL_WEAPONS:
			var count := 2 if weapon_id == &"shotgun" else 1
			shell_eject.eject(muzzle_pos, dir, count)
	AudioLayerManager.play_shot_layer(weapon_id, heavy, target_kind)


func on_environment_hit(world_pos: Vector2, direction: Vector2) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"impact_particles"):
		return
	if impact_particles != null:
		impact_particles.burst(&"debris", world_pos, -direction.normalized())
	AudioLayerManager.play_impact(&"debris", false)


# ------------------------------------------------------------- enemy hits ---
func on_enemy_hit(target: Node, damage: int, world_pos: Vector2, direction: Vector2,
		weapon_id: StringName, crit: bool, kind: StringName, armored: bool,
		apply_hitstop: bool = true) -> void:
	if not GameFeelConfig.enabled:
		return
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	if apply_hitstop:
		HitStop.request(&"crit" if crit else &"normal", target)
	if GameFeelConfig.is_module_enabled(&"hit_flash") and hit_flash != null:
		hit_flash.flash(target, &"crit" if crit else &"hit")
	if GameFeelConfig.is_module_enabled(&"knockback") and knockback != null:
		var boss := _is_boss(target)
		knockback.apply(target, dir, weapon_id, boss, armored)
	if GameFeelConfig.is_module_enabled(&"damage_numbers") and damage_numbers != null:
		if damage > 0:
			damage_numbers.spawn(damage, world_pos, crit, target.get_instance_id())
	if GameFeelConfig.is_module_enabled(&"impact_particles") and impact_particles != null:
		impact_particles.burst(kind, world_pos, dir, crit)
	AudioLayerManager.play_impact(kind, crit)
	if crit and GameFeelConfig.is_module_enabled(&"camera_punch"):
		CameraPunch.punch(dir, weapon_id, true)


func on_enemy_death(target: Node, world_pos: Vector2, direction: Vector2,
		weapon_id: StringName, crit: bool, kind: StringName, color: Color,
		human: bool = false, player_source: bool = true) -> void:
	if not GameFeelConfig.enabled:
		return
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var boss := _is_boss(target)
	var special := _is_special(target)
	if player_source:
		HitStop.request(&"kill", target)
	if crit and player_source:
		HitStop.request(&"crit", target)
		if damage_numbers != null and GameFeelConfig.is_module_enabled(&"damage_numbers"):
			damage_numbers.spawn_text("爆头", world_pos + Vector2(0, -8), Color(1.0, 0.86, 0.28, 1.0))
		if GameFeelConfig.is_module_enabled(&"camera_punch"):
			CameraPunch.headshot_kill(dir)
	if GameFeelConfig.is_module_enabled(&"death_ragdoll") and death_ragdoll != null:
		death_ragdoll.spawn(world_pos, dir, color, boss, special, human)
	if GameFeelConfig.is_module_enabled(&"impact_particles") and impact_particles != null:
		if crit:
			impact_particles.burst(&"blood_burst", world_pos, dir, true)
		elif not boss:
			impact_particles.burst(kind, world_pos, dir, false)
	AudioLayerManager.play_kill(kind, crit)


func on_boss_death(world_pos: Vector2) -> void:
	if not GameFeelConfig.enabled:
		return
	if GameFeelConfig.is_module_enabled(&"screenshake"):
		ScreenShake.add_boss_death()
	if GameFeelConfig.is_module_enabled(&"camera_punch"):
		CameraPunch.boss_death()
	if GameFeelConfig.is_module_enabled(&"impact_particles") and impact_particles != null:
		impact_particles.burst(&"blood_burst", world_pos, Vector2.UP, true)
	if damage_numbers != null and GameFeelConfig.is_module_enabled(&"damage_numbers"):
		damage_numbers.spawn_text("目标清除", world_pos + Vector2(0, -20), Color(1.0, 0.62, 0.24, 1.0))


# ------------------------------------------------------------- player side ---
func on_player_hit(amount: int, player: Node2D, direction: Vector2) -> void:
	if not GameFeelConfig.enabled or player == null:
		return
	if GameFeelConfig.is_module_enabled(&"screenshake"):
		ScreenShake.add_player_hit(direction)
	if GameFeelConfig.is_module_enabled(&"hit_flash") and hit_flash != null:
		hit_flash.flash_player(player)
	if GameFeelConfig.is_module_enabled(&"damage_numbers") and damage_numbers != null:
		damage_numbers.spawn_player(amount, player.global_position + Vector2(0, -10))
	if GameFeelConfig.is_module_enabled(&"hit_direction") and hit_direction != null:
		hit_direction.add_from_direction(direction)
	AudioLayerManager.play_player_impact()


func on_player_healed(amount: int, player: Node2D) -> void:
	if player == null or amount <= 0:
		return
	if GameFeelConfig.is_module_enabled(&"damage_numbers") and damage_numbers != null:
		damage_numbers.spawn_heal(amount, player.global_position + Vector2(0, -10))


func on_explosion(world_pos: Vector2, radius: float) -> void:
	if not GameFeelConfig.enabled:
		return
	if GameFeelConfig.is_module_enabled(&"screenshake"):
		ScreenShake.add_explosion()
	if GameFeelConfig.is_module_enabled(&"impact_particles") and impact_particles != null:
		var density := GameFeelConfig.effective_particle_density()
		var bursts := maxi(1, int(radius / 42.0))
		for i in bursts:
			var offset := Vector2(randf_range(-radius, radius) * 0.4, randf_range(-18.0, 10.0))
			impact_particles.burst(&"debris", world_pos + offset, Vector2.UP, false, density * 0.7)
	if GameFeelConfig.is_module_enabled(&"camera_punch"):
		CameraPunch.boss_death()
	AudioLayerManager.play_explosion_layer()


func on_reload_started(weapon_id: StringName, reload_time: float, empty: bool) -> void:
	if not GameFeelConfig.enabled:
		return
	AudioLayerManager.play_reload_sequence(weapon_id, reload_time, empty)


func on_reload_finished(_weapon_id: StringName) -> void:
	pass


func on_streak_milestone(tier: int) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"kill_streak"):
		return
	if kill_streak != null:
		kill_streak.show_milestone(tier)


# --------------------------------------------------------------- internals ---
func _is_boss(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var data: Variant = target.get("data")
	if data != null:
		var value: Variant = data.get("is_boss")
		if value != null:
			return bool(value)
	return false


func _is_special(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var data: Variant = target.get("data")
	if data != null:
		var value: Variant = data.get("is_special")
		if value != null:
			return bool(value)
	return target.is_in_group("faction_units")
