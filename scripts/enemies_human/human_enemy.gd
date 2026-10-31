class_name HumanEnemy
extends CharacterBody2D
## 「锈蚀频率」人类派系武装单位（地平线安保 / 锈帮枪手 / 残警 / 信号局特工）。
## 行为：巡逻 → 接敌（对僵尸天然敌对；对玩家按 FactionManager 敌意判定）；
##       受击后 0.6 秒内找最近掩体点（props 注册位置），周期投掷燃烧瓶/震撼雷。
## 简化说明：复用现有角色动画条带 + 派系色 tint（记录于 DECISIONS.md）。

const GRAVITY := 1400.0

var faction: StringName = &"horizon"
var kind: StringName = &"guard"     # guard / gunner / remnants / agent
var level: Node = null
var health: int = 60
var max_health: int = 60
var dead := false
var facing: int = 1
var target: Node2D = null
var shoot_cd: float = 1.0
var throw_cd: float = 8.0
var _retarget_timer: float = 0.0
var hurt_flash: float = 0.0
var cover_point: Vector2 = Vector2.ZERO
var seeking_cover: float = 0.0
var sprite: AnimatedSprite2D

const DAMAGE := 8
const SHOOT_RANGE := 380.0


func _ready() -> void:
	add_to_group("humans")
	collision_layer = 4
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 26)
	shape.shape = rect
	shape.position = Vector2(0, -13)
	add_child(shape)
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteLibrary.character_frames(_visual())
	sprite.play("idle")
	sprite.position = Vector2(0, -24)
	sprite.modulate = _tint()
	add_child(sprite)
	health = max_health


func _visual() -> String:
	match kind:
		&"gunner": return "scout"
		&"remnants": return "officer"
		&"agent": return "ninja"
		_: return "assault"


func _tint() -> Color:
	var base := Color(0.85, 0.90, 1.0)
	match faction:
		&"rust": base = Color(1.0, 0.8, 0.6)
		&"remnants": base = Color(0.7, 0.8, 1.0)
		&"signal_bureau": base = Color(0.8, 0.75, 1.0)
	if health < max_health * 0.35:
		base = base.darkened(0.25)
	return base


var _agent_pulse := 12.0


func _physics_process(delta: float) -> void:
	if dead or GameManager.state != GameManager.State.PLAYING:
		return
	if kind == &"agent":
		_agent_pulse -= delta
		if _agent_pulse <= 0.0:
			_agent_pulse = 12.0
			EventBus.signal_interference.emit(true)
			var t := get_tree().create_timer(2.0)
			t.timeout.connect(func() -> void: EventBus.signal_interference.emit(false))
	hurt_flash = maxf(0.0, hurt_flash - delta)
	if hurt_flash <= 0.0:
		sprite.modulate = _tint()
	shoot_cd = maxf(0.0, shoot_cd - delta)
	throw_cd = maxf(0.0, throw_cd - delta)
	seeking_cover = maxf(0.0, seeking_cover - delta)
	velocity.y += GRAVITY * delta

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.8
		_acquire_target()

	var move := 0.0
	if seeking_cover > 0.0:
		var d := cover_point.x - global_position.x
		if absf(d) > 12.0:
			move = signf(d)
			facing = 1 if d > 0 else -1
		elif shoot_cd <= 0.0:
			_shoot()
	elif target != null and is_instance_valid(target):
		var dx := target.global_position.x - global_position.x
		facing = 1 if dx > 0 else -1
		var dist := absf(dx)
		# 交战距离：太近后退，太远逼近，中距离射击
		if dist < 120.0:
			move = -signf(dx)
		elif dist > SHOOT_RANGE * 0.7:
			move = signf(dx)
		if shoot_cd <= 0.0 and dist < SHOOT_RANGE:
			_shoot()
		if throw_cd <= 0.0 and dist > 150.0 and dist < 320.0 and randf() < 0.5:
			_throw()
	else:
		move = 0.0
	velocity.x = move_toward(velocity.x, move * 130.0, 900.0 * delta)
	move_and_slide()
	_play_anim()


