class_name GameHUD
extends CanvasLayer
## In-mission HUD. Reads presentation state from LevelRunner and reacts to
## EventBus; it never owns gameplay state. Runs while paused so the pause menu
## and overlays stay alive.

const VIEW := Vector2(640, 360)
const ROW_H := 20.0
const THREAT_ARROWS := preload("res://scripts/ui/threat_arrows.gd")

var level: Node = null

var _root: Control
var _team_panel: Panel
var _member_rows: Array[Dictionary] = []
var _player_row: Dictionary
var _team_columns: int = 1

var _objective_label: Label
var _objective_fill: ColorRect
var _director_fill: ColorRect
var _director_label: Label
var _score_label: Label
var _combo_label: Label
var _streak_label: Label
var _killstreak: int = 0
var _streak_timer: float = 0.0
var _time_label: Label
var _level_label: Label

var _boss_panel: Panel
var _boss_label: Label
var _boss_fill: ColorRect
var _boss_kind: StringName = &""
var _boss_ratio: float = 0.0

var _timer_panel: Panel
var _timer_label: Label
var _timer_fill: ColorRect
var _timer_mode: String = ""

var _hp_fill: ColorRect
var _temp_fill: ColorRect
var _hp_text: Label
var _player_name: Label
var _status_text: Label
var _downs_text: Label
var _weapon_name: Label
var _ammo_text: Label
var _weapon_state: Label
var _skill_icon: TextureRect
var _skill_cover: ColorRect
var _skill_ready: Label
var _medkit_count: Label
var _pills_count: Label
var _throw_icons: Array[TextureRect] = []
var _throw_counts: Array[Label] = []
var _throw_index: int = 0
var _weapon_id: StringName = &""
var _weapon_mag: int = 0
var _weapon_reserve: int = 0
var _currency_label: Label
var _currency_icon: Control

var _command_panel: Panel
var _command_cells: Dictionary = {}
var _formation_label: Label
var _threat_arrows: Control
var _debug_panel: Panel
var _debug_label: Label
var _debug_ally_label: Label
var _debug_open: bool = false

var _prompt_panel: Panel
var _prompt_label: Label
var _downed_label: Label
var _event_label: Label
var _notify_box: VBoxContainer

var _crosshair: TextureRect
var _hitmarker: TextureRect
var _hitmarker_tween: Tween
var _damage_flash: ColorRect
var _damage_tween: Tween
var _lowhp: TextureRect
var _bile: TextureRect
var _rain_a: TextureRect
var _rain_b: TextureRect
var _grain: TextureRect

var _pause_root: Control
var _pause_open: bool = false
var _event_tween: Tween
var _refresh_accum: float = 0.0
var _clock_accum: float = 0.0
var _time_shown: float = -1.0
var _director_value: float = 0.0
var _last_hp: int = -1
var _last_temp: int = -1


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_overlays()
	_build_threat_arrows()
	_build_team_panel()
	_build_top_center()
	_build_score_panel()
	_build_boss_bar()
	_build_timer_bar()
	_build_player_panel()
	_build_weapon_panel()
	_currency_label.text = str(GameManager.get_currency())
	_build_command_panel()
	_build_prompt()
	_build_event_banner()
	_build_notifications()
	_build_crosshair()
	_build_pause()
	_build_debug_panel()
	_connect_events()
	_refresh_team()
	_refresh_player(true)
	_refresh_weapon()
	_refresh_objective()
	_refresh_time(true)
	_setup_rain()
	_apply_visibility()
	EventBus.interact_prompt.emit("")


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Engine.time_scale = 1.0
	get_tree().paused = false


# ------------------------------------------------------------------ build ----
func _build_overlays() -> void:
	var vignette := TextureRect.new()
	vignette.texture = UIKit.icon("vignette")
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.modulate = Color(1, 1, 1, 0.72)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vignette)

	_grain = TextureRect.new()
	_grain.texture = UIKit.icon("grain")
	_grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_grain.stretch_mode = TextureRect.STRETCH_TILE
	_grain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_grain.modulate = Color(1, 1, 1, 0.055)
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_grain)

	_rain_a = _make_rain_rect(0.55, 0.34)
	_rain_b = _make_rain_rect(0.92, 0.20)
	_rain_b.scale = Vector2(1.0, 1.0)

	_lowhp = TextureRect.new()
	_lowhp.texture = UIKit.icon("lowhp")
	_lowhp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lowhp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lowhp.stretch_mode = TextureRect.STRETCH_SCALE
	_lowhp.modulate = Color(1, 1, 1, 0.0)
	_lowhp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_lowhp)

	_bile = TextureRect.new()
	_bile.texture = UIKit.icon("bile_overlay")
	_bile.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bile.stretch_mode = TextureRect.STRETCH_SCALE
	_bile.modulate = Color(1, 1, 1, 0.0)
	_bile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bile)

	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.62, 0.04, 0.03, 0.0)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage_flash)


func _make_rain_rect(speed: float, alpha: float) -> TextureRect:
	var rain := TextureRect.new()
	rain.texture = UIKit.icon("rain")
	rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	rain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rain.stretch_mode = TextureRect.STRETCH_SCALE
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float fall_speed = 0.55;
uniform float drift = 0.03;
uniform float opacity = 0.3;
void fragment() {
	vec2 uv = fract(UV + vec2(TIME * drift, TIME * fall_speed));
	vec4 c = texture(TEXTURE, uv);
	COLOR = vec4(c.rgb, c.a * opacity);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fall_speed", speed)
	mat.set_shader_parameter("opacity", alpha)
	rain.material = mat
	_root.add_child(rain)
	return rain


func _setup_rain() -> void:
	var raining := false
	if level != null:
		var d: LevelData = level.get("data")
		raining = d != null and d.rain
	_rain_a.visible = raining
	_rain_b.visible = raining


func _build_team_panel() -> void:
	var allies: Array = level.get_allies() if level and level.has_method("get_allies") else []
	var count := 1 + allies.size()
	var command := GameManager.current_mode == &"COMMAND"
	_team_columns = 2 if command else 1
	var rows := int(ceil(float(count) / float(_team_columns)))
	var width := 168.0 if command else 158.0
	var height := 16.0 + rows * ROW_H + 4.0
	_team_panel = UIKit.panel()
	_team_panel.position = Vector2(8, 8)
	_team_panel.size = Vector2(width, height)
	_root.add_child(_team_panel)
	var header := UIKit.label("SQUAD" if not command else "COMMAND", 7, UIKit.MUTED, UIKit.font_latin())
	header.position = Vector2(5, 3)
	_team_panel.add_child(header)
	var count_label := UIKit.label("%d 人" % count, 7, UIKit.DIM)
	count_label.position = Vector2(width - 36, 3)
	count_label.size = Vector2(30, 9)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_team_panel.add_child(count_label)

	var col_width := (width - 8.0) / float(_team_columns)
	for i in count:
		var col := i % _team_columns
		var row_index := int(i / _team_columns)
		var pos := Vector2(4.0 + col * col_width, 16.0 + row_index * ROW_H)
		var row := _make_member_row(pos, col_width - 2.0, i == 0)
		_member_rows.append(row)
	_player_row = _member_rows[0] if not _member_rows.is_empty() else {}


func _make_member_row(pos: Vector2, width: float, is_player: bool) -> Dictionary:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(width, ROW_H - 1.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team_panel.add_child(holder)

	var portrait := UIKit.portrait_rect("assault", 17.0)
	portrait.position = Vector2(0, 1)
	portrait.modulate = Color(1, 1, 1, 0.95)
	holder.add_child(portrait)

	var name_label := UIKit.label("—", 8, UIKit.INK)
	name_label.position = Vector2(20, -1)
	name_label.size = Vector2(width - 22, 10)
	name_label.clip_text = true
	holder.add_child(name_label)

	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.04, 0.9)
	back.position = Vector2(20, 10)
	back.size = Vector2(width - 22, 4)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(back)
	var hp_fill := ColorRect.new()
	hp_fill.color = UIKit.GREEN
	hp_fill.position = Vector2(20, 10)
	hp_fill.size = Vector2(width - 22, 4)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hp_fill)
	var temp_fill := ColorRect.new()
	temp_fill.color = UIKit.TEAL
	temp_fill.position = Vector2(20, 10)
	temp_fill.size = Vector2(0, 2)
	temp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(temp_fill)

	var status := UIKit.label("", 6, UIKit.MUTED)
	status.position = Vector2(20, 14)
	status.size = Vector2(width - 22, 6)
	status.clip_text = true
	holder.add_child(status)

	var accent := ColorRect.new()
	accent.color = UIKit.AMBER if is_player else UIKit.LINE
	accent.position = Vector2(-4, 1)
	accent.size = Vector2(2, ROW_H - 4)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(accent)

	return {
		"holder": holder,
		"portrait": portrait,
		"name": name_label,
		"hp": hp_fill,
		"temp": temp_fill,
		"status": status,
		"accent": accent,
		"width": width - 22.0,
		"is_player": is_player,
	}


