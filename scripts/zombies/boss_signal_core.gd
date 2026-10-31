class_name ZombieSignalCore
extends ZombieBase
## 4-2 最终 Boss「信号核心 AI 管理员」：三阶段形态，吸收场景尸体回血，
## 周期召唤僵尸，战斗期间施加信号干扰特效。死亡触发最终抉择。

var _phase: int = 1
var _summon_cd: float = 4.0
var _absorb_cd: float = 3.0


func _ready() -> void:
	super._ready()
	EventBus.signal_interference.emit(true)


func _exit_tree() -> void:
	if is_instance_valid(self) and not dead:
		EventBus.signal_interference.emit(false)


func _ai_tick(delta: float) -> void:
	var ratio := float(health) / float(max_health)
	var new_phase := 1
	if ratio < 0.33:
		new_phase = 3
	elif ratio < 0.66:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		EventBus.notify.emit("信号核心：形态切换 —— 阶段 %d" % _phase)
		EventBus.screen_shake.emit(5.0)
		if sprite:
			sprite.modulate = [Color.WHITE, Color(1.15, 0.9, 1.1), Color(1.3, 0.6, 0.7)][_phase - 1]
	velocity.x = 0.0
	_summon_cd -= delta
	if _summon_cd <= 0.0 and level != null:
		_summon_cd = 5.0 - float(_phase)
		var count := _phase
		for i in count:
			var side := -1.0 if randf() < 0.5 else 1.0
			var x: float = clampf(global_position.x + side * randf_range(120.0, 300.0), 60.0, 4000.0)
			level.call("spawn_horde_at", Vector2(x, level.call("get_ground_y", x) - 2.0), 1, true)
	_absorb_cd -= delta
	if _absorb_cd <= 0.0:
		_absorb_cd = 3.0
		# P2-14: 吸收 260px 内的尸体登记点（每具 +2% 上限生命）；玩家射击尸体点可销毁
		if level != null and level.has_method("consume_corpse_near"):
			var consumed: int = 0
			for i in _phase:
				if level.call("consume_corpse_near", global_position, 260.0):
					consumed += 1
			if consumed > 0:
				health = mini(max_health, health + int(max_health * 0.02) * consumed)
				Fx.blood(level.fx_layer if level != null else null, global_position + Vector2(0, -30), Vector2.DOWN, 0.6)
				EventBus.notify.emit("信号核心吸收了尸体！射击尸体阻止回血")
	_play_anim("idle")


func _on_death_effect() -> void:
	EventBus.signal_interference.emit(false)
	super._on_death_effect()
