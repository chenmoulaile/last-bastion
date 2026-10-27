extends Node
## EnemyPerception - global perception arbitration for the stealth layer.
##
## Zombies ask this singleton before they can see a target. Three effects live
## here so every AI (common, special, faction) obeys the same rules:
##   ignore_source()      -> a source is invisible to all infected for N seconds
##   suppress_noise()     -> a world position stops propagating alert chains
##   reveal_enemies()     -> marks infected so their outline draws over walls
##
## It never holds scene references; only instance ids and timestamps.

var _ignored: Dictionary = {} # instance_id -> expire_at_msec
var _revealed: Dictionary = {} # instance_id -> expire_at_msec
var _quiet_zones: Array[Dictionary] = []


func _process(_delta: float) -> void:
	if _ignored.is_empty() and _revealed.is_empty() and _quiet_zones.is_empty():
		return
	var now := Time.get_ticks_msec()
	for key in _ignored.keys():
		if int(_ignored[key]) <= now:
			_ignored.erase(key)
	for key in _revealed.keys():
		if int(_revealed[key]) <= now:
			_revealed.erase(key)
	var kept: Array[Dictionary] = []
	for zone in _quiet_zones:
		if int(zone["until"]) > now:
			kept.append(zone)
	_quiet_zones = kept


# ------------------------------------------------------------------ ignore ----
func ignore_source(source: Node, duration: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	_ignored[source.get_instance_id()] = Time.get_ticks_msec() + int(duration * 1000.0)


func is_ignored(source: Node) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	var key := source.get_instance_id()
	if not _ignored.has(key):
		return false
	if int(_ignored[key]) <= Time.get_ticks_msec():
		_ignored.erase(key)
		return false
	return true


func clear_ignore(source: Node) -> void:
	if source != null and is_instance_valid(source):
		_ignored.erase(source.get_instance_id())


# ------------------------------------------------------------------ reveal ----
func reveal_enemies_in_radius(center: Vector2, radius: float, duration: float) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		if node == null or not is_instance_valid(node):
			continue
		if node.global_position.distance_to(center) > radius:
			continue
		if node.has_method("reveal_through_walls"):
			node.reveal_through_walls(duration)
			count += 1
		else:
			_revealed[node.get_instance_id()] = Time.get_ticks_msec() + int(duration * 1000.0)
	if count > 0:
		EventBus.enemies_revealed.emit(count, radius)
	return count


func is_revealed(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var key := node.get_instance_id()
	if not _revealed.has(key):
		return false
	if int(_revealed[key]) <= Time.get_ticks_msec():
		_revealed.erase(key)
		return false
	return true


# ------------------------------------------------------------------- quiet ----
## Silences alert propagation around a position: used by silent executions so a
## corpse does not wake the room.
func suppress_noise(pos: Vector2, radius: float, duration: float) -> void:
	_quiet_zones.append({
		"pos": pos,
		"radius": radius,
		"until": Time.get_ticks_msec() + int(duration * 1000.0),
	})


func is_noise_suppressed(pos: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	for zone in _quiet_zones:
		if int(zone["until"]) <= now:
			continue
		var center: Vector2 = zone["pos"]
		if center.distance_to(pos) <= float(zone["radius"]):
			return true
	return false


func reset() -> void:
	_ignored.clear()
	_revealed.clear()
	_quiet_zones.clear()