func _build_top_center() -> void:
	_objective_label = UIKit.label("推进至撤离点", 9, UIKit.INK)
	_objective_label.position = Vector2(180, 7)
	_objective_label.size = Vector2(280, 12)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_objective_label.add_theme_constant_override("shadow_offset_x", 1)
	_objective_label.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_objective_label)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.position = Vector2(190, 21)
	back.size = Vector2(260, 3)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	_objective_fill = ColorRect.new()
	_objective_fill.color = UIKit.AMBER
	_objective_fill.position = Vector2(190, 21)
	_objective_fill.size = Vector2(0, 3)
	_objective_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_objective_fill)

	_director_label = UIKit.label("DIRECTOR", 6, UIKit.DIM, UIKit.font_latin())
	_director_label.position = Vector2(190, 26)
	_director_label.size = Vector2(44, 7)
	_root.add_child(_director_label)
	var dback := ColorRect.new()
	dback.color = Color(0, 0, 0, 0.45)
	dback.position = Vector2(232, 28)
	dback.size = Vector2(218, 2)
	dback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dback)
	_director_fill = ColorRect.new()
	_director_fill.color = UIKit.TEAL
	_director_fill.position = Vector2(232, 28)
	_director_fill.size = Vector2(0, 2)
	_director_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_director_fill)


func _build_score_panel() -> void:
	var panel := UIKit.panel()
	panel.position = Vector2(474, 8)
	panel.size = Vector2(158, 48)
	_root.add_child(panel)

	_level_label = UIKit.label("", 6, UIKit.MUTED)
	_level_label.position = Vector2(6, 3)
	_level_label.size = Vector2(146, 8)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_level_label)

	_score_label = UIKit.label("0", 16, UIKit.AMBER, UIKit.font_latin_bold())
	_score_label.position = Vector2(6, 10)
	_score_label.size = Vector2(146, 18)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_score_label)
	var score_caption := UIKit.label("SCORE", 6, UIKit.DIM, UIKit.font_latin())
	score_caption.position = Vector2(6, 13)
	score_caption.size = Vector2(50, 8)
	panel.add_child(score_caption)

	_combo_label = UIKit.label("", 7, UIKit.GREEN, UIKit.font_latin())
	_combo_label.position = Vector2(6, 29)
	_combo_label.size = Vector2(96, 9)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(_combo_label)

	_streak_label = UIKit.label("", 8, UIKit.RED, UIKit.font_latin_bold())
	_streak_label.position = Vector2(104, 29)
	_streak_label.size = Vector2(150, 9)
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_streak_label.visible = false
	panel.add_child(_streak_label)

	_time_label = UIKit.label("0:00", 8, UIKit.MUTED, UIKit.font_latin())
	_time_label.position = Vector2(102, 29)
	_time_label.size = Vector2(50, 9)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_time_label)


func _build_boss_bar() -> void:
	_boss_panel = UIKit.panel(Color(0.06, 0.03, 0.03, 0.94), UIKit.RED_DARK)
	_boss_panel.position = Vector2(180, 44)
	_boss_panel.size = Vector2(280, 20)
	_boss_panel.visible = false
	_root.add_child(_boss_panel)
	_boss_label = UIKit.label("TANK", 7, UIKit.RED, UIKit.font_latin_bold())
	_boss_label.position = Vector2(6, 2)
	_boss_label.size = Vector2(120, 8)
	_boss_panel.add_child(_boss_label)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.02, 0.02, 0.9)
	back.position = Vector2(6, 11)
	back.size = Vector2(268, 5)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(back)
	_boss_fill = ColorRect.new()
	_boss_fill.color = UIKit.RED
	_boss_fill.position = Vector2(6, 11)
	_boss_fill.size = Vector2(268, 5)
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.add_child(_boss_fill)


func _build_timer_bar() -> void:
	_timer_panel = UIKit.panel(Color(0.06, 0.03, 0.03, 0.94), UIKit.RED_DARK)
	_timer_panel.position = Vector2(230, 68)
	_timer_panel.size = Vector2(180, 20)
	_timer_panel.visible = false
	_root.add_child(_timer_panel)
	_timer_label = UIKit.label("撤离", 8, UIKit.INK)
	_timer_label.position = Vector2(6, 1)
	_timer_label.size = Vector2(168, 9)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_panel.add_child(_timer_label)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.02, 0.02, 0.9)
	back.position = Vector2(6, 11)
	back.size = Vector2(168, 5)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_panel.add_child(back)
	_timer_fill = ColorRect.new()
	_timer_fill.color = UIKit.RED
	_timer_fill.position = Vector2(6, 11)
	_timer_fill.size = Vector2(168, 5)
	_timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_panel.add_child(_timer_fill)


