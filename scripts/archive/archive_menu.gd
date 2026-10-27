extends UIScreen
## ArchiveMenu - the "档案" tab. Lists every fragment by security level;
## locked entries render as █████ until the player finds them.

var _selected: String = ""
var _rows: Dictionary = {} # fragment_id -> Button
var _detail_title: Label
var _detail_meta: Label
var _detail_body: Label
var _detail_hint: Label
var _progress: Label
var _filter: int = 0 # 0 = all
var _list_root: Control


func _build() -> void:
	add_background("title_bg", 0.72)
	add_header("RUST FREQUENCY ARCHIVE", "档案库", UIKit.AMBER)
	add_back_button(&"menu", "返回")
	add_footer("四层密级：传闻 · 证据 · 共谋 · 深渊 ｜ 高密级档案会提高各派系对你的敌意")

	_progress = UIKit.label("", 8, UIKit.AMBER, UIKit.font_latin())
	_progress.position = Vector2(380, 14)
	_progress.size = Vector2(160, 10)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_progress)

	_build_filters()

	_list_root = Control.new()
	_list_root.position = Vector2(20, 96)
	_list_root.size = Vector2(300, 232)
	add_child(_list_root)

	var detail := add_panel(Vector2(330, 58), Vector2(290, 270), UIKit.PANEL, UIKit.LINE)
	_detail_title = UIKit.label("", 13, UIKit.INK)
	_detail_title.position = Vector2(10, 8)
	_detail_title.size = Vector2(268, 16)
	detail.add_child(_detail_title)
	_detail_meta = UIKit.label("", 7, UIKit.AMBER, UIKit.font_latin())
	_detail_meta.position = Vector2(10, 26)
	_detail_meta.size = Vector2(268, 10)
	detail.add_child(_detail_meta)
	var rule := UIKit.hsep(detail, UIKit.LINE)
	rule.position = Vector2(10, 40)
	rule.size = Vector2(268, 1)
	_detail_body = UIKit.label("", 9, UIKit.INK, UIKit.font_cjk())
	_detail_body.position = Vector2(10, 48)
	_detail_body.size = Vector2(268, 180)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_body)
	_detail_hint = UIKit.label("", 8, UIKit.DIM, UIKit.font_cjk())
	_detail_hint.position = Vector2(10, 232)
	_detail_hint.size = Vector2(268, 30)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_hint)

	_rebuild_list()
	_refresh_progress()


func _build_filters() -> void:
	var labels := ["全部", "传闻", "证据", "共谋", "深渊"]
	for i in labels.size():
		var button := UIKit.button(labels[i], 54, 20)
		button.position = Vector2(20 + i * 58, 62)
		button.pressed.connect(_set_filter.bind(i))
		add_child(button)


func _set_filter(index: int) -> void:
	_filter = index
	_selected = ""
	_rebuild_list()
	AudioManager.play_sfx(&"ui_click")


func _rebuild_list() -> void:
	for child in _list_root.get_children():
		_list_root.remove_child(child)
		child.queue_free()
	_rows.clear()

	var scroll := ScrollContainer.new()
	scroll.position = Vector2.ZERO
	scroll.size = Vector2(302, 232)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_list_root.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(296, 0)
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)

	var first_id := ""
	for fragment in _all_fragments():
		if _filter > 0 and fragment.security_level != _filter:
			continue
		var row := _make_row(fragment)
		box.add_child(row)
		if first_id == "":
			first_id = fragment.fragment_id
	if _selected == "" and first_id != "":
		_selected = first_id
	if _selected != "":
		_select(_selected)


func _all_fragments() -> Array[ArchiveFragment]:
	var out: Array[ArchiveFragment] = []
	for chapter in [1, 2, 3, 4]:
		out.append_array(ArchiveManager.fragments_for_chapter(chapter))
	return out


func _make_row(fragment: ArchiveFragment) -> Control:
	var unlocked := ArchiveManager.is_unlocked(fragment.fragment_id)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(296, 24)
	holder.size = Vector2(296, 24)

	var bg := UIKit.panel(Color(0.06, 0.07, 0.085, 0.9) if unlocked else Color(0.04, 0.045, 0.055, 0.9),
		fragment.security_color() if unlocked else UIKit.LINE)
	bg.position = Vector2.ZERO
	bg.size = Vector2(296, 24)
	holder.add_child(bg)

	var badge := UIKit.label("LV%d" % fragment.security_level, 7, fragment.security_color(), UIKit.font_latin())
	badge.position = Vector2(6, 7)
	badge.size = Vector2(26, 9)
	holder.add_child(badge)

	var title := UIKit.label(fragment.title if unlocked else fragment.redacted_title(),
		9, UIKit.INK if unlocked else UIKit.DIM)
	title.position = Vector2(34, 6)
	title.size = Vector2(240, 12)
	holder.add_child(title)

	var button := Button.new()
	button.size = Vector2(296, 24)
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", UIKit.panel_style(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed", UIKit.panel_style(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_select.bind(fragment.fragment_id))
	holder.add_child(button)
	return holder


func _select(fragment_id: String) -> void:
	_selected = fragment_id
	var fragment := ArchiveManager.get_fragment(fragment_id)
	if fragment == null:
		return
	var unlocked := ArchiveManager.is_unlocked(fragment_id)
	_detail_title.text = fragment.title if unlocked else fragment.redacted_title()
	_detail_meta.text = "%s · %s  |  %s" % [fragment.security_name(), fragment.security_label_zh(), fragment.timestamp]
	_detail_meta.add_theme_color_override("font_color", fragment.security_color())
	if unlocked:
		_detail_body.text = fragment.content_text
		if fragment.translation != "":
			_detail_body.text += "\n\n" + fragment.translation
		_detail_hint.text = "来源：" + fragment.source
		_detail_hint.add_theme_color_override("font_color", UIKit.DIM)
	else:
		_detail_body.text = "████████████████\n██████████\n\n████████████████████"
		if fragment.is_specialist_gated():
			_detail_hint.text = "需要 %s 的专业知识才能解读。" % fragment.required_specialist_name()
		else:
			_detail_hint.text = "尚未找到。继续推进第 %d 章。" % fragment.chapter
		_detail_hint.add_theme_color_override("font_color", UIKit.AMBER)
	AudioManager.play_sfx(&"ui_click")


func _refresh_progress() -> void:
	_progress.text = "COLLECTED %d / %d" % [ArchiveManager.unlocked_count(), ArchiveManager.total_count()]
	if ArchiveManager.has_final_choice():
		_progress.text += "   ·   ENDING: " + ArchiveManager.final_choice.to_upper()
