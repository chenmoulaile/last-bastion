class_name UIKit
extends RefCounted
## Shared pixel-UI vocabulary: palette, fonts, styleboxes and small builders.
## Every screen uses this file so the 360p presentation stays coherent.

const BG := Color("0a0c10")
const BG_SOFT := Color("10141a")
const PANEL := Color(0.055, 0.070, 0.086, 0.94)
const PANEL_SOLID := Color("10141a")
const PANEL_RAISED := Color("171d25")
const LINE := Color("303a43")
const INK := Color("e8e2d4")
const MUTED := Color("8e9795")
const DIM := Color("5b6464")
const RED := Color("d24a38")
const RED_DARK := Color("7a241d")
const AMBER := Color("e3b354")
const GREEN := Color("82ac5c")
const TEAL := Color("5fa89d")
const BLUE := Color("7099c2")
const PURPLE := Color("9a7bb5")

const FONT_LATIN := "res://assets/fonts/silkscreen.ttf"
const FONT_LATIN_BOLD := "res://assets/fonts/silkscreen_bold.ttf"
const FONT_CJK := "res://assets/fonts/zcool.ttf"
const FONT_NOTO := "res://assets/fonts/noto400.woff2"

static var _slider_grabber_tex: Texture2D = null


static func font_latin() -> Font:
	var base: Font = load(FONT_LATIN)
	var cjk: Font = load(FONT_CJK)
	if base is FontFile and cjk != null:
		var ff := base as FontFile
		if ff.fallbacks.is_empty():
			ff.fallbacks = [cjk]
	return base


static func font_latin_bold() -> Font:
	var base: Font = load(FONT_LATIN_BOLD)
	var cjk: Font = load(FONT_CJK)
	if base is FontFile and cjk != null:
		var ff := base as FontFile
		if ff.fallbacks.is_empty():
			ff.fallbacks = [cjk]
	return base


static func font_cjk() -> Font:
	var base: Font = load(FONT_CJK)
	var fallback: Font = load(FONT_NOTO)
	if base is FontFile and fallback != null:
		var ff := base as FontFile
		if ff.fallbacks.is_empty():
			ff.fallbacks = [fallback]
	return base


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font_cjk()
	theme.default_font_size = 10
	theme.set_color("font_color", "Label", INK)
	theme.set_font_size("font_size", "Label", 10)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", AMBER)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", DIM)
	theme.set_font_size("font_size", "Button", 10)
	theme.set_stylebox("normal", "Button", button_style(PANEL_RAISED, LINE))
	theme.set_stylebox("hover", "Button", button_style(Color("222b34"), AMBER))
	theme.set_stylebox("pressed", "Button", button_style(Color("2b2119"), AMBER))
	theme.set_stylebox("focus", "Button", focus_style())
	theme.set_stylebox("disabled", "Button", button_style(Color("12161b"), Color("242b31")))
	theme.set_stylebox("panel", "Panel", panel_style())
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_constant("outline_size", "Label", 0)
	theme.set_constant("separation", "HBoxContainer", 6)
	theme.set_constant("separation", "VBoxContainer", 4)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color("0b0f13")
	slider_bg.border_color = LINE
	slider_bg.set_border_width_all(1)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = Color("b98435")
	slider_fill.border_color = AMBER
	slider_fill.set_border_width_all(1)
	slider_fill.content_margin_top = 2
	slider_fill.content_margin_bottom = 2
	var slider_fill_hi := slider_fill.duplicate() as StyleBoxFlat
	slider_fill_hi.bg_color = AMBER
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill_hi)
	theme.set_icon("grabber", "HSlider", _slider_grabber())
	theme.set_icon("grabber_highlight", "HSlider", _slider_grabber())
	theme.set_constant("center_grabber", "HSlider", 1)
	return theme


