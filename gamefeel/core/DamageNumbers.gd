class_name GameFeelDamageNumbers
extends CanvasLayer
## Pooled floating damage numbers. 40 labels are pre-allocated; spawning never
## creates a node. Labels follow their world anchor by converting through the
## viewport canvas transform each frame, so camera movement cannot separate the
## number from the hit.
##
## Created by GameFeelBridge; never touches combat state.

const MAX_LABELS := 40
const COMBO_WINDOW := 1.5
const RISE_PIXELS := 30.0
const LIFE := 0.62

const COLOR_NORMAL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_CRIT := Color(1.0, 0.88, 0.30, 1.0)
const COLOR_PLAYER := Color(1.0, 0.30, 0.26, 1.0)
const COLOR_HEAL := Color(0.52, 0.92, 0.58, 1.0)
const COLOR_WARM := Color(1.0, 0.58, 0.24, 1.0)

var _root: Control
var _labels: Array[Label] = []
var _states: Array[Dictionary] = []
var _combo: Dictionary = {}
var _font: Font
var _hidden: bool = false


func _ready() -> void:
	layer = 66
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = load("res://assets/fonts/silkscreen_bold.ttf")
	if _font == null:
		_font = load("res://assets/fonts/silkscreen.ttf")
	_root = Control.new()
	_root.name = "DamageNumberRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for i in MAX_LABELS:
		var label := Label.new()
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(96, 18)
		label.pivot_offset = Vector2(48, 9)
		label.z_index = 2
		if _font != null:
			label.add_theme_font_override("font", _font)
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_color", COLOR_NORMAL)
		_root.add_child(label)
		_labels.append(label)


func _process(delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"damage_numbers") \
			or not GameFeelConfig.damage_number_enabled:
		if not _hidden:
			_hide_all()
			_hidden = true
		return
	_hidden = false
	if _states.is_empty():
		return
	var canvas := get_viewport().get_canvas_transform()
	var expired: Array[int] = []
	for index in _states.size():
		var state: Dictionary = _states[index]
		state["t"] = float(state["t"]) + delta
		var life := float(state["life"])
		var t := float(state["t"])
		if t >= life:
			expired.append(index)
			continue
		# (expired indices are removed in reverse below)
		var progress := clampf(t / life, 0.0, 1.0)
		var world: Vector2 = state["world"]
		var screen := canvas * world
		var label: Label = state["label"]
		var drift := Vector2(sin(float(state["seed"]) + t * 5.0) * 3.0, -RISE_PIXELS * progress)
		label.position = screen + drift - Vector2(label.size.x * 0.5, 15.0)
		var fade := 1.0
		if progress > 0.55:
			fade = 1.0 - (progress - 0.55) / 0.45
		label.modulate.a = clampf(fade, 0.0, 1.0)
		if bool(state["crit"]) and t < 0.15:
			var bounce := 1.0 + 0.30 * sin((t / 0.15) * PI)
			label.scale = Vector2(bounce, bounce)
		else:
			label.scale = Vector2.ONE
	for i in range(expired.size() - 1, -1, -1):
		var remove_at := expired[i]
		if remove_at >= 0 and remove_at < _states.size():
			var state: Dictionary = _states[remove_at]
			var label: Label = state["label"]
			label.visible = false
			label.scale = Vector2.ONE
			_states.remove_at(remove_at)


## Normal enemy damage. `target_key` drives the per-target combo counter.
func spawn(amount: int, world: Vector2, crit: bool = false, target_key: int = 0,
		color: Color = COLOR_NORMAL) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"damage_numbers") \
			or not GameFeelConfig.damage_number_enabled:
		return
	if amount <= 0:
		return
	var now := Time.get_ticks_usec()
	var text := str(amount)
	var use_color := COLOR_CRIT if crit else color
	var life := 0.78 if crit else LIFE
	if target_key != 0:
		var entry: Variant = _combo.get(target_key, null)
		if entry is Dictionary and now - int((entry as Dictionary)["last"]) <= int(COMBO_WINDOW * 1_000_000.0):
			var count := int((entry as Dictionary)["count"]) + 1
			var total := int((entry as Dictionary)["total"]) + amount
			(entry as Dictionary)["count"] = count
			(entry as Dictionary)["total"] = total
			(entry as Dictionary)["last"] = now
			_combo[target_key] = entry
			text = "%d × %d" % [total, count]
			use_color = COLOR_NORMAL.lerp(COLOR_WARM, clampf(float(count - 1) / 6.0, 0.0, 1.0))
			life = maxf(life, 0.7)
		else:
			_combo[target_key] = {"count": 1, "total": amount, "last": now}
	_emit_label(text, world, crit, use_color, life)
	_prune_combo(now)


func spawn_player(amount: int, world: Vector2) -> void:
	if amount <= 0:
		return
	_emit_label("-" + str(amount), world + Vector2(0, -8), false, COLOR_PLAYER, 0.8)


func spawn_heal(amount: int, world: Vector2) -> void:
	if amount <= 0:
		return
	_emit_label("+" + str(amount), world + Vector2(0, -8), false, COLOR_HEAL, 0.8)


func spawn_text(text: String, world: Vector2, color: Color = COLOR_CRIT) -> void:
	_emit_label(text, world, true, color, 0.9)


func active_count() -> int:
	return _states.size()


func pool_size() -> int:
	return _labels.size()


func clear_all() -> void:
	for state in _states:
		var label: Label = state["label"]
		label.visible = false
		label.scale = Vector2.ONE
	_states.clear()
	_combo.clear()


func _emit_label(text: String, world: Vector2, crit: bool, color: Color, life: float) -> void:
	_hidden = false
	var label := _oldest_free_label()
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13 if crit else 9)
	label.modulate = Color(1, 1, 1, 1)
	label.scale = Vector2.ONE
	label.visible = true
	var canvas := get_viewport().get_canvas_transform()
	label.position = canvas * world - Vector2(label.size.x * 0.5, 15.0)
	_states.append({
		"label": label,
		"world": world,
		"t": 0.0,
		"life": life,
		"crit": crit,
		"seed": randf() * TAU,
		"seq": Time.get_ticks_usec(),
	})
	if _states.size() > MAX_LABELS:
		var oldest: Dictionary = _states.pop_front()
		var old_label: Label = oldest["label"]
		old_label.visible = false


func _oldest_free_label() -> Label:
	for label in _labels:
		var used := false
		for state in _states:
			if state["label"] == label:
				used = true
				break
		if not used:
			return label
	return null


func _hide_all() -> void:
	for label in _labels:
		label.visible = false
	_states.clear()
	_combo.clear()


func _prune_combo(now: int) -> void:
	var expired: Array = []
	for key in _combo.keys():
		var entry: Dictionary = _combo[key]
		if now - int(entry["last"]) > int(COMBO_WINDOW * 1_000_000.0):
			expired.append(key)
	for key in expired:
		_combo.erase(key)


func _repack_indices() -> void:
	# Kept as a hook for future pool compaction; state dictionaries are already
	# ordered by spawn sequence.
	pass
