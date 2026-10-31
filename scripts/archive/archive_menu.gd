extends UIScreen
## 档案库：按关卡浏览已收集的档案碎片，未收集显示锁定，无专家显示「无法解读」。
## 「锈蚀频率」P3-5。

var _list_box: VBoxContainer
var _detail_title: Label
var _detail_body: Label
var _detail_stamp: Label
var _selected: StringName = &""


func _build() -> void:
	add_background("title_bg", 0.5)
	add_header("ARCHIVE", "档案库", Color(0.75, 0.32, 0.28))
	add_back_button(&"menu", "主菜单")
	add_footer("碎片收集进度 %d / %d · 当前密级：%s" % [
		ArchiveManager.collected_count(), ArchiveManager.total_count(),
		ArchiveManager.tier_name(maxi(0, ArchiveManager.current_tier()))])

	var left := add_panel(Vector2(24, 66), Vector2(240, 268), UIKit.PANEL, UIKit.LINE)
	var scroll_hint := UIKit.label("关卡档案", 7, UIKit.AMBER, UIKit.font_latin())
	scroll_hint.position = Vector2(8, 4)
	left.add_child(scroll_hint)

	_list_box = VBoxContainer.new()
	_list_box.position = Vector2(8, 16)
	_list_box.size = Vector2(224, 240)
	left.add_child(_list_box)

	var right := add_panel(Vector2(276, 66), Vector2(340, 268), Color(0.04, 0.045, 0.055, 0.95), UIKit.LINE)
	_detail_title = UIKit.label("选择一份档案", 11, UIKit.INK)
	_detail_title.position = Vector2(10, 8)
	_detail_title.size = Vector2(320, 14)
	right.add_child(_detail_title)
	_detail_stamp = UIKit.label("", 8, Color(0.75, 0.32, 0.28))
	_detail_stamp.position = Vector2(250, 8)
	_detail_stamp.size = Vector2(80, 10)
	_detail_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_detail_stamp)
	_detail_body = UIKit.label("", 9, UIKit.INK)
	_detail_body.position = Vector2(10, 26)
	_detail_body.size = Vector2(320, 230)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_detail_body)

	_populate_list()


func _populate_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var by_level := ArchiveManager.fragments_by_level()
	for level_id in by_level.keys():
		for fid in by_level[level_id]:
			var frag := ArchiveManager.get_fragment(fid)
			var collected: bool = ArchiveManager.is_collected(fid)
			var label_text := "□ %s" % String(frag.get("title", String(fid)))
			if not collected:
				label_text = "■ %s（未收集）" % String(frag.get("level", ""))
			var btn := Button.new()
			btn.text = label_text
			btn.add_theme_font_size_override("font_size", 8)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.flat = true
			btn.pressed.connect(_show_detail.bind(fid))
			_list_box.add_child(btn)


func _show_detail(fid: StringName) -> void:
	_selected = fid
	var frag := ArchiveManager.get_fragment(fid)
	if frag.is_empty():
		return
	var collected: bool = ArchiveManager.is_collected(fid)
	_detail_title.text = String(frag.get("title", "")) if collected else "████████（未收集）"
	_detail_stamp.text = String(frag.get("stamp", "")) if collected else ""
	if not collected:
		_detail_body.text = "该碎片尚未在任务中发现。档案位置标记为 %s。" % String(frag.get("level", ""))
	elif ArchiveManager.can_decode(fid):
		_detail_body.text = String(frag.get("content", ""))
	else:
		_detail_body.text = "【无法解读】\n碎片内容经过专业加密。队伍中缺少对应专家：\n%s\n（维克多→生物数据 / 露西亚→物流记录 / 马库斯→安保协议 / 林远→地下结构）" % _specialist_name(StringName(frag.get("requires", "")))


func _specialist_name(kind: StringName) -> String:
	match kind:
		&"bio": return "维克多·陈（生物学家）"
		&"logistics": return "露西亚·莫雷诺（街头直觉）"
		&"security": return "马库斯·德尔加多（老兵直觉）"
		&"terrain": return "林远（山猫）"
		_: return "任意专家"
