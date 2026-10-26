class_name ZombieSpitter
extends ZombieBase
## Spitter: keeps its distance and lobs acid at the squad's feet, leaving a
## damaging pool. It is fragile and flees when survivors close in.

var state: String = "approach"
var windup: float = 0.0
var spit_cooldown: float = 0.0


func _ready() -> void:
	super()
	spit_cooldown = randf_range(2.0, 4.0)


func _ai_tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	spit_cooldown = maxf(0.0, spit_cooldown - delta)
	match state:
		"windup":
			_tick_windup(delta)
		"recover":
			_tick_recover(delta)
		_:
			_tick_approach(delta)


func _tick_approach(delta: float) -> void:
	face_toward_target()
	var dist := distance_x_to_target()
	if dist < 115.0:
		facing = -1 if target.global_position.x > global_position.x else 1
		if sprite:
			sprite.flip_h = facing < 0
		velocity.x = move_toward(velocity.x, data.walk_speed_max * float(facing), 600.0 * delta)
		_play_anim("run")
		return
	if dist < 400.0 and absf(target.global_position.y - global_position.y) < 180.0 \
			and spit_cooldown <= 0.0 and has_line_of_sight_to_target():
		state = "windup"
		state_name = "windup"
		windup = 0.55
		stop_horizontal(delta)
		_play_anim("spit")
		AudioManager.play_sfx_2d(&"spitter_hiss", global_position, 900.0)
		return
	if dist > 310.0:
		chase_target(delta, 1.0, "run")
	else:
		stop_horizontal(delta)
		_play_anim("idle")


func _tick_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup > 0.0:
		return
	var mouth := global_position + Vector2(float(facing) * 12.0, -24.0)
	var aim := target.global_position + Vector2(0, -10)
	if target is CharacterBody2D:
		aim += (target as CharacterBody2D).velocity * 0.45
	if level:
		level.spawn_acid_glob(mouth, aim)
	state = "recover"
	windup = 0.7
	spit_cooldown = randf_range(3.6, 5.4)


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("idle")
	if windup <= 0.0:
		state = "approach"


func _on_death_effect() -> void:
	if level:
		level.spawn_acid_zone(global_position + Vector2(0, -4), 54.0, 3.5, 0)
		Fx.acid(level.fx_layer, global_position + Vector2(0, -10))
