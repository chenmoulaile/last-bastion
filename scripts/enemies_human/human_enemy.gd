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

# wp7（P2-8）：信号局特工对玩家的距离分带战术
const AGENT_WANDER_RANGE := 400.0   # 距玩家 >400px：游走 + 周期架枪
const AGENT_HOLSTER_RANGE := 600.0  # 距玩家 >600px：收枪巡逻
const AGENT_AIM_TELEGRAPH := 1.0    # 架枪前摇 1s（红点提示）
const AGENT_BURST_COUNT := 3        # 三连点射
const AGENT_BURST_GAP := 0.12       # 连射间隔


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
# wp6：信号局特工专属招式状态（仅 kind==agent 使用）
var _blink_cd := 0.0        # 受击瞬移冷却
var _summon_cd := 10.0      # 诱导尸群冷却（首次接敌后 10s）
# wp7（P2-8）：特工对玩家距离分带状态机
var _aim_state := 0         # 0=游走/未架枪 1=架枪前摇（红点） 2=三连射中
var _aim_timer := 1.5       # 架枪周期计时（前摇倒计时 / 游走期倒计时）
var _burst_left := 0        # 三连射剩余弹数
var _burst_timer := 0.0
var _wander_dir := 1.0
var _wander_timer := 0.0
var _red_dot: Node2D = null # 架枪前摇红点提示（挂在 fx_layer，独立于本节点）


func _physics_process(delta: float) -> void:
	if dead or GameManager.state != GameManager.State.PLAYING:
		return
	if kind == &"agent":
		_tick_agent(delta)
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
	if kind == &"agent":
		move = _agent_move(delta)   # wp7：特工走距离分带状态机
	else:
		move = _generic_move()
	velocity.x = move_toward(velocity.x, move * 130.0, 900.0 * delta)
	move_and_slide()
	_play_anim()


## 通用交战移动（掩体反应 / 对目标逼近后退 / 中距射击）——wp7 扩展前原逻辑原样保留。
func _generic_move() -> float:
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
	return move


# --- wp6：信号局特工（kind==agent）专属战术 ---------------------------------
## 脉冲干扰：每 12s 一次 2s 干扰（原 P1-7 行为，改由统一窗口发出）；
## 诱导尸群：玩家进入 500px 后每 18s 在玩家身边召出 1-2 只普通僵尸。
func _tick_agent(delta: float) -> void:
	_agent_pulse -= delta
	if _agent_pulse <= 0.0:
		_agent_pulse = 12.0
		_agent_interference(2.0)
	_blink_cd = maxf(0.0, _blink_cd - delta)
	_summon_cd = maxf(0.0, _summon_cd - delta)
	if _summon_cd <= 0.0 and level != null:
		var p: Node2D = level.get_player()
		if p != null and is_instance_valid(p) and not bool(p.get("is_dead")) \
				and global_position.distance_to(p.global_position) < 500.0:
			_summon_zombie_wave()


## 发出一段干扰窗口：置 true 后 `seconds` 秒再置 false（计时器独立于本节点存活）。
func _agent_interference(seconds: float) -> void:
	EventBus.signal_interference.emit(true)
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(func() -> void: EventBus.signal_interference.emit(false))


## 受击瞬移换位：from_dir 语义为「受害者→攻击者」，逃逸方向取其反向。
func _agent_blink(from_dir: Vector2) -> void:
	_blink_cd = 5.0
	var side := -signf(from_dir.x) if absf(from_dir.x) > 0.05 else float(-facing)
	var width: float = level.level_width
	var new_x := clampf(global_position.x + side * randf_range(110.0, 150.0),
		80.0, maxf(100.0, width - 80.0))
	var gy: float = level.get_ground_y(new_x)
	if gy < 0.0:
		return
	var fx_parent: Node = level.fx_layer if level.fx_layer != null else level
	Fx.smoke(fx_parent, global_position + Vector2(0, -20))
	global_position = Vector2(new_x, gy - 2.0)
	Fx.smoke(fx_parent, global_position + Vector2(0, -20))
	EventBus.screen_shake.emit(1.5)
	_reset_agent_aim()   # 换位后旧红点/连射作废（wp7）


## 诱导尸群：在玩家身边 ±110px 落地 1-2 只普通僵尸（alert 直接锁定玩家）。
func _summon_zombie_wave() -> void:
	_summon_cd = 18.0
	if level == null:
		return
	var player: Node2D = level.get_player()
	if player == null or not is_instance_valid(player):
		return
	var count := 1 + (randi() % 2)
	var width: float = level.level_width
	var spawned := 0
	for i in count:
		var x := clampf(player.global_position.x + randf_range(-110.0, 110.0),
			80.0, maxf(100.0, width - 80.0))
		var gy: float = level.get_ground_y(x)
		if gy < 0.0:
			continue
		level._spawn_zombie(&"common", Vector2(x, gy - 2.0), true)
		spawned += 1
	if spawned > 0:
		EventBus.notify.emit("信号局特工：诱导尸群！")
		EventBus.zombie_scream.emit(global_position, 300.0)


