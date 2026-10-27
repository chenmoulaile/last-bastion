extends Node
## DialogueManager - barks, scripted conversations and the subtitle layer.
##
## Rules from the narrative design:
##   * 林远的 bark 数量是其他角色的 1/3，且每次发言让全队沉默 1.5 秒。
##   * 林远说中文 -> 中文字幕；其他角色说英文 -> 英文字幕 + 中文翻译。
##   * 对话数据全部放在 res://resources/data/dialogues/*.json，方便填充。
##
## The manager owns only its own CanvasLayer; it never touches level nodes.

const BARK_PATH := "res://resources/data/dialogues/barks.json"
const CONVERSATION_PATH := "res://resources/data/dialogues/conversations.json"
const LIN_YUAN := "lin_yuan"
const LIN_YUAN_SILENCE := 1.5
const LIN_YUAN_BARK_GAP := 9.0
const BARK_GAP := 3.0

const NPC_COLORS := {
	"marlo": Color(0.86, 0.52, 0.26),
	"reyes": Color(0.46, 0.62, 0.82),
	"signal_core": Color(0.42, 0.82, 0.78),
	"xiaoman": Color(0.92, 0.72, 0.80),
	"narrator": Color(0.72, 0.72, 0.68),
}

var barks: Dictionary = {}
var conversations: Dictionary = {}
var is_busy: bool = false
var current_sequence: String = ""

var _layer: CanvasLayer
var _panel: Panel
var _speaker_label: Label
var _text_label: Label
var _translation_label: Label
var _hide_timer: float = 0.0
var _silence_until: float = 0.0
var _last_bark: Dictionary = {}
var _last_bark_id: Dictionary = {}


func _ready() -> void:
	_load_data()
	_build_ui()
	set_process(true)


func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0 and not is_busy:
			_panel.visible = false


# ------------------------------------------------------------------ data ----
func _load_data() -> void:
	barks = _read_json(BARK_PATH)
	conversations = _read_json(CONVERSATION_PATH)
	# JSON files carry a "_comment" documentation key; it is not a speaker.
	barks.erase("_comment")
	conversations.erase("_comment")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Dialogue data missing: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		push_warning("Dialogue data invalid: " + path)
		return {}
	return parsed as Dictionary


# -------------------------------------------------------------------- ui ----
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "DialogueLayer"
	_layer.layer = 85
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.04, 0.05, 0.92), UIKit.LINE))
	# Sits above the bottom HUD panels (health / weapon) so subtitles never
	# cover the player's own status.
	_panel.position = Vector2(52, 196)
	_panel.size = Vector2(536, 62)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_layer.add_child(_panel)

	_speaker_label = UIKit.label("", 8, UIKit.AMBER, UIKit.font_latin())
	_speaker_label.position = Vector2(8, 3)
	_speaker_label.size = Vector2(520, 10)
	_panel.add_child(_speaker_label)

	_text_label = UIKit.label("", 11, UIKit.INK, UIKit.font_cjk())
	_text_label.position = Vector2(8, 14)
	_text_label.size = Vector2(520, 18)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_text_label)

	_translation_label = UIKit.label("", 9, UIKit.MUTED, UIKit.font_cjk())
	_translation_label.position = Vector2(8, 34)
	_translation_label.size = Vector2(520, 24)
	_translation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_translation_label)


func _speaker_name(speaker_id: String) -> String:
	var character: CharacterData = GameManager.get_character(StringName(speaker_id))
	if character != null:
		return character.display_name + " · " + character.callsign
	match speaker_id:
		"marlo":
			return "马洛 · RUST GANG"
		"reyes":
			return "雷耶斯 · REMNANT PD"
		"signal_core":
			return "信号核心 · 1.7 GHz"
		"xiaoman":
			return "林小满 · ADAPTER-07"
		"narrator":
			return "档案记录"
		_:
			return speaker_id.to_upper()


func _speaker_color(speaker_id: String) -> Color:
	var character: CharacterData = GameManager.get_character(StringName(speaker_id))
	if character != null:
		return character.dialogue_color
	return NPC_COLORS.get(speaker_id, UIKit.INK)


