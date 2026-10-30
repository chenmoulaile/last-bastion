extends UIScreen
## Credits, licenses and the original-assets statement.


func _build() -> void:
	add_background("title_bg", 0.68)
	add_header("CREDITS", "制作人员", UIKit.AMBER)
	add_back_button(&"menu", "主菜单")

	var left := add_panel(Vector2(24, 62), Vector2(344, 232), UIKit.PANEL, UIKit.LINE)
	var lines := [
		["DESIGN & CODE", "Last Bastion Studio"],
		["PIXEL ART", "Procedural original sprites"],
		["AUDIO", "Synthesized original score & SFX"],
		["ENGINE", "Godot 4.7.2 · GDScript"],
		["ART PIPELINE", "Python · Pillow · NumPy"],
		["FONTS", "Silkscreen · ZCOOL QingKe HuangYou · Noto Sans SC"],
		["LICENSE", "MIT · source available on GitHub"],
	]
	for i in lines.size():
		var key := UIKit.label(lines[i][0], 7, UIKit.AMBER, UIKit.font_latin())
		key.position = Vector2(10, 10 + i * 30)
		key.size = Vector2(320, 8)
		left.add_child(key)
		var value := UIKit.label(lines[i][1], 9, UIKit.INK)
		value.position = Vector2(10, 19 + i * 30)
		value.size = Vector2(320, 11)
		left.add_child(value)

	var right := add_panel(Vector2(380, 62), Vector2(236, 232), UIKit.PANEL, UIKit.LINE)
	var note_head := UIKit.label("ORIGINAL ASSETS", 7, UIKit.GREEN, UIKit.font_latin())
	note_head.position = Vector2(8, 8)
	note_head.size = Vector2(220, 8)
	right.add_child(note_head)
	var note := UIKit.label("所有角色、感染者、场景、图标与音频均为本项目原创程序化生成资产。Left 4 Dead 2 仅作为合作丧尸生存玩法与剪影色彩语言的参考；本作不包含任何 Valve 的素材、商标或音频。", 8, UIKit.MUTED)
	note.position = Vector2(8, 20)
	note.size = Vector2(220, 86)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(note)

	var font_head := UIKit.label("FONT LICENSE", 7, UIKit.AMBER, UIKit.font_latin())
	font_head.position = Vector2(8, 114)
	font_head.size = Vector2(220, 8)
	right.add_child(font_head)
	var font_note := UIKit.label("Silkscreen, ZCOOL QingKe HuangYou and Noto Sans SC are distributed under the SIL Open Font License 1.1. A copy is included at assets/licenses/OFL.txt.", 7, UIKit.MUTED)
	font_note.position = Vector2(8, 126)
	font_note.size = Vector2(220, 58)
	font_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(font_note)

	var thanks := UIKit.label("感谢每一位在最后防线前没有后退的人。", 9, UIKit.INK)
	thanks.position = Vector2(8, 196)
	thanks.size = Vector2(220, 20)
	thanks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(thanks)

	var footer := UIKit.label("LAST BASTION · 最后防线  ·  v%s  ·  MIT"
		% str(ProjectSettings.get_setting("application/config/version", "3.1.1")),
		8, UIKit.DIM, UIKit.font_latin())
	footer.position = Vector2(24, 308)
	footer.size = Vector2(592, 10)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)
