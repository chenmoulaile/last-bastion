class_name FactionData
extends Resource
## 「锈蚀频率」派系定义。敌意是运行时数值，由 FactionManager 持有矩阵。

@export var id: StringName = &"horizon"
@export var display_name: String = "地平线生物"
@export var color: Color = Color(0.90, 0.94, 0.98)
@export var base_hostility: float = 1.0        # 0 友好 … 1 敌对
@export var knowledge: int = 2                 # 知情程度 0-3（3 = 完全知情）
@export var attitude: String = "hostile"       # hostile / neutral / friendly
@export var blurb: String = ""
