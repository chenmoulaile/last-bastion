extends Node
## ArchiveManager - 档案碎片收集、密级与专家解读门槛。
## 职责：加载 archive_fragments.json、记录收集进度、判定可否解读、广播 tier_changed。
## 依赖：SaveSystem（持久化）、EventBus。
## 对外接口：fragments / collected_ids / can_decode(frag) / collect(id) /
##           current_tier() / total_count() / collected_count()

signal tier_changed(tier: int)
signal fragment_collected(id: StringName)
signal archive_library_changed

const DATA_PATH := "res://resources/data/archives/archive_fragments.json"
const TIER_NAMES := ["谣言 RUMOR", "证据 EVIDENCE", "共谋 COMPLICITY", "深渊 THE DEEP"]

var fragments: Dictionary = {}                 # id -> Dictionary
var collected_ids: Array = []                  # of StringName


func _ready() -> void:
	_load()
	var saved: Array = SaveSystem.data.get("archives_collected", [])
	for id in saved:
		if fragments.has(StringName(String(id))):
			collected_ids.append(StringName(String(id)))


func _load() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("archive_fragments.json missing")
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has("id"):
				fragments[StringName(entry["id"])] = entry


func total_count() -> int:
	return fragments.size()


func collected_count() -> int:
	return collected_ids.size()


func current_tier() -> int:
	var best := -1
	for id in collected_ids:
		var frag: Dictionary = fragments.get(id, {})
		best = maxi(best, int(frag.get("tier", 0)))
	return best


func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, 3)]


func get_fragment(id: StringName) -> Dictionary:
	return fragments.get(id, {})


## 队伍里是否有对应专家（四主角被动解锁高密级档案）。
func party_has_specialist(kind: StringName) -> bool:
	if kind == &"":
		return true
	var party: Array = [GameManager.selected_character]
	for cid in GameManager.selected_squad:
		party.append(cid)
	for cid in party:
		var ch := GameManager.get_character(StringName(cid))
		if ch != null and (ch as CharacterData).archive_types.has(kind):
			return true
	return false


func can_decode(id: StringName) -> bool:
	var frag := get_fragment(id)
	if frag.is_empty():
		return false
	return party_has_specialist(StringName(frag.get("requires", "")))


func is_collected(id: StringName) -> bool:
	return collected_ids.has(id)


func collect(id: StringName) -> void:
	if is_collected(id) or not fragments.has(id):
		return
	collected_ids.append(id)
	var store: Array = SaveSystem.data.get("archives_collected", [])
	store.append(String(id))
	SaveSystem.data["archives_collected"] = store
	SaveSystem.save()
	var before := current_tier()
	fragment_collected.emit(id)
	archive_library_changed.emit()
	var after := current_tier()
	if after > before:
		tier_changed.emit(after)
		EventBus.notify.emit("档案密级提升：%s" % tier_name(after))
	EventBus.notify.emit("获得档案碎片：%s" % String(get_fragment(id).get("title", id)))


## 未收集的碎片按关卡分组（档案库 UI 用）。
func fragments_by_level() -> Dictionary:
	var out: Dictionary = {}
	for id in fragments.keys():
		var level_id := String(get_fragment(id).get("level", ""))
		if not out.has(level_id):
			out[level_id] = []
		out[level_id].append(id)
	return out