func _build_player_panel() -> void:
	var panel := UIKit.panel()
	panel.position = Vector2(8, 302)
	panel.size = Vector2(232, 50)
	_root.add_child(panel)

	var portrait := UIKit.portrait_rect("assault", 32.0)
	portrait.position = Vector2(4, 9)
	panel.add_child(portrait)

	_player_name = UIKit.label("突击兵", 10, UIKit.INK)
	_player_name.position = Vector2(40, 2)
	_player_name.size = Vector2(112, 12)
	_player_name.clip_text = true
	panel.add_child(_player_name)

	_hp_text = UIKit.label("100", 9, UIKit.INK, UIKit.font_latin())
	_hp_text.position = Vector2(148, 3)
	_hp_text.size = Vector2(78, 10)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_hp_text)

	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.04, 0.95)
	back.position = Vector2(40, 15)
	back.size = Vector2(186, 7)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(back)
	_hp_fill = ColorRect.new()
	_hp_fill.color = UIKit.GREEN
	_hp_fill.position = Vector2(40, 15)
	_hp_fill.size = Vector2(186, 7)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hp_fill)
	_temp_fill = ColorRect.new()
	_temp_fill.color = UIKit.TEAL
	_temp_fill.position = Vector2(40, 15)
	_temp_fill.size = Vector2(0, 3)
	_temp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_temp_fill)

	_status_text = UIKit.label("", 8, UIKit.MUTED)
	_status_text.position = Vector2(40, 26)
	_status_text.size = Vector2(150, 9)
	panel.add_child(_status_text)
	_downs_text = UIKit.label("", 7, UIKit.DIM, UIKit.font_latin())
	_downs_text.position = Vector2(40, 36)
	_downs_text.size = Vector2(186, 8)
	panel.add_child(_downs_text)


func _build_weapon_panel() -> void:
	var panel := UIKit.panel()
	panel.position = Vector2(404, 302)
	panel.size = Vector2(228, 50)
	_root.add_child(panel)

	_weapon_name = UIKit.label("M9 手枪", 9, UIKit.INK)
	_weapon_name.position = Vector2(6, 2)
	_weapon_name.size = Vector2(130, 11)
	_weapon_name.clip_text = true
	panel.add_child(_weapon_name)

	_ammo_text = UIKit.label("15 / ∞", 14, UIKit.AMBER, UIKit.font_latin_bold())
	_ammo_text.position = Vector2(132, 1)
	_ammo_text.size = Vector2(90, 15)
	_ammo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(_ammo_text)

	_weapon_state = UIKit.label("", 6, UIKit.DIM, UIKit.font_latin())
	_weapon_state.position = Vector2(6, 12)
	_weapon_state.size = Vector2(120, 7)
	panel.add_child(_weapon_state)

	_skill_icon = UIKit.icon_rect("skill_assault", 18.0)
	_skill_icon.position = Vector2(6, 22)
	panel.add_child(_skill_icon)
	_skill_cover = ColorRect.new()
	_skill_cover.color = Color(0, 0, 0, 0.65)
	_skill_cover.position = Vector2(6, 40)
	_skill_cover.size = Vector2(18, 0)
	_skill_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_skill_cover)
	_skill_ready = UIKit.label("SHIFT", 6, UIKit.DIM, UIKit.font_latin())
	_skill_ready.position = Vector2(4, 42)
	_skill_ready.size = Vector2(24, 6)
	_skill_ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_skill_ready)

	var medkit_icon := UIKit.icon_rect("status_bw", 12.0)
	medkit_icon.texture = UIKit.texture("res://assets/sprites/environment/pickup_medkit.png")
	medkit_icon.position = Vector2(52, 24)
	panel.add_child(medkit_icon)
	_medkit_count = UIKit.label("1", 9, UIKit.INK, UIKit.font_latin())
	_medkit_count.position = Vector2(66, 24)
	_medkit_count.size = Vector2(18, 10)
	panel.add_child(_medkit_count)
	var medkit_key := UIKit.label("H", 6, UIKit.DIM, UIKit.font_latin())
	medkit_key.position = Vector2(54, 38)
	medkit_key.size = Vector2(18, 6)
	panel.add_child(medkit_key)

	var pills_icon := UIKit.icon_rect("status_bw", 12.0)
	pills_icon.texture = UIKit.texture("res://assets/sprites/environment/pickup_pills.png")
	pills_icon.position = Vector2(90, 24)
	panel.add_child(pills_icon)
	_pills_count = UIKit.label("1", 9, UIKit.INK, UIKit.font_latin())
	_pills_count.position = Vector2(104, 24)
	_pills_count.size = Vector2(18, 10)
	panel.add_child(_pills_count)
	var pills_key := UIKit.label("T", 6, UIKit.DIM, UIKit.font_latin())
	pills_key.position = Vector2(92, 38)
	pills_key.size = Vector2(18, 6)
	panel.add_child(pills_key)

	var kinds := ["grenade", "molotov", "bile"]
	for i in 3:
		var kind: String = kinds[i]
		var icon := UIKit.icon_rect("status_bw", 12.0)
		icon.texture = UIKit.texture("res://assets/sprites/environment/pickup_%s.png" % kind)
		icon.position = Vector2(130 + i * 30, 24)
		icon.modulate = Color(1, 1, 1, 0.5)
		panel.add_child(icon)
		var count_label := UIKit.label("0", 8, UIKit.MUTED, UIKit.font_latin())
		count_label.position = Vector2(144 + i * 30, 24)
		count_label.size = Vector2(14, 9)
		panel.add_child(count_label)
		_throw_icons.append(icon)
		_throw_counts.append(count_label)
	var throw_key := UIKit.label("G  V", 6, UIKit.DIM, UIKit.font_latin())
	throw_key.position = Vector2(128, 38)
	throw_key.size = Vector2(52, 6)
	panel.add_child(throw_key)

	## 货币显示（右上角）：废铁/废料，敌人掉落，商人处消费。
	_currency_icon = ColorRect.new()
	_currency_icon.color = UIKit.AMBER
	_currency_icon.size = Vector2(14, 14)
	_currency_icon.position = Vector2(510, 302)
	_currency_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_currency_icon)
	_currency_label = UIKit.label("0", 12, UIKit.AMBER, UIKit.font_latin_bold())
	_currency_label.position = Vector2(528, 304)
	_currency_label.size = Vector2(100, 14)
	_root.add_child(_currency_label)


