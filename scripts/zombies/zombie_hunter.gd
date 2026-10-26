class_name ZombieHunter
extends ZombieBase
## Hunter: stalks at speed, screams, then leaps in a long arc. A successful
## pounce pins the victim until a teammate interrupts the Hunter.

var state: String = "stalk"
var windup: float = 0.0
var pounce_time: float = 0.0
var pin_time: float = 0.0
var pin_damage_timer: float = 0.0
var pounce_cooldown: float = 0.0


func _ready() -> void:
	super()
	pounce_cooldown = randf_range(2.0, 4.5)


func _ai_tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	pounce_cooldown = maxf(0.0, pounce_cooldown - delta)
	if pinning:
		_tick_pin(delta)
		return
	match state:
		"windup":
			_tick_windup(delta)
		"pounce":
			_tick_pounce(delta)
		"recover":
			_tick_recover(delta)
		_:
			_tick_stalk(delta)


func _tick_stalk(delta: float) -> void:
	face_toward_target()
	var dist_x := distance_x_to_target()
	var dist_y := absf(target.global_position.y - global_position.y)
	if dist_x < 54.0 and dist_y < 44.0:
		state_name = "attack"
		stop_horizontal(delta)
		_play_anim("attack")
		if attack_cooldown <= 0.0:
			_attack_target()
		return
	if dist_x < data.pounce_range and dist_y < 190.0 and is_on_floor() \
			and pounce_cooldown <= 0.0 and has_line_of_sight_to_target():
		state = "windup"
		state_name = "windup"
		windup = 0.65
		stop_horizontal(delta)
		_play_anim("idle")
		AudioManager.play_sfx_2d(&"hunter_scream", global_position, 1100.0, -2.0)
		EventBus.zombie_scream.emit(global_position, 110.0)
		if level:
			level.alert_commons_near(global_position, 100.0)
		return
	chase_target(delta, 1.0, "run")


func _tick_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup > 0.0:
		return
	if target == null or not is_instance_valid(target):
		state = "stalk"
		return
	var to_target := target.global_position - global_position
	var dir := to_target.normalized()
	velocity = Vector2(dir.x * 430.0, -410.0)
	pounce_time = 0.0
	state = "pounce"
	state_name = "pounce"
	pounce_cooldown = 5.0
	_play_anim("pounce")
	AudioManager.play_sfx_2d(&"hunter_pounce", global_position, 900.0, -3.0)


func _tick_pounce(delta: float) -> void:
	pounce_time += delta
	_play_anim("pounce")
	if target != null and is_instance_valid(target) and not bool(target.get("is_controlled")):
		if distance_to_target() < 36.0 and pounce_time > 0.14:
			_start_pin()
			return
	if (is_on_floor() and pounce_time > 0.18) or pounce_time > 1.5 or is_on_wall():
		state = "recover"
		state_name = "recover"
		windup = 0.8
		_play_anim("idle")
		AudioManager.play_sfx_2d(&"zombie_land", global_position, 500.0)


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	if windup <= 0.0:
		state = "stalk"


func _start_pin() -> void:
	if target == null or not is_instance_valid(target):
		return
	target.enter_control(&"pin", self)
	if not bool(target.get("is_controlled")):
		state = "recover"
		windup = 0.8
		return
	pinning = true
	pin_time = 6.0
	pin_damage_timer = 0.4
	state = "pin"
	state_name = "pin"
	velocity = Vector2.ZERO
	_play_anim("pin")
	EventBus.ally_pinned.emit(target)
	AudioManager.play_sfx_2d(&"hunter_pin", global_position, 800.0)


func _tick_pin(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target_is_controlled_by_me():
		release_controlled_target()
		state = "recover"
		windup = 0.6
		return
	global_position = target.global_position + Vector2(0, 1)
	velocity = Vector2.ZERO
	_play_anim("pin")
	pin_time -= delta
	pin_damage_timer -= delta
	if pin_damage_timer <= 0.0:
		pin_damage_timer = 0.8
		if target.has_method("take_damage"):
			target.take_damage(data.attack_damage, Vector2.ZERO, &"zombie", &"melee")
	if pin_time <= 0.0:
		release_controlled_target()
		state = "recover"
		windup = 1.0
		EventBus.ally_unpinned.emit(target)
		EventBus.notify.emit("受害者挣脱了猎手")


func on_melee_interrupt() -> bool:
	var was_active := pinning or state == "pounce"
	if pinning:
		var victim := target
		release_controlled_target()
		if victim:
			EventBus.ally_unpinned.emit(victim)
	state = "recover"
	windup = 1.1
	state_name = "recover"
	apply_stagger(0.7)
	return was_active


func is_pounce_active() -> bool:
	return state == "pounce" or pinning


func _on_death_effect() -> void:
	release_controlled_target()
	Fx.smoke(level.fx_layer if level else get_parent(), global_position + Vector2(0, -10), 0.8)
