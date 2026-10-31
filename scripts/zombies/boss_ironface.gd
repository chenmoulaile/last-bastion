class_name ZombieIronface
extends ZombieBase
## 3-3 Boss「铁面」安保指挥官：正面完全免伤（需绕后或爆炸物），二阶段丢盾狂暴，
## 周期召唤无人机（简化为召唤普通感染者增援）。

var _enraged: bool = false


func _ai_tick(delta: float) -> void:
	if not _enraged and health < max_health * 0.5:
		_enraged = true
		EventBus.notify.emit("铁面丢弃盾牌——进入狂暴！")
		EventBus.screen_shake.emit(4.0)
		if sprite:
			sprite.modulate = Color(1.25, 0.85, 0.85)
	if target != null and is_instance_valid(target):
		facing = 1 if target.global_position.x > global_position.x else -1
	var speed := data.walk_speed_max * (1.35 if _enraged else 0.85)
	velocity.x = move_toward(velocity.x, speed * float(facing), 700.0 * delta)
	_try_jump_for_target(target.global_position - global_position if target != null else Vector2.ZERO)
	_try_attack_door()
	_play_anim("run")


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"melee") -> void:
	# 正面免伤：伤害方向与自身朝向相反（从正面打来）时无效，爆炸物除外。
	if not _enraged and damage_type != &"explosion" and damage_type != &"fire" \
			and signf(from_dir.x) == signf(float(facing)):
		Fx.spark(level.fx_layer if level else null, global_position + Vector2(facing * 14.0, -20.0))
		AudioManager.play_sfx(&"ricochet")
		return
	super.apply_damage(amount, from_dir, is_head, source, damage_type)


func _on_death_effect() -> void:
	# 铁面临死台词由 level_runner 的 boss_killed 流程接管（剧情对话）。
	super._on_death_effect()
