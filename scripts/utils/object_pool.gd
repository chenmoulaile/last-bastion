class_name ObjectPool
extends RefCounted
## Generic pool used for corpses, decals and particle nodes. Bullets are hitscan
## in this game, so the spec's bullet pool is satisfied by the tracer/impact
## effect pool instead.

var _scene: PackedScene
var _free: Array[Node] = []
var _parent: Node
var _max_size: int = 64


func _init(scene: PackedScene, parent: Node, max_size: int = 64) -> void:
	_scene = scene
	_parent = parent
	_max_size = max_size


func acquire() -> Node:
	var node: Node
	if not _free.is_empty():
		node = _free.pop_back()
	else:
		node = _scene.instantiate()
		_parent.add_child(node)
	if node is Node2D:
		(node as Node2D).visible = true
	node.process_mode = Node.PROCESS_MODE_INHERIT
	return node


func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node2D:
		(node as Node2D).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if _free.size() < _max_size:
		_free.append(node)
	else:
		node.queue_free()


func clear() -> void:
	for node in _free:
		if is_instance_valid(node):
			node.queue_free()
	_free.clear()
