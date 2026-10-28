class_name GameFeelHitDirection
extends CanvasLayer
## Directional damage arcs at the screen edge. Four pre-allocated arcs share a
## pre-computed polyline; _draw() only rotates and tints it.
##
## reduced_motion: a short, faint edge-red flash replaces the arcs.

const MAX_ARCS := 4
const ARC_LIFETIME := 0.8
const ARC_RADIUS := 162.0
const ARC_HALF_ANGLE := PI / 12.0
const ARC_STEPS := 18


class ArcLayer:
	extends Node2D
	var arcs: Array[Dictionary] = []
	var points: PackedVector2Array = PackedVector2Array()

	func _draw() -> void:
		var now := Time.get_ticks_usec()
		for arc in arcs:
			var until := int(arc.get("until", 0))
			var remaining := float(until - now) / 1_000_000.0
			if remaining <= 0.0:
				continue
			var alpha := clampf(remaining / 0.8, 0.0, 1.0)
			var angle := float(arc.get("angle", 0.0))
			draw_set_transform(Vector2(320.0, 180.0), angle, Vector2.ONE)
			draw_polyline(points, Color(1.0, 0.10, 0.08, 0.18 * alpha), 7.0, true)
			draw_polyline(points, Color(1.0, 0.20, 0.14, 0.72 * alpha), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _arc_layer: ArcLayer = null
var _root: Control = null
var _edge_flash: TextureRect = null
var _flash_until: int = 0


func _ready() -> void:
	layer = 67
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "HitDirectionRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_arc_layer = ArcLayer.new()
	_arc_layer.name = "Arcs"
	_arc_layer.points = _build_arc_points()
	_root.add_child(_arc_layer)
	_edge_flash = TextureRect.new()
	_edge_flash.name = "EdgeFlash"
	_edge_flash.texture = _build_edge_texture()
	_edge_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_edge_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_flash.modulate = Color(1, 1, 1, 0)
	_root.add_child(_edge_flash)


func _process(_delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"hit_direction"):
		if not _arc_layer.arcs.is_empty():
			_arc_layer.arcs.clear()
			_arc_layer.queue_redraw()
		_edge_flash.modulate.a = 0.0
		return
	var now := Time.get_ticks_usec()
	var changed := false
	for index in range(_arc_layer.arcs.size() - 1, -1, -1):
		if now >= int(_arc_layer.arcs[index].get("until", 0)):
			_arc_layer.arcs.remove_at(index)
			changed = true
	if changed or not _arc_layer.arcs.is_empty():
		_arc_layer.queue_redraw()
	if now < _flash_until:
		var remaining := float(_flash_until - now) / 300_000.0
		_edge_flash.modulate.a = clampf(remaining, 0.0, 1.0) * 0.75
	else:
		_edge_flash.modulate.a = 0.0


func add_from_direction(direction: Vector2) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"hit_direction"):
		return
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.LEFT
	if GameFeelConfig.reduced_motion:
		_flash_until = Time.get_ticks_usec() + 300_000
		return
	var now := Time.get_ticks_usec()
	var angle := dir.angle()
	if _arc_layer.arcs.size() >= MAX_ARCS:
		_arc_layer.arcs.pop_front()
	_arc_layer.arcs.append({
		"angle": angle,
		"until": now + int(ARC_LIFETIME * 1_000_000.0),
		"started": now,
	})
	_arc_layer.queue_redraw()


func clear() -> void:
	_arc_layer.arcs.clear()
	_arc_layer.queue_redraw()
	_edge_flash.modulate.a = 0.0
	_flash_until = 0


func arc_count() -> int:
	return _arc_layer.arcs.size()


func max_arcs() -> int:
	return MAX_ARCS


func _build_arc_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(ARC_STEPS + 1)
	for i in ARC_STEPS + 1:
		var angle := -ARC_HALF_ANGLE + (2.0 * ARC_HALF_ANGLE) * float(i) / float(ARC_STEPS)
		points[i] = Vector2(cos(angle), sin(angle)) * ARC_RADIUS
	return points


func _build_edge_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.6, 0.02, 0.02, 0.0),
		Color(0.62, 0.02, 0.02, 0.0),
		Color(0.86, 0.06, 0.04, 0.85),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture
