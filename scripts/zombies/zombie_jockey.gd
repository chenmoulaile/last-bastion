class_name ZombieJockey
extends ZombieBase
## Jockey: small, fast, and leaps onto a survivor's shoulders. While riding it
## steers the victim toward danger until it is knocked off or killed.

var state: String = "chase"
var leap_time: float = 0.0
var ride_time: float = 0.0
var ride_damage_timer: float = 0.0
var leap_cooldown: float = 0.0
var windup: float = 0.0


func _ready() -> void:
	super()
	leap_cooldown = randf_range(1.0, 2.0)


func _ai_tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	leap_cooldown = maxf(0.0, leap_cooldown - delta)
	if pinning:
		_tick_ride(delta)
		return
	match state:
		"leap":
			_tick_leap(delta)
		"recover":
			_tick_recover(delta)
		_:
			_tick_chase(delta)


func _tick_chase(delta: float) -> void:
	face_toward_target()
	var dist := distance_to_target()
	if dist < 120.0 and leap_cooldown <= 0.0 and not bool(target.get("is_controlled")) \
			and has_line_of_sight_to_target():
		state = "leap"
		state_name = "leap"
		leap_time = 0.7
		var dir := (target.global_position - global_position).normalized()
		velocity = Vector2(dir.x * 300.0, -320.0)
		_play_anim("leap")
		AudioManager.play_sfx_2d(&"jockey_giggle", global_position, 900.0)
		return
	chase_target(delta, 1.0, "run")


func _tick_leap(delta: float) -> void:
	leap_time -= delta
	_play_anim("leap")
	if target != null and is_instance_valid(target) and not bool(target.get("is_controlled")):
		if distance_to_target() < 38.0:
			_start_ride()
			return
	if leap_time <= 0.0 or (is_on_floor() and leap_time < 0.45):
		state = "recover"
		windup = 0.6
		_play_anim("idle")


func _start_ride() -> void:
	if target == null or not is_instance_valid(target):
		return
	target.enter_control(&"ride", self)
	if not bool(target.get("is_controlled")):
		state = "recover"
		windup = 0.6
		return
	pinning = true
	ride_time = 5.5
	ride_damage_timer = 0.7
	state = "ride"
	state_name = "ride"
	velocity = Vector2.ZERO
	_play_anim("ride")
	EventBus.ally_pinned.emit(target)
	AudioManager.play_sfx_2d(&"jockey_ride", global_position, 900.0)
	EventBus.notify.emit("Jockey 骑上了队友！")


func _tick_ride(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target_is_controlled_by_me():
		release_controlled_target()
		state = "recover"
		windup = 0.8
		return
	global_position = target.global_position + Vector2(0, -26)
	velocity = Vector2.ZERO
	_play_anim("ride")
	ride_time -= delta
	ride_damage_timer -= delta
	# Steer the victim forward, toward the level's danger.
	if target is CharacterBody2D:
		target.global_position.x += float(facing) * 82.0 * delta
		var ground: float = level.get_ground_y(target.global_position.x) if level else -1.0
		if ground > 0.0:
			target.global_position.y = ground
	if ride_damage_timer <= 0.0:
		ride_damage_timer = 0.9
		if target.has_method("take_damage"):
			target.take_damage(data.attack_damage, Vector2.ZERO, &"zombie", &"melee")
	if ride_time <= 0.0:
		var victim := target
		release_controlled_target()
		EventBus.ally_unpinned.emit(victim)
		state = "recover"
		windup = 0.8
		EventBus.notify.emit("Jockey 被甩了下来")


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("idle")
	if windup <= 0.0:
		state = "chase"
		leap_cooldown = randf_range(2.5, 4.0)


func on_melee_interrupt() -> bool:
	if pinning:
		var victim := target
		release_controlled_target()
		if victim:
			EventBus.ally_unpinned.emit(victim)
		state = "recover"
		windup = 1.0
		apply_stagger(0.8)
		return true
	if state == "leap":
		state = "recover"
		windup = 0.8
		return true
	return false


func is_pounce_active() -> bool:
	return state == "leap" or pinning


func _on_death_effect() -> void:
	release_controlled_target()
