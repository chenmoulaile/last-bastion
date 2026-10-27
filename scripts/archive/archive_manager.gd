extends Node
## ArchiveManager - the narrative progression spine.
##
## Responsibilities:
##   * own the fragment registry (res://resources/data/archives/*.tres)
##   * gate unlocks by survivor expertise / passive
##   * answer "how much does the player know?" for the AI Director
##   * persist unlocks through SaveSystem
##   * own the final-choice outcome (destroy / decode) and New Game+ state
##
## It never touches level nodes: pickups ask it for permission, the Director
## asks it for a knowledge level, UI asks it for lists.

const DATA_DIR := "res://resources/data/archives"
const JSON_PATH := "res://resources/data/archives/archive_fragments.json"
const SAVE_KEY := "archives"
const CHOICE_DESTROY := "destroy"
const CHOICE_DECODE := "decode"

var fragments: Dictionary = {} # fragment_id -> ArchiveFragment
var unlocked: Array[String] = []
var final_choice: String = ""

var _pending: Array[String] = []
var _jam_zones: Array[Dictionary] = []


func _ready() -> void:
	_load_fragments()
	_load_progress()


# ------------------------------------------------------------------ data ----
func _load_fragments() -> void:
	fragments.clear()
	_load_tres_fragments()
	_load_json_fragments()


## Bulk narrative content lives in JSON (fast to edit, no editor round-trip);
## one-off fragments can still ship as .tres resources with audio/images.
func _load_json_fragments() -> void:
	if not FileAccess.file_exists(JSON_PATH):
		return
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		push_warning("Archive JSON invalid: " + JSON_PATH)
		return
	var rows: Variant = (parsed as Dictionary).get("fragments", [])
	if not (rows is Array):
		return
	for row in (rows as Array):
		if not (row is Dictionary):
			continue
		var data: Dictionary = row
		var fragment := ArchiveFragment.new()
		fragment.fragment_id = String(data.get("fragment_id", ""))
		if fragment.fragment_id == "":
			continue
		fragment.title = String(data.get("title", fragment.fragment_id))
		fragment.security_level = int(data.get("security_level", 1))
		fragment.chapter = int(data.get("chapter", 1))
		fragment.level = int(data.get("level", 1))
		fragment.source = String(data.get("source", ""))
		fragment.timestamp = String(data.get("timestamp", ""))
		fragment.content_text = String(data.get("content_text", ""))
		fragment.translation = String(data.get("translation", ""))
		fragment.content_type = String(data.get("content_type", "text"))
		fragment.required_character = String(data.get("required_character", ""))
		fragment.required_passive = String(data.get("required_passive", ""))
		fragment.archive_type = String(data.get("archive_type",
			ArchiveFragment.SECURITY_NAMES.get(fragment.security_level, "rumor").to_lower()))
		fragments[fragment.fragment_id] = fragment


