class_name WeaponData
extends Resource
## Every gun, melee weapon and throwable. Balance values are loaded from
## resources/data/weapons/*.tres.

@export var id: StringName = &"m9"
@export var display_name: String = "M9 手枪"
@export var category: StringName = &"secondary" # primary / secondary / melee / throwable
@export var damage: int = 18
@export var pellets: int = 1
@export var rpm: float = 400.0
@export var mag_size: int = 15
@export var reserve_ammo: int = -1 # -1 = infinite
@export var reload_time: float = 1.2
@export var spread: float = 1.5
@export var effective_range: float = 400.0
@export var score_mult: float = 1.0
@export var unlock_score: int = 0
@export var automatic: bool = false
@export var pierce: int = 0
@export var knockback: float = 40.0
@export var melee_arc: float = 120.0
@export var melee_range: float = 60.0
@export var fuel: float = 0.0
@export var fire_mode: StringName = &"hitscan" # hitscan / melee / throwable / chainsaw
@export var throw_radius: float = 0.0
@export var fuse_time: float = 0.0
@export var effect_duration: float = 0.0
@export var effect_dps: float = 0.0
@export var sprite: String = "m9"
@export var description: String = ""
@export var scoped_spread: float = -1.0
