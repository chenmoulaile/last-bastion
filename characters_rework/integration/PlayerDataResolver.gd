class_name ReworkPlayerDataResolver
extends RefCounted
## Resolves the legacy / narrative character selection into a ReworkCharacterData
## instance. Kept outside PlayerControllerV2 so the level runner and tests can
## share the same 6 -> 4 narrative mapping without duplicating tables.

const PLAYABLE_DIR := "res://characters_rework/data/playable"
const FALLBACK_ID: StringName = &"assault"

## Archive survivor id (legacy CharacterData) -> rework playable id.
const NARRATIVE_TO_REWORK: Dictionary = {
	&"lin_yuan": &"operative",
	&"marcus": &"heavy",
	&"lucia": &"scout",
	&"victor": &"medic",
}

## Legacy archetypes whose ids do not exist in the rework roster.
const LEGACY_TO_REWORK: Dictionary = {
	&"ninja": &"operative",
	&"rifleman": &"assault",
	&"gunner": &"heavy",
	&"demolisher": &"heavy",
	&"medic_soldier": &"medic",
}


static func for_selected(selected: StringName) -> ReworkCharacterData:
	var id := _resolve_id(selected)
	var data := _load(id)
	if data == null and id != FALLBACK_ID:
		data = _load(FALLBACK_ID)
	return data


static func _resolve_id(selected: StringName) -> StringName:
	if selected == &"":
		return FALLBACK_ID
	if ResourceLoader.exists(_path(selected)):
		return selected
	if NARRATIVE_TO_REWORK.has(selected):
		return NARRATIVE_TO_REWORK[selected]
	if LEGACY_TO_REWORK.has(selected):
		return LEGACY_TO_REWORK[selected]
	return FALLBACK_ID


static func _load(id: StringName) -> ReworkCharacterData:
	var path := _path(id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ReworkCharacterData


static func _path(id: StringName) -> String:
	return "%s/%s.tres" % [PLAYABLE_DIR, String(id)]


static func available_ids() -> Array[StringName]:
	var out: Array[StringName] = [
		&"assault", &"heavy", &"medic", &"scout", &"operative", &"officer",
	]
	return out
