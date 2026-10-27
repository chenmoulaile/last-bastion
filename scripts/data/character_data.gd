class_name CharacterData
extends Resource
## Playable survivor / AI squad archetype.
##
## Two rosters share this resource:
##   roster = "legacy"  -> the original six archetypes (assault/heavy/...)
##   roster = "archive" -> the four named survivors of the 2019 RUST FREQUENCY
##                         campaign (lin_yuan / marcus / lucia / victor)
##
## Legacy fields keep the v1.0 screens working untouched; the narrative fields
## below are additive so old .tres files still load without migration.

# ---------------------------------------------------------------- identity ----
@export var id: StringName = &"assault"
@export var display_name: String = "突击兵"
@export var callsign: String = "ASSAULT"
@export var character_id: String = "" # canonical string id used by narrative data
@export var codename: String = "" # 代号，例：LYNX / SERGEANT / SAINT / BIOLOGIST
@export var roster: StringName = &"legacy" # legacy / archive

# ------------------------------------------------------------------ combat ----
@export var max_hp: int = 100
@export var speed: float = 220.0
@export var stealth_speed_multiplier: float = 0.6 # 潜行移速倍率（林远 = 1.0）
@export var melee_damage: float = 40.0
@export var starting_weapon: PackedScene = null
@export var starting_items: Array[PackedScene] = []

# ----------------------------------------------------------------- passive ----
@export var passive_ability_id: StringName = &""
@export var passive_name: String = ""
@export var passive_desc: String = ""
@export var passive_cooldown: float = 30.0

# -------------------------------------------------------------------- gear ----
@export var skill_id: StringName = &"assault_rush"
@export var skill_name: String = "突击冲锋"
@export var skill_desc: String = "4 秒内换弹速度 ×2、移速 +20%"
@export var skill_cd: float = 25.0
@export var primary_weapon: StringName = &"ar15"
@export var secondary_weapon: StringName = &"m9"
@export var melee_weapon: StringName = &"axe"

# ---------------------------------------------------------------- metadata ----
@export var unlock_score: int = 0
@export var portrait: String = "assault"
@export var visual_base: String = "" # 复用哪套像素动画（不重画素材）
@export var palette_tint: Color = Color.WHITE # 调色板偏移
@export var accent: Color = Color(0.55, 0.78, 0.45)
@export var dialogue_color: Color = Color(0.86, 0.86, 0.80) # 对话气泡颜色
@export var description: String = ""
@export var soldier_role: StringName = &"" # rifleman/gunner/medic/demolisher for command mode
@export var unlock_archive_types: Array[String] = [] # 该角色可解锁的档案类型

# --------------------------------------------------------------- narrative ----
@export var monologue: String = "" # 角色选择界面的一段独白
@export var language: String = "en" # zh / en —— 决定字幕与语音规则
@export var voice_pitch: float = 1.0


## Canonical id as a plain String; falls back to the legacy `id` field.
func cid() -> String:
	return character_id if character_id != "" else String(id)


## Visual animation set, falling back to the portrait id for legacy entries.
func animation_id() -> String:
	return visual_base if visual_base != "" else portrait


func is_archive_survivor() -> bool:
	return roster == &"archive"


## Legacy archetypes still drive squad/command mode; archive survivors use the
## passive system and are selected on their own screen.
func has_passive() -> bool:
	return passive_ability_id != &""
