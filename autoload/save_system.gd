extends Node
## SaveSystem - single-slot JSON save with atomic write. Also owns persistent
## counters, achievements and meta-unlocks.

const SAVE_DIR := "user://save"
const SAVE_PATH := "user://save/save_01.json"
const TEMP_PATH := "user://save/save_01.tmp"
const VERSION := 1

const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_blood", "name": "初尝战果", "desc": "通关 L1 街道突破口", "icon": "ach_first_blood"},
	{"id": "door_kicker", "name": "门当关", "desc": "累计踹门 100 次", "icon": "ach_door"},
	{"id": "witch_crowning", "name": "灭灯者", "desc": "Crowning 秒杀 Witch", "icon": "ach_witch"},
	{"id": "tank_slayer", "name": "拆塔专家", "desc": "60 秒内击杀 Tank", "icon": "ach_tank"},
	{"id": "combo_50", "name": "快枪手", "desc": "单关达成 50 连击", "icon": "ach_combo"},
	{"id": "arsenal", "name": "军火商", "desc": "解锁全部武器", "icon": "ach_arsenal"},
	{"id": "old_sergeant", "name": "老班长", "desc": "指挥模式通关 L9 且无士兵阵亡", "icon": "ach_commander"},
	{"id": "medic", "name": "白衣天使", "desc": "累计救助队友 50 次", "icon": "ach_medic"},
	{"id": "not_a_drill", "name": "这不是演习", "desc": "专家难度通关全战役", "icon": "ach_expert"},
	{"id": "full_house", "name": "全军出击", "desc": "指挥模式 8 兵满编通关任意关", "icon": "ach_squad"},
	{"id": "stealth", "name": "完美潜行", "desc": "不惊动 Witch 通过 L5", "icon": "ach_stealth"},
	{"id": "no_casualties", "name": "零伤亡", "desc": "L6 防守期间全队无人倒地", "icon": "ach_no_downs"},
	{"id": "codex", "name": "全图鉴收藏家", "desc": "击杀过每种特感与变异普感", "icon": "ach_codex"},
	{"id": "scavenger", "name": "拾荒者", "desc": "找到全部隐藏房间（每关至少 1 个）", "icon": "ach_scavenger"},
	{"id": "no_one_left", "name": "没有人被落下", "desc": "任意关全队 4 人存活结算", "icon": "ach_no_one_left"},
	{"id": "fire_safety", "name": "消防安全", "desc": "燃烧瓶单次烧死 15 只普感", "icon": "ach_fire"},
	{"id": "environmentalist", "name": "环境利用大师", "desc": "用油桶爆炸击杀 50 只僵尸", "icon": "ach_barrel"},
	{"id": "hunter_interrupter", "name": "老练猎手", "desc": "近战推开打断 Hunter 扑击 25 次", "icon": "ach_hunter"},
	{"id": "mr_perfect", "name": "满分先生", "desc": "任意关取得 S 评价", "icon": "ach_s_rank"},
	{"id": "last_bastion", "name": "最后防线", "desc": "通关 L11 最后防线", "icon": "ach_last_stand"},
]

const CODEX_SPECIALS := ["hunter", "smoker", "boomer", "charger", "spitter", "jockey", "tank", "witch"]
const CODEX_UNCOMMONS := ["riot", "hazmat", "mud", "hardhat", "clown", "scavenger"]

var data: Dictionary = {}


func _ready() -> void:
	_ensure_dir()
	load_game()
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.witch_crowned.connect(_on_witch_crowned)
	EventBus.door_kicked.connect(_on_door_kicked)
	EventBus.player_rescued.connect(_on_player_rescued)


func _default_data() -> Dictionary:
	return {
		"version": VERSION,
		"progress": {"chapter": 1, "level": 1, "completed": []},
		"unlocks": {"weapons": [], "characters": [], "grenade_cap": 3, "title": ""},
		"highscores": {},
		"score_total": 0,
		"achievements": [],
		"settings": {
			"volumes": {"Master": 1.0, "Music": 0.8, "SFX": 0.9, "Ambience": 0.7, "Voice": 0.9},
			"keymap": {},
			"fullscreen": false,
			"screenshake": 1.0,
			"show_tips": true,
		},
		"counters": {
			"doors_kicked": 0,
			"rescues": 0,
			"barrel_kills": 0,
			"hunter_interrupts": 0,
			"witch_crowns": 0,
			"molotov_kills": 0,
			"levels_completed": 0,
		},
		"codex": [],
		"hidden_rooms": [],
		"expert_levels": [],
		"command_wins": [],
		"flags": [],
		"playtime": 0.0,
	}


func _ensure_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("save"):
		dir.make_dir("save")


func load_game() -> void:
	data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is corrupt; using defaults.")
		return
	_merge_dict(data, parsed)
	data["version"] = VERSION


func _merge_dict(base: Dictionary, incoming: Dictionary) -> void:
	for key in incoming:
		if base.has(key) and typeof(base[key]) == TYPE_DICTIONARY and typeof(incoming[key]) == TYPE_DICTIONARY:
			_merge_dict(base[key], incoming[key])
		else:
			base[key] = incoming[key]