func _acquire_target() -> void:
	# 僵尸永远是敌人；玩家按派系敌意判定
	var best: Node2D = null
	var best_d := 420.0
	if level != null:
		for z in level.get_zombies_near(global_position, 420.0):
			var d: float = global_position.distance_to(z.global_position)
			if d < best_d:
				best = z
				best_d = d
	# 对其他派系人类单位的索敌（P1-10）：优先级低于僵尸
	if best == null and level != null:
		var sight := 420.0
		# P1-11：高密级下地平线单位索敌半径 +50%
		if faction == &"horizon" and ArchiveManager.current_tier() >= 2:
			sight = 630.0
		for h in get_tree().get_nodes_in_group("humans"):
			if h == null or not is_instance_valid(h) or bool(h.get("dead")) or h == self:
				continue
			if not FactionManager.factions_at_war(faction, h.get("faction")):
				continue
			var d2: float = global_position.distance_to(h.global_position)
			if d2 < sight:
				best = h
				best_d = d2
	if best == null and FactionManager.unit_wants_to_attack(faction):
		var player: Node2D = level.get_player() if level != null else null
		if player != null and is_instance_valid(player) and not bool(player.get("is_dead")):
			if global_position.distance_to(player.global_position) < 420.0:
				best = player


func _shoot() -> void:
	shoot_cd = randf_range(0.7, 1.4)
	if target == null or not is_instance_valid(target):
		return
	var origin := global_position + Vector2(facing * 10.0, -18.0)
	var aim := (target.global_position + Vector2(0, -14) - origin).normalized()
	var result := _ray(origin, aim, SHOOT_RANGE)
	var end := origin + aim * SHOOT_RANGE
	if not result.is_empty():
		end = result["position"]
		var collider: Object = result["collider"]
		if collider.has_method("apply_damage"):
			collider.apply_damage(DAMAGE, -aim, false, faction, &"bullet")
			if collider != target and collider.is_in_group("zombies"):
				Fx.blood(level.fx_layer if level != null else null, end, aim)
			elif collider == target:
				Fx.blood(level.fx_layer if level != null else null, end, aim)
	Fx.tracer(level.fx_layer if level != null else null, origin, end)
	Fx.muzzle(level.fx_layer if level != null else null, origin, aim.angle())
	AudioManager.play_sfx_2d(&"gunshot", global_position, 500.0)


func _ray(from: Vector2, dir: Vector2, dist: float) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, from + dir * dist, 2 | 4 | 8)
	query.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	return result


func _throw() -> void:
	throw_cd = randf_range(9.0, 14.0)
	if level == null or target == null or not is_instance_valid(target):
		return
	EventBus.notify.emit("注意投掷物！")
	var marker := Sprite2D.new()
	marker.texture = SpriteLibrary.prop_texture("pickup_molotov" if faction == &"rust" else "pickup_grenade")
	marker.scale = Vector2(0.8, 0.8)
	marker.z_index = 18
	var parent: Node = level.fx_layer if level.fx_layer != null else level
	parent.add_child(marker)
	var from := global_position + Vector2(0, -20)
	var to := target.global_position
	var tw := marker.create_tween()
	tw.tween_property(marker, "position", (from + to) * 0.5 + Vector2(0, -70), 0.55)
	tw.tween_property(marker, "position", to, 0.55)
	tw.tween_callback(func() -> void:
		EventBus.explosion.emit(to, 60.0)
		EventBus.screen_shake.emit(3.0)
		for z in level.get_zombies_near(to, 70.0):
			if z.has_method("apply_damage"):
				z.apply_damage(30, (z.global_position - to).normalized(), false, faction, &"explosion")
		var player: Node2D = level.get_player()
		if player != null and is_instance_valid(player) and player.global_position.distance_to(to) < 70.0:
			player.call("take_damage", 14, (player.global_position - to).normalized(), faction, &"explosion")
		marker.queue_free())


func _play_anim() -> void:
	if sprite == null:
		return
	if absf(velocity.x) > 8.0:
		if sprite.animation != "run":
			sprite.play("run")
	elif sprite.animation != "idle":
		sprite.play("idle")


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if dead:
		return
	health -= amount
	hurt_flash = 0.1
	sprite.modulate = Color(2.0, 1.4, 1.4)
	Fx.blood(level.fx_layer if level != null else null, global_position + Vector2(0, -18), from_dir)
	# 受击后找掩体（P4-2：0.6 秒反应窗）
	if seeking_cover <= 0.0 and level != null:
		seeking_cover = 2.0
		cover_point = global_position - Vector2(signf(from_dir.x) * 90.0, 0)
	if health <= 0:
		dead = true
		_play_die()


func _play_die() -> void:
	sprite.play("die")
	collision_layer = 0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(sprite, "modulate:a", 0.0, 1.2)
	tw.tween_callback(queue_free)
	EventBus.enemy_died.emit(kind, global_position, 400)
