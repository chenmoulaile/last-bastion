extends Node
## GameManager - global flow state, campaign selection, unlocks and data access.
## It never touches level nodes directly: level requests travel over EventBus.

enum State { BOOT, MENU, BRIEFING, PLAYING, PAUSED, RESULT }

const DATA_LEVELS := "res://resources/data/levels"
const DATA_WEAPONS := "res://resources/data/weapons"
const DATA_CHARACTERS := "res://resources/data/characters"
const DATA_ZOMBIES := "res://resources/data/zombies"

const DIFFICULTY := {
	&"NORMAL": {
		"name": "普通", "damage": 1.0, "special_interval": 1.3, "max_downs": 3,
		"friendly_fire": false, "medkit": 1.0, "hint": "教学提示全开，推荐首次游玩。"
	},
	&"HARD": {
		"name": "困难", "damage": 1.5, "special_interval": 1.0, "max_downs": 2,
		"friendly_fire": false, "medkit": 0.75, "hint": "敌人更痛，医疗包更少。"
	},
	&"EXPERT": {
		"name": "专家", "damage": 2.0, "special_interval": 0.75, "max_downs": 1,
		"friendly_fire": true, "medkit": 0.75, "hint": "友军伤害开启，倒下即濒死。"
	}
}

const UNLOCK_NINJA := 100000
const UNLOCK_LMG := 300000
const UNLOCK_SNIPER := 500000
const UNLOCK_GRENADE_4 := 800000
const UNLOCK_TITLE := 1200000

var state: State = State.BOOT
var current_level: LevelData = null
var current_level_id: StringName = &"l01"
var current_mode: StringName = &"SQUAD"
var current_difficulty: StringName = &"NORMAL"
var selected_character: StringName = &"assault"
var selected_squad: Array[StringName] = []
var selected_soldiers: Array[StringName] = []
## Co-op roster locks: player_index -> character_id. Local co-op and any future
## network session both go through claim_character() so "must pick different
## survivors" is enforced in exactly one place.
var coop_slots: Dictionary = {}
var coop_active: bool = false
var last_result: Dictionary = {}
var run_seed: int = 0

var levels: Dictionary = {}
var weapons: Dictionary = {}
var characters: Dictionary = {}
var zombies: Dictionary = {}

var _hitstop_token: int = 0


func _ready() -> void:
	_load_all_data()
	EventBus.retry_level_requested.connect(retry_level)
	EventBus.next_level_requested.connect(next_level)
	EventBus.return_to_menu_requested.connect(return_to_menu)
	EventBus.director_request_horde.connect(_on_director_horde)
	EventBus.hitstop.connect(hitstop)
	change_state(State.BOOT)
	call_deferred("_boot")


func _boot() -> void:
	_refresh_unlocks(false)
	change_state(State.MENU)


func change_state(next_state: State) -> void:
	state = next_state
	if state == State.PLAYING:
		Engine.time_scale = 1.0


# ------------------------------------------------------------------ data ----
func _load_all_data() -> void:
	levels = _load_resources(DATA_LEVELS)
	weapons = _load_resources(DATA_WEAPONS)
	characters = _load_resources(DATA_CHARACTERS)
	zombies = _load_resources(DATA_ZOMBIES)


func _load_resources(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Data directory missing: " + dir_path)
		return result
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = load(dir_path + "/" + file_name)
		if res == null:
			continue
		var id_value: Variant = res.get("id")
		if id_value == null:
			continue
		result[StringName(id_value)] = res
	return result


func get_level(id: StringName) -> LevelData:
	return levels.get(id, null)


func get_weapon(id: StringName) -> WeaponData:
	return weapons.get(id, null)


func get_character(id: StringName) -> CharacterData:
	return characters.get(id, null)


func get_zombie(id: StringName) -> ZombieData:
	return zombies.get(id, null)


func get_levels() -> Array[LevelData]:
	var out: Array[LevelData] = []
	for level in levels.values():
		out.append(level)
	out.sort_custom(func(a: LevelData, b: LevelData) -> bool: return String(a.id) < String(b.id))
	return out


func get_playable_characters() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for character in characters.values():
		if character.soldier_role == &"" and not character.is_archive_survivor():
			out.append(character)
	out.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return a.unlock_score < b.unlock_score)
	return out


