class_name ZombieArmoredCar
extends ZombieBase
## 1-3 Boss「改装装甲车」：移动 Boss，轮胎 ×4 弱点 + 油箱。
## 简化实现：高护甲（非弱点期间 85% 减伤），周期性冲撞，冲撞后短暂抛锚暴露弱点。
## 弱点轮换：每受到 12 次有效命中暴露「轮胎」，轮胎阶段受到的伤害 ×4。

var _hits_since_exposed: int = 0
var _exposed: bool = false
var _expose_timer: float = 0.0
var _charge_cd: float = 4.0
var _weakpoint_cycle: int = 0  # 0=履带 1=油箱
var _charging: float = 0.0


func _ai_tick(delta: float) -> void:
	if _exposed:
		_expose_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)
		if _expose_timer <= 0.0:
			_exposed = false
		if sprite and sprite.animation != "hurt":
			sprite.play("hurt")
		move_and_slide()
		return
	_charge_cd -= delta
	if _charge_cd <= 0.0 and target != null and is_instance_valid(target):
		_charging = 1.1
		_charge_cd = 7.0
		velocity.x = facing * 520.0
		AudioManager.play_sfx(&"horde_growl", 1.0, -4.0)
	if _charging > 0.0:
		_charging -= delta
		velocity.x = facing * 520.0
		if absf(velocity.x) < 60.0 and is_on_wall():
			_charging = 0.0
			_exposed = true
			_expose_timer = 3.0
			EventBus.notify.emit("装甲车抛锚——攻击轮胎！")
		move_and_slide()
		return
	if target != null and is_instance_valid(target):
		facing = 1 if target.global_position.x > global_position.x else -1
	var speed := data.walk_speed_max
	velocity.x = move_toward(velocity.x, speed * float(facing), 500.0 * delta)
	_play_anim("run")
	move_and_slide()


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"melee") -> void:
	if _exposed:
		super.apply_damage(amount * 4, from_dir, is_head, source, damage_type)
		return
	_hits_since_exposed += 1
	if _hits_since_exposed >= 12:
		_hits_since_exposed = 0
		_exposed = true
		_expose_timer = 2.5
		_weakpoint_cycle = (_weakpoint_cycle + 1) % 2
		EventBus.notify.emit("弱点暴露——打击%s！" % ("油箱" if _weakpoint_cycle == 1 else "履带"))
	super.apply_damage(int(amount * 0.15), from_dir, is_head, source, damage_type)