func save() -> void:
	_ensure_dir()
	var text := JSON.stringify(data, "\t")
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null:
		push_error("Cannot write save temp file.")
		return
	temp.store_string(text)
	temp.flush()
	temp.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("Atomic rename failed, falling back to direct write.")
		var direct := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if direct:
			direct.store_string(text)
			direct.close()


func set_progress(chapter: int, level: int) -> void:
	data["progress"]["chapter"] = maxi(int(data["progress"].get("chapter", 1)), chapter)
	data["progress"]["level"] = maxi(int(data["progress"].get("level", 1)), level)
	save()


func mark_level_completed(level_id: StringName) -> void:
	var list: Array = data["progress"]["completed"]
	if String(level_id) not in list:
		list.append(String(level_id))
		data["counters"]["levels_completed"] = int(data["counters"].get("levels_completed", 0)) + 1


func is_level_completed(level_id: StringName) -> bool:
	return String(level_id) in data["progress"]["completed"]


func record_result(result: Dictionary, level: LevelData, mode: StringName, difficulty: StringName) -> void:
	var level_id := String(level.id)
	var score := int(result.get("score", 0))
	var rank := String(result.get("rank", "C"))
	var failed := bool(result.get("failed", false))
	if not failed:
		mark_level_completed(level.id)
		data["score_total"] = int(data.get("score_total", 0)) + score
		data["counters"]["levels_completed"] = int(data["counters"].get("levels_completed", 0)) + 0
		if difficulty == &"EXPERT" and level_id not in data["expert_levels"]:
			data["expert_levels"].append(level_id)
		if mode == &"COMMAND" and level_id not in data["command_wins"]:
			data["command_wins"].append(level_id)
	var highscores: Dictionary = data["highscores"]
	var prev: Dictionary = highscores.get(level_id, {})
	if score > int(prev.get("score", 0)) or not prev.has("score"):
		highscores[level_id] = {
			"score": score, "rank": rank, "mode": String(mode),
			"difficulty": String(difficulty), "time": float(result.get("time", 0.0))
		}
	# Run counters feed lifetime achievements.
	_add_counter("doors_kicked", int(result.get("doors_kicked", 0)))
	_add_counter("rescues", int(result.get("rescues", 0)))
	_add_counter("barrel_kills", int(result.get("barrel_kills", 0)))
	_add_counter("hunter_interrupts", int(result.get("hunter_interrupts", 0)))
	_add_counter("witch_crowns", int(result.get("witch_crowns", 0)))
	_add_counter("molotov_kills", int(result.get("molotov_kills", 0)))
	for kind in result.get("codex", []):
		if String(kind) not in data["codex"]:
			data["codex"].append(String(kind))
	var hidden: Array = result.get("hidden_rooms", [])
	for room_id in hidden:
		if String(room_id) not in data["hidden_rooms"]:
			data["hidden_rooms"].append(String(room_id))
	data["playtime"] = float(data.get("playtime", 0.0)) + float(result.get("time", 0.0))
	save()
	_check_meta_achievements()


func _add_counter(key: String, amount: int) -> void:
	if amount <= 0:
		return
	data["counters"][key] = int(data["counters"].get(key, 0)) + amount


func get_score_total() -> int:
	return int(data.get("score_total", 0))


func add_score_total(amount: int) -> void:
	data["score_total"] = int(data.get("score_total", 0)) + amount
	save()


func s_rank_count() -> int:
	var count := 0
	for entry in data.get("highscores", {}).values():
		if String(entry.get("rank", "")) == "S":
			count += 1
	return count


func unlock_character(id: StringName) -> void:
	var list: Array = data["unlocks"]["characters"]
	if String(id) not in list:
		list.append(String(id))
		save()


func unlock_weapon(id: StringName) -> void:
	var list: Array = data["unlocks"]["weapons"]
	if String(id) not in list:
		list.append(String(id))
		save()


func is_character_unlocked(id: StringName) -> bool:
	return String(id) in data["unlocks"]["characters"]


func is_weapon_unlocked(id: StringName) -> bool:
	return String(id) in data["unlocks"]["weapons"]


func set_flag(flag: StringName) -> void:
	var list: Array = data["flags"]
	if String(flag) not in list:
		list.append(String(flag))
		save()


func has_flag(flag: StringName) -> bool:
	return String(flag) in data["flags"]


func register_kill(kind: StringName) -> void:
	var key := String(kind)
	if key not in data["codex"]:
		data["codex"].append(key)


func register_hidden_room(level_id: StringName) -> void:
	var key := String(level_id) + "_hidden"
	if key not in data["hidden_rooms"]:
		data["hidden_rooms"].append(key)


func get_hidden_room_count() -> int:
	return data["hidden_rooms"].size()


func register_counter(key: String, amount: int = 1) -> void:
	_add_counter(key, amount)


func get_counter(key: String) -> int:
	return int(data["counters"].get(key, 0))


