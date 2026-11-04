class_name InteriorAmbience
extends Node2D
## wp3-interior-visuals：室内氛围挂件。
## 每帧检查玩家是否在房间 rect 内：在屋内时给玩家 / 队友（allies 组）/
## 室内掉落物（pickups 组且位于房间内）的根 CanvasItem 加轻微暖色 modulate
## Color(1.0, 0.92, 0.82)，回到街道后恢复原值。
## 房间本体（InteriorRoot）的暖色调是固定的，不在此管理。
## 只改 modulate，不碰 transform/碰撞；节点被释放时原值随节点一起失效。

const WARM := Color(1.0, 0.92, 0.82)

var room_rect := Rect2()
var _inside := false
var _tinted := {}  # CanvasItem -> 原始 modulate


func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player") as Node2D
	var inside := player != null and is_instance_valid(player) \
			and room_rect.grow(24.0).has_point(player.global_position)
	if inside:
		_apply_warm(player)
		for n in tree.get_nodes_in_group("allies"):
			_apply_warm(n)
		for n in tree.get_nodes_in_group("pickups"):
			if n is Node2D and room_rect.has_point((n as Node2D).global_position):
				_apply_warm(n)
		_inside = true
	elif _inside:
		_restore_all()
		_inside = false


func _apply_warm(node: Node) -> void:
	if node is not CanvasItem or _tinted.has(node):
		return
	_tinted[node] = (node as CanvasItem).modulate
	(node as CanvasItem).modulate = WARM


func _restore_all() -> void:
	for node in _tinted.keys():
		if is_instance_valid(node):
			(node as CanvasItem).modulate = _tinted[node]
	_tinted.clear()
