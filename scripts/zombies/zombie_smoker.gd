class_name ZombieSmoker
extends ZombieBase
## Smoker: keeps its distance and yanks a survivor with a long tongue. The
## victim is dragged toward the Smoker until it is killed or the tongue breaks.

var state: String = "approach"
var windup: float = 0.0
var tongue_time: float = 0.0
var tongue_damage_timer: float = 0.0
var tongue_cooldown: float = 0.0
var damage_since_grab: int = 0
var tongue_line: Line2D


func _ready() -> void:
	super()
	tongue_cooldown = randf_range(2.5, 5.0)
	tongue_line = Line2D.new()
	tongue_line.width = 2.0
	tongue_line.default_color = Color(0.78, 0.52, 0.58, 0.95)
	tongue_line.z_index = 7
	tongue_line.visible = false
	add_child(tongue_line)


func _ai_tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	tongue_cooldown = maxf(0.0, tongue_cooldown - delta)
	if pinning:
		_tick_tongue(delta)
		return
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
	var can_attack := dist < data.sight_range and absf(target.global_position.y - global_position.y) < 160.0
	if can_attack and tongue_cooldown <= 0.0 and has_line_of_sight_to_target() \
			and not bool(target.get("is_controlled")):
		state = "windup"
		state_name = "windup"
		windup = 0.5
		stop_horizontal(delta)
		_play_anim("attack")
		AudioLayerManager.play_spatial_sfx(&"smoker_cough", global_position, 900.0, -2.0)
		return
	# Prefer a mid-range pocket, but keep advancing if the target escapes.
	if dist > 260.0:
		chase_target(delta, 1.0, "run")
	elif dist < 130.0:
		facing = -1 if target.global_position.x > global_position.x else 1
		if sprite:
			sprite.flip_h = facing < 0
		velocity.x = move_toward(velocity.x, data.walk_speed_max * float(facing), 500.0 * delta)
		_play_anim("run")
	else:
		stop_horizontal(delta)
		_play_anim("idle")


func _tick_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup > 0.0:
		return
	if target == null or not is_instance_valid(target) or bool(target.get("is_controlled")):
		state = "recover"
		windup = 0.6
		return
	var from := global_position + Vector2(float(facing) * 10.0, -24.0)
	var to := target.global_position + Vector2(0, -16)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1, [get_rid()])
	if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		state = "recover"
		windup = 0.8
		return
	target.enter_control(&"tongue", self)
	if not bool(target.get("is_controlled")):
		state = "recover"
		windup = 0.8
		return
	pinning = true
	tongue_time = 5.5
	tongue_damage_timer = 0.8
	damage_since_grab = 0
	state = "tongue"
	state_name = "tongue"
	tongue_line.visible = true
	AudioLayerManager.play_spatial_sfx(&"smoker_tongue", global_position, 900.0)
	EventBus.ally_pinned.emit(target)


func _tick_tongue(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target_is_controlled_by_me():
		_release_tongue()
		return
	tongue_time -= delta
	tongue_damage_timer -= delta
	_play_anim("attack")
	var mouth := global_position + Vector2(float(facing) * 10.0, -24.0)
	var target_pos := target.global_position + Vector2(0, -14)
	tongue_line.points = PackedVector2Array([mouth - global_position, target_pos - global_position])
	# Drag the victim toward the Smoker.
	var pull_to := global_position + Vector2(float(facing) * 18.0, 0)
	target.global_position = target.global_position.move_toward(pull_to, 115.0 * delta)
	if tongue_damage_timer <= 0.0:
		tongue_damage_timer = 0.9
		if target.has_method("take_damage"):
			target.take_damage(data.attack_damage, Vector2.ZERO, &"zombie", &"melee")
	if tongue_time <= 0.0 or global_position.distance_to(target.global_position) < 28.0:
		_release_tongue()
		state = "recover"
		windup = 0.7


func _release_tongue() -> void:
	if pinning:
		var victim := target
		release_controlled_target()
		if victim and is_instance_valid(victim):
			EventBus.ally_unpinned.emit(victim)
		EventBus.notify.emit("舌头断了")
	pinning = false
	if tongue_line:
		tongue_line.visible = false
		tongue_line.points = PackedVector2Array()


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("idle")
	if windup <= 0.0:
		state = "approach"
		tongue_cooldown = randf_range(3.5, 5.5)


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	super(amount, from_dir, is_head, source, damage_type)
	if pinning:
		damage_since_grab += amount
		if damage_since_grab >= 55 or health <= 0:
			_release_tongue()
			state = "recover"
			windup = 0.6


func on_melee_interrupt() -> bool:
	if pinning:
		_release_tongue()
		state = "recover"
		windup = 1.0
		apply_stagger(0.6)
		return true
	return false


func _on_death_effect() -> void:
	_release_tongue()
	if level:
		Fx.smoke(level.fx_layer, global_position + Vector2(0, -14), 1.4)
		Fx.smoke(level.fx_layer, global_position + Vector2(-10, -22), 1.0)
		Fx.smoke(level.fx_layer, global_position + Vector2(12, -8), 0.9)