func _load_tres_fragments() -> void:
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("Archive data directory missing: " + DATA_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = load(DATA_DIR + "/" + file_name)
		if res == null:
			continue
		var fragment := res as ArchiveFragment
		if fragment == null or fragment.fragment_id == "":
			continue
		fragments[fragment.fragment_id] = fragment


func _load_progress() -> void:
	unlocked.clear()
	var raw: Variant = SaveSystem.data.get(SAVE_KEY, [])
	if raw is Array:
		for id in (raw as Array):
			var key := String(id)
			if key != "" and key not in unlocked:
				unlocked.append(key)
	final_choice = String(SaveSystem.data.get("final_choice", ""))


func _persist() -> void:
	SaveSystem.data[SAVE_KEY] = unlocked.duplicate()
	SaveSystem.data["final_choice"] = final_choice
	SaveSystem.save()


# --------------------------------------------------------------- queries ----
func get_fragment(fragment_id: String) -> ArchiveFragment:
	return fragments.get(fragment_id, null)


func is_unlocked(fragment_id: String) -> bool:
	return fragment_id in unlocked


func total_count() -> int:
	return fragments.size()


func unlocked_count() -> int:
	return unlocked.size()


func highest_security_level_collected() -> int:
	var best := 0
	for id in unlocked:
		var fragment: ArchiveFragment = fragments.get(id, null)
		if fragment != null:
			best = maxi(best, fragment.security_level)
	return best


func count_by_security(level: int) -> int:
	var count := 0
	for id in unlocked:
		var fragment: ArchiveFragment = fragments.get(id, null)
		if fragment != null and fragment.security_level == level:
			count += 1
	return count


func fragments_for_chapter(chapter: int) -> Array[ArchiveFragment]:
	var out: Array[ArchiveFragment] = []
	for fragment in fragments.values():
		if fragment.chapter == chapter:
			out.append(fragment)
	out.sort_custom(func(a: ArchiveFragment, b: ArchiveFragment) -> bool:
		if a.security_level == b.security_level:
			return a.fragment_id < b.fragment_id
		return a.security_level < b.security_level)
	return out


func fragments_for_level(chapter: int, level: int) -> Array[ArchiveFragment]:
	var out: Array[ArchiveFragment] = []
	for fragment in fragments_for_chapter(chapter):
		if fragment.level == level:
			out.append(fragment)
	return out


## Chapter thresholds that gate the "extra archive spawn" rule and hidden talks.
func chapter_threshold(chapter: int) -> int:
	match chapter:
		1:
			return 2 # >= 2 RUMOR
		2:
			return 2 # >= 2 EVIDENCE
		3:
			return 2 # >= 2 COMPLICITY
		_:
			return 1 # >= 1 THE_DEEP


func chapter_required_security(chapter: int) -> int:
	return clampi(chapter, 1, 4)


func chapter_quota_met(chapter: int) -> bool:
	return count_by_security(chapter_required_security(chapter)) >= chapter_threshold(chapter)


## The chapter 4 final choice is only available with a THE_DEEP fragment
## (the signal core recording) in hand.
func can_decode_signal() -> bool:
	return count_by_security(4) >= 1


# --------------------------------------------------------------- unlocks ----
## Returns {ok: bool, reason: String, fragment: ArchiveFragment}.
func try_unlock(fragment_id: String, character_id: String, passive_id: String = "") -> Dictionary:
	var fragment: ArchiveFragment = fragments.get(fragment_id, null)
	if fragment == null:
		return {"ok": false, "reason": "档案不存在", "fragment": null}
	if is_unlocked(fragment_id):
		return {"ok": false, "reason": "已收录", "fragment": fragment}
	if fragment.required_character != "" and fragment.required_character != character_id:
		return {
			"ok": false,
			"reason": "需要%s的专业知识" % fragment.required_specialist_name(),
			"fragment": fragment,
		}
	if fragment.required_passive != "" and fragment.required_passive != passive_id:
		return {"ok": false, "reason": "需要特定专长", "fragment": fragment}
	_force_unlock(fragment_id)
	return {"ok": true, "reason": "", "fragment": fragment}


## Story-critical fragments bypass the expertise gate.
func force_unlock(fragment_id: String) -> bool:
	if not fragments.has(fragment_id) or is_unlocked(fragment_id):
		return false
	_force_unlock(fragment_id)
	return true


func _force_unlock(fragment_id: String) -> void:
	unlocked.append(fragment_id)
	var fragment: ArchiveFragment = fragments.get(fragment_id, null)
	_persist()
	EventBus.archive_unlocked.emit(fragment_id, fragment.security_level if fragment != null else 1)
	EventBus.archive_progress_changed.emit(unlocked.size(), highest_security_level_collected())
	AudioManager.play_sfx(&"unlock")
	_refresh_noise()


# --------------------------------------------------------------- spawning ----
## Which fragments should a level offer? Story fragments first, then fill up to
## `slots` with locked fragments of that chapter. When the previous chapter's
## quota is unmet, the caller asks for extra slots (see extra_spawn_slots()).
func plan_for_level(chapter: int, level: int, slots: int) -> Array[String]:
	var out: Array[String] = []
	var pool := fragments_for_level(chapter, level)
	for fragment in pool:
		if out.size() >= slots:
			break
		if not is_unlocked(fragment.fragment_id):
			out.append(fragment.fragment_id)
	if out.size() < slots:
		for fragment in fragments_for_chapter(chapter):
			if out.size() >= slots:
				break
			if not is_unlocked(fragment.fragment_id) and fragment.fragment_id not in out:
				out.append(fragment.fragment_id)
	return out


## Extra spawn points when the player is falling behind the narrative curve.
func extra_spawn_slots(previous_chapter: int) -> int:
	if previous_chapter <= 0:
		return 0
	return 0 if chapter_quota_met(previous_chapter) else 2


func next_missing_fragment(chapter: int) -> String:
	for fragment in fragments_for_chapter(chapter):
		if not is_unlocked(fragment.fragment_id):
			return fragment.fragment_id
	return ""


# ---------------------------------------------------------------- choices ----
func record_final_choice(choice: String) -> void:
	final_choice = choice
	SaveSystem.data["final_choice"] = choice
	SaveSystem.set_flag(StringName("ending_" + choice))
	if choice == CHOICE_DESTROY:
		SaveSystem.mark_achievement(&"silent_price")
	else:
		SaveSystem.mark_achievement(&"answer")
	_persist()
	EventBus.final_choice_made.emit(choice)


func has_final_choice() -> bool:
	return final_choice != ""


## New Game+ broadcast text, driven by the ending the player picked.
func new_game_plus_broadcast() -> String:
	match final_choice:
		CHOICE_DESTROY:
			return "信号消失，但 1.7 GHz 背景噪声仍在。"
		CHOICE_DECODE:
			return "信号已接收。回应将在 72 小时内到达。"
		_:
			return ""


func unlocks_lin_yuan_epilogue() -> bool:
	return final_choice == CHOICE_DECODE


# ---------------------------------------------------------------- jamming ----
## 信号局的干扰器会临时封锁区域内的档案交互。
func jam_zone(pos: Vector2, radius: float, duration: float) -> void:
	_jam_zones.append({
		"pos": pos,
		"radius": radius,
		"until": Time.get_ticks_msec() + int(duration * 1000.0),
	})


func is_jammed(pos: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	for zone in _jam_zones:
		if int(zone["until"]) <= now:
			continue
		kept.append(zone)
	_jam_zones = kept
	for zone in _jam_zones:
		var center: Vector2 = zone["pos"]
		if center.distance_to(pos) <= float(zone["radius"]):
			return true
	return false


# ---------------------------------------------------------------- helpers ----
func _refresh_noise() -> void:
	var level := float(highest_security_level_collected()) / 4.0
	EventBus.signal_noise_changed.emit(level)
	if AudioManager.has_method("set_signal_noise"):
		AudioManager.set_signal_noise(level)


## Test / debug helper: wipe narrative progress without touching the save file
## on disk (the caller decides whether to persist).
func reset_progress(persist: bool = false) -> void:
	unlocked.clear()
	final_choice = ""
	if persist:
		_persist()


func debug_unlock_all() -> void:
	for id in fragments.keys():
		if not is_unlocked(id):
			_force_unlock(id)
