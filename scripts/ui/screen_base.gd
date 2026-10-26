class_name UIScreen
extends Control
## Base class for every full-screen menu. Screens never load each other:
## they emit navigate() and Main owns the router.

signal navigate(target: StringName, payload: Dictionary)

const VIEW := Vector2(640, 360)

var _fade_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	modulate = Color(1, 1, 1, 0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.16)


func _build() -> void:
	pass


func go(target: StringName, payload: Dictionary = {}) -> void:
	navigate.emit(target, payload)


func add_background(texture_name: String = "title_bg", dim: float = 0.35) -> void:
	UIKit.screen_background(self, texture_name, dim)
	UIKit.add_scanlines(self, 0.05)


func add_header(kicker: String, heading: String, accent: Color = UIKit.AMBER) -> void:
	var kicker_label := UIKit.label(kicker, 7, accent, UIKit.font_latin())
	kicker_label.position = Vector2(24, 12)
	kicker_label.size = Vector2(500, 9)
	add_child(kicker_label)

	var title_label := UIKit.title(heading, 24, UIKit.INK)
	title_label.position = Vector2(22, 21)
	title_label.size = Vector2(560, 28)
	add_child(title_label)

	var line := ColorRect.new()
	line.color = accent
	line.position = Vector2(24, 50)
	line.size = Vector2(592, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


func add_footer(text: String) -> void:
	var footer := UIKit.label(text, 7, UIKit.DIM, UIKit.font_latin())
	footer.position = Vector2(24, 340)
	footer.size = Vector2(592, 9)
	add_child(footer)


func add_back_button(target: StringName = &"menu", label: String = "返回") -> Button:
	var back := UIKit.button("← " + label, 76, 22)
	back.position = Vector2(548, 14)
	back.pressed.connect(func() -> void: go(target))
	add_child(back)
	return back


func add_panel(pos: Vector2, panel_size: Vector2, fill: Color = UIKit.PANEL,
		border: Color = UIKit.LINE) -> Panel:
	var panel := UIKit.panel(fill, border)
	panel.position = pos
	panel.size = panel_size
	add_child(panel)
	return panel


func add_stat(parent: Node, pos: Vector2, label_text: String, value_text: String,
		color: Color = UIKit.INK, width: float = 120.0) -> Label:
	var key := UIKit.label(label_text, 7, UIKit.MUTED, UIKit.font_latin())
	key.position = pos
	key.size = Vector2(width, 8)
	parent.add_child(key)
	var value := UIKit.label(value_text, 10, color)
	value.position = pos + Vector2(0, 9)
	value.size = Vector2(width, 12)
	parent.add_child(value)
	return value


func add_progress_bar(parent: Node, pos: Vector2, bar_width: float, ratio: float,
		fill_color: Color = UIKit.AMBER, height: float = 4.0) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0.01, 0.015, 0.02, 0.9)
	back.position = pos
	back.size = Vector2(bar_width, height)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = pos
	fill.size = Vector2(bar_width * clampf(ratio, 0.0, 1.0), height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fill)
	return fill