## The four named survivors of the 2019 RUST FREQUENCY campaign.
func get_archive_survivors() -> Array[CharacterData]:
	var order := ["lin_yuan", "marcus", "lucia", "victor"]
	var out: Array[CharacterData] = []
	for id in order:
		var character: CharacterData = characters.get(StringName(id), null)
		if character != null:
			out.append(character)
	return out


## Archive survivors and legacy archetypes live in the same data directory; this
## keeps squad/command lookups from accidentally pulling narrative characters in.
func get_survivor(id: StringName) -> CharacterData:
	var character: CharacterData = get_character(id)
	if character == null or not character.is_archive_survivor():
		return null
	return character


# --------------------------------------------------------------- co-op ------
func reset_coop() -> void:
	coop_slots.clear()
	coop_active = false


## Reserve a survivor for a local player slot. Returns false when another slot
## already holds that survivor (co-op requires four different characters).
func claim_character(slot: int, character_id: StringName) -> bool:
	var key := String(character_id)
	for other_slot in coop_slots.keys():
		if int(other_slot) != slot and String(coop_slots[other_slot]) == key:
			return false
	coop_slots[slot] = key
	if slot == 0:
		selected_character = character_id
	return true


func character_taken_by_other(slot: int, character_id: StringName) -> bool:
	var key := String(character_id)
	for other_slot in coop_slots.keys():
		if int(other_slot) != slot and String(coop_slots[other_slot]) == key:
			return true
	return false


# --------------------------------------------------------------- story ------
func story_flag(flag: StringName) -> bool:
	return SaveSystem.has_flag(flag)


func set_story_flag(flag: StringName) -> void:
	SaveSystem.set_flag(flag)


## Chapter 3 has two routes through the same level slot (3-1A sewer / 3-1B
## front gate). The chapter 2 chip decision decides which one loads.
func route_variant() -> StringName:
	return &"sewer" if story_flag(&"route_sewer") else &"gate"


func has_deep_archive() -> bool:
	return ArchiveManager != null and ArchiveManager.highest_security_level_collected() >= 4


func get_soldier_roles() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for character in characters.values():
		if character.soldier_role != &"":
			out.append(character)
	out.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return String(a.id) < String(b.id))
	return out


# ------------------------------------------------------------------ flow ----
func start_level(level_id: StringName, mode: StringName = &"", difficulty: StringName = &"",
		character_id: StringName = &"", squad_ids: Array[StringName] = []) -> void:
	var level: LevelData = get_level(level_id)
	if level == null:
		push_error("Unknown level: " + String(level_id))
		return
	current_level = level
	current_level_id = level_id
	current_mode = mode if mode != &"" else default_mode_for(level)
	if current_mode == &"FREE":
		current_mode = &"SQUAD"
	current_difficulty = difficulty if DIFFICULTY.has(difficulty) else &"NORMAL"
	if character_id != &"" and get_character(character_id) != null:
		selected_character = character_id
	selected_squad = squad_ids.duplicate()
	if selected_squad.is_empty():
		selected_squad = _auto_squad()
	selected_soldiers = _auto_soldiers(level)
	run_seed = int(Time.get_unix_time_from_system()) ^ (randi() << 8)
	last_result = {}
	DirectorSystem.begin_level(level, current_difficulty)
	change_state(State.PLAYING)
	AudioManager.play_level_music(String(level.music_theme))
	EventBus.start_level_requested.emit()


func default_mode_for(level: LevelData) -> StringName:
	if level.default_mode == &"COMMAND":
		return &"COMMAND"
	return &"SQUAD"


