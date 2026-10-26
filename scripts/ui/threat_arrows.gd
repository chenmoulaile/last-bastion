class_name ThreatArrows
extends Control
## Draws edge markers for special infected that are outside the camera view.
## The HUD owns one of these; it reads only public zombie data and never
## changes gameplay state.

const MARGIN := 16.0
const ARROW := 9.0

var level: Node = null
var debug_vision: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if level == null or GameManager.state != GameManager.State.PLAYING:
		return
	var view := get_viewport_rect().size
	var center := view * 0.5
	var half := view * 0.5 - Vector2(MARGIN, MARGIN)
	var xform := get_viewport().get_canvas_transform()
	if debug_vision:
		_draw_vision(xform)
	for node in get_tree().get_nodes_in_group("zombies"):
		if node == null or not is_instance_valid(node) or bool(node.get("dead")):
			continue
		var zd: ZombieData = node.get("data")
		if zd == null or not zd.is_special:
			continue
		var screen: Vector2 = xform * (node.global_position + Vector2(0, -18))
		if Rect2(Vector2(12, 12), view - Vector2(24, 24)).has_point(screen):
			continue
		var dir := screen - center
		if dir.length_squared() < 1.0:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var edge := center + dir * _border_distance(dir, half)
		var perp := Vector2(-dir.y, dir.x)
		var tip := edge + dir * ARROW
		var base := edge - dir * ARROW
		var color := Color("d24a38")
		match String(zd.id):
			"tank":
				color = Color("e3b354")
			"witch":
				color = Color("9a7bb5")
			"boomer":
				color = Color("82ac5c")
		draw_colored_polygon(PackedVector2Array([
			tip, base + perp * 6.0, base - perp * 6.0,
		]), color)
		draw_line(edge - dir * 3.0, tip, Color(0, 0, 0, 0.55), 1.0)


func _border_distance(dir: Vector2, half: Vector2) -> float:
	var tx := half.x / maxf(absf(dir.x), 0.001)
	var ty := half.y / maxf(absf(dir.y), 0.001)
	return minf(tx, ty)


func _draw_vision(xform: Transform2D) -> void:
	var player: Node2D = level.get_player()
	if player == null or not is_instance_valid(player):
		return
	var aim: Vector2 = player.get("aim_dir")
	var origin := player.global_position + Vector2(0, -16)
	var end := origin + aim * 420.0
	draw_line(xform * origin, xform * end, Color(0.25, 1.0, 0.85, 0.45), 1.0)
	draw_circle(xform * end, 2.0, Color(0.25, 1.0, 0.85, 0.65))
	for ally in level.get_allies():
		if ally == null or not is_instance_valid(ally) or bool(ally.get("is_dead")):
			continue
		var enemy: Node2D = ally.get("enemy")
		if enemy == null or not is_instance_valid(enemy) or bool(enemy.get("dead")):
			continue
		var from: Vector2 = xform * (ally.global_position + Vector2(0, -14))
		var to: Vector2 = xform * (enemy.global_position + Vector2(0, -14))
		draw_line(from, to, Color(1.0, 0.75, 0.25, 0.40), 1.0)
		draw_circle(to, 2.0, Color(1.0, 0.75, 0.25, 0.65))
