class_name ZombieCharger
extends ZombieBase
## Charger：普通特感保持「冲锋-扑倒锤击」行为；wp7 起 l07/l08 关卡的 charger
## 由 LEVEL_CFG 命中（泵站迫击兽 / 净化区处刑者）走 BossEngine boss 模式——
## 普通 charger 只出现在 l09/l10/l11 的 special_weights（不在 boss 化关卡表内），
## 行为不受影响。

var state: String = "approach"
var windup: float = 0.0
var charge_time: float = 0.0
var pound_time: float = 0.0
var pound_damage_timer: float = 0.0
var charge_cooldown: float = 0.0

var _mind: RefCounted = null
var _bcfg: Dictionary = {}


func _ready() -> void:
	super()
	# 仅 l07/l08（LEVEL_CFG 命中且 kind==charger 会被 level_runner 注册为 boss）
	# 走 boss 模式；其余关卡 charger 是普通特感（如 l09/l10/l11 的 special_weights）
	var lid := ""
	if level != null and level.get("data") != null:
		lid = String(level.data.id)
	if lid in ["l07", "l08"]:
		_bcfg = BossEngine.setup(self)
	if _bcfg.is_empty():
		charge_cooldown = randf_range(1.5, 3.0)


func _ai_tick(delta: float) -> void:
	if _mind != null:
		BossEngine.tick(self, delta)
		return
	if target == null or not is_instance_valid(target):
		_wander(delta)
		return
	charge_cooldown = maxf(0.0, charge_cooldown - delta)
	if pinning:
		_tick_pound(delta)
		return
	match state:
		"windup":
			_tick_windup(delta)
		"charge":
			_tick_charge(delta)
		"recover":
			_tick_recover(delta)
		_:
			_tick_approach(delta)


func _tick_approach(delta: float) -> void:
	face_toward_target()
	var dist := distance_x_to_target()
	if dist < 48.0 and absf(target.global_position.y - global_position.y) < 44.0:
		stop_horizontal(delta)
		_play_anim("punch")
		if attack_cooldown <= 0.0:
			_attack_target()
		return
	if dist > 110.0 and dist < data.pounce_range and charge_cooldown <= 0.0 \
			and absf(target.global_position.y - global_position.y) < 60.0 \
			and has_line_of_sight_to_target():
		state = "windup"
		state_name = "windup"
		windup = 0.55
		stop_horizontal(delta)
		_play_anim("idle")
		AudioManager.play_sfx_2d(&"charger_roar", global_position, 1000.0)
		return
	chase_target(delta, 1.0, "run")


func _tick_windup(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	face_toward_target()
	if windup <= 0.0:
		state = "charge"
		state_name = "charge"
		charge_time = 0.9
		velocity.x = data.walk_speed_max * 2.6 * float(facing)
		_play_anim("charge")
		AudioManager.play_sfx_2d(&"charger_charge", global_position, 900.0)


func _tick_charge(delta: float) -> void:
	charge_time -= delta
	velocity.x = data.walk_speed_max * 2.6 * float(facing)
	_play_anim("charge")
	if target != null and is_instance_valid(target) and not bool(target.get("is_controlled")):
		if distance_to_target() < 40.0:
			_start_pound()
			return
	if charge_time <= 0.0 or is_on_wall():
		state = "recover"
		windup = 1.0
		velocity.x = 0.0
		_play_anim("idle")
		if is_on_wall():
			EventBus.shake(2.5)
			AudioManager.play_sfx_2d(&"charger_impact", global_position, 900.0)


func _start_pound() -> void:
	if target == null or not is_instance_valid(target):
		return
	target.enter_control(&"pound", self)
	if not bool(target.get("is_controlled")):
		state = "recover"
		windup = 0.8
		return
	pinning = true
	pound_time = 4.5
	pound_damage_timer = 0.5
	state = "pound"
	state_name = "pound"
	velocity = Vector2.ZERO
	_play_anim("punch")
	EventBus.ally_pinned.emit(target)
	EventBus.shake(4.0)
	AudioManager.play_sfx_2d(&"charger_pound", global_position, 1000.0)


func _tick_pound(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target_is_controlled_by_me():
		release_controlled_target()
		state = "recover"
		windup = 0.8
		return
	global_position = target.global_position + Vector2(float(facing) * -18.0, 0)
	velocity = Vector2.ZERO
	_play_anim("punch")
	pound_time -= delta
	pound_damage_timer -= delta
	if pound_damage_timer <= 0.0:
		pound_damage_timer = 0.9
		if target.has_method("take_damage"):
			target.take_damage(data.attack_damage, Vector2.ZERO, &"zombie", &"melee")
		EventBus.shake(2.0)
		AudioManager.play_sfx_2d(&"charger_pound", global_position, 900.0)
	if pound_time <= 0.0:
		var victim := target
		release_controlled_target()
		EventBus.ally_unpinned.emit(victim)
		state = "recover"
		windup = 1.2
		EventBus.notify.emit("Charger 松手了")


func _tick_recover(delta: float) -> void:
	stop_horizontal(delta)
	windup -= delta
	_play_anim("idle")
	if windup <= 0.0:
		state = "approach"
		charge_cooldown = randf_range(3.0, 5.0)


func on_melee_interrupt() -> bool:
	if _mind != null:
		return false
	if pinning:
		var victim := target
		release_controlled_target()
		if victim:
			EventBus.ally_unpinned.emit(victim)
		state = "recover"
		windup = 1.1
		apply_stagger(0.8)
		return true
	if state == "charge":
		state = "recover"
		windup = 1.0
		velocity.x = 0.0
		apply_stagger(0.5)
		return true
	return false


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if _mind != null:
		amount = BossEngine.mitigate(self, amount, from_dir, damage_type)
		if amount <= 0:
			return
	super(amount, from_dir, is_head, source, damage_type)
	if not dead and _mind != null:
		BossEngine.on_damaged(self)


func _on_death_effect() -> void:
	if _mind != null:
		BossEngine.on_death(self)
		return
	release_controlled_target()
	EventBus.shake(3.0)
