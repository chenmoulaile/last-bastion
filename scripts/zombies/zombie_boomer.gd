class_name ZombieBoomer
extends ZombieBase
## Boomer: waddles toward the squad and bursts, covering nearby survivors in
## bile and calling a horde. Shooting it at range still triggers the burst.

var state: String = "approach"
var windup: float = 0.0
var exploded: bool = false


func _ready() -> void:
	super()
	voice_timer = randf_range(1.0, 3.0)


func _ai_tick(delta: float) -> void:
	if exploded:
		return
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	face_toward_target()
	if state == "inflate":
		stop_horizontal(delta)
		_play_anim("inflate")
		windup -= delta
		if windup <= 0.0:
			_explode()
			_die(&"player", false)
		return
	if distance_to_target() < 62.0 and has_line_of_sight_to_target():
		state = "inflate"
		state_name = "inflate"
		windup = 0.7
		stop_horizontal(delta)
		_play_anim("inflate")
		AudioManager.play_sfx_2d(&"boomer_burp", global_position, 900.0)
		return
	chase_target(delta, 1.0, "run")


func _explode() -> void:
	if exploded:
		return
	exploded = true
	var fx_parent: Node = level.fx_layer if level else get_parent()
	Fx.bile(fx_parent, global_position + Vector2(0, -14), 1.6)
	Fx.bile(fx_parent, global_position + Vector2(-18, -6), 1.1)
	Fx.bile(fx_parent, global_position + Vector2(20, -18), 1.2)
	AudioManager.play_sfx_2d(&"boomer_explode", global_position, 1000.0)
	EventBus.bile_splashed.emit(4.5)
	if level:
		var player: Node = level.get_player()
		if player and is_instance_valid(player) and not bool(player.get("is_dead")):
			if player.global_position.distance_to(global_position) < 150.0:
				player.apply_bile(5.0)
		for ally in level.get_allies():
			if ally and is_instance_valid(ally) and ally.global_position.distance_to(global_position) < 120.0:
				if ally.has_method("apply_bile"):
					ally.apply_bile(3.0)
		level.spawn_horde_at(global_position, 12, true)
		level.record_boomer_burst()
	EventBus.notify.emit("Boomer 爆了——尸潮被胆汁吸引！")
	EventBus.shake(3.0)


func _on_death_effect() -> void:
	_explode()
