extends Node
## Centralized object pool manager for v2.0.0 vertical slice.
## Pools are created lazily on first acquire; no warmup needed.

var pools: Dictionary = {}

func _get_or_create(key: StringName, scene_path: String, max_size: int) -> ObjectPool:
	var pool: ObjectPool = pools.get(key, null)
	if pool == null:
		var scene: PackedScene = load(scene_path)
		if scene == null:
			push_warning("PoolManager: missing scene " + scene_path)
			return null
		pool = ObjectPool.new()
		pool._init(scene, self, max_size)
		pools[key] = pool
	return pool

func acquire(key: StringName) -> Node2D:
	var pool: ObjectPool = _get_or_create(key, "", 64)
	if pool == null:
		push_warning("PoolManager: unknown pool '" + String(key) + "'")
		return null
	return pool.acquire()

func release(key: StringName, node: Node2D) -> void:
	var pool: ObjectPool = pools.get(key, null)
	if pool == null:
		return
	pool.release(node)

func reset() -> void:
	for key in pools.keys():
		var pool: ObjectPool = pools[key]
		if pool != null:
			pool.clear()

func pool_count() -> int:
	return pools.size()

## Pre-register a pool without warmup.
func register(key: StringName, scene_path: String, max_size: int = 64) -> void:
	_get_or_create(key, scene_path, max_size)