# ------------------------------------------------------------------ barks ----
## Short combat line. Returns false when suppressed (conversation, silence
## window, rate limit or the character simply has nothing to say).
func play_bark(character_id: String, bark_id: String, force: bool = false) -> bool:
	if is_busy and not force:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now < _silence_until:
		return false
	var gap := LIN_YUAN_BARK_GAP if character_id == LIN_YUAN else BARK_GAP
	if not force and _last_bark.has(character_id) \
			and now - float(_last_bark[character_id]) < gap:
		return false
	var pool := _bark_pool(character_id, bark_id)
	if pool.is_empty():
		return false
	var text: String = pool[randi() % pool.size()]
	if not force and _last_bark_id.get(character_id, "") == text and pool.size() > 1:
		text = pool[(pool.find(text) + 1) % pool.size()]
	_last_bark[character_id] = now
	_last_bark_id[character_id] = text
	var color := _speaker_color(character_id)
	EventBus.dialogue_bark.emit(character_id, text, color)
	_show_line(_speaker_name(character_id), text, "", color, 2.6)
	# 林远开口 -> 全队短暂沉默。
	if character_id == LIN_YUAN:
		_silence_until = now + LIN_YUAN_SILENCE
	return true


func _bark_pool(character_id: String, bark_id: String) -> Array:
	var by_character: Variant = barks.get(character_id)
	if by_character == null or not (by_character is Dictionary):
		return []
	var pool: Variant = (by_character as Dictionary).get(bark_id)
	if pool == null or not (pool is Array):
		return []
	return pool as Array


## 林远的 bark 总量：数据层面每个 id 只有 1 条，这里再暴露一个统计给测试用。
func bark_variant_count(character_id: String) -> int:
	var by_character: Variant = barks.get(character_id)
	if by_character == null or not (by_character is Dictionary):
		return 0
	var total := 0
	for key in (by_character as Dictionary).keys():
		var pool: Variant = (by_character as Dictionary)[key]
		if pool is Array:
			total += (pool as Array).size()
	return total


# ------------------------------------------------------------ conversations ----
func play_conversation(conversation_id: String, interrupt: bool = false) -> void:
	if is_busy and not interrupt:
		return
	var entry: Variant = conversations.get(conversation_id)
	if entry == null or not (entry is Dictionary):
		push_warning("Unknown conversation: " + conversation_id)
		return
	var lines: Variant = (entry as Dictionary).get("lines", [])
	if not (lines is Array) or (lines as Array).is_empty():
		return
	is_busy = true
	current_sequence = conversation_id
	EventBus.dialogue_sequence_started.emit(conversation_id)
	for line in lines:
		if not (line is Dictionary):
			continue
		var row: Dictionary = line
		var speaker := String(row.get("speaker", "narrator"))
		var text := String(row.get("text", ""))
		var translation := String(row.get("translation", ""))
		var duration := float(row.get("duration", 2.8))
		var color := _speaker_color(speaker)
		EventBus.dialogue_line.emit(speaker, text, translation, duration)
		_show_line(_speaker_name(speaker), text, translation, color, duration)
		if speaker == LIN_YUAN:
			_silence_until = Time.get_ticks_msec() / 1000.0 + LIN_YUAN_SILENCE
		await get_tree().create_timer(duration, true, false, true).timeout
	is_busy = false
	current_sequence = ""
	_panel.visible = false
	EventBus.dialogue_sequence_finished.emit(conversation_id)


func stop() -> void:
	is_busy = false
	current_sequence = ""
	_panel.visible = false


func has_conversation(conversation_id: String) -> bool:
	return conversations.has(conversation_id)


# ------------------------------------------------------------------- view ----
func _show_line(speaker: String, text: String, translation: String, color: Color, duration: float) -> void:
	_speaker_label.text = speaker
	_speaker_label.add_theme_color_override("font_color", color)
	_text_label.text = text
	_text_label.add_theme_color_override("font_color", UIKit.INK)
	_translation_label.text = translation
	_translation_label.visible = translation != "" and translation != text
	_panel.visible = true
	_hide_timer = duration + 0.35
