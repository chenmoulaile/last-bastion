class_name ReworkSoldierData
extends Resource
## ---------------------------------------------------------------------------
## 职责: 指挥模式士兵(4 种)的纯数据定义 —— 属性、策略 ID、配色与投掷物参数。
## 依赖: 无(纯 Resource;class_name 加 Rework 前缀,现有工程无 SoldierData)。
## 对外接口:
##   - SoldierBase 通过 @export var soldier_data 注入;
##   - strategy_id 由 RoleStrategy.create(strategy_id) 工厂解析为策略实例;
##   - palette / visual_profile 供 rendering/SoldierRenderer.gd 使用。
## ---------------------------------------------------------------------------

@export var id: StringName = &"rifleman"
@export var display_name: String = "步枪手"
@export var description: String = ""

## 核心属性(与现有 character_rifleman/gunner/medic_soldier/demolisher.tres 对齐)
@export var max_hp: int = 80
@export var speed: float = 215.0

## 策略: demolition / mg / rifleman / field_medic → soldiers/strategies/*.gd
@export var strategy_id: StringName = &"rifleman"

## 武器槽(同 ReworkCharacterData 的解析规则)
@export var primary_weapon: StringName = &"ar15"
@export var secondary_weapon: StringName = &"m9"

## 爆破手参数(其他兵种 grenade_capacity=0,策略不会触发投掷)
@export var grenade_capacity: int = 0
@export var grenade_cooldown: float = 60.0
@export var grenade_damage: int = 55
@export var grenade_radius: float = 120.0

## 代码绘制参数
@export var palette: Dictionary = {}
@export var visual_profile: StringName = &"rifleman"
@export var body_width_scale: float = 1.0
@export var body_height_scale: float = 1.0


func palette_color(key: String, fallback: Color = Color.WHITE) -> Color:
	var value: Variant = palette.get(key, fallback)
	if value is Color:
		return value
	return fallback
