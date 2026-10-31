class_name ZombieNestMother
extends ZombieBase
## 2-2 Boss「巢穴母体」：墙上固定的巨型孢子囊。营养管 ×4 未摧毁时本体减伤 80%，
## 每 6 秒召唤小僵尸；所有营养管被摧毁后护盾消失。

var _tube_hp: Array[int] = [120, 120, 120, 120]
var _summon_cd: float = 5.0
var _marker: Node2D = null


func _ready() -> void:
	super._ready()
	# 固定不动：屏蔽重力位移
	_marker = Node2D.new()
	_marker.position = Vector2(0, -40)
	add_child(_marker)


func _ai_tick(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = 0.0
	_summon_cd -= delta
	if _summon_cd <= 0.0 and level != null:
		_summon_cd = 6.0
		var count := 2 if _tubes_alive() < 4 else 1
		for i in count:
			var side := -1.0 if randf() < 0.5 else 1.0
			var x: float = clampf(global_position.x + side * randf_range(90.0, 220.0), 60.0, 4000.0)
			level.call("spawn_horde_at", Vector2(x, level.call("get_ground_y", x) - 2.0), 1, true)
		_play_anim("attack")
	else:
		_play_anim("idle")


func _tubes_alive() -> int:
	var n := 0
	for hp in _tube_hp:
		if hp > 0:
			n += 1
	return n


## 营养管受击（由 level_runner 的 hit 转发或直接暴露接口）。
func damage_tube(index: int, amount: int) -> void:
	if index < 0 or index >= _tube_hp.size():
		return
	_tube_hp[index] = maxi(0, _tube_hp[index] - amount)
	if _tube_hp[index] == 0:
		EventBus.notify.emit("营养管断裂！剩余 %d 根" % _tubes_alive())
		Fx.blood(level.fx_layer if level else null, global_position + Vector2(40 * index - 60, -40), Vector2.UP, 1.6)


func tubes_alive() -> int:
	return _tubes_alive()


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"melee") -> void:
	var alive := _tubes_alive()
	if alive > 0:
		super.apply_damage(int(amount * 0.2), from_dir, is_head, source, damage_type)
		return
	super.apply_damage(amount, from_dir, is_head, source, damage_type)