func mark_achievement(id: StringName) -> void:
	var key := String(id)
	var list: Array = data["achievements"]
	if key in list:
		return
	list.append(key)
	save()
	EventBus.achievement_unlocked.emit(StringName(key))
	AudioManager.play_sfx(&"achievement")
	EventBus.toast.emit("成就解锁", _achievement_name(key))


func has_achievement(id: StringName) -> bool:
	return String(id) in data["achievements"]


func _achievement_name(id: String) -> String:
	for ach in ACHIEVEMENTS:
		if ach["id"] == id:
			return ach["name"]
	return id


func get_achievement_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ach in ACHIEVEMENTS:
		var row := ach.duplicate()
		row["unlocked"] = has_achievement(StringName(ach["id"]))
		out.append(row)
	return out


func get_settings() -> Dictionary:
	return data.get("settings", {})


func set_settings(settings: Dictionary) -> void:
	data["settings"] = settings
	save()


func evaluate_result_achievements(result: Dictionary, level: LevelData, mode: StringName, difficulty: StringName) -> void:
	var failed := bool(result.get("failed", false))
	if failed:
		return
	if level.id == &"l01":
		mark_achievement(&"first_blood")
	if level.id == &"l11":
		mark_achievement(&"last_bastion")
	if level.id == &"l09" and mode == &"COMMAND" and int(result.get("soldiers_lost", 0)) == 0:
		mark_achievement(&"old_sergeant")
	if level.id == &"l05" and not bool(result.get("witch_woken", true)):
		mark_achievement(&"stealth")
	if level.id == &"l06" and int(result.get("defense_downs", 1)) == 0:
		mark_achievement(&"no_casualties")
	if String(result.get("rank", "")) == "S":
		mark_achievement(&"mr_perfect")
	if int(result.get("max_combo", 0)) >= 50:
		mark_achievement(&"combo_50")
	if int(result.get("soldiers_start", 0)) >= 8 and mode == &"COMMAND":
		mark_achievement(&"full_house")
	if int(result.get("squad_alive", 0)) >= 4 and mode == &"SQUAD":
		mark_achievement(&"no_one_left")
	if int(result.get("max_molotov_kills", 0)) >= 15:
		mark_achievement(&"fire_safety")
	if float(result.get("tank_kill_time", 999.0)) <= 60.0 and int(result.get("tanks_killed", 0)) > 0:
		mark_achievement(&"tank_slayer")
	if get_counter("barrel_kills") >= 50:
		mark_achievement(&"environmentalist")
	if get_counter("hunter_interrupts") >= 25:
		mark_achievement(&"hunter_interrupter")
	if get_counter("doors_kicked") >= 100:
		mark_achievement(&"door_kicker")
	if get_counter("rescues") >= 50:
		mark_achievement(&"medic")
	if get_counter("witch_crowns") >= 1:
		mark_achievement(&"witch_crowning")
	if _all_codex():
		mark_achievement(&"codex")
	if _all_hidden_rooms():
		mark_achievement(&"scavenger")
	if GameManager.all_weapons_unlocked():
		mark_achievement(&"arsenal")
	if _all_expert():
		mark_achievement(&"not_a_drill")
	_check_meta_achievements()


func _check_meta_achievements() -> void:
	if _all_codex():
		mark_achievement(&"codex")
	if _all_hidden_rooms():
		mark_achievement(&"scavenger")
	if _all_expert():
		mark_achievement(&"not_a_drill")
	if get_counter("doors_kicked") >= 100:
		mark_achievement(&"door_kicker")
	if get_counter("rescues") >= 50:
		mark_achievement(&"medic")
	if get_counter("barrel_kills") >= 50:
		mark_achievement(&"environmentalist")
	if get_counter("hunter_interrupts") >= 25:
		mark_achievement(&"hunter_interrupter")
	if get_counter("witch_crowns") >= 1:
		mark_achievement(&"witch_crowning")
	if GameManager.all_weapons_unlocked():
		mark_achievement(&"arsenal")


func _all_codex() -> bool:
	for id in CODEX_SPECIALS:
		if id not in data["codex"]:
			return false
	for id in CODEX_UNCOMMONS:
		if id not in data["codex"]:
			return false
	return true


func _all_hidden_rooms() -> bool:
	for level in GameManager.get_levels():
		if (String(level.id) + "_hidden") not in data["hidden_rooms"]:
			return false
	return GameManager.get_levels().size() >= 11


func _all_expert() -> bool:
	for level in GameManager.get_levels():
		if String(level.id) not in data["expert_levels"]:
			return false
	return GameManager.get_levels().size() >= 11


# ---------------------------------------------------------- event handlers ----
func _on_enemy_died(kind: StringName, _pos: Vector2, _score: int) -> void:
	register_kill(kind)


func _on_witch_crowned(_pos: Vector2) -> void:
	_add_counter("witch_crowns", 1)


func _on_door_kicked(_pos: Vector2) -> void:
	_add_counter("doors_kicked", 1)


func _on_player_rescued() -> void:
	_add_counter("rescues", 1)
