extends Node
## GameFeelBridge - the only integration point between the existing game and
## the presentation layer.
##
## Responsibilities:
##   * instantiate the router and all feedback modules (world + UI)
##   * subscribe to existing EventBus signals (read-only)
##   * detect real enemy damage by polling public health values, because the
##     legacy combat scripts intentionally have no "damage_dealt" signal
##   * take over the legacy hitstop/camera shake while enabled, and hand them
##     back untouched when disabled
##
## It never writes a combat value. Every effect is local presentation only.
##
## Autoload: GameFeelBridge (last gamefeel autoload).

const POLL_INTERVAL_USEC := 12_000
const TRACK_RETRY_USEC := 500_000
const BOSS_FALLBACK_OFFSET := Vector2(0, -30)
const _HC_SCRIPT := preload("res://components/HealthComponent.gd")

var router: GameFeelFeedbackRouter = null
var damage_numbers: GameFeelDamageNumbers = null
var hit_flash: GameFeelHitFlash = null
var knockback: GameFeelKnockback = null
var muzzle_flash: GameFeelMuzzleFlash = null
var impact_particles: GameFeelImpactParticles = null
var shell_eject: GameFeelShellEject = null
var death_ragdoll: GameFeelDeathRagdoll = null
var hit_direction: GameFeelHitDirection = null
var low_health: GameFeelLowHealth = null
var kill_streak: GameFeelKillStreak = null

var _world: Node2D = null
var _player: Node2D = null
var _player_retry_usec: int = 0
var _tracked: Dictionary = {}
var _last_poll_usec: int = 0
var _last_shot_usec: int = 0
var _last_shot_dir: Vector2 = Vector2.RIGHT
var _current_weapon: StringName = &"m9"
var _crit_window_usec: int = 0
var _last_legacy_hitstop_usec: int = 0
var _suppress_legacy_shake_until: int = 0
var _was_reloading: bool = false
var _boss_pos: Vector2 = Vector2.ZERO
var _boss_tracked: bool = false
var _gm_hitstop: Callable = Callable()
var _hitstop_taken: bool = false

## 信号驱动注册的 HealthComponent 实例（instance_id -> component）。
var _health_components: Dictionary = {}
## 信号驱动启用后，轮询默认关闭；仅作为无信号场景的兜底。
var _poll_enabled: bool = false

var _perf_accum_usec: int = 0
var _perf_frames: int = 0
var _perf_max_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 100
	_build_modules()
	_connect_bus()
	_sync_hitstop_takeover()


func _exit_tree() -> void:
	_release_hitstop()
	_disconnect_bus()
	# 清理所有注册的 HealthComponent 信号连接。
	for key in _health_components.keys():
		var id := int(key)
		var comp: Node = _health_components.get(key, null)
		if comp != null and is_instance_valid(comp):
			if comp.is_connected("damaged", _on_health_damaged):
				comp.damaged.disconnect(_on_health_damaged)
	_health_components.clear()


func _process(_delta: float) -> void:
	if not GameFeelConfig.enabled:
		return
	var now := Time.get_ticks_usec()
	if now - _last_poll_usec < POLL_INTERVAL_USEC:
		return
	_last_poll_usec = now
	var started := Time.get_ticks_usec()
	_poll(now)
	var elapsed := Time.get_ticks_usec() - started
	_perf_accum_usec += elapsed
	_perf_frames += 1
	_perf_max_usec = maxi(_perf_max_usec, elapsed)


