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
