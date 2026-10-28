extends RoleStrategy
## ---------------------------------------------------------------------------
## 职责: 爆破手策略 —— 优先向 ≥3 只普感的密集点投掷手雷(容量/冷却/伤害/
##       半径来自 SoldierData);对密集集群伤害 ×1.5;基础移速 ×0.9。
## 依赖: SoldierBase(投掷物以 Marker2D 抛物线近似,落点范围伤害,零外部素材)。
## 对外接口: 覆写 RoleStrategy 钩子;movement_speed_mult / damage_multiplier /
##           try_special_action / think。
## ---------------------------------------------------------------------------

const CLUSTER_RADIUS: float = 90.0
const CLUSTER_MIN: int = 3
const GRENADE_FLIGHT: float = 0.7
const GRENADE_SCAN_INTERVAL: float = 0.5

var grenades_left: int = 0
var grenade_cd: float = 0.0
var cluster_count: int = 0
var _scan_timer: float = 0.0
var _grenade_marker: Marker2D = null
var _grenade_t: float = 0.0
var _grenade_from: Vector2 = Vector2.ZERO
var _grenade_to: Vector2 = Vector2.ZERO
var _grenade_damage: int = 55
var _grenade_radius: float = 120.0


func on_attached(attached_host: Node) -> void:
	super(attached_host)
	if data != null:
		grenades_left = data.grenade_capacity
		grenade_cd = 0.0
		_grenade_damage = data.grenade_damage
		_grenade_radius = data.grenade_radius


func movement_speed_mult() -> float:
	return 0.9


func damage_multiplier(_target: Node2D) -> float:
	## 规格: 对 zombie_cluster(≥3 只密集群)伤害 ×1.5。
	return 1.5 if cluster_count >= CLUSTER_MIN else 1.0


func think(delta: float) -> void:
	grenade_cd = maxf(0.0, grenade_cd - delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = GRENADE_SCAN_INTERVAL
		_update_cluster()


func _update_cluster() -> void:
	cluster_count = 0
	var enemies := alive_enemies()
	if host == null or enemies.is_empty():
		return
	var origin: Vector2 = host.global_position
	var best_count: int = 0
	for enemy in enemies:
		var candidate: Vector2 = enemy.global_position
		if origin.distance_to(candidate) > 640.0:
			continue
		var count: int = 0
		for other in enemies:
			if candidate.distance_to(other.global_position) <= CLUSTER_RADIUS:
				count += 1
		if count > best_count:
			best_count = count
	cluster_count = best_count


func try_special_action(_delta: float) -> void:
	if _grenade_marker != null or grenades_left <= 0 or grenade_cd > 0.0:
		return
	if cluster_count < CLUSTER_MIN or host == null:
		return
	var target := _densest_point()
	if target == Vector2.ZERO:
		return
	_throw_grenade(target)


func _densest_point() -> Vector2:
	var enemies := alive_enemies()
	var best := Vector2.ZERO
	var best_count: int = 0
	for enemy in enemies:
		var candidate: Vector2 = enemy.global_position
		var count: int = 0
		for other in enemies:
			if candidate.distance_to(other.global_position) <= CLUSTER_RADIUS:
				count += 1
		if count > best_count:
			best_count = count
			best = candidate
	return best if best_count >= CLUSTER_MIN else Vector2.ZERO


func _throw_grenade(target: Vector2) -> void:
	grenades_left -= 1
	grenade_cd = data.grenade_cooldown if data != null else 60.0
	_grenade_from = host.global_position + Vector2(0, -20)
	_grenade_to = target
	_grenade_t = 0.0
	_grenade_marker = Marker2D.new()
	_grenade_marker.name = "GrenadeFlight"
	host.add_child(_grenade_marker)
	_grenade_marker.global_position = _grenade_from
	if host.has_signal("soldier_state_changed"):
		host.soldier_state_changed.emit(&"grenade_thrown", {})


func physics_tick(delta: float) -> void:
	if _grenade_marker == null:
		return
	_grenade_t += delta
	var t: float = clampf(_grenade_t / GRENADE_FLIGHT, 0.0, 1.0)
	var pos := _grenade_from.lerp(_grenade_to, t)
	pos.y -= sin(t * PI) * 90.0 # 抛物线弧高
	_grenade_marker.global_position = pos
	if t >= 1.0:
		_detonate(_grenade_to)


func _detonate(at: Vector2) -> void:
	if _grenade_marker != null and is_instance_valid(_grenade_marker):
		_grenade_marker.queue_free()
	_grenade_marker = null
	for enemy in alive_enemies():
		var distance: float = at.distance_to(enemy.global_position)
		if distance > _grenade_radius:
			continue
		var falloff: float = 1.0 - 0.5 * (distance / maxf(1.0, _grenade_radius))
		var amount := int(round(float(_grenade_damage) * falloff * damage_multiplier(enemy)))
		if enemy.has_method("apply_damage"):
			enemy.apply_damage(amount, (enemy.global_position - at).normalized(),
				false, &"ally", &"explosion")
	var event_bus := bus()
	if event_bus != null and event_bus.has_signal("explosion"):
		event_bus.explosion.emit(at, _grenade_radius)
