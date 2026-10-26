extends UIScreen
## 20 achievements with icons, unlock state and counter progress.


func _build() -> void:
	add_background("title_bg", 0.66)
	var unlocked: int = SaveSystem.data.get("achievements", []).size()
	add_header("ACHIEVEMENTS", "成就墙  %d / %d" % [unlocked, SaveSystem.ACHIEVEMENTS.size()], UIKit.AMBER)
	add_back_button(&"menu", "主菜单")
	add_footer("成就跨存档永久记录 · 计数器成就会显示当前进度 · 全部成就是完整战役的最终目标")

	var rows := SaveSystem.ACHIEVEMENTS
	for i in rows.size():
		var ach: Dictionary = rows[i]
		var col := i % 4
		var row := int(i / 4)
		var pos := Vector2(24 + col * 148, 60 + row * 54)
		_make_card(ach, pos)
	var count := UIKit.label("%d / %d UNLOCKED" % [unlocked, rows.size()], 8, UIKit.AMBER, UIKit.font_latin())
	count.position = Vector2(500, 50)
	count.size = Vector2(116, 9)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(count)


func _make_card(ach: Dictionary, pos: Vector2) -> void:
	var id := String(ach.get("id", ""))
	var is_unlocked := SaveSystem.has_achievement(StringName(id))
	var card := Control.new()
	card.position = pos
	card.size = Vector2(142, 50)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	var bg := Panel.new()
	bg.size = Vector2(142, 50)
	bg.add_theme_stylebox_override("panel", UIKit.panel_style(
		Color(0.10, 0.085, 0.05, 0.95) if is_unlocked else UIKit.PANEL,
		UIKit.AMBER if is_unlocked else UIKit.LINE))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var icon := UIKit.icon_rect(String(ach.get("icon", "ach_" + id)), 24.0)
	icon.position = Vector2(5, 5)
	icon.modulate = Color.WHITE if is_unlocked else Color(0.32, 0.34, 0.34, 0.9)
	card.add_child(icon)

	var name_label := UIKit.label(String(ach.get("name", id)), 8, UIKit.INK if is_unlocked else UIKit.MUTED)
	name_label.position = Vector2(34, 3)
	name_label.size = Vector2(104, 10)
	name_label.clip_text = true
	card.add_child(name_label)

	var desc := UIKit.label(String(ach.get("desc", "")), 7, UIKit.MUTED if is_unlocked else Color("7e8784"))
	desc.position = Vector2(34, 14)
	desc.size = Vector2(104, 24)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	var status := UIKit.label("", 6, UIKit.GREEN if is_unlocked else UIKit.MUTED, UIKit.font_latin())
	status.position = Vector2(5, 38)
	status.size = Vector2(132, 8)
	card.add_child(status)
	if is_unlocked:
		status.text = "UNLOCKED  ·  已解锁"
	else:
		status.text = _progress_text(id)


func _progress_text(id: String) -> String:
	match id:
		"door_kicker":
			return "进度 %d / 100" % SaveSystem.get_counter("doors_kicked")
		"medic":
			return "进度 %d / 50" % SaveSystem.get_counter("rescues")
		"environmentalist":
			return "进度 %d / 50" % SaveSystem.get_counter("barrel_kills")
		"hunter_interrupter":
			return "进度 %d / 25" % SaveSystem.get_counter("hunter_interrupts")
		"fire_safety":
			return "进度 %d / 15" % SaveSystem.get_counter("molotov_kills")
		"witch_crowning":
			return "进度 %d / 1" % SaveSystem.get_counter("witch_crowns")
		_:
			return "LOCKED  ·  未解锁"