# ------------------------------------------------------------------ setup ----
func _build_modules() -> void:
	_world = Node2D.new()
	_world.name = "GameFeelWorld"
	_world.z_index = 50
	_world.z_as_relative = false
	add_child(_world)

	damage_numbers = GameFeelDamageNumbers.new()
	damage_numbers.name = "DamageNumbers"
	add_child(damage_numbers)

	hit_flash = GameFeelHitFlash.new()
	hit_flash.name = "HitFlash"
	_world.add_child(hit_flash)

	knockback = GameFeelKnockback.new()
	knockback.name = "Knockback"
	add_child(knockback)

	muzzle_flash = GameFeelMuzzleFlash.new()
	muzzle_flash.name = "MuzzleFlash"
	_world.add_child(muzzle_flash)

	impact_particles = GameFeelImpactParticles.new()
	impact_particles.name = "ImpactParticles"
	_world.add_child(impact_particles)

	shell_eject = GameFeelShellEject.new()
	shell_eject.name = "ShellEject"
	_world.add_child(shell_eject)

	death_ragdoll = GameFeelDeathRagdoll.new()
	death_ragdoll.name = "DeathRagdoll"
	_world.add_child(death_ragdoll)

	hit_direction = GameFeelHitDirection.new()
	hit_direction.name = "HitDirection"
	add_child(hit_direction)

	low_health = GameFeelLowHealth.new()
	low_health.name = "LowHealthVignette"
	add_child(low_health)

	kill_streak = GameFeelKillStreak.new()
	kill_streak.name = "KillStreakPopup"
	add_child(kill_streak)

	router = GameFeelFeedbackRouter.new()
	router.name = "FeedbackRouter"
	add_child(router)
	router.setup(damage_numbers, hit_flash, knockback, muzzle_flash,
		impact_particles, shell_eject, death_ragdoll, hit_direction, kill_streak)


func _connect_bus() -> void:
	EventBus.gunshot.connect(_on_gunshot)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_healed.connect(_on_player_healed)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_rescued.connect(_on_player_rescued)
	EventBus.explosion.connect(_on_explosion)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.weapon_changed.connect(_on_weapon_changed)
	EventBus.screen_shake.connect(_on_legacy_shake)
	EventBus.door_broken.connect(_on_door_broken)
	EventBus.barrel_exploded.connect(_on_barrel_exploded)
	EventBus.start_level_requested.connect(_on_level_start)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.level_failed.connect(_on_level_failed)
	EventBus.return_to_menu_requested.connect(_on_return_to_menu)
	GameFeelConfig.config_changed.connect(_on_config_changed)


func _disconnect_bus() -> void:
	if EventBus.gunshot.is_connected(_on_gunshot):
		EventBus.gunshot.disconnect(_on_gunshot)
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)
	if EventBus.player_hit.is_connected(_on_player_hit):
		EventBus.player_hit.disconnect(_on_player_hit)
	if EventBus.player_healed.is_connected(_on_player_healed):
		EventBus.player_healed.disconnect(_on_player_healed)
	if EventBus.player_downed.is_connected(_on_player_downed):
		EventBus.player_downed.disconnect(_on_player_downed)
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)
	if EventBus.player_rescued.is_connected(_on_player_rescued):
		EventBus.player_rescued.disconnect(_on_player_rescued)
	if EventBus.explosion.is_connected(_on_explosion):
		EventBus.explosion.disconnect(_on_explosion)
	if EventBus.boss_spawned.is_connected(_on_boss_spawned):
		EventBus.boss_spawned.disconnect(_on_boss_spawned)
	if EventBus.boss_killed.is_connected(_on_boss_killed):
		EventBus.boss_killed.disconnect(_on_boss_killed)
	if EventBus.weapon_changed.is_connected(_on_weapon_changed):
		EventBus.weapon_changed.disconnect(_on_weapon_changed)
	if EventBus.screen_shake.is_connected(_on_legacy_shake):
		EventBus.screen_shake.disconnect(_on_legacy_shake)
	if EventBus.door_broken.is_connected(_on_door_broken):
		EventBus.door_broken.disconnect(_on_door_broken)
	if EventBus.barrel_exploded.is_connected(_on_barrel_exploded):
		EventBus.barrel_exploded.disconnect(_on_barrel_exploded)
	if EventBus.start_level_requested.is_connected(_on_level_start):
		EventBus.start_level_requested.disconnect(_on_level_start)
	if EventBus.level_completed.is_connected(_on_level_completed):
		EventBus.level_completed.disconnect(_on_level_completed)
	if EventBus.level_failed.is_connected(_on_level_failed):
		EventBus.level_failed.disconnect(_on_level_failed)
	if EventBus.return_to_menu_requested.is_connected(_on_return_to_menu):
		EventBus.return_to_menu_requested.disconnect(_on_return_to_menu)
	if GameFeelConfig.config_changed.is_connected(_on_config_changed):
		GameFeelConfig.config_changed.disconnect(_on_config_changed)


## 注册 HealthComponent：订阅其 damaged 信号，实现信号驱动的伤害反馈。
func register_health_component(component: Node) -> void:
	if component.get_script() != _HC_SCRIPT:
		return
	var id := component.get_instance_id()
	if _health_components.has(id):
		return
	_health_components[id] = component
	component.damaged.connect(_on_health_damaged)


