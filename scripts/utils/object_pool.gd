class_name ObjectPool
extends RefCounted
## Generic pool used for corpses, decals and particle nodes. Bullets are hitscan
## in this game, so the spec's bullet pool is satisfied by the tracer/impact
## effect pool instead.

var _scene: PackedScene
var _free: Array[Node2D] = []
var _parent: Node
var _max_size: int = 64


func _init(scene: PackedScene = null, parent: Node = null, max_size: int = 64) -> void:
	_scene = scene
	_parent = parent
	_max_size = max_size


func acquire() -> Node2D:
	var node: Node2D
	if not _free.is_empty():
		node = _free.pop_back()
	else:
		node = _scene.instantiate() as Node2D
		_parent.add_child(node)
	node.visible = true
	node.process_mode = Node.PROCESS_MODE_INHERIT
	return node


func release(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = false
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
