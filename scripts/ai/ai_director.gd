class_name AIDirector
extends Node
## AIDirector - the faction-aware scheduling layer that sits on top of the
## v1.0 DirectorSystem loop (which keeps owning zombie pressure).
##
## Every 30s  : reads ArchiveManager.highest_security_level_collected()
## Every ~18s : sends a faction patrol toward the player
## Every 45s  : resolves a street skirmish between two hostile factions
##
## It never spawns nodes itself; LevelRunner owns the world and executes.

const PATROL_INTERVAL := 18.0
const SKIRMISH_INTERVAL := 45.0
const ARCHIVE_SCAN_INTERVAL := 30.0
const PATROL_SIZE := 2
const SKIRMISH_SIZE := 2

var level: Node = null
var enabled: bool = true

var _patrol_timer: float = 12.0
var _skirmish_timer: float = SKIRMISH_INTERVAL
var _archive_timer: float = ARCHIVE_SCAN_INTERVAL
var _last_security: int = 0
var _skirmish_active: bool = false
var _skirmish_until: float = 0.0
var _skirmish_pair: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(true)


func _process(delta: float) -> void:
	if not enabled or level == null:
		return
	if GameManager.state != GameManager.State.PLAYING:
		return
	_patrol_timer -= delta
	_skirmish_timer -= delta
	_archive_timer -= delta
	if _archive_timer <= 0.0:
		_archive_timer = ARCHIVE_SCAN_INTERVAL
		_scan_archive_pressure()
	if _patrol_timer <= 0.0:
		_patrol_timer = PATROL_INTERVAL * _rng.randf_range(0.8, 1.25)
		_spawn_patrol()
	if _skirmish_timer <= 0.0:
		_skirmish_timer = SKIRMISH_INTERVAL
		_try_skirmish()
	if _skirmish_active and Time.get_ticks_msec() / 1000.0 > _skirmish_until:
		_end_skirmish("timeout")


# ------------------------------------------------------------------ patrol ----
func _spawn_patrol() -> void:
	var faction_id := FactionManager.pick_patrol_faction(_rng)
	if faction_id == "":
		return
	var count := PATROL_SIZE
	if FactionManager.is_hostile(faction_id):
		count += 1
	for i in count:
		var kind := FactionManager.pick_unit(faction_id, _rng)
		if kind == "":
			continue
		var pos := _spawn_position(i)
		level.spawn_faction_unit(faction_id, kind, pos)


func _spawn_position(index: int) -> Vector2:
	var player := _player_position()
	var side := 1.0 if _rng.randf() < 0.65 else -1.0
	var x := player.x + side * _rng.randf_range(420.0, 620.0) + float(index) * 34.0 * side
	if level.has_method("clamp_spawn_x"):
		x = level.clamp_spawn_x(x)
	var y := player.y
	if level.has_method("get_ground_y"):
		var gy: float = level.get_ground_y(x)
		if gy > 0.0:
			y = gy
	return Vector2(x, y)


func _player_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return Vector2.ZERO
	return player.global_position


# ---------------------------------------------------------------- skirmish ----
func _try_skirmish() -> void:
	if _skirmish_active:
		return
	var player := _player_position()
	var pair := FactionManager.pick_skirmish_pair(player)
	if pair.size() < 2:
		return
	_skirmish_active = true
	_skirmish_pair = pair
	_skirmish_until = Time.get_ticks_msec() / 1000.0 + 55.0
	var center := Vector2(player.x + 520.0, player.y)
	if level.has_method("clamp_spawn_x"):
		center.x = level.clamp_spawn_x(center.x)
	if level.has_method("get_ground_y"):
		var gy: float = level.get_ground_y(center.x)
		if gy > 0.0:
			center.y = gy
	EventBus.faction_skirmish_started.emit(center, pair[0], pair[1])
	EventBus.level_event.emit("%s 与 %s 在街区交火" % [
		FactionManager.display_name(pair[0]), FactionManager.display_name(pair[1])])
	for side in 2:
		var faction_id: String = pair[side]
		var offset := -180.0 if side == 0 else 180.0
		for i in SKIRMISH_SIZE:
			var kind := FactionManager.pick_unit(faction_id, _rng)
			if kind == "":
				continue
			var pos := center + Vector2(offset + float(i) * 30.0 * (-1.0 if side == 0 else 1.0), 0)
			level.spawn_faction_unit(faction_id, kind, pos)
	# A skirmish is loud: the infected converge on it.
	if level.has_method("spawn_horde_at"):
		level.spawn_horde_at(center, 6, true)


func _end_skirmish(reason: String) -> void:
	if not _skirmish_active:
		return
	_skirmish_active = false
	var winner := _skirmish_pair[0] if _rng.randf() < 0.5 else _skirmish_pair[1]
	if _skirmish_pair.size() > 0:
		EventBus.faction_skirmish_ended.emit(_player_position(), winner)
		# The loser pulls back, the winner digs in: both get slightly hotter.
		for faction_id in _skirmish_pair:
			FactionManager.add_hostility(faction_id, 0.02)
	_skirmish_pair.clear()
	if reason == "timeout":
		EventBus.notify.emit("交火结束 · 街区暂时安静")


# ------------------------------------------------------------ archive link ----
func _scan_archive_pressure() -> void:
	var security := ArchiveManager.highest_security_level_collected()
	if security == _last_security:
		return
	_last_security = security
	if security >= 2:
		EventBus.level_event.emit("地平线安保巡逻频率上升")
	if security >= 3:
		EventBus.level_event.emit("证据销毁小队已出动")
		# Send a destroyer straight at the nearest uncollected fragment.
		if level.has_method("nearest_archive_position"):
			var pos: Vector2 = level.nearest_archive_position(_player_position())
			if pos != Vector2.ZERO:
				level.spawn_faction_unit("horizon", "evidence_destroyer", pos + Vector2(-260.0, 0.0))
	if security >= 4:
		EventBus.level_event.emit("信号核心防御协议 · 全部单位进入猎杀状态")
		for faction_id in ["horizon", "signal_bureau"]:
			FactionManager.add_hostility(faction_id, 0.15)


func set_skirmish_enabled(value: bool) -> void:
	enabled = value