## 注销 HealthComponent：取消订阅。
func unregister_health_component(component: Node) -> void:
	if component.get_script() != _HC_SCRIPT:
		return
	var id := component.get_instance_id()
	if _health_components.has(id):
		if component.is_connected("damaged", _on_health_damaged):
			component.damaged.disconnect(_on_health_damaged)
		_health_components.erase(id)


## HealthComponent.damaged 信号处理器：每命中一次触发一次独立反馈。
func _on_health_damaged(amount: float, source: Node, hit_position: Vector2, is_critical: bool) -> void:
	if not GameFeelConfig.enabled:
		return
	if source == null:
		return
	var target := source.get_parent() if source != null else null
	if target == null or not is_instance_valid(target):
		return
	var body := target as Node2D
	if body == null:
		return
	var player := _get_player()
	if player == null:
		return
	var damage_type := StringName(target.get("last_damage_type"))
	var crit := is_critical or damage_type == &"execution" or damage_type == &"headshot"
	var human := target.is_in_group("faction_units")
	var armored := _is_armored(target, human)
	var kind := _particle_kind(target, human, armored)
	var world_position := hit_position
	if world_position == Vector2.ZERO:
		world_position = body.global_position + Vector2(0, -15)
	var direction := Vector2(signf(body.global_position.x - player.global_position.x), -0.12)
	if absf(direction.x) < 0.01:
		direction.x = 1.0
	direction = direction.normalized()
	router.on_enemy_hit(body, int(amount), world_position, direction,
		_current_weapon, crit, kind, armored, true)


# ---------------------------------------------------------- hitstop takeover --
func _sync_hitstop_takeover() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return
	_gm_hitstop = Callable(game_manager, "hitstop")
	if GameFeelConfig.enabled:
		if EventBus.hitstop.is_connected(_gm_hitstop):
			EventBus.hitstop.disconnect(_gm_hitstop)
		if not EventBus.hitstop.is_connected(_on_legacy_hitstop):
			EventBus.hitstop.connect(_on_legacy_hitstop)
		_hitstop_taken = true
	else:
		if EventBus.hitstop.is_connected(_on_legacy_hitstop):
			EventBus.hitstop.disconnect(_on_legacy_hitstop)
		if not EventBus.hitstop.is_connected(_gm_hitstop):
			EventBus.hitstop.connect(_gm_hitstop)
		_hitstop_taken = false


func _release_hitstop() -> void:
	if _hitstop_taken and EventBus.hitstop.is_connected(_on_legacy_hitstop):
		EventBus.hitstop.disconnect(_on_legacy_hitstop)
	if _gm_hitstop.is_valid() and not EventBus.hitstop.is_connected(_gm_hitstop):
		var game_manager := get_node_or_null("/root/GameManager")
		if game_manager != null:
			EventBus.hitstop.connect(_gm_hitstop)
	_hitstop_taken = false


func _on_legacy_hitstop(duration: float) -> void:
	var now := Time.get_ticks_usec()
	if duration <= 0.032 and now - _last_shot_usec <= 250_000:
		_crit_window_usec = now + 150_000
	_last_legacy_hitstop_usec = now
	HitStop.request_legacy(duration)


# ------------------------------------------------------------- bus handlers --
func _on_gunshot(position: Vector2, _loudness: float) -> void:
	if not GameFeelConfig.enabled:
		return
	var player := _get_player()
	if player == null:
		return
	if position.distance_to(player.global_position) > 110.0:
		# Faction units also emit gunshot(); only the local player owns the
		# camera/weapon feedback.
		return
	var direction: Vector2 = player.get("aim_dir")
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	var weapon := _resolve_weapon(player)
	_current_weapon = weapon
	_last_shot_usec = Time.get_ticks_usec()
	_last_shot_dir = direction
	router.on_shot(weapon, position, direction)
	_suppress_legacy_shake(0.06)
	_probe_environment_hit(player, position, direction, weapon)


func _on_enemy_died(_kind: StringName, _position: Vector2, _score: int) -> void:
	# Death visuals are resolved by the health poll, which also knows the hit
	# direction, crit flag and ragdoll colour.
	pass


func _on_enemy_killed(_kind: StringName, source: StringName, _position: Vector2) -> void:
	kill_streak.note_kill(source)


