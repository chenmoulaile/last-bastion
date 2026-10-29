class_name ItemComponent
extends Node
## 道具组件：处理投掷物、医疗包、药片逻辑。
## 由 PlayerControllerV2 持有并委托调用，避免在控制器中重写物品行为。
## 数值全部从 owner 的字段读取，不修改任何战斗数值。

var owner: Node = null

## 投掷当前选中的投掷物类型。
func throw(throw_index: int) -> void:
	var _owner := owner as PlayerControllerV2
	if _owner == null:
		return
	var keys := ["grenade", "molotov", "bile"]
	var kind: String = keys[int(throw_index) % keys.size()]
	var state: Dictionary = _owner.throwables
	if int(state.get(kind, 0)) <= 0:
		# 没有该类型投掷物，循环到下一个有库存的
		for i in keys.size():
			var k := keys[(int(throw_index) + i) % keys.size()]
			if int(state.get(k, 0)) > 0:
				kind = k
				break
		else:
			if _owner.get_node_or_null("/root/AudioManager") != null:
				_owner.get_node_or_null("/root/AudioManager").play_sfx(&"notify_empty")
			return
	state[kind] = int(state.get(kind, 0)) - 1
	_owner.throwables = state
	var pos := _owner.global_position + Vector2(_owner.facing * 10.0, -22.0)
	_owner.level.spawn_throwable(kind, pos, _owner.aim_dir)
	if _owner.get_node_or_null("/root/AudioManager") != null:
		_owner.get_node_or_null("/root/AudioManager").play_sfx(&"throw")


## 使用医疗包：治疗自身，消耗一个医疗包。
func use_medkit() -> void:
	var _owner := owner as PlayerControllerV2
	if _owner == null:
		return
	if _owner.medkits <= 0 or _owner.is_dead:
		return
	_owner.medkits -= 1
	var mult := 1.0
	if _owner.get_node_or_null("/root/GameManager") != null \
			and _owner.get_node_or_null("/root/GameManager").has_method("medkit_mult"):
		mult = float(_owner.get_node_or_null("/root/GameManager").medkit_mult())
	_owner.heal(int(ceil(70.0 * mult)))
	_owner.black_white = false


## 使用药片：增加临时生命，消耗一片药丸。
func use_pills() -> void:
	var _owner := owner as PlayerControllerV2
	if _owner == null:
		return
	if _owner.pills <= 0 or _owner.is_dead:
		return
	_owner.pills -= 1
	_owner.temp_hp = min(100, _owner.temp_hp + 50)
