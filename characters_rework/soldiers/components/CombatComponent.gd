class_name ReworkCombatComponent
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 士兵战斗 —— 分帧索敌(0.2s)、视线校验、按策略节奏开火(点射/持续)、
##       hitscan 伤害(基础 ×0.62,与现有 AllyAgent 一致;不消耗玩家弹药)、
##       自动换弹。开火节奏/目标偏好/伤害倍率全部由 RoleStrategy 决定,
##       本组件不出现兵种分支。
## 依赖: 宿主 SoldierBase、RoleStrategy、GameManager.get_weapon(可选)。
## 对外接口: attach(host, strategy) / tick(delta) / enemy / is_firing()
## ---------------------------------------------------------------------------

const SCAN_INTERVAL: float = 0.2
const SIGHT_MASK: int = 1                # 只被 WORLD 遮挡
const ACQUIRE_RANGE: float = 420.0
const AI_DAMAGE_MULT: float = 0.62       # 与现有工程约定一致
const RELOAD_TIME: float = 2.2

var enemy: Node2D = null
var fire_cooldown: float = 0.0

var _host: Node = null
var _strategy: RoleStrategy = null
var _scan_timer: float = 0.0
var _weapon: Resource = null
var _mag: int = 0
var _mag_size: int = 12
var _reload_timer: float = 0.0
var _burst_left: int = 0
var _burst_pause: float = 0.0
var _candidates: Array = []


func attach(host: Node, strategy: RoleStrategy) -> void:
	_host = host
	_strategy = strategy
	_load_weapon()


func tick(delta: float) -> void:
	if _host == null:
		return
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	_burst_pause = maxf(0.0, _burst_pause - delta)
	if _reload_timer > 0.0:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_mag = _mag_size
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_rescan()
	if enemy == null or not is_instance_valid(enemy):
		return
	_try_fire(delta)


func is_firing() -> bool:
	return fire_cooldown > 0.0 and _burst_pause <= 0.0


func _load_weapon() -> void:
	var weapon_id: StringName = &"ar15"
	var data: Variant = _host.get("soldier_data")
	if data != null:
		weapon_id = data.get("primary_weapon")
	var game: Variant = _host.get("_game")
	if game != null and game.has_method("get_weapon"):
		_weapon = game.get_weapon(weapon_id)
	if _weapon == null:
		var path := "res://resources/data/weapons/weapon_%s.tres" % weapon_id
		if ResourceLoader.exists(path):
			_weapon = load(path)
	if _weapon != null:
		_mag_size = int(_weapon.get("mag_size"))
	else:
		_mag_size = 12
	_mag = _mag_size


func _rescan() -> void:
	_candidates.clear()
	if _host == null:
		return
	var origin: Vector2 = _host.global_position
	var enemies: Array = _host.get_tree().get_nodes_in_group("zombies")
	for zombie in enemies:
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("dead")) or bool(node.get("is_dead")):
			continue
		if origin.distance_to(node.global_position) > ACQUIRE_RANGE:
			continue
		if not _has_line_of_sight(node):
			continue
		_candidates.append(node)
	if _candidates.is_empty():
		enemy = null
		return
	var preferred := _strategy.prefer_target(_candidates)
	if preferred == null or not is_instance_valid(preferred):
		preferred = _candidates[0]
	enemy = preferred
	_host.set("enemy", enemy)


func _has_line_of_sight(target: Node2D) -> bool:
	var space: PhysicsDirectSpaceState2D = _host.get_world_2d().direct_space_state
	var from: Vector2 = _host.global_position + Vector2(0, -18)
	var to: Vector2 = target.global_position + Vector2(0, -14)
	var query := PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK, [_host.get_rid()])
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty()


func _try_fire(delta: float) -> void:
	if not _strategy.can_fire():
		return
	if not _strategy.wants_to_fire(enemy):
		if _strategy.has_method("note_firing"):
			_strategy.note_firing(null)
		return
	if _mag <= 0:
		_reload_timer = RELOAD_TIME
		return
	# 点射节奏: burst_length>0 时打 N 停 M;≤0 = 持续全自动
	if _strategy.burst_length() > 0:
		if _burst_pause > 0.0:
			return
		if _burst_left <= 0:
			_burst_left = _strategy.burst_length()
			_burst_pause = 0.0
	var interval := 60.0 / maxf(60.0, _weapon_rpm())
	interval *= _strategy.fire_interval_mult()
	if fire_cooldown > 0.0:
		return
	fire_cooldown = interval
	_fire_shot()
	if _strategy.burst_length() > 0:
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_pause = _strategy.burst_pause()
			_burst_left = _strategy.burst_length()
	if _strategy.has_method("note_firing"):
		_strategy.note_firing(enemy)


func _fire_shot() -> void:
	_mag -= 1
	if _mag <= 0:
		_reload_timer = RELOAD_TIME
	var from: Vector2 = _host.global_position + Vector2(0, -18)
	var to: Vector2 = enemy.global_position + Vector2(0, -14)
	# 轻微散布(±4px 落点抖动)
	to += Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	var dir := (to - from).normalized()
	var damage := float(_weapon_damage()) * AI_DAMAGE_MULT * _strategy.damage_multiplier(enemy)
	var space: PhysicsDirectSpaceState2D = _host.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, from + dir * ACQUIRE_RANGE,
		SIGHT_MASK | 8 | 16, [_host.get_rid()])
	query.collide_with_areas = false
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return
	var collider: Object = result["collider"]
	var point: Vector2 = result["position"]
	if collider.has_method("apply_damage"):
		var falloff := _falloff(from.distance_to(point))
		collider.apply_damage(int(round(damage * falloff)), -dir, false, &"ally", &"bullet")
	var renderer: Variant = _host.get("_renderer")
	if renderer != null and renderer.has_method("trigger_muzzle_flash"):
		renderer.trigger_muzzle_flash()
	var audio: Variant = _host.get("_audio")
	if audio != null and audio.has_method("play_sfx_2d"):
		audio.play_sfx_2d(&"gunshot", _host.global_position, 700.0, -3.0)
	if _host.has_signal("shots_fired"):
		_host.shots_fired.emit(_host.global_position)


func _falloff(distance: float) -> float:
	var effective := 400.0
	if _weapon != null:
		effective = float(_weapon.get("effective_range"))
	if distance <= effective:
		return 1.0
	return maxf(0.4, 1.0 - (distance - effective) / 100.0 * 0.15)


func _weapon_rpm() -> float:
	if _weapon == null:
		return 300.0
	var value: Variant = _weapon.get("rpm")
	return 300.0 if value == null else float(value)


func _weapon_damage() -> int:
	if _weapon == null:
		return 14
	var value: Variant = _weapon.get("damage")
	return 14 if value == null else int(value)