func _on_player_hit(amount: int) -> void:
	if not GameFeelConfig.enabled:
		return
	var player := _get_player()
	if player == null:
		return
	var facing := int(player.get("facing"))
	var direction := Vector2(float(facing), 0.0)
	router.on_player_hit(amount, player, direction)
	_suppress_legacy_shake(0.06)


func _on_player_healed(amount: int) -> void:
	var player := _get_player()
	if player != null:
		router.on_player_healed(amount, player)


func _on_player_downed() -> void:
	RecoilController.reset()


func _on_player_died() -> void:
	RecoilController.reset()
	kill_streak.reset()


func _on_player_rescued() -> void:
	pass


func _on_explosion(position: Vector2, radius: float) -> void:
	router.on_explosion(position, radius)
	_suppress_legacy_shake(0.08)


func _on_boss_spawned(_kind: StringName) -> void:
	_boss_tracked = true
	_boss_pos = Vector2.ZERO


func _on_boss_killed(_kind: StringName) -> void:
	var position := _find_boss_position()
	router.on_boss_death(position)
	_suppress_legacy_shake(0.35)
	_boss_tracked = false


func _on_weapon_changed(id: StringName, _display_name: String) -> void:
	_current_weapon = id
	RecoilController.set_weapon(id)


func _on_legacy_shake(amount: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"screenshake"):
		return
	var now := Time.get_ticks_usec()
	if now < _suppress_legacy_shake_until:
		return
	var trauma := clampf(amount / 8.0, 0.04, 0.75)
	var peak := clampf(2.0 + amount * 1.6, 2.0, 14.0)
	var direction := Vector2.ZERO
	if now - _last_shot_usec <= 60_000:
		direction = _last_shot_dir
	ScreenShake.add_trauma(trauma, peak, direction)


func _on_door_broken(position: Vector2) -> void:
	if not GameFeelConfig.enabled:
		return
	if impact_particles != null:
		impact_particles.burst(&"debris", position, Vector2.UP, false)
	_suppress_legacy_shake(0.05)


func _on_barrel_exploded(position: Vector2) -> void:
	if not GameFeelConfig.enabled:
		return
	if impact_particles != null:
		impact_particles.burst(&"debris", position, Vector2.UP, false)
	_suppress_legacy_shake(0.05)


func _on_level_start() -> void:
	_reset_runtime()


func _on_level_completed(_score: int, _rank: String) -> void:
	_reset_runtime()


func _on_level_failed(_reason: String) -> void:
	_reset_runtime()


func _on_return_to_menu() -> void:
	_reset_runtime()


func _on_config_changed(key: StringName, _value: Variant) -> void:
	if key == &"enabled" or key == &"reset":
		_sync_hitstop_takeover()
		if not GameFeelConfig.enabled:
			_reset_runtime()


# ------------------------------------------------------------ health polling --
func _poll(now: int) -> void:
	if not GameFeelConfig.enabled:
		return
	# 信号驱动模式下轮询默认关闭，仅作为无信号场景的兜底。
	if not _poll_enabled:
		return
	var player := _get_player()
	if player == null:
		return
	_poll_reload(player)
	var visible: Array = get_tree().get_nodes_in_group("zombies")
	for raw_node in visible:
		if raw_node == null or not is_instance_valid(raw_node) or not (raw_node is Node):
			continue
		var node: Node = raw_node as Node
		var id: int = node.get_instance_id()
		if not _tracked.has(id):
			_tracked[id] = _new_entry(node)
	var keys: Array = _tracked.keys()
	for raw_key in keys:
		var key := int(raw_key)
		if not _tracked.has(key):
			continue
		var entry: Dictionary = _tracked[key]
		var node: Node = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			_tracked.erase(key)
			continue
		if bool(node.get("dead")):
			if not bool(entry.get("death_fx", false)):
				_handle_death(node, entry, player, now)
				entry["death_fx"] = true
			entry["health"] = int(node.get("health"))
			continue
		var health := int(node.get("health"))
		var previous := int(entry.get("health", health))
		if health < previous:
			var damage := previous - health
			var source := StringName(node.get("last_source"))
			if source == &"player" or source == &"barrel":
				var body := node as Node2D
				if body == null:
					continue
				var damage_type := StringName(node.get("last_damage_type"))
				var crit := damage_type == &"execution" or now <= _crit_window_usec
				var apply_hitstop := not (crit and now - _last_legacy_hitstop_usec <= 220_000)
				var human := node.is_in_group("faction_units")
				var armored := _is_armored(node, human)
				var kind := _particle_kind(node, human, armored)
				var world_position: Vector2 = body.global_position + Vector2(0, -22 if crit else -15)
				var direction := Vector2(signf(body.global_position.x - player.global_position.x), -0.12)
				if absf(direction.x) < 0.01:
					direction.x = 1.0
				direction = direction.normalized()
				router.on_enemy_hit(node, damage, world_position, direction,
					_current_weapon, crit, kind, armored, apply_hitstop)
				if health <= 0:
					_handle_death(node, entry, player, now)
					entry["death_fx"] = true
			entry["health"] = health
		elif health > previous:
			entry["health"] = health
		if health <= 0 and not bool(entry.get("death_fx", false)):
			_handle_death(node, entry, player, now)
			entry["death_fx"] = true


