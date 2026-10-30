extends Node
## FactionManager - the four-faction knowledge & hostility model.
##
## The v1.0 AI Director asked "how stressed is the player?". The faction layer
## asks a colder question: "how much does each power in Rift City know, and how
## much do they care?" AIDirector consumes the answers; nothing else does.
##
## effective_hostility = base
##     + archive_pressure            (player holds high-security fragments)
##     + kills * 0.05                (player killed their people)
##     - quests * 0.2                (player did them a favour)
##     + manual bonus                (story triggers)
## clamped to 0..1. Above 0.7 the faction actively hunts the player.

const DATA_DIR := "res://resources/data/factions"
const FACTION_IDS := ["horizon", "signal_bureau", "rust", "remnants"]
const ARCHIVE_WEIGHT := 0.15
const KILL_WEIGHT := 0.05
const QUEST_WEIGHT := 0.2
const HOSTILE_THRESHOLD := 0.7

## Fallback matrix from the design doc (row -> column), used when a .tres is
## missing or has an empty table.
const DEFAULT_MATRIX := {
	"horizon": {"signal_bureau": 0.2, "rust": 0.6, "remnants": 0.9},
	"signal_bureau": {"horizon": 0.2, "rust": 0.4, "remnants": 0.3},
	"rust": {"horizon": 0.3, "signal_bureau": 0.5, "remnants": 0.8},
	"remnants": {"horizon": 0.9, "signal_bureau": 0.3, "rust": 0.8},
}

var factions: Dictionary = {} # faction_id -> FactionData
var kills: Dictionary = {} # faction_id -> int
var quests: Dictionary = {} # faction_id -> int
var bonuses: Dictionary = {} # faction_id -> float
var knowledge_bonus: Dictionary = {} # faction_id -> int

var _last_archive_level: int = 0


func _ready() -> void:
	_load_factions()
	reset_runtime()
	EventBus.archive_unlocked.connect(_on_archive_unlocked)


func _load_factions() -> void:
	factions.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir != null:
		for dir_file in dir.get_files():
			var file_name := dir_file.trim_suffix(".remap")
			if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				continue
			var res: Resource = load(DATA_DIR + "/" + file_name)
			var faction := res as FactionData
			if faction == null or faction.faction_id == "":
				continue
			if faction.hostility_to_other_factions.is_empty():
				faction.hostility_to_other_factions = DEFAULT_MATRIX.get(faction.faction_id, {}).duplicate()
			factions[faction.faction_id] = faction
		print("[Data] factions=%d" % factions.size())
	for id in FACTION_IDS:
		if not factions.has(id):
			push_warning("Faction data missing: " + id)
			var fallback := FactionData.new()
			fallback.faction_id = id
			fallback.display_name = id
			fallback.hostility_to_other_factions = DEFAULT_MATRIX.get(id, {}).duplicate()
			factions[id] = fallback


func reset_runtime() -> void:
	kills.clear()
	quests.clear()
	bonuses.clear()
	knowledge_bonus.clear()
	for id in factions.keys():
		kills[id] = 0
		quests[id] = 0
		bonuses[id] = 0.0
		knowledge_bonus[id] = 0


# ---------------------------------------------------------------- queries ----
func get_faction(faction_id: String) -> FactionData:
	return factions.get(faction_id, null)


func display_name(faction_id: String) -> String:
	var faction := get_faction(faction_id)
	return faction.display_name if faction != null else faction_id


func accent(faction_id: String) -> Color:
	var faction := get_faction(faction_id)
	return faction.accent if faction != null else Color.WHITE


func relationship(a: String, b: String) -> float:
	var faction := get_faction(a)
	if faction == null:
		return float(DEFAULT_MATRIX.get(a, {}).get(b, 0.0))
	return float(faction.hostility_to_other_factions.get(b, 0.0))


## 0..1 pressure from the player's archive collection.
func archive_pressure() -> float:
	if ArchiveManager == null:
		return 0.0
	return float(ArchiveManager.highest_security_level_collected()) * ARCHIVE_WEIGHT


func effective_hostility(faction_id: String) -> float:
	var faction := get_faction(faction_id)
	if faction == null:
		return 0.0
	var value := faction.base_hostility_to_player
	value += archive_pressure()
	value += float(kills.get(faction_id, 0)) * KILL_WEIGHT
	value -= float(quests.get(faction_id, 0)) * QUEST_WEIGHT
	value += float(bonuses.get(faction_id, 0.0))
	return clampf(value, 0.0, 1.0)


func is_hostile(faction_id: String) -> bool:
	return effective_hostility(faction_id) > HOSTILE_THRESHOLD


func hostile_factions() -> Array[String]:
	var out: Array[String] = []
	for id in factions.keys():
		if is_hostile(String(id)):
			out.append(String(id))
	return out


func knowledge_level(faction_id: String) -> int:
	var faction := get_faction(faction_id)
	if faction == null:
		return 0
	return clampi(faction.knowledge_level + int(knowledge_bonus.get(faction_id, 0)), 0, 3)


# --------------------------------------------------------------- mutation ----
func register_kill(faction_id: String, amount: int = 1) -> void:
	if not factions.has(faction_id):
		return
	kills[faction_id] = int(kills.get(faction_id, 0)) + amount
	EventBus.faction_hostility_changed.emit(faction_id, effective_hostility(faction_id))


func complete_quest(faction_id: String) -> void:
	if not factions.has(faction_id):
		return
	quests[faction_id] = int(quests.get(faction_id, 0)) + 1
	EventBus.faction_hostility_changed.emit(faction_id, effective_hostility(faction_id))


