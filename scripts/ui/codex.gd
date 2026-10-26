extends UIScreen
## Codex of special infected and uncommon common infected. Entries unlock on kill.

const SPECIALS := ["hunter", "smoker", "boomer", "charger", "spitter", "jockey", "tank", "witch"]
const UNCOMMONS := ["riot", "hazmat", "mud", "hardhat", "clown", "scavenger"]


func _build() -> void:
	add_background("title_bg", 0.66)
	var seen: int = SaveSystem.data.get("codex", []).size()
	add_header("CODEX", "感染图鉴  %d / 14" % seen, UIKit.RED)
	add_back_button(&"menu", "主菜单")
	add_footer("击杀特殊感染者或变异普感后解锁条目 · 图鉴跨存档保留 · 全部条目解锁可获得“全图鉴收藏家”")

	var entries: Array[String] = []
	entries.append_array(SPECIALS)
	entries.append_array(UNCOMMONS)
	for i in entries.size():
		var col := i % 2
		var row := int(i / 2)
		var pos := Vector2(24 + col * 300, 60 + row * 36)
		_make_entry(StringName(entries[i]), pos, i >= SPECIALS.size())

	var count := UIKit.label("%d RECORDED" % seen, 8, UIKit.AMBER, UIKit.font_latin())
	count.position = Vector2(500, 50)
	count.size = Vector2(116, 9)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(count)


func _make_entry(kind: StringName, pos: Vector2, uncommon: bool) -> void:
	var zd := GameManager.get_zombie(kind)
	if zd == null:
		return
	var recorded: bool = String(kind) in SaveSystem.data.get("codex", [])
	var card := Control.new()
	card.position = pos
	card.size = Vector2(292, 34)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	var bg := Panel.new()
	bg.size = Vector2(292, 34)
	bg.add_theme_stylebox_override("panel", UIKit.panel_style(
		Color(0.09, 0.065, 0.06, 0.95) if recorded else UIKit.PANEL,
		UIKit.RED_DARK if recorded else UIKit.LINE))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var sprite := TextureRect.new()
	sprite.position = Vector2(3, 2)
	sprite.size = Vector2(30, 30)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := UIKit.texture("res://assets/sprites/zombies/%s_idle.png" % zd.sprite_prefix)
	if tex != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(0, 0, float(tex.get_width()) / 4.0, float(tex.get_height()))
		sprite.texture = atlas
	sprite.modulate = Color.WHITE if recorded else Color(0.25, 0.27, 0.27, 0.9)
	card.add_child(sprite)

	var name_label := UIKit.label(zd.display_name, 9, UIKit.INK if recorded else UIKit.MUTED)
	name_label.position = Vector2(38, 1)
	name_label.size = Vector2(120, 11)
	card.add_child(name_label)

	var tag := UIKit.label("UNCOMMON" if uncommon else "SPECIAL", 6,
		UIKit.AMBER if uncommon else UIKit.RED, UIKit.font_latin())
	tag.position = Vector2(158, 3)
	tag.size = Vector2(128, 8)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(tag)

	var desc := UIKit.label(zd.description, 7, UIKit.MUTED if recorded else Color("7e8784"))
	desc.position = Vector2(38, 13)
	desc.size = Vector2(248, 18)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)
	if not recorded:
		desc.text = "尚未记录 · 击杀后解锁档案"
