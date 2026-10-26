class_name ZombieTank
extends ZombieBase
## Tank: boss infected. Heavy punches, thrown debris, a huge health pool and an
## enrage phase below 30% health. It ignores knockback and stagger.

var state: String = "chase"
var windup: float = 0.0
var throw_cooldown: float = 0.0
var enraged: bool = false
var _roared: bool = false


func _ready() -> void:
	super()
	throw_cooldown = randf_range(2.5, 4.0)
	AudioManager.play_sfx_2d(&"tank_bell", global_position, 1400.0, 2.0)
	EventBus.shake(5.0)


func _ai_tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	throw_cooldown = maxf(0.0, throw_cooldown - delta)
	var health_ratio := float(health) / float(maxi(1, max_health))
	if health_ratio < 0.3 and not enraged:
		enraged = true
		AudioManager.play_sfx_2d(&"tank_roar", global_position, 1400.0, 2.0)
		EventBus.shake(4.0)
		EventBus.notify.emit("TANK 暴怒了！")
		EventBus.level_event.emit("TANK 进入暴怒")
	match state:
		"punch_windup":
			_tick_punch_windup(delta)
		"punch":
			_tick_punch(delta)
		"throw_windup":
			_tick_throw_windup(delta)
		"recover":
			_tick_recover(delta)
		_:
			_tick_chase(delta)


func _tick_chase(delta: float) -> void:
	face_toward_target()
	var dist := distance_to_target()
	if dist < 74.0 and absf(target.global_position.y - global_position.y) < 70.0:
		state = "punch_windup"
		state_name = "punch_windup"
		windup = 0.42
		stop_horizontal(delta)
		_play_anim("punch")
		AudioManager.play_sfx_2d(&"tank_roar", global_position, 1200.0, -4.0)
		return
	if dist > 130.0 and dist < 680.0 and throw_cooldown <= 0.0 and has_line_of_sight_to_target():
		state = "throw_windup"
		state_name = "throw_windup"
		windup = 0.6
		stop_horizontal(delta)
		_play_anim("throw")
		return
	var speed := 1.0
	if enraged:
		speed = 1.35
	chase_target(delta, speed, "run")


func _tick_punch_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup <= 0.0:
		state = "punch"
		state_name = "punch"
		windup = 0.22
		velocity.x = float(facing) * 120.0
		_play_anim("punch")
		_tank_punch()


func _tick_punch(delta: float) -> void:
	windup -= delta
	stop_horizontal(delta)
	if windup <= 0.0:
		state = "recover"
		windup = 0.75 if not enraged else 0.55


func _tank_punch() -> void:
	if level == null:
		return
	var hit_any := false
	for body in level.get_damageable_near(global_position, 88.0):
		if body == self:
			continue
		var dir: Vector2 = (body.global_position - global_position).normalized()
		if body.has_method("take_damage"):
			body.take_damage(data.attack_damage, dir, &"zombie", &"melee")
			hit_any = true
		if body.has_method("apply_knockback"):
			body.apply_knockback(Vector2(dir.x * 260.0, -260.0))
	Fx.explosion(level.fx_layer, global_position + Vector2(float(facing) * 30.0, -6), 0.9)
	AudioManager.play_sfx_2d(&"tank_punch", global_position, 1200.0, 0.0)
	EventBus.shake(6.0)
	if hit_any:
		EventBus.hitstop.emit(0.05)


func _tick_throw_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup <= 0.0:
		var aim := target.global_position + Vector2(0, -12)
		if target is CharacterBody2D:
			aim += (target as CharacterBody2D).velocity * 0.35
		if level:
			level.spawn_tank_rock(global_position + Vector2(float(facing) * 26.0, -42.0), aim)
		throw_cooldown = 5.5 if not enraged else 4.0
		state = "recover"
		windup = 0.7
		_play_anim("idle")


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("idle")
	if windup <= 0.0:
		state = "chase"


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	super(amount, from_dir, is_head, source, damage_type)
	if not dead:
		EventBus.boss_health_changed.emit(health, max_health)


func _on_death_effect() -> void:
	if level:
		Fx.explosion(level.fx_layer, global_position + Vector2(0, -24), 1.8)
		Fx.blood(level.fx_layer, global_position + Vector2(0, -24), Vector2.UP, 2.0)
		EventBus.shake(7.0)
		AudioManager.set_tank_active(false)
		level.drop_boss_loot(global_position)
	EventBus.boss_health_changed.emit(0, max_health)
