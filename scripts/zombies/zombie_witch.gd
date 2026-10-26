class_name ZombieWitch
extends ZombieBase
## Witch: kneels passively until startled. A clean headshot while kneeling
## crowns her instantly; otherwise she screams and cuts the squad apart.

var state: String = "kneel"
var scream_timer: float = 0.0
var windup: float = 0.0
var _crown_emitted: bool = false


func _ready() -> void:
	super()
	state = "kneel"
	state_name = "kneel"
	alerted = false
	_play_anim("idle")
	EventBus.gunshot.connect(_on_gunshot)


func _ai_tick(delta: float) -> void:
	if not alerted:
		state_name = "kneel"
		_play_anim("idle")
		if target != null and is_instance_valid(target):
			var dist := distance_to_target()
			var player: Node = level.get_player() if level else null
			var lit := player != null and bool(player.get("flashlight_on"))
			if dist < 92.0 or (lit and dist < 230.0):
				_wake()
		return
	match state:
		"scream":
			stop_horizontal(delta)
			_play_anim("scream")
			scream_timer -= delta
			if scream_timer <= 0.0:
				state = "chase"
		"chase":
			_tick_chase(delta)
		"attack":
			_tick_attack(delta)


func _tick_chase(delta: float) -> void:
	face_toward_target()
	if distance_to_target() < 62.0 and absf(target.global_position.y - global_position.y) < 54.0:
		state = "attack"
		windup = 0.25
		stop_horizontal(delta)
		_play_anim("attack")
		return
	chase_target(delta, 1.0, "chase")


func _tick_attack(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("attack")
	if windup > 0.0:
		return
	if target != null and is_instance_valid(target) and distance_to_target() < 74.0:
		if target.has_method("take_damage"):
			target.take_damage(data.attack_damage, Vector2.ZERO, &"zombie", &"melee")
		EventBus.shake(5.0)
		EventBus.hitstop.emit(0.05)
		AudioManager.play_sfx_2d(&"witch_attack", global_position, 1100.0)
	state = "chase"
	attack_cooldown = data.attack_interval


func _wake() -> void:
	if alerted:
		return
	alerted = true
	state = "scream"
	state_name = "scream"
	scream_timer = 0.75
	_play_anim("scream")
	AudioManager.play_sfx_2d(&"witch_scream", global_position, 1400.0, 2.0)
	EventBus.witch_woken.emit(global_position)
	EventBus.notify.emit("你惊动了 WITCH！")
	EventBus.shake(3.0)
	if level:
		level.record_witch_woken()
		level.alert_commons_near(global_position, 140.0)


func _on_gunshot(pos: Vector2, _loudness: float) -> void:
	if not alerted and global_position.distance_to(pos) < 190.0:
		_wake()


func is_headshot_point(point: Vector2) -> bool:
	return not alerted and point.y < global_position.y - data.collision_size.y * 0.62


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if not alerted:
		if is_head and amount >= 45:
			_crown_emitted = true
			EventBus.witch_crowned.emit(global_position)
			EventBus.notify.emit("CROWNING！一枪爆头终结了 Witch")
			EventBus.shake(4.0)
			AudioManager.play_sfx_2d(&"witch_crowned", global_position, 1200.0)
			_die(source, true)
			return
		_wake()
	super(amount, from_dir, is_head, source, damage_type)
	if alerted and not dead:
		EventBus.boss_health_changed.emit(health, max_health)


func _on_death_effect() -> void:
	if level:
		Fx.blood(level.fx_layer, global_position + Vector2(0, -18), Vector2.UP, 1.8)
	EventBus.boss_health_changed.emit(0, max_health)