# --- wp7（P2-8）：特工对玩家距离分带战术 ---------------------------------------
## 分带：≤400px 走通用交战；400-600px 游走 + 周期架枪（1s 红点前摇）→ 三连点射；
##       >600px 收枪巡逻（慢速游走、不射击、不出红点）。僵尸目标优先级高于分带。
## 敌意门控与 _acquire_target 一致：FactionManager.unit_wants_to_attack(faction)。
func _agent_move(delta: float) -> float:
	var p: Node2D = level.get_player() if level != null else null
	if p == null or not is_instance_valid(p) or bool(p.get("is_dead")) \
			or not FactionManager.unit_wants_to_attack(faction):
		_reset_agent_aim()
		return _generic_move()
	# 僵尸近身时优先处理僵尸，回到通用交战（不回退 wp6 之前的僵尸索敌行为）
	if target != null and is_instance_valid(target) and target.is_in_group("zombies"):
		_reset_agent_aim()
		return _generic_move()
	var pdist := global_position.distance_to(p.global_position)
	if pdist <= AGENT_WANDER_RANGE:
		_reset_agent_aim()
		return _generic_move()
	if pdist > AGENT_HOLSTER_RANGE:
		_reset_agent_aim()
		return _agent_patrol(delta)
	return _agent_aim_burst(delta, p)


## >600px：收枪巡逻——慢速往返游走，不架枪不射击。
func _agent_patrol(delta: float) -> float:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.4, 2.6)
		_wander_dir = -1.0 if randf() < 0.5 else 1.0
	facing = 1 if _wander_dir > 0 else -1
	return _wander_dir * 0.7   # 巡逻速度约为交战移速 70%


## 400-600px：游走 + 周期架枪。前摇 1s（红点跟随玩家）→ 站定三连点射 → 冷却循环。
func _agent_aim_burst(delta: float, p: Node2D) -> float:
	facing = 1 if p.global_position.x > global_position.x else -1
	if _aim_state == 2:
		# 三连射中：站定连发，可见曳光由 _shoot_at 内 Fx.tracer 保证
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = AGENT_BURST_GAP
			_burst_left -= 1
			_shoot_at(p)
			if _burst_left <= 0:
				_reset_agent_aim()
		return 0.0
	if _aim_state == 1:
		# 1s 前摇：红点持续锁定玩家胸口，特工站定架枪
		_aim_timer -= delta
		if _red_dot != null and is_instance_valid(_red_dot):
			_red_dot.global_position = p.global_position + Vector2(0, -14.0)
			_red_dot.modulate.a = 0.55 + 0.45 * absf(sin(_aim_timer * 12.0))
		if _aim_timer <= 0.0:
			_aim_state = 2
			_burst_left = AGENT_BURST_COUNT
			_burst_timer = 0.0
		return 0.0
	# 游走期：左右换向，倒计时归零进入架枪前摇
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(1.0, 2.0)
		_wander_dir = -1.0 if randf() < 0.5 else 1.0
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_state = 1
		_aim_timer = AGENT_AIM_TELEGRAPH
		_agent_show_red_dot(p)
		return 0.0
	return _wander_dir


func _agent_show_red_dot(p: Node2D) -> void:
	var parent: Node = level.fx_layer if level.fx_layer != null else level
	if parent == null:
		return
	_red_dot = Sprite2D.new()
	_red_dot.texture = SpriteLibrary.ui_texture("crosshair")
	_red_dot.modulate = Color(1.0, 0.15, 0.15, 0.9)
	_red_dot.scale = Vector2(0.9, 0.9)
	_red_dot.z_index = 31
	parent.add_child(_red_dot)
	_red_dot.global_position = p.global_position + Vector2(0, -14.0)


## 清空架枪状态（红点 / 连射计数），重置架枪周期计时。
func _reset_agent_aim() -> void:
	if _red_dot != null and is_instance_valid(_red_dot):
		_red_dot.queue_free()
	_red_dot = null
	if _aim_state != 0:
		_aim_state = 0
		_burst_left = 0
		_aim_timer = randf_range(1.0, 2.5)


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
	_shoot_at(target)


## 朝指定目标开一枪（wp7：从 _shoot 拆出以便三连点射直射玩家；曳光可见）。
func _shoot_at(t: Node2D) -> void:
	var origin := global_position + Vector2(facing * 10.0, -18.0)
	var aim := (t.global_position + Vector2(0, -14) - origin).normalized()
	var result := _ray(origin, aim, SHOOT_RANGE)
	var end := origin + aim * SHOOT_RANGE
	if not result.is_empty():
		end = result["position"]
		var collider: Object = result["collider"]
		if collider.has_method("apply_damage"):
			collider.apply_damage(DAMAGE, -aim, false, faction, &"bullet")
			if collider != t and collider.is_in_group("zombies"):
				Fx.blood(level.fx_layer if level != null else null, end, aim)
			elif collider == t:
				Fx.blood(level.fx_layer if level != null else null, end, aim)
		elif collider.is_in_group("player"):
			# 玩家只有 take_damage（无 apply_damage）：旧 _shoot 对玩家命中实际不掉血，
			# wp7 起特工子弹对玩家生效
			collider.call("take_damage", DAMAGE, aim, faction, &"bullet")
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
	# wp6：特工受击瞬移换位（仅存活时）
	if health > 0 and kind == &"agent" and _blink_cd <= 0.0 and level != null:
		_agent_blink(from_dir)
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
	# wp6：特工死亡反制——一次大范围干扰爆发（4s）+ 屏幕震动
	if kind == &"agent":
		_reset_agent_aim()
		# wp7（P2-8）：被击杀掉落弹药（复用关卡 _spawn_pickup，玩家拾取 +90 备弹）
		if level != null:
			level.call("_spawn_pickup", "ammo", global_position + Vector2(0, -12.0), 90)
		EventBus.notify.emit("信号局特工：信号反制爆发！")
		EventBus.screen_shake.emit(4.0)
		_agent_interference(4.0)
