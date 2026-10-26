class_name ZombieData
extends Resource
## Data-driven definition for every infected. All balance values live in
## resources/data/zombies/*.tres and are never hard-coded in AI scripts.

@export var id: StringName = &"common"
@export var display_name: String = "感染者"
@export var max_hp: int = 30
@export var walk_speed_min: float = 120.0
@export var walk_speed_max: float = 180.0
@export var attack_damage: int = 5
@export var attack_interval: float = 0.5
@export var score_value: int = 100
@export var behavior_id: StringName = &"common"
@export var tint: Color = Color.WHITE
@export var size_scale: float = 1.0
@export var anim_map: Dictionary = {}
@export var is_special: bool = false
@export var is_uncommon: bool = false
@export var is_boss: bool = false
@export var head_hittable: bool = true
@export var head_immune: bool = false
@export var fire_immune: bool = false
@export var front_immune: bool = false
@export var low_profile: bool = false
@export var control_kind: StringName = &""
@export var special_weight: float = 0.0
@export var sprite_prefix: String = "common_a"
@export var sprite_size: Vector2i = Vector2i(24, 32)
@export var collision_size: Vector2 = Vector2(14, 26)
@export var death_animation: String = "die"
@export var codex_category: String = "special"
@export var description: String = ""

## Extra tuning used by special AI. Values are percentages / seconds.
@export var pounce_range: float = 380.0
@export var attack_range: float = 40.0
@export var sight_range: float = 260.0
@export var voice_id: StringName = &"zombie_growl"
