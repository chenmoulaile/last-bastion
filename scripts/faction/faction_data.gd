class_name FactionData
extends Resource
## One faction of the RIFT CITY power map (2019).
##
## knowledge_level: 0 unaware / 1 scattered / 2 high / 3 total
## hostility_*:    0..1 weights consumed by AIDirector + FactionManager

@export var faction_id: String = "horizon"
@export var display_name: String = "地平线安保"
@export var short_name: String = "HORIZON"
@export var knowledge_level: int = 1
@export var base_hostility_to_player: float = 0.4
@export var hostility_to_zombies: float = 0.7
@export var hostility_to_other_factions: Dictionary = {} # faction_id -> float
@export var patrol_density: float = 1.0
@export var special_units: Array[String] = []
@export var accent: Color = Color(0.86, 0.62, 0.30)
@export var description: String = ""
@export var hostile_when_above: float = 0.7


func is_hostile(value: float) -> bool:
	return value > hostile_when_above