func _build_command_panel() -> void:
	_command_panel = UIKit.panel()
	_command_panel.position = Vector2(244, 302)
	_command_panel.size = Vector2(152, 50)
	_command_panel.visible = GameManager.current_mode == &"COMMAND"
	_root.add_child(_command_panel)
	var header := UIKit.label("COMMAND 1-4", 6, UIKit.MUTED, UIKit.font_latin())
	header.position = Vector2(5, 2)
	_command_panel.add_child(header)
	_formation_label = UIKit.label("楔形", 6, UIKit.TEAL)
	_formation_label.position = Vector2(98, 2)
	_formation_label.size = Vector2(48, 8)
	_formation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_command_panel.add_child(_formation_label)
	var names := ["follow", "advance", "hold", "focus"]
	var labels := ["跟随", "推进", "防守", "集火"]
	for i in 4:
		var cell := Control.new()
		cell.position = Vector2(5 + i * 36, 13)
		cell.size = Vector2(33, 32)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_command_panel.add_child(cell)
		var frame := Panel.new()
		frame.position = Vector2.ZERO
		frame.size = Vector2(33, 32)
		frame.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.05, 0.06, 0.07, 0.5), Color(0, 0, 0, 0)))
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(frame)
		var icon := UIKit.icon_rect("cmd_" + names[i], 16.0)
		icon.position = Vector2(8, 2)
		cell.add_child(icon)
		var key_label := UIKit.label(str(i + 1), 6, UIKit.AMBER, UIKit.font_latin())
		key_label.position = Vector2(2, 1)
		cell.add_child(key_label)
		var name_label := UIKit.label(labels[i], 7, UIKit.MUTED)
		name_label.position = Vector2(0, 20)
		name_label.size = Vector2(33, 8)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name_label)
		_command_cells[StringName(names[i])] = {"frame": frame, "label": name_label}


func _build_prompt() -> void:
	_prompt_panel = UIKit.panel(Color(0.04, 0.05, 0.06, 0.92), UIKit.AMBER)
	_prompt_panel.position = Vector2(220, 268)
	_prompt_panel.size = Vector2(200, 20)
	_prompt_panel.visible = false
	_root.add_child(_prompt_panel)
	_prompt_label = UIKit.label("", 9, UIKit.INK)
	_prompt_label.position = Vector2(4, 3)
	_prompt_label.size = Vector2(192, 12)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)

	_downed_label = UIKit.label("", 14, UIKit.RED, UIKit.font_latin_bold())
	_downed_label.position = Vector2(160, 236)
	_downed_label.size = Vector2(320, 22)
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_downed_label.add_theme_constant_override("shadow_offset_x", 1)
	_downed_label.add_theme_constant_override("shadow_offset_y", 1)
	_downed_label.visible = false
	_root.add_child(_downed_label)


func _build_event_banner() -> void:
	_event_label = UIKit.label("", 12, UIKit.INK)
	_event_label.position = Vector2(120, 140)
	_event_label.size = Vector2(400, 24)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_event_label.add_theme_constant_override("shadow_offset_x", 2)
	_event_label.add_theme_constant_override("shadow_offset_y", 2)
	_event_label.modulate = Color(1, 1, 1, 0)
	_root.add_child(_event_label)


func _build_notifications() -> void:
	_notify_box = VBoxContainer.new()
	_notify_box.position = Vector2(380, 96)
	_notify_box.size = Vector2(252, 130)
	_notify_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_notify_box.add_theme_constant_override("separation", 3)
	_notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notify_box)


func _build_threat_arrows() -> void:
	_threat_arrows = THREAT_ARROWS.new()
	_threat_arrows.level = level
	_root.add_child(_threat_arrows)


func _build_crosshair() -> void:
	_crosshair = TextureRect.new()
	_crosshair.texture = UIKit.icon("crosshair")
	_crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crosshair.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crosshair.size = Vector2(20, 20)
	_crosshair.modulate = Color(1, 1, 1, 0.85)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_hitmarker = TextureRect.new()
	_hitmarker.texture = UIKit.icon("hitmarker")
	_hitmarker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hitmarker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hitmarker.size = Vector2(16, 16)
	_hitmarker.modulate = Color(1, 1, 1, 0)
	_hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hitmarker)