func _new_entry(node: Node) -> Dictionary:
	return {
		"node": node,
		"health": int(node.get("health")),
		"max_health": int(node.get("max_health")),
		"death_fx": false,
	}


func _handle_death(node: Node, entry: Dictionary, player: Node2D, now: int) -> void:
	if not GameFeelConfig.enabled:
		return
	var health := int(node.get("health"))
	var source := StringName(node.get("last_source"))
	var damage_type := StringName(node.get("last_damage_type"))
	var crit := damage_type == &"execution" or now <= _crit_window_usec
	var human := node.is_in_group("faction_units")
	var armored := _is_armored(node, human)
	var kind := _particle_kind(node, human, armored)
	var direction := Vector2(signf(node.global_position.x - player.global_position.x), -0.2)
	if absf(direction.x) < 0.01:
		direction.x = 1.0
	direction = direction.normalized()
	var color := _death_color(node, human)
	var player_source := source == &"player" or source == &"barrel"
	router.on_enemy_death(node, node.global_position + Vector2(0, -14), direction,
		_current_weapon, crit, kind, color, human, player_source)
	if _is_boss(node):
		_boss_pos = node.global_position
		_boss_tracked = true
	entry["health"] = health


func _poll_reload(player: Node) -> void:
	var reloading := bool(player.get("reloading"))
	if reloading and not _was_reloading:
		_was_reloading = true
		var weapon_id := _resolve_weapon(player)
		var weapon: WeaponData = GameManager.get_weapon(weapon_id)
		var reload_time := 1.0
		if weapon != null:
			reload_time = weapon.reload_time
		var empty := false
		var ammo_state: Variant = player.get("ammo")
		if ammo_state is Dictionary:
			var state: Dictionary = (ammo_state as Dictionary).get(weapon_id, {"mag": 1})
			empty = int(state.get("mag", 1)) <= 0
		router.on_reload_started(weapon_id, reload_time, empty)
	elif not reloading and _was_reloading:
		_was_reloading = false
		router.on_reload_finished(_resolve_weapon(player))


# --------------------------------------------------------------- helpers -----
func _get_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var now := Time.get_ticks_usec()
	if now - _player_retry_usec < TRACK_RETRY_USEC:
		return null
	_player_retry_usec = now
	_player = null
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node is Node2D and is_instance_valid(node):
			_player = node
			break
	return _player


func _resolve_weapon(player: Node) -> StringName:
	var slots: Variant = player.get("weapon_slots")
	var index: Variant = player.get("slot_index")
	if slots is Array and index is int:
		var list := slots as Array
		if index >= 0 and index < list.size():
			var id := StringName(list[index])
			if id != &"":
				return id
	return _current_weapon if _current_weapon != &"" else &"m9"


func _probe_environment_hit(player: Node2D, origin: Vector2, direction: Vector2, weapon_id: StringName) -> void:
	if weapon_id in [&"katana", &"axe", &"chainsaw", &"throwable"]:
		return
	var weapon: WeaponData = GameManager.get_weapon(weapon_id)
	var reach := 700.0
	if weapon != null:
		reach = maxf(120.0, weapon.effective_range)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + direction * reach, 89, [player.get_rid()])
	var result := player.get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result.get("collider")
	if collider == null:
		return
	if collider.has_method("apply_damage") or collider.has_method("is_headshot_point"):
		return
	if collider is Node:
		var node := collider as Node
		if node.is_in_group("player") or node.is_in_group("allies"):
			return
	router.on_environment_hit(result.get("position", origin), direction)


