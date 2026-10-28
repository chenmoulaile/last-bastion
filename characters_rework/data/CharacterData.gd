class_name ReworkCharacterData
extends Resource
## ---------------------------------------------------------------------------
## 职责: 可玩角色(6 名)的纯数据定义 —— 属性、配色、绘制轮廓与被动技能 ID。
## 依赖: 无(纯 Resource;class_name 加 Rework 前缀避免与现有 CharacterData 冲突)。
## 对外接口:
##   - 字段全部 @export,可被 PlayerControllerV2 / PlayerRenderer / UI 直接读取;
##   - palette: Dictionary,键约定见 data/palettes.gd(body_primary 等 7 键);
##   - passive_ability_id 对应 playable/passives/passive_<id>.gd 文件名;
##   - visual_profile 对应 rendering/PlayerRenderer.gd 的绘制档案键。
## ---------------------------------------------------------------------------

@export var id: StringName = &"assault"
## 叙事角色映射: 指向剧情层 CharacterData.id (lin_yuan / marcus / lucia / victor)。
## 空 StringName 表示通用角色(突击兵 / 军官),可安全用于后续扩展。
@export var narrative_id: StringName = &""
@export var display_name: String = "突击兵"
@export var callsign: String = "ASSAULT"
@export var description: String = ""

## 核心属性(与现有 resources/data/characters/*.tres 数值保持一致)
@export var max_hp: int = 100
@export var speed: float = 220.0
@export var unlock_score: int = 0

## 被动 / 主动技能(沿用现有 skill_id 命名,由 passives/ 组件实现)
@export var passive_ability_id: StringName = &"assault_rush"
@export var skill_name: String = "突击冲锋"
@export var skill_desc: String = ""
@export var skill_cd: float = 25.0

## 武器槽: 引用现有 resources/data/weapons/*.tres 的 id(StringName)。
## 控制器优先通过 GameManager.get_weapon(id) 解析;独立运行时按路径直接 load。
@export var primary_weapon: StringName = &"ar15"
@export var secondary_weapon: StringName = &"m9"
@export var melee_weapon: StringName = &"axe"

## 代码绘制参数
@export var palette: Dictionary = {}
@export var visual_profile: StringName = &"assault"
## 体型缩放: 1.0 = 标准 32px 高、12px 宽躯干。重装 1.08/1.12,侦察 0.94/0.98 等。
@export var body_width_scale: float = 1.0
@export var body_height_scale: float = 1.0


func palette_color(key: String, fallback: Color = Color.WHITE) -> Color:
	## 零分支取色: palette 缺键时返回 fallback,渲染器每帧调用也不报错。
	var value: Variant = palette.get(key, fallback)
	if value is Color:
		return value
	return fallback