func _build_pause() -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.visible = false
	_root.add_child(_pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.add_child(dim)

	var panel := UIKit.panel(Color(0.045, 0.055, 0.07, 0.98), UIKit.AMBER)
	panel.position = Vector2(190, 58)
	panel.size = Vector2(260, 250)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.add_child(panel)

	var title := UIKit.title("暂停", 26, UIKit.INK)
	title.position = Vector2(0, 8)
	title.size = Vector2(260, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var sub := UIKit.label("PAUSED", 7, UIKit.AMBER, UIKit.font_latin())
	sub.position = Vector2(0, 38)
	sub.size = Vector2(260, 9)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)
	var rule := UIKit.hsep(panel, UIKit.LINE)
	rule.position = Vector2(20, 52)
	rule.size = Vector2(220, 1)

	var resume := UIKit.button("继续任务", 210, 24, true)
	resume.position = Vector2(25, 62)
	resume.pressed.connect(_close_pause)
	panel.add_child(resume)

	var restart := UIKit.button("重新开始本关", 210, 24)
	restart.position = Vector2(25, 92)
	restart.pressed.connect(_pause_restart)
	panel.add_child(restart)

	var menu := UIKit.button("返回主菜单", 210, 24)
	menu.position = Vector2(25, 122)
	menu.pressed.connect(_pause_menu)
	panel.add_child(menu)

	var archive := UIKit.button("档案库  " + _archive_progress_text(), 210, 24)
	archive.position = Vector2(25, 152)
	archive.pressed.connect(_open_archive_menu)
	panel.add_child(archive)

	var hint := UIKit.label("ESC 继续 · 进度会在检查点保存", 8, UIKit.MUTED)
	hint.position = Vector2(0, 184)
	hint.size = Vector2(260, 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)

	var keys := UIKit.label("WASD 移动   鼠标瞄准   J 开火   F 近战/处决\nE 互动/救助   R 换弹   H 医疗包   T 药丸", 8, UIKit.DIM)
	keys.position = Vector2(12, 202)
	keys.size = Vector2(236, 34)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(keys)

	_pause_root.set_meta("resume", resume)


func _archive_progress_text() -> String:
	if ArchiveManager == null:
		return ""
	return "%d/%d" % [ArchiveManager.unlocked_count(), ArchiveManager.total_count()]


## Opens the archive browser on top of the pause menu (tree stays paused, the
## screen runs in ALWAYS mode and closes itself through its navigate signal).
func _open_archive_menu() -> void:
	var packed: PackedScene = load("res://scenes/ui/archive/ArchiveMenu.tscn")
	if packed == null:
		return
	var menu := packed.instantiate()
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.navigate.connect(func(_target: StringName, _payload: Dictionary) -> void:
		menu.queue_free())
	_root.add_child(menu)
	AudioManager.play_sfx(&"ui_click")


func _build_debug_panel() -> void:
	if not OS.is_debug_build():
		return
	_debug_panel = UIKit.panel(Color(0.02, 0.03, 0.04, 0.93), UIKit.TEAL)
	_debug_panel.position = Vector2(8, 176)
	_debug_panel.size = Vector2(360, 118)
	_debug_panel.visible = false
	_root.add_child(_debug_panel)
	_debug_label = UIKit.label("", 6, UIKit.INK, UIKit.font_latin())
	_debug_label.position = Vector2(6, 4)
	_debug_label.size = Vector2(166, 110)
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_label.add_theme_constant_override("line_spacing", -2)
	_debug_panel.add_child(_debug_label)
	var sep := ColorRect.new()
	sep.color = UIKit.LINE
	sep.position = Vector2(176, 4)
	sep.size = Vector2(1, 110)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.add_child(sep)
	_debug_ally_label = UIKit.label("", 6, UIKit.INK, UIKit.font_latin())
	_debug_ally_label.position = Vector2(182, 4)
	_debug_ally_label.size = Vector2(172, 110)
	_debug_ally_label.add_theme_constant_override("line_spacing", -2)
	_debug_panel.add_child(_debug_ally_label)


# ---------------------------------------------------------------- signals ----
func _connect_events() -> void:
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.weapon_changed.connect(_on_weapon_changed)
	EventBus.skill_state_changed.connect(_on_skill_state)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.objective_changed.connect(_on_objective_changed)
	EventBus.interact_prompt.connect(_on_interact_prompt)
	EventBus.notify.connect(_notify)
	EventBus.level_event.connect(_on_level_event)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.damage_flash.connect(_on_damage_flash)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.player_rescued.connect(_on_player_rescued)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_health_changed.connect(_on_boss_health)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.extraction_started.connect(_on_extraction_started)
	EventBus.extraction_arrived.connect(_on_extraction_arrived)
	EventBus.checkpoint_reached.connect(_on_checkpoint)
	EventBus.command_issued.connect(_on_command_issued)
	EventBus.formation_changed.connect(_on_formation_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed_streak)
	if _debug_panel != null:
		EventBus.debug_panel_toggled.connect(_toggle_debug)
		EventBus.debug_vision_toggled.connect(_on_debug_vision_toggled)
	EventBus.horde_started.connect(_on_horde_started)
	EventBus.horde_ended.connect(_on_horde_ended)
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.unlock_earned.connect(_on_unlock)
	EventBus.toast.connect(_on_toast)
	EventBus.currency_changed.connect(_on_currency_changed)


func _on_health_changed(hp: int, temp_hp: int, max_hp: int) -> void:
	_last_hp = hp
	_last_temp = temp_hp
	_refresh_health(hp, temp_hp, max_hp)


func _on_ammo_changed(mag: int, reserve: int) -> void:
	_weapon_mag = mag
	_weapon_reserve = reserve
	_refresh_ammo()


func _on_weapon_changed(id: StringName, display_name: String) -> void:
	_weapon_id = id
	_weapon_name.text = display_name
	var data := GameManager.get_weapon(id)
	if data != null:
		_weapon_state.text = String(data.category).to_upper()
	_refresh_ammo()


func _on_currency_changed(amount: int) -> void:
	_currency_label.text = str(amount)


func _on_skill_state(ratio: float, active: bool) -> void:
	_skill_cover.size.y = 18.0 * (1.0 - clampf(ratio, 0.0, 1.0))
	_skill_cover.position.y = 22.0 + 18.0 * clampf(ratio, 0.0, 1.0)
	_skill_icon.modulate = Color(1, 1, 1, 1) if ratio >= 1.0 else Color(0.55, 0.58, 0.58, 1)
	_skill_ready.text = "ACTIVE" if active else ("READY" if ratio >= 1.0 else "SHIFT")
	_skill_ready.add_theme_color_override("font_color", UIKit.AMBER if active or ratio >= 1.0 else UIKit.DIM)


func _on_score_changed(score: int) -> void:
	_score_label.text = UIKit.format_score(score)
	var tw := create_tween()
	_score_label.scale = Vector2(1.08, 1.08)
	tw.tween_property(_score_label, "scale", Vector2.ONE, 0.16)


func _on_combo_changed(combo: int, mult: float) -> void:
	if combo <= 1:
		_combo_label.text = ""
		return
	_combo_label.text = "x%.2f  %d COMBO" % [mult, combo]
	_combo_label.add_theme_color_override("font_color", UIKit.AMBER if combo >= 20 else UIKit.GREEN)
	_combo_label.scale = Vector2(1.18, 1.18)
	var tw := create_tween()
	tw.tween_property(_combo_label, "scale", Vector2.ONE, 0.18)


func _on_objective_changed(text: String) -> void:
	_objective_label.text = text
	var tw := create_tween()
	_objective_label.modulate = Color(1.4, 1.3, 1.0, 1.0)
	tw.tween_property(_objective_label, "modulate", Color.WHITE, 0.35)


func _on_interact_prompt(text: String) -> void:
	_prompt_panel.visible = text != ""
	_prompt_label.text = text


func _notify(text: String) -> void:
	if _notify_box.get_child_count() >= 5:
		var oldest := _notify_box.get_child(0)
		_notify_box.remove_child(oldest)
		oldest.queue_free()
	var label := UIKit.label(text, 8, UIKit.INK)
	label.custom_minimum_size = Vector2(252, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.modulate = Color(1, 1, 1, 0)
	_notify_box.add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.12)
	tw.tween_interval(2.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(label.queue_free)


func _on_level_event(text: String) -> void:
	_event_label.text = text
	_event_label.modulate = Color(1, 1, 1, 1)
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_interval(2.8)
	_event_tween.tween_property(_event_label, "modulate:a", 0.0, 0.7)


func _on_enemy_died(_kind: StringName, _pos: Vector2, _score: int) -> void:
	if _hitmarker_tween != null and _hitmarker_tween.is_valid():
		_hitmarker_tween.kill()
	_hitmarker.modulate = Color(1, 0.9, 0.6, 1)
	_hitmarker.scale = Vector2(1.6, 1.6)
	_hitmarker_tween = create_tween()
	_hitmarker_tween.set_parallel(true)
	_hitmarker_tween.tween_property(_hitmarker, "modulate:a", 0.0, 0.22)
	_hitmarker_tween.tween_property(_hitmarker, "scale", Vector2.ONE, 0.22)


func _on_damage_flash() -> void:
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_flash.color.a = 0.34
	_damage_tween = create_tween()
	_damage_tween.tween_property(_damage_flash, "color:a", 0.0, 0.32)


func _on_player_downed() -> void:
	_notify("你被击倒了！")
	_downshot()


func _downshot() -> void:
	_downed_label.visible = true
	_downed_label.text = "倒地 · 等待队友救援"


func _on_player_rescued() -> void:
	_downed_label.visible = false
	_notify("队友把你扶了起来")


func _on_boss_spawned(kind: StringName) -> void:
	_boss_kind = kind
	var zd := GameManager.get_zombie(kind)
	_boss_label.text = String(zd.display_name if zd else String(kind)).to_upper()
	_boss_panel.visible = true
	_boss_ratio = 1.0
	_boss_fill.size.x = 268.0


func _on_boss_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	_boss_ratio = clampf(float(current) / float(maximum), 0.0, 1.0)
	_boss_fill.size.x = 268.0 * _boss_ratio
	if _boss_ratio > 0.0:
		_boss_panel.visible = true


func _on_boss_killed(_kind: StringName) -> void:
	_boss_ratio = 0.0
	_boss_fill.size.x = 0.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		_boss_panel.visible = false
	)


func _on_extraction_started(seconds: float) -> void:
	_timer_mode = "extraction"
	_timer_panel.visible = true
	_timer_label.text = "撤离 %.0fs" % seconds
	_timer_fill.size.x = 168.0


func _on_extraction_arrived() -> void:
	_timer_panel.visible = false


func _on_checkpoint(_pos: Vector2) -> void:
	_notify("检查点已激活")


func _on_command_issued(cmd: StringName) -> void:
	for key in _command_cells.keys():
		var cell: Dictionary = _command_cells[key]
		var active: bool = key == cmd
		cell["frame"].add_theme_stylebox_override("panel", UIKit.panel_style(
			Color(0.22, 0.17, 0.07, 0.9) if active else Color(0.05, 0.06, 0.07, 0.5),
			UIKit.AMBER if active else Color(0, 0, 0, 0)))
		cell["label"].add_theme_color_override("font_color", UIKit.AMBER if active else UIKit.MUTED)


func _on_horde_started(_count: int) -> void:
	_timer_mode = ""
	EventBus.notify.emit("尸潮来袭")


func _on_horde_ended() -> void:
	pass


func _on_achievement(id: StringName) -> void:
	var name := String(id)
	for row in SaveSystem.ACHIEVEMENTS:
		if String(row.get("id", "")) == String(id):
			name = String(row.get("name", name))
			break
	_big_toast("成就解锁", name, UIKit.AMBER, _achievement_icon(String(id)))


func _achievement_icon(id: String) -> String:
	for row in SaveSystem.ACHIEVEMENTS:
		if String(row.get("id", "")) == id:
			return String(row.get("icon", "ach_" + id))
	return "ach_" + id


func _on_unlock(id: StringName) -> void:
	_big_toast("解锁", String(id), UIKit.TEAL, "")


func _on_toast(title: String, detail: String) -> void:
	_big_toast(title, detail, UIKit.INK, "")


func _big_toast(title: String, detail: String, color: Color, icon_name: String) -> void:
	var box := UIKit.panel(Color(0.04, 0.05, 0.06, 0.96), color)
	box.position = Vector2(196, 214)
	box.size = Vector2(248, 38)
	box.modulate = Color(1, 1, 1, 0)
	_root.add_child(box)
	var x := 8.0
	if icon_name != "":
		var icon := UIKit.icon_rect(icon_name, 22.0)
		icon.position = Vector2(7, 8)
		box.add_child(icon)
		x = 36.0
	var t := UIKit.label(title, 7, color, UIKit.font_latin())
	t.position = Vector2(x, 4)
	t.size = Vector2(210, 8)
	box.add_child(t)
	var d := UIKit.label(detail, 9, UIKit.INK)
	d.position = Vector2(x, 13)
	d.size = Vector2(210, 18)
	d.clip_text = true
	box.add_child(d)
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.5)
	tw.tween_callback(box.queue_free)