func _auto_squad() -> Array[StringName]:
	var pool: Array[StringName] = []
	for character in get_playable_characters():
		if character.id == selected_character:
			continue
		if is_character_unlocked(character.id):
			pool.append(character.id)
	var out: Array[StringName] = []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	while out.size() < 3:
		out.append(&"assault")
	return out


func _auto_soldiers(level: LevelData) -> Array[StringName]:
	var roles: Array[StringName] = []
	for role in level.commander_squad:
		roles.append(StringName(role))
	if roles.is_empty():
		roles = [&"rifleman", &"rifleman", &"rifleman", &"gunner", &"medic", &"demolisher"]
	var out: Array[StringName] = []
	for i in mini(8, roles.size()):
		out.append(roles[i])
	return out


func complete_level(result: Dictionary) -> void:
	if current_level == null:
		return
	var score := int(result.get("score", 0))
	var rank := rank_for(score, current_level.par_score)
	result["rank"] = rank
	result["level_id"] = String(current_level.id)
	result["level_title"] = current_level.title
	result["mode"] = String(current_mode)
	result["difficulty"] = String(current_difficulty)
	result["seed"] = run_seed
	var achievements_before: Array = SaveSystem.data.get("achievements", []).duplicate()
	last_result = result
	SaveSystem.record_result(result, current_level, current_mode, current_difficulty)
	SaveSystem.set_progress(current_level.chapter, int(String(current_level.id).substr(1)))
	_refresh_unlocks(true)
	SaveSystem.evaluate_result_achievements(result, current_level, current_mode, current_difficulty)
	var new_achievements: Array = []
	for ach_id in SaveSystem.data.get("achievements", []):
		if String(ach_id) not in achievements_before:
			new_achievements.append(String(ach_id))
	last_result["new_achievements"] = new_achievements
	DirectorSystem.end_level()
	AudioManager.play_result_sting(rank)
	change_state(State.RESULT)
	EventBus.level_completed.emit(score, rank)


func fail_level(reason: String) -> void:
	last_result = {
		"failed": true,
		"reason": reason,
		"score": 0,
		"rank": "F",
		"level_id": String(current_level_id),
		"level_title": current_level.title if current_level else "",
		"mode": String(current_mode),
		"difficulty": String(current_difficulty),
	}
	DirectorSystem.end_level()
	AudioManager.stop_level_music()
	change_state(State.RESULT)
	EventBus.level_failed.emit(reason)


func retry_level() -> void:
	if current_level == null:
		return_to_menu()
		return
	start_level(current_level_id, current_mode, current_difficulty, selected_character, selected_squad)


func next_level() -> void:
	if current_level == null:
		return_to_menu()
		return
	var ids: Array[String] = []
	for level in get_levels():
		ids.append(String(level.id))
	var index := ids.find(String(current_level.id))
	if index >= 0 and index + 1 < ids.size():
		start_level(StringName(ids[index + 1]))
	else:
		return_to_menu()


func return_to_menu() -> void:
	DirectorSystem.end_level()
	AudioManager.play_menu_music()
	change_state(State.MENU)


func pause_game(paused: bool) -> void:
	if state != State.PLAYING and state != State.PAUSED:
		return
	change_state(State.PAUSED if paused else State.PLAYING)
	get_tree().paused = paused
	EventBus.game_paused.emit(paused)


func rank_for(score: int, par: int) -> String:
	if par <= 0:
		return "C"
	var ratio := float(score) / float(par)
	if ratio >= 0.95:
		return "S"
	if ratio >= 0.80:
		return "A"
	if ratio >= 0.60:
		return "B"
	return "C"