func add_hostility(faction_id: String, delta: float) -> void:
	if not factions.has(faction_id):
		return
	bonuses[faction_id] = float(bonuses.get(faction_id, 0.0)) + delta
	EventBus.faction_hostility_changed.emit(faction_id, effective_hostility(faction_id))


func set_hostility(faction_id: String, value: float) -> void:
	if not factions.has(faction_id):
		return
	var faction := get_faction(faction_id)
	var target := clampf(value, 0.0, 1.0)
	# Solve for the manual bonus that lands exactly on `value`.
	var base := faction.base_hostility_to_player + archive_pressure() \
		+ float(kills.get(faction_id, 0)) * KILL_WEIGHT \
		- float(quests.get(faction_id, 0)) * QUEST_WEIGHT
	bonuses[faction_id] = target - base
	EventBus.faction_hostility_changed.emit(faction_id, effective_hostility(faction_id))


func set_knowledge(faction_id: String, level: int) -> void:
	var faction := get_faction(faction_id)
	if faction == null:
		return
	knowledge_bonus[faction_id] = clampi(level, 0, 3) - faction.knowledge_level


# ---------------------------------------------------------------- spawning ----
## Patrol density multiplier fed to AIDirector (archive level 2+ makes Horizon
## sweep the streets harder).
func patrol_density(faction_id: String) -> float:
	var faction := get_faction(faction_id)
	if faction == null:
		return 0.0
	var density := faction.patrol_density
	var security := ArchiveManager.highest_security_level_collected() if ArchiveManager != null else 0
	if faction_id == "horizon" and security >= 2:
		density *= 1.2
	if faction_id == "signal_bureau" and security >= 3:
		density *= 1.3
	if security >= 4 and faction_id in ["horizon", "signal_bureau"]:
		density *= 1.4
	return density


## Per-unit spawn weight, modified by the archive level (3.6 in the spec).
func unit_weight(faction_id: String, unit_kind: String) -> float:
	var weight := 1.0
	var security := ArchiveManager.highest_security_level_collected() if ArchiveManager != null else 0
	if security >= 3 and unit_kind == "signal_agent":
		weight *= 1.3
	if security >= 3 and unit_kind == "evidence_destroyer":
		weight = maxf(weight, 1.0) # appears at all once the player holds Complicity
	if security >= 4 and unit_kind in ["horizon_enforcer", "evidence_destroyer"]:
		weight *= 2.0
	if security >= 2 and unit_kind == "horizon_enforcer":
		weight *= 1.2
	return weight


## Picks the two factions for a street skirmish. Returns [] when nobody in the
## area hates anybody enough to shoot first.
func pick_skirmish_pair(near_pos: Vector2) -> Array[String]:
	var candidates: Array[String] = []
	for id in factions.keys():
		var faction := get_faction(String(id))
		if faction == null:
			continue
		if faction.hostility_to_zombies < 0.5:
			continue
		candidates.append(String(id))
	if candidates.size() < 2:
		return []
	var best_a := ""
	var best_b := ""
	var best := 0.0
	for a in candidates:
		for b in candidates:
			if a == b:
				continue
			var score := relationship(a, b) + relationship(b, a)
			# Skirmishes are more likely where the player already stirred things.
			score += effective_hostility(a) * 0.2 + effective_hostility(b) * 0.2
			if score > best:
				best = score
				best_a = a
				best_b = b
	var out: Array[String] = []
	if best >= 0.9:
		out.append(best_a)
		out.append(best_b)
	return out


## Which faction should own the next patrol near the player? Weighted by
## density * (1 + hostility), so hostile factions show up more often.
func pick_patrol_faction(rng: RandomNumberGenerator = null) -> String:
	var total := 0.0
	var weights: Dictionary = {}
	for id in factions.keys():
		var faction := get_faction(String(id))
		if faction == null:
			continue
		if faction.knowledge_level <= 0 and float(bonuses.get(String(id), 0.0)) <= 0.0:
			continue
		var weight := patrol_density(String(id)) * (0.35 + effective_hostility(String(id)))
		if weight <= 0.01:
			continue
		weights[String(id)] = weight
		total += weight
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total if rng != null else randf() * total
	for id in weights.keys():
		roll -= float(weights[id])
		if roll <= 0.0:
			return String(id)
	return String(weights.keys().back())


func pick_unit(faction_id: String, rng: RandomNumberGenerator = null) -> String:
	var faction := get_faction(faction_id)
	if faction == null or faction.special_units.is_empty():
		return ""
	var total := 0.0
	for unit in faction.special_units:
		total += unit_weight(faction_id, unit)
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total if rng != null else randf() * total
	for unit in faction.special_units:
		roll -= unit_weight(faction_id, unit)
		if roll <= 0.0:
			return unit
	return faction.special_units.back()


## Hostility a faction feels toward infected: high values mean they will shoot
## zombies before they shoot the player.
func hostility_to_zombies(faction_id: String) -> float:
	var faction := get_faction(faction_id)
	return faction.hostility_to_zombies if faction != null else 0.5


func _on_archive_unlocked(_fragment_id: String, _security: int) -> void:
	var level := ArchiveManager.highest_security_level_collected()
	if level == _last_archive_level:
		return
	_last_archive_level = level
	for id in factions.keys():
		EventBus.faction_hostility_changed.emit(String(id), effective_hostility(String(id)))
