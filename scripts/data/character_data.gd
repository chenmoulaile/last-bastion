class_name CharacterData
extends Resource
## Playable survivor / AI squad archetype.

@export var id: StringName = &"assault"
@export var display_name: String = "突击兵"
@export var callsign: String = "ASSAULT"
@export var max_hp: int = 100
@export var speed: float = 220.0
@export var skill_id: StringName = &"assault_rush"
@export var skill_name: String = "突击冲锋"
@export var skill_desc: String = "4 秒内换弹速度 ×2、移速 +20%"
@export var skill_cd: float = 25.0
@export var primary_weapon: StringName = &"ar15"
@export var secondary_weapon: StringName = &"m9"
@export var melee_weapon: StringName = &"axe"
@export var unlock_score: int = 0
@export var portrait: String = "assault"
@export var accent: Color = Color(0.55, 0.78, 0.45)
@export var description: String = ""
@export var soldier_role: StringName = &"" # rifleman/gunner/medic/demolisher for command mode
# --- Rust Frequency narrative layer (optional fields, safe defaults) --------
@export var codename: String = ""          # 代号，如「山猫」
@export var passive_name: String = ""      # 被动技能名
@export var passive_desc: String = ""      # 被动技能描述
@export var dialogue_color: Color = Color(0.9, 0.9, 0.9)
@export var visual_base: String = ""       # 复用的现有精灵前缀；空则用 portrait
@export var archive_types: Array = []      # 可解读的档案类型（专家门槛）
@export var bio: String = ""               # 角色选择界面简介
@export var language: String = "zh"
@export var survivor: bool = false         # 「锈蚀频率」四主角标记
