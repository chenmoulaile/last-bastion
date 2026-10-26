class_name LevelData
extends Resource
## Campaign level definition. The generic level runner builds geometry from
## theme + length, then places data-driven events, checkpoints and bosses.

@export var id: StringName = &"l01"
@export var chapter: int = 1
@export var chapter_name: String = "郊区突围"
@export var title: String = "街道突破口"
@export var subtitle: String = "天亮之前，穿过街区。"
@export var theme: StringName = &"suburb"
@export var length: float = 9000.0
@export var default_mode: StringName = &"SQUAD" # SQUAD / COMMAND / FREE
@export var difficulty_scale: float = 1.0
@export var base_score: int = 100000
@export var par_score: int = 160000
@export var time_target: float = 300.0
@export var special_density: float = 1.0
@export var special_weights: Dictionary = {}
@export var uncommon_weights: Dictionary = {}
@export var bosses: Array = []
@export var events: Array = []
@export var checkpoint_at: float = 0.5
@export var hidden_room_at: float = 0.35
@export var dark: bool = false
@export var rain: bool = false
@export var extraction: String = "safehouse" # safehouse / helicopter / apc
@export var extraction_defense: float = 0.0
@export var tutorial_tips: Array = []
@export var briefing: String = ""
@export var new_threat: String = ""
@export var player_weapons: Array = []
@export var commander_squad: Array = []
@export var ammo_crates: int = 3
@export var medkits: int = 2
@export var unlocks_weapon: String = ""
@export var music_theme: StringName = &"suburb"
@export var escort_vehicle: bool = false