static func _slider_grabber() -> Texture2D:
	if _slider_grabber_tex != null:
		return _slider_grabber_tex
	var img := Image.create(7, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 11:
		for x in 7:
			var edge := x == 0 or x == 6 or y == 0 or y == 10
			var highlight := y == 1 or y == 2
			img.set_pixel(x, y, Color("0a0c10") if edge else (Color("f2d38a") if highlight else AMBER))
	_slider_grabber_tex = ImageTexture.create_from_image(img)
	return _slider_grabber_tex


static func panel_style(fill: Color = PANEL, border: Color = LINE, border_width: int = 1,
		radius: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 3
	box.shadow_offset = Vector2(1, 2)
	return box


static func button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


static func focus_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = AMBER
	box.set_border_width_all(1)
	box.expand_margin_left = 1
	box.expand_margin_right = 1
	box.expand_margin_top = 1
	box.expand_margin_bottom = 1
	return box


static func label(text: String, size: int = 10, color: Color = INK, font: Font = null) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	if font != null:
		out.add_theme_font_override("font", font)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


static func title(text: String, size: int = 28, color: Color = INK) -> Label:
	var out := label(text, size, color, font_latin_bold())
	out.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	out.add_theme_constant_override("shadow_offset_x", 2)
	out.add_theme_constant_override("shadow_offset_y", 2)
	return out


static func button(text: String, min_width: float = 120.0, height: float = 24.0,
		accent: bool = false) -> Button:
	var out := Button.new()
	out.text = text
	out.custom_minimum_size = Vector2(min_width, height)
	out.focus_mode = Control.FOCUS_ALL
	out.add_theme_font_size_override("font_size", 10)
	if accent:
		out.add_theme_color_override("font_color", Color("1a1208"))
		out.add_theme_color_override("font_hover_color", Color("120d06"))
		out.add_theme_stylebox_override("normal", button_style(AMBER, Color("f3ce7a")))
		out.add_theme_stylebox_override("hover", button_style(Color("f0c76b"), Color("ffe4a4")))
		out.add_theme_stylebox_override("pressed", button_style(Color("c9993d"), Color("ffe4a4")))
	return out


static func panel(fill: Color = PANEL, border: Color = LINE) -> Panel:
	var out := Panel.new()
	out.add_theme_stylebox_override("panel", panel_style(fill, border))
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


static func icon(name: String) -> Texture2D:
	return load("res://assets/sprites/ui/%s.png" % name) as Texture2D


static func portrait(id: String) -> Texture2D:
	return load("res://assets/sprites/characters/%s_portrait.png" % id) as Texture2D


static func texture(path: String) -> Texture2D:
	return load(path) as Texture2D


static func icon_rect(name: String, size: float = 16.0) -> TextureRect:
	var out := TextureRect.new()
	out.texture = icon(name)
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	out.custom_minimum_size = Vector2(size, size)
	out.size = Vector2(size, size)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


static func portrait_rect(id: String, size: float = 32.0) -> TextureRect:
	var out := TextureRect.new()
	out.texture = portrait(id)
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	out.custom_minimum_size = Vector2(size, size)
	out.size = Vector2(size, size)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return out


static func format_score(value: int) -> String:
	var digits := str(maxi(0, value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


static func format_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%d:%02d" % [total / 60, total % 60]


static func rank_color(rank: String) -> Color:
	match rank:
		"S":
			return AMBER
		"A":
			return GREEN
		"B":
			return BLUE
		_:
			return MUTED


static func difficulty_name(id: StringName) -> String:
	var row: Dictionary = GameManager.DIFFICULTY.get(id, {})
	return String(row.get("name", String(id)))


static func mode_name(id: StringName) -> String:
	match id:
		&"COMMAND":
			return "指挥模式"
		&"SQUAD":
			return "小队模式"
		_:
			return "自由模式"


static func chapter_color(chapter: int) -> Color:
	match chapter:
		1:
			return Color("a3b36b")
		2:
			return Color("7d9bb8")
		3:
			return Color("c0a269")
		4:
			return Color("b86a5c")
		_:
			return INK


static func chapter_subtitle(chapter: int) -> String:
	match chapter:
		1:
			return "郊区突围 · OUTSKIRTS"
		2:
			return "城市坠落 · THE FALL"
		3:
			return "军事残部 · LAST UNITS"
		4:
			return "最后防线 · LAST BASTION"
		_:
			return ""


static func hsep(parent: Node, color: Color = LINE, height: float = 1.0) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, height)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	return line


static func add_scanlines(root: Control, alpha: float = 0.06) -> void:
	var lines := Control.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.draw.connect(func() -> void:
		var h := lines.size.y
		var y := 0.0
		while y < h:
			lines.draw_line(Vector2(0, y), Vector2(lines.size.x, y), Color(0, 0, 0, alpha), 1.0)
			y += 3.0
	)
	root.add_child(lines)


static func add_vignette(root: Control, texture_name: String = "vignette", alpha: float = 0.6) -> void:
	var rect := TextureRect.new()
	rect.texture = icon(texture_name)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.modulate = Color(1, 1, 1, alpha)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)


static func screen_background(root: Control, texture_name: String = "title_bg",
		dim: float = 0.35) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture("res://assets/sprites/environment/%s.png" % texture_name)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.04, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	return rect