# ------------------------------------------------------------------ refresh --
func _on_enemy_killed_streak(kind: StringName, source: StringName, pos: Vector2) -> void:
	if source != &"player":
		return
	_killstreak += 1
	_streak_timer = 2.5
	if _killstreak >= 3:
		_streak_label.text = "%d KILL STREAK" % _killstreak
		_streak_label.visible = true
		_streak_label.modulate = Color(1, 1, 1, 1)
		_streak_label.scale = Vector2(1.3, 1.3)
		var tw := create_tween()
		tw.tween_property(_streak_label, "scale", Vector2.ONE, 0.2)
		if _killstreak >= 10:
			_streak_label.text = "MONSTER KILL!"
			_streak_label.add_theme_color_override("font_color", UIKit.RED)
		elif _killstreak >= 5:
			_streak_label.text = "RAMPAGE!"
			_streak_label.add_theme_color_override("font_color", Color(1, 0.5, 0, 1))

func _process(delta: float) -> void:
	if _streak_timer > 0.0:
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_killstreak = 0
			_streak_label.visible = false
	if _pause_open:
		return
	_refresh_accum += delta
	_clock_accum += delta
	if _refresh_accum >= 0.1:
		_refresh_accum = 0.0
		_refresh_team()
		_refresh_player()
		_refresh_weapon()
		_refresh_objective()
		_refresh_timer()
		_refresh_boss()
		_refresh_command()
		_refresh_overlays()
	if _clock_accum >= 0.25:
		_clock_accum = 0.0
		_refresh_time()
		_refresh_debug()
	_update_crosshair()
	_update_hitmarker()


func _update_crosshair() -> void:
	if _pause_open:
		_crosshair.visible = false
		_hitmarker.visible = false
		return
	var mouse := _root.get_local_mouse_position()
	_crosshair.visible = true
	_hitmarker.visible = true
	_crosshair.position = mouse - Vector2(10, 10)
	_hitmarker.position = mouse - Vector2(8, 8)
	var player = level.get("player") if level != null else null
	if player != null and is_instance_valid(player):
		var spread: float = 1.0 + clampf(float(player.get("spread_heat")), 0.0, 4.0) * 0.5
		_crosshair.scale = Vector2(spread, spread)
		_crosshair.modulate.a = 0.9 if not bool(player.get("is_downed")) else 0.25


func _update_hitmarker() -> void:
	pass