func _particle_kind(node: Node, human: bool, armored: bool) -> StringName:
	if human:
		return &"armor" if armored else &"human"
	var data: Variant = node.get("data")
	if data != null and bool(data.get("is_special")):
		return &"spore"
	return &"blood"


func _is_armored(node: Node, human: bool) -> bool:
	if not human:
		return false
	var spec: Variant = node.get("spec")
	if spec is Dictionary:
		return bool((spec as Dictionary).get("shield", false))
	return false


func _is_boss(node: Node) -> bool:
	var data: Variant = node.get("data")
	if data != null:
		var value: Variant = data.get("is_boss")
		if value != null:
			return bool(value)
	return false


func _death_color(node: Node, human: bool) -> Color:
	if human:
		var spec: Variant = node.get("spec")
		if spec is Dictionary:
			var tint: Variant = (spec as Dictionary).get("tint")
			if tint is Color:
				return tint as Color
	var data: Variant = node.get("data")
	if data != null:
		var tint: Variant = data.get("tint")
		if tint is Color and (tint as Color) != Color.WHITE:
			return tint as Color
	return Color(0.52, 0.14, 0.12, 1.0)


func _find_boss_position() -> Vector2:
	var best := Vector2.ZERO
	var found := false
	for raw_key in _tracked.keys():
		var entry: Dictionary = _tracked[raw_key]
		var node: Node = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if _is_boss(node):
			best = node.global_position
			found = true
			break
	if found:
		return best
	if _boss_pos != Vector2.ZERO:
		return _boss_pos
	var player := _get_player()
	if player != null:
		return player.global_position + BOSS_FALLBACK_OFFSET
	return BOSS_FALLBACK_OFFSET


func _suppress_legacy_shake(seconds: float) -> void:
	_suppress_legacy_shake_until = maxi(_suppress_legacy_shake_until,
		Time.get_ticks_usec() + int(seconds * 1_000_000.0))


func _reset_runtime() -> void:
	HitStop.cancel_all()
	ScreenShake.reset()
	CameraPunch.reset()
	if damage_numbers != null:
		damage_numbers.clear_all()
	if hit_flash != null:
		hit_flash.clear()
	if knockback != null:
		knockback.clear()
	if muzzle_flash != null:
		muzzle_flash.clear()
	if impact_particles != null:
		impact_particles.clear()
	if shell_eject != null:
		shell_eject.clear()
	if death_ragdoll != null:
		death_ragdoll.clear()
	if hit_direction != null:
		hit_direction.clear()
	if low_health != null:
		low_health.clear()
	if kill_streak != null:
		kill_streak.reset()
	RecoilController.reset()
	_tracked.clear()
	_health_components.clear()
	_was_reloading = false
	_crit_window_usec = 0
	_last_legacy_hitstop_usec = 0
	_last_shot_usec = 0
	_boss_pos = Vector2.ZERO
	_boss_tracked = false


# ------------------------------------------------------------ diagnostics ----
func tracked_enemy_count() -> int:
	return _tracked.size()


func perf_average_ms() -> float:
	if _perf_frames <= 0:
		return 0.0
	return float(_perf_accum_usec) / float(_perf_frames) / 1000.0


func perf_max_ms() -> float:
	return float(_perf_max_usec) / 1000.0


func perf_reset() -> void:
	_perf_accum_usec = 0
	_perf_frames = 0
	_perf_max_usec = 0


func debug_stress_burst(position: Vector2, target: Node = null) -> void:
	if not GameFeelConfig.enabled:
		return
	var direction := Vector2.RIGHT
	if muzzle_flash != null:
		muzzle_flash.flash(position, direction, &"shotgun", true)
	if shell_eject != null:
		shell_eject.eject(position, direction, 2)
	if impact_particles != null:
		impact_particles.burst(&"blood_burst", position + Vector2(0, -12), direction, true)
	if damage_numbers != null:
		damage_numbers.spawn(24, position + Vector2(0, -18), false, 0)
	if hit_flash != null and target != null:
		hit_flash.flash(target, &"crit")
	if knockback != null and target != null:
		knockback.apply(target, direction, &"shotgun", false, false)
	if hit_direction != null:
		hit_direction.add_from_direction(direction)
