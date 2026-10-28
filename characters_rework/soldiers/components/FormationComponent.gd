class_name ReworkFormationComponent
extends RefCounted
## ---------------------------------------------------------------------------
## 职责: 阵型槽位计算(楔形/横列/纵队)。数学与现有 AllyAgent._formation_offset
##       完全一致,保证指挥模式队形观感不变。只算槽位,不驱动移动。
## 依赖: 无(纯计算)。
## 对外接口:
##   set_formation(id: StringName)      # wedge / line / column
##   cycle_formation() -> StringName    # Tab 循环: wedge → line → column
##   offset_for(index: int, dir: float) -> Vector2
## ---------------------------------------------------------------------------

const FORMATIONS: Array[StringName] = [&"wedge", &"line", &"column"]

var formation: StringName = &"wedge"


func set_formation(id: StringName) -> void:
	if FORMATIONS.has(id):
		formation = id


func cycle_formation() -> StringName:
	var index := FORMATIONS.find(formation)
	formation = FORMATIONS[(index + 1) % FORMATIONS.size()]
	return formation


func offset_for(index: int, dir: float) -> Vector2:
	## 与现有 AllyAgent._formation_offset 相同的槽位数学(侧视队形只改 X)。
	match formation:
		&"line":
			return Vector2(-dir * (44.0 + float(index) * 26.0), 0.0)
		&"column":
			return Vector2(-dir * (38.0 + float(index / 2) * 26.0), 0.0)
		_:
			var row := float(index / 2)
			var stagger := 8.0 if index % 2 == 0 else -8.0
			return Vector2(-dir * (34.0 + row * 22.0) + stagger, 0.0)