func _refresh_team() -> void:
	if level == null:
		return
	var members: Array = []
	if level.get("player") != null and is_instance_valid(level.get("player")):
		members.append(level.get("player"))
	for ally in level.get_allies():
		if ally != null and is_instance_valid(ally):
			members.append(ally)
	for i in mini(members.size(), _member_rows.size()):
		var member = members[i]
		var row: Dictionary = _member_rows[i]
		var is_player: bool = bool(row["is_player"])
		var display_name := "你"
		var portrait_id := "assault"
		var hp := 0
		var max_hp := 100
		var temp_hp := 0
		var accent := UIKit.AMBER
		if is_player:
			var character: CharacterData = member.get("character")
			if character != null:
				display_name = "你 · " + character.display_name
				portrait_id = character.portrait
				accent = character.accent
			hp = int(member.get("hp"))
			max_hp = int(member.get("max_hp"))
			temp_hp = int(member.get("temp_hp"))
		else:
			var cd: CharacterData = member.get("data")
			if cd != null:
				display_name = cd.display_name
				portrait_id = cd.portrait
				accent = cd.accent
			hp = int(member.get("hp"))
			max_hp = int(member.get("max_hp"))
			temp_hp = 0
		row["portrait"].texture = UIKit.portrait(portrait_id)
		row["name"].text = display_name
		row["name"].add_theme_color_override("font_color", UIKit.INK if member.get("is_dead") != true else UIKit.DIM)
		row["accent"].color = accent
		var width: float = float(row["width"])
		var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		row["hp"].size.x = width * ratio
		row["hp"].color = _hp_color(ratio)
		var temp_ratio := clampf(float(temp_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		row["temp"].size = Vector2(width * minf(1.0, ratio + temp_ratio), 2)
		row["temp"].visible = temp_hp > 0
		var status := ""
		var status_color := UIKit.MUTED
		if member.get("is_dead") == true:
			status = "阵亡"
			status_color = UIKit.RED_DARK
			row["holder"].modulate = Color(1, 1, 1, 0.45)
		else:
			row["holder"].modulate = Color.WHITE
			if member.get("is_downed") == true:
				status = "倒地 %.0fs" % maxf(0.0, float(member.get("bleedout")))
				status_color = UIKit.RED
			elif member.get("is_pinned") == true:
				status = "被控制"
				status_color = UIKit.AMBER
			elif member.get("is_controlled") == true:
				status = "受控"
				status_color = UIKit.AMBER
			elif is_player and member.get("black_white") == true:
				status = "黑血"
				status_color = UIKit.PURPLE
			else:
				var state_text := ""
				if member.has_method("get_status_text"):
					state_text = member.get_status_text()
				status = state_text if state_text != "" else "OK"
				status_color = UIKit.MUTED if status != "OK" else UIKit.DIM
		row["status"].text = status
		row["status"].add_theme_color_override("font_color", status_color)


func _refresh_player(force: bool = false) -> void:
	var player = level.get("player") if level != null else null
	if player == null or not is_instance_valid(player):
		return
	var hp := int(player.get("hp"))
	var max_hp := int(player.get("max_hp"))
	var temp_hp := int(player.get("temp_hp"))
	if force or hp != _last_hp or temp_hp != _last_temp:
		_last_hp = hp
		_last_temp = temp_hp
		_refresh_health(hp, temp_hp, max_hp)
	var character: CharacterData = player.get("character")
	if character != null:
		_player_name.text = character.display_name
		_skill_icon.texture = UIKit.icon("skill_" + String(character.id))
	var statuses: Array[String] = []
	if bool(player.get("is_downed")):
		statuses.append("倒地")
	elif bool(player.get("black_white")):
		statuses.append("黑血")
	if bool(player.get("is_controlled")):
		statuses.append("受控")
	if float(player.get("bile_timer")) > 0.0:
		statuses.append("胆汁")
	if float(player.get("burn_timer")) > 0.0:
		statuses.append("燃烧")
	if float(player.get("slow_timer")) > 0.0:
		statuses.append("减速")
	if float(player.get("inspire_timer")) > 0.0:
		statuses.append("鼓舞")
	if float(player.get("shield_wall_timer")) > 0.0:
		statuses.append("盾墙")
	if statuses.is_empty():
		_status_text.text = "状态正常"
		_status_text.add_theme_color_override("font_color", UIKit.DIM)
	else:
		_status_text.text = " · ".join(statuses)
		_status_text.add_theme_color_override("font_color", UIKit.AMBER if statuses.has("胆汁") or statuses.has("燃烧") else UIKit.RED)
	_downs_text.text = "倒地次数 %d / %d" % [int(player.get("downs")), GameManager.max_downs()]
	if bool(player.get("is_downed")):
		_downed_label.visible = true
		_downed_label.text = "倒地 · %.0fs 后死亡 · 等待队友" % maxf(0.0, float(player.get("bleedout")))
	else:
		_downed_label.visible = false


func _refresh_health(hp: int, temp_hp: int, max_hp: int) -> void:
	if _hp_fill == null:
		return
	var ratio := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_hp_fill.size.x = 186.0 * ratio
	_hp_fill.color = _hp_color(ratio)
	_temp_fill.size = Vector2(minf(186.0 * clampf(float(temp_hp) / float(maxi(1, max_hp)), 0.0, 1.0), 186.0 * (1.0 - ratio)), 3)
	_temp_fill.position.x = 40.0 + 186.0 * ratio
	_temp_fill.visible = temp_hp > 0
	_hp_text.text = "%d / %d" % [hp, max_hp]
	_hp_text.add_theme_color_override("font_color", UIKit.RED if ratio < 0.3 else UIKit.INK)


func _refresh_ammo() -> void:
	if _ammo_text == null:
		return
	var data := GameManager.get_weapon(_weapon_id)
	var reserve_text := "∞" if _weapon_reserve < 0 else str(_weapon_reserve)
	if data != null and data.category == &"melee":
		if _weapon_id == &"chainsaw":
			_ammo_text.text = "%d" % _weapon_mag
			_weapon_state.text = "FUEL"
		else:
			_ammo_text.text = "—"
			_weapon_state.text = "MELEE"
	else:
		_ammo_text.text = "%d / %s" % [_weapon_mag, reserve_text]
		if data != null:
			_weapon_state.text = String(data.category).to_upper()
	_ammo_text.add_theme_color_override("font_color", UIKit.RED if _weapon_mag <= 0 and _weapon_reserve != 0 else UIKit.AMBER)


func _refresh_weapon() -> void:
	var player = level.get("player") if level != null else null
	if player == null or not is_instance_valid(player):
		return
	_medkit_count.text = str(int(player.get("medkits")))
	_pills_count.text = str(int(player.get("pills")))
	var throws: Dictionary = player.get("throwables")
	var kinds := ["grenade", "molotov", "bile"]
	_throw_index = int(player.get("throw_index"))
	for i in 3:
		var count := int(throws.get(kinds[i], 0))
		_throw_counts[i].text = str(count)
		_throw_counts[i].add_theme_color_override("font_color", UIKit.INK if count > 0 else UIKit.DIM)
		var selected: bool = i == _throw_index and count > 0
		_throw_icons[i].modulate = Color(1, 1, 1, 1) if count > 0 else Color(0.45, 0.48, 0.48, 0.6)
		_throw_icons[i].scale = Vector2(1.18, 1.18) if selected else Vector2.ONE


func _refresh_objective() -> void:
	if level == null:
		return
	var progress := 0.0
	if level.has_method("get_progress"):
		progress = float(level.get_progress())
	_objective_fill.size.x = 260.0 * clampf(progress, 0.0, 1.0)
	_director_value = clampf(DirectorSystem.intensity, 0.0, 1.0)
	_director_fill.size.x = 218.0 * _director_value
	if _director_value > 0.75:
		_director_fill.color = UIKit.RED
		_director_label.add_theme_color_override("font_color", UIKit.RED)
	elif _director_value > 0.45:
		_director_fill.color = UIKit.AMBER
		_director_label.add_theme_color_override("font_color", UIKit.AMBER)
	else:
		_director_fill.color = UIKit.TEAL
		_director_label.add_theme_color_override("font_color", UIKit.DIM)
	_level_label.text = "%s · %s" % [String(GameManager.current_level_id).to_upper(), _level_title()]


func _level_title() -> String:
	if level == null:
		return ""
	var d: LevelData = level.get("data")
	return d.title if d != null else ""


func _refresh_time(force: bool = false) -> void:
	if level == null:
		return
	var elapsed := float(level.get_elapsed()) if level.has_method("get_elapsed") else 0.0
	if force or absf(elapsed - _time_shown) >= 1.0:
		_time_shown = elapsed
		_time_label.text = UIKit.format_time(elapsed)


func _refresh_timer() -> void:
	if level == null:
		return
	var extracting := false
	if level.has_method("is_extraction_active"):
		extracting = bool(level.is_extraction_active())
	if extracting:
		_timer_panel.visible = true
		var left := float(level.get_extraction_left())
		_timer_label.text = "撤离 %.0fs" % maxf(0.0, left)
		_timer_fill.size.x = 168.0
		_timer_fill.color = UIKit.RED
		return
	if level.has_method("is_defense_active") and bool(level.is_defense_active()):
		_timer_panel.visible = true
		var left := float(level.get_defense_left())
		var total := 1.0
		var d: LevelData = level.get("data")
		if d != null and d.extraction_defense > 0.0:
			total = d.extraction_defense
		_timer_label.text = "防守 %.0fs" % maxf(0.0, left)
		_timer_fill.size.x = 168.0 * clampf(left / maxf(1.0, total), 0.0, 1.0)
		_timer_fill.color = UIKit.AMBER
		return
	_timer_panel.visible = false


func _refresh_boss() -> void:
	if level == null:
		return
	var boss = level.get_boss_node()
	if boss != null and is_instance_valid(boss) and not bool(boss.get("dead")):
		_boss_panel.visible = true
		var hp := int(boss.get("health"))
		var max_hp := int(boss.get("max_health"))
		_boss_ratio = clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
		_boss_fill.size.x = 268.0 * _boss_ratio
		var zd: ZombieData = boss.get_data() if boss.has_method("get_data") else null
		if zd != null:
			_boss_label.text = zd.display_name.to_upper()
	elif _boss_ratio <= 0.0:
		_boss_panel.visible = false


func _refresh_command() -> void:
	if _command_panel == null or not _command_panel.visible:
		return
	var player = level.get("player") if level != null else null
	if player == null:
		return
	if _formation_label != null and level != null:
		_formation_label.text = _formation_name(StringName(level.get("formation")))


func _formation_name(value: StringName) -> String:
	match value:
		&"line":
			return "横列"
		&"column":
			return "纵队"
		_:
			return "楔形"


func _on_formation_changed(value: StringName) -> void:
	if _formation_label != null:
		_formation_label.text = _formation_name(value)


func _on_debug_vision_toggled() -> void:
	if _threat_arrows == null:
		return
	var enabled := not bool(_threat_arrows.get("debug_vision"))
	_threat_arrows.set("debug_vision", enabled)
	EventBus.notify.emit("调试视线：" + ("开" if enabled else "关"))


func _toggle_debug() -> void:
	if _debug_panel == null:
		return
	_debug_open = not _debug_open
	_debug_panel.visible = _debug_open
	if _debug_open:
		_refresh_debug()


func _refresh_debug() -> void:
	if _debug_panel == null or not _debug_open:
		return
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	var alive := 0
	var specials := 0
	for node in zombies:
		if node == null or not is_instance_valid(node) or bool(node.get("dead")):
			continue
		alive += 1
		var zd: ZombieData = node.get("data")
		if zd != null and zd.is_special:
			specials += 1
	var allies_alive := 0
	var allies_downed := 0
	if level != null:
		for ally in level.get_allies():
			if ally == null or not is_instance_valid(ally) or bool(ally.get("is_dead")):
				continue
			allies_alive += 1
			if bool(ally.get("is_downed")):
				allies_downed += 1
	var lines: Array[String] = []
	var ally_lines: Array[String] = []
	lines.append("F10 DEBUG · F7 视线 F8 特感 F9 时间")
	lines.append("FPS %d DRAW %d" % [
		Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	lines.append("INT %.2f H:%s S:%s" % [
		DirectorSystem.intensity, str(DirectorSystem.horde_active), str(DirectorSystem.safe_room)])
	lines.append("INF %d SPC %d" % [alive, specials])
	lines.append("ALLY %d DOWN %d" % [allies_alive, allies_downed])
	if level != null:
		lines.append("SCORE %d CMB %d" % [
			int(level.get("_score")), int(level.get("_combo"))])
		lines.append("TIME %.1fs %.0f%%" % [
			float(level.get("_elapsed")), float(level.call("get_progress")) * 100.0])
		lines.append("SEED %d" % GameManager.run_seed)
		lines.append("MODE %s %s" % [
			GameManager.current_mode, _formation_name(StringName(level.get("formation")))])
		ally_lines.append("AI BLACKBOARD")
		for ally in level.get_allies():
			if ally == null or not is_instance_valid(ally) or bool(ally.get("is_dead")):
				continue
			var target: Node = ally.get("enemy")
			var target_text := "-"
			if target != null and is_instance_valid(target):
				var target_data = target.get("data")
				if target_data != null:
					target_text = String(target_data.id)
			ally_lines.append("%s %d/%d %s %s %s" % [
				String(ally.get("visual_id")).to_upper(), int(ally.get("hp")), int(ally.get("max_hp")),
				String(ally.get("state_text")), String(ally.get("command")).to_upper(), target_text])
	var player = level.get("player") if level != null else null
	if player != null and is_instance_valid(player):
		lines.append("PLAYER %d/%d %.0f,%.0f" % [
			int(player.get("hp")), int(player.get("max_hp")),
			player.global_position.x, player.global_position.y])
	_debug_label.text = "\n".join(lines)
	_debug_ally_label.text = "\n".join(ally_lines)


func _refresh_overlays() -> void:
	var player = level.get("player") if level != null else null
	if player == null or not is_instance_valid(player):
		return
	var ratio := clampf(float(player.get("hp")) / float(maxi(1, int(player.get("max_hp")))), 0.0, 1.0)
	var low_alpha := 0.0
	if ratio < 0.35 and not bool(player.get("is_dead")):
		low_alpha = clampf((0.35 - ratio) / 0.35, 0.0, 1.0) * 0.55
		low_alpha *= 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
	_lowhp.modulate.a = low_alpha
	var bile_left := float(player.get("bile_timer"))
	_bile.modulate.a = clampf(bile_left / 4.0, 0.0, 1.0) * (0.32 + 0.12 * sin(Time.get_ticks_msec() * 0.012))
	var downed := bool(player.get("is_downed"))
	_downed_label.visible = downed and not bool(player.get("is_dead"))


func _hp_color(ratio: float) -> Color:
	if ratio > 0.55:
		return UIKit.GREEN
	if ratio > 0.28:
		return UIKit.AMBER
	return UIKit.RED


# ------------------------------------------------------------------- pause ----
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause_open:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func _open_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	_pause_root.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.pause_game(true)
	var resume: Button = _pause_root.get_meta("resume")
	if resume != null:
		resume.grab_focus()


func _close_pause() -> void:
	if not _pause_open:
		return
	_pause_open = false
	_pause_root.visible = false
	GameManager.pause_game(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if _root != null:
		_root.grab_focus()


func _pause_restart() -> void:
	_pause_open = false
	_pause_root.visible = false
	GameManager.pause_game(false)
	EventBus.retry_level_requested.emit()


func _pause_menu() -> void:
	_pause_open = false
	_pause_root.visible = false
	GameManager.pause_game(false)
	EventBus.return_to_menu_requested.emit()


func _apply_visibility() -> void:
	_crosshair.visible = true
	_hitmarker.visible = true
	_downed_label.visible = false
