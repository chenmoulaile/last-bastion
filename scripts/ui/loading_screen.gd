extends Control
## LoadingScreen - shows a progress bar and random tip while a level scene
## loads asynchronously in the background.

signal loading_complete(level_id: StringName)

const TIPS := [
	"开火会降低音乐音量，掩盖敌人靠近的声音。",
	"近战格挡可以抵消伤害并反击。",
	"药丸会随时间恢复生命，但不会超过上限。",
	"不同武器对不同僵尸类型有不同的效果。",
	"在安全房休息可以恢复所有生命值。",
	"火瓶投向僵尸密集处可以连续清除大量敌人。",
	"坦克到达时，优先使用爆破武器处理装甲部位。",
	"子弹上膛前按reload可以快速切枪取消换弹。",
	"幸存者倒地时靠近并按E即可治疗。",
	"镜头晃动和后坐力会随武器重量变化。",
]

const BAR_W := 188.0
const BAR_H := 7.0

var _level_path: String = ""
var _level_id: StringName = ""
var _progress: Array[float] = []
var _bar_fill: ColorRect = null
var _tip_label: Label = null
var _pct_label: Label = null
var _loading_started: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if not _level_path.is_empty():
		ResourceLoader.load_threaded_request(_level_path, "PackedScene")
		_loading_started = true


func setup(level_id: StringName, level_path: String) -> void:
	_level_id = level_id
	_level_path = level_path


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2((640 - BAR_W) * 0.5, 280.0)
	vbox.size = Vector2(BAR_W, 46)
	add_child(vbox)

	_tip_label := Label.new()
	_tip_label.position = Vector2(0, 0)
	_tip_label.size = Vector2(BAR_W, 12)
	_tip_label.horizontal_alignment = HorizontalAlignment.CENTER
	_tip_label.add_theme_font_override("font", UIKit.font_latin())
	_tip_label.add_theme_font_size_override("font_size", 9)
	_tip_label.add_theme_color_override("font_color", UIKit.MUTED)
	_tip_label.text = TIPS.pick_random()
	vbox.add_child(_tip_label)

	var bar_back := ColorRect.new()
	bar_back.position = Vector2(0, 14)
	bar_back.size = Vector2(BAR_W, BAR_H)
	bar_back.color = Color(0.02, 0.03, 0.04, 0.95)
	bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_back)

	_bar_fill := ColorRect.new()
	_bar_fill.position = Vector2(0, 0)
	_bar_fill.size = Vector2(0, BAR_H)
	_bar_fill.color = UIKit.AMBER
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bar_fill.material = mat
	bar_back.add_child(_bar_fill)

	_pct_label := Label.new()
	_pct_label.position = Vector2(0, 26)
	_pct_label.size = Vector2(BAR_W, 10)
	_pct_label.horizontal_alignment = HorizontalAlignment.CENTER
	_pct_label.add_theme_font_override("font", UIKit.font_latin())
	_pct_label.add_theme_font_size_override("font_size", 8)
	_pct_label.add_theme_color_override("font_color", UIKit.INK)
	_pct_label.text = "0%"
	vbox.add_child(_pct_label)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)


func _process(_delta: float) -> void:
	if not _loading_started or _level_path.is_empty():
		return
	var status = ResourceLoader.get_load_status(_level_path, _progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var pct := 0.0
		if not _progress.is_empty():
			pct = _progress[0]
		pct = clampf(pct, 0.0, 1.0)
		_bar_fill.size.x = BAR_W * pct
		_pct_label.text = "%d%%" % int(pct * 100.0)
	elif status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_DONE:
		_bar_fill.size.x = BAR_W
		_pct_label.text = "100%"
		loading_complete.emit(_level_id)
	else:
		_bar_fill.size.x = BAR_W
		_pct_label.text = "100%"
		loading_complete.emit(_level_id)
			_bar_fill.size.x = BAR_W
			_pct_label.text = "100%"
			loading_complete.emit(_level_id)