# --------------------------------------------------------------- unlocks ----
func _refresh_unlocks(announce: bool) -> void:
	var total := SaveSystem.get_score_total()
	if total >= UNLOCK_NINJA and not SaveSystem.is_character_unlocked(&"ninja"):
		SaveSystem.unlock_character(&"ninja")
		_announce_unlock(&"ninja", announce)
	if total >= UNLOCK_LMG and not SaveSystem.is_weapon_unlocked(&"lmg"):
		SaveSystem.unlock_weapon(&"lmg")
		_announce_unlock(&"lmg", announce)
	if total >= UNLOCK_SNIPER and not SaveSystem.is_weapon_unlocked(&"sniper"):
		SaveSystem.unlock_weapon(&"sniper")
		_announce_unlock(&"sniper", announce)
	if total >= UNLOCK_GRENADE_4:
		SaveSystem.data["unlocks"]["grenade_cap"] = 4
	if total >= UNLOCK_TITLE:
		SaveSystem.data["unlocks"]["title"] = "最后防线老兵"
	if SaveSystem.s_rank_count() >= 3 and not SaveSystem.is_character_unlocked(&"officer"):
		SaveSystem.unlock_character(&"officer")
		_announce_unlock(&"officer", announce)
	if all_weapons_unlocked():
		SaveSystem.mark_achievement(&"arsenal")
	SaveSystem.save()


func _announce_unlock(id: StringName, announce: bool) -> void:
	SaveSystem.save()
	if announce:
		EventBus.unlock_earned.emit(id)
		AudioManager.play_sfx(&"unlock")


func all_weapons_unlocked() -> bool:
	return SaveSystem.is_weapon_unlocked(&"lmg") and SaveSystem.is_weapon_unlocked(&"sniper")


func is_character_unlocked(id: StringName) -> bool:
	if id in [&"assault", &"medic", &"heavy", &"scout"]:
		return true
	if id in [&"rifleman", &"gunner", &"medic_soldier", &"demolisher"]:
		return true
	if id in [&"lin_yuan", &"marcus", &"lucia", &"victor"]:
		return true
	return SaveSystem.is_character_unlocked(id)


func is_weapon_unlocked(id: StringName) -> bool:
	if id in [&"m9", &"ar15", &"smg", &"shotgun", &"axe", &"katana", &"grenade", &"molotov", &"bile"]:
		return true
	if id == &"chainsaw":
		return SaveSystem.has_flag("chainsaw_found")
	return SaveSystem.is_weapon_unlocked(id)


func grenade_capacity() -> int:
	return int(SaveSystem.data.get("unlocks", {}).get("grenade_cap", 3))


func is_level_unlocked(id: StringName) -> bool:
	var level: LevelData = get_level(id)
	if level == null:
		return false
	if level.chapter <= 1:
		return true
	var required := {2: &"l03", 3: &"l06", 4: &"l09"}
	var gate: StringName = required.get(level.chapter, &"")
	if gate != &"" and not SaveSystem.is_level_completed(gate):
		return false
	var ids: Array[String] = []
	for l in get_levels():
		ids.append(String(l.id))
	var index := ids.find(String(id))
	if index <= 0:
		return true
	return SaveSystem.is_level_completed(StringName(ids[index - 1])) or SaveSystem.is_level_completed(id)


func is_chapter_unlocked(chapter: int) -> bool:
	if chapter <= 1:
		return true
	var gate := {2: &"l03", 3: &"l06", 4: &"l09"}
	return SaveSystem.is_level_completed(gate.get(chapter, &"l01"))


func continue_level_id() -> StringName:
	for level in get_levels():
		if is_level_unlocked(level.id) and not SaveSystem.is_level_completed(level.id):
			return level.id
	return &"l11"


# ------------------------------------------------------------ difficulty ----
func difficulty_data() -> Dictionary:
	return DIFFICULTY.get(current_difficulty, DIFFICULTY[&"NORMAL"])


func enemy_damage_mult() -> float:
	return float(difficulty_data()["damage"])


func special_interval_mult() -> float:
	return float(difficulty_data()["special_interval"])


func max_downs() -> int:
	return int(difficulty_data()["max_downs"])


func friendly_fire_enabled() -> bool:
	return bool(difficulty_data()["friendly_fire"])


func medkit_mult() -> float:
	return float(difficulty_data()["medkit"])


# ------------------------------------------------------------------ misc ----
func hitstop(seconds: float) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.06
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func _on_director_horde(_count: int) -> void:
	pass
