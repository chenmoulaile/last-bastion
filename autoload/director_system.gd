extends Node
## DirectorSystem - reads run statistics and emits spawn requests. It owns no
## level nodes; LevelRunner executes every request. One tick per second.
##
## wp5-zombie-pacing-buff 节奏改写：目标 = 大部分游玩时间（约 75-85%）场上维持
## 僵尸压力，只留小段空窗喘息。三个抓手：
##   1. min_alive 涓流——场上普通僵尸低于目标时，每 4-6s 投一小波（3-10 只、
##      游荡态、不走 horde_started 通路故不弹「尸潮来袭」横幅），维持最低数量；
##   2. 主动休止——每 60-90s 请求一次喘息，等场上普通僵尸 ≤2 才启动，持续
##      10-18s（期间涓流/大潮/特感全部冻结），保证空窗 ≤25s；
##   3. 压短间隔——intensity 重建 0.02→0.05/s、潮概率三档上调、潮后强制休息
##      8s→3s、特感基础间隔压短且移出「潮进行中」gate（原实现潮不清完连
##      特感都不刷，加剧空街）。
## 尸潮/特感事件与 _in_interior 投放改投（LevelRunner 侧）逻辑原样保留。

var intensity: float = 0.15
var active: bool = false
var boss_active: bool = false
var safe_room: bool = false
var horde_active: bool = false

# wp5：场上最低普通僵尸数（min_alive），按难度抬升。
const TRICKLE_MIN_ALIVE := {&"NORMAL": 10, &"HARD": 13, &"EXPERT": 15}
# wp5：涓流投放间隔（秒）；单次投放量 = target - alive + randi(1,3)，clamp [3,10]。
const TRICKLE_CD := Vector2(4.0, 6.0)
# wp5：主动休止周期 / 持续 / 启动阈值（场上普通僵尸 ≤2 才启动，避免打断战斗）。
const DOWNTIME_EVERY := Vector2(60.0, 90.0)
const DOWNTIME_LEN := Vector2(10.0, 18.0)
const DOWNTIME_TRIGGER_ALIVE := 2
# wp5：休止请求最多挂起 45s（期间场上一直压着大波僵尸则放弃本次）。
const DOWNTIME_PENDING_MAX := 45.0

var _tick_accum: float = 0.0
var _special_timer: float = 25.0
var _rest_timer: float = 0.0
var _hits_this_second: int = 0
var _party_avg_hp: float = 1.0
var _party_avg_ammo: float = 1.0
var _player_x: float = 0.0
var _supply_medkit_given: bool = false
var _supply_ammo_given: bool = false
var _supply_timer: float = 0.0

# wp5：涓流与休止状态。
var _min_alive: int = 10
var _trickle_cd: float = 0.0
var _downtime_cd: float = 0.0
var _downtime_left: float = 0.0
var _downtime_pending: bool = false
var _downtime_pending_for: float = 0.0

var _weights: Dictionary = {}
var _density: float = 1.0
var _difficulty_mult: float = 1.0
var _level_id: StringName = &""


func _ready() -> void:
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.safe_room_entered.connect(_on_safe_room)
	EventBus.horde_started.connect(_on_horde_started)
	EventBus.horde_ended.connect(_on_horde_ended)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_killed.connect(_on_boss_killed)
	set_process(true)


func begin_level(level: LevelData, difficulty: StringName) -> void:
	reset()
	active = true
	_level_id = level.id
	_weights = level.special_weights.duplicate()
	_density = maxf(0.1, level.special_density)
	var diff: Dictionary = GameManager.DIFFICULTY.get(difficulty, GameManager.DIFFICULTY[&"NORMAL"])
	_difficulty_mult = float(diff["special_interval"])
	_min_alive = int(TRICKLE_MIN_ALIVE.get(difficulty, TRICKLE_MIN_ALIVE[&"NORMAL"]))
	_special_timer = randf_range(18.0, 28.0) * _difficulty_mult
	_rest_timer = 3.0
	_trickle_cd = 5.0
	_downtime_cd = randf_range(DOWNTIME_EVERY.x, DOWNTIME_EVERY.y)
	_downtime_left = 0.0
	_downtime_pending = false
	_downtime_pending_for = 0.0
	intensity = 0.15
	EventBus.director_intensity_changed.emit(intensity)


func end_level() -> void:
	active = false
	horde_active = false
	boss_active = false
	intensity = 0.0
	set_process(false)


func reset() -> void:
	intensity = 0.15
	boss_active = false
	safe_room = false
	horde_active = false
	_tick_accum = 0.0
	_special_timer = 25.0
	_rest_timer = 0.0
	_hits_this_second = 0
	_party_avg_hp = 1.0
	_party_avg_ammo = 1.0
	_player_x = 0.0
	_supply_medkit_given = false
	_supply_ammo_given = false
	_supply_timer = 0.0
	_min_alive = int(TRICKLE_MIN_ALIVE[&"NORMAL"])
	_trickle_cd = 0.0
	_downtime_cd = 0.0
	_downtime_left = 0.0
	_downtime_pending = false
	_downtime_pending_for = 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_tick_accum += delta
	_supply_timer += delta
	if _tick_accum >= 1.0:
		_tick_accum -= 1.0
		_tick()
	if _supply_timer >= 2.0:
		_supply_timer = 0.0
		_check_supplies()


func _tick() -> void:
	# Intensity model from the design spec (wp5: 重建速度 0.02 -> 0.05/s，压短潮间重建期).
	intensity += 0.05
	intensity += 0.10 * float(_hits_this_second)
	if _rest_timer > 0.0:
		_rest_timer -= 1.0
		intensity -= 0.15
	if safe_room:
		intensity -= 0.05
	if _downtime_left > 0.0:
		intensity -= 0.10
	intensity = clampf(intensity, 0.0, 1.0)
	_hits_this_second = 0
	EventBus.director_intensity_changed.emit(intensity)
	AudioManager.set_intensity(intensity)

	if boss_active or safe_room:
		return

	var commons := _count_common_zombies()
	_tick_downtime(commons)

	# wp5：特感计时移出「潮进行中」gate——潮不清完连特感都不刷是空街成因之一；
	# 休止期内特感冻结（喘息）。
	if _downtime_left <= 0.0:
		_tick_specials()

	# 休止期 / 大潮进行中：不掷新潮、不涓流。
	if _downtime_left > 0.0 or horde_active:
		return

	# Horde probability table (wp5: 门槛 0.30->0.35，三档 0.08/0.15/1.0 -> 0.25/0.45/1.0).
	if intensity >= 0.35 and _rest_timer <= 0.0:
		var chance := 0.0
		if intensity < 0.60:
			chance = 0.25
		elif intensity < 0.85:
			chance = 0.45
		else:
			chance = 1.0
		if randf() < chance:
			var count := randi_range(14, 22)
			if intensity > 0.85:
				count = 30
			elif intensity >= 0.60:
				count = randi_range(20, 28)
			EventBus.director_request_horde.emit(count)
			if intensity > 0.85:
				_rest_timer = 3.0

	# wp5：min_alive 涓流——维持场上最低普通僵尸数。
	_tick_trickle(commons)


## wp5：场上存活普通僵尸数（不含特感/boss；与 LevelRunner._alive_common_count 同口径）。
func _count_common_zombies() -> int:
	var count := 0
	if get_tree() == null:
		return 0
	for node in get_tree().get_nodes_in_group("zombies"):
		if node == null or not is_instance_valid(node) or bool(node.get("dead")):
			continue
		var zd: ZombieData = node.get("data")
		if zd != null and not zd.is_special:
			count += 1
	return count


## wp5：涓流投放。走 LevelRunner._spawn_horde_around（不 emit horde_started，
## 不弹「尸潮来袭」横幅、不拉音乐强度）；alert=false 投成游荡态，怪从
## 玩家 ±260-620px 慢慢涌来；_in_interior 时该方法内部自动改投 _street_return。
func _tick_trickle(commons: int) -> void:
	_trickle_cd -= 1.0
	if _trickle_cd > 0.0:
		return
	if GameManager.state != GameManager.State.PLAYING:
		return
	var target := _min_alive + int(roundf(intensity * 6.0))
	if commons >= target:
		return
	var level := _find_level_runner()
	if level == null or not level.has_method("_spawn_horde_around"):
		return
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var count := clampi(target - commons + randi_range(1, 3), 3, 10)
	level.call("_spawn_horde_around", player.global_position, count, false)
	# 场上持续有压力，intensity 至少顶到中档，音乐/氛围与实况匹配。
	intensity = maxf(intensity, 0.45)
	_trickle_cd = randf_range(TRICKLE_CD.x, TRICKLE_CD.y)


## wp5：通过玩家节点祖先链找 LevelRunner（玩家由 LevelRunner 生成，必为其后代）。
func _find_level_runner() -> Node:
	if get_tree() == null:
		return null
	var node: Node = get_tree().get_first_node_in_group("player")
	while node != null:
		if node is LevelRunner:
			return node
		node = node.get_parent()
	return null


## wp5：主动休止。每 60-90s 请求一次；请求挂起，等场上普通僵尸 ≤2（自然空隙）
## 才启动 10-18s 喘息；挂起超 45s（场上一直压着大波）则放弃并重排周期。
func _tick_downtime(commons: int) -> void:
	if _downtime_left > 0.0:
		_downtime_left -= 1.0
		if _downtime_left <= 0.0:
			_downtime_left = 0.0
			_downtime_cd = randf_range(DOWNTIME_EVERY.x, DOWNTIME_EVERY.y)
			# 休止结束立刻让涓流接力补怪，避免休止后接一个长空窗。
			_trickle_cd = minf(_trickle_cd, 1.0)
		return
	if _downtime_pending:
		_downtime_pending_for += 1.0
		if _downtime_pending_for > DOWNTIME_PENDING_MAX:
			_downtime_pending = false
			_downtime_cd = randf_range(DOWNTIME_EVERY.x, DOWNTIME_EVERY.y)
		elif commons <= DOWNTIME_TRIGGER_ALIVE:
			_downtime_pending = false
			_downtime_left = randf_range(DOWNTIME_LEN.x, DOWNTIME_LEN.y)
			EventBus.notify.emit("四周暂时安静下来……稳住")
	else:
		_downtime_cd -= 1.0
		if _downtime_cd <= 0.0:
			_downtime_pending = true
			_downtime_pending_for = 0.0


## wp5：特感计时（从 _tick 内联段提为独立函数；基础间隔压短 25/18/12 -> 20/15/11）。
func _tick_specials() -> void:
	if intensity >= 0.30:
		_special_timer -= 1.0
		if _special_timer <= 0.0:
			var kind := _pick_special()
			if kind != &"":
				EventBus.director_request_special.emit(kind)
			var base := 20.0
			var variance := 7.0
			if intensity < 0.30:
				base = 30.0
				variance = 10.0
			elif intensity >= 0.85:
				base = 11.0
				variance = 4.0
			elif intensity >= 0.60:
				base = 15.0
				variance = 5.0
			_special_timer = maxf(6.0, randf_range(base - variance, base + variance) * _difficulty_mult / _density)
	else:
		_special_timer = minf(_special_timer, 30.0 * _difficulty_mult)


func _pick_special() -> StringName:
	if _weights.is_empty():
		return [&"hunter", &"smoker", &"boomer"].pick_random()
	var total := 0.0
	for key in _weights:
		total += float(_weights[key])
	if total <= 0.0:
		return &""
	var roll := randf() * total
	for key in _weights:
		roll -= float(_weights[key])
		if roll <= 0.0:
			return StringName(key)
	return StringName(_weights.keys().back())


func _check_supplies() -> void:
	if not active or safe_room or boss_active:
		return
	if _party_avg_hp < 0.45 and not _supply_medkit_given:
		_supply_medkit_given = true
		EventBus.director_request_supply.emit(&"medkit")
	elif _party_avg_hp >= 0.60:
		_supply_medkit_given = false
	if _party_avg_ammo < 0.20 and not _supply_ammo_given:
		_supply_ammo_given = true
		EventBus.director_request_supply.emit(&"ammo")
	elif _party_avg_ammo >= 0.40:
		_supply_ammo_given = false


func report_party(avg_hp: float, avg_ammo: float, player_x: float) -> void:
	_party_avg_hp = avg_hp
	_party_avg_ammo = avg_ammo
	_player_x = player_x


func set_boss_active(value: bool) -> void:
	boss_active = value
	if value:
		horde_active = false


func _on_player_hit(_amount: int) -> void:
	_hits_this_second += 1


func _on_safe_room(entered: bool) -> void:
	safe_room = entered


func _on_horde_started(_count: int) -> void:
	horde_active = true


func _on_horde_ended() -> void:
	horde_active = false
	_rest_timer = 3.0
	intensity = maxf(0.0, intensity - 0.10)
	# wp5：潮清完涓流立刻接力补怪，不留 30-50s 的长空街。
	_trickle_cd = 0.5


func _on_boss_spawned(_kind: StringName) -> void:
	set_boss_active(true)


func _on_boss_killed(_kind: StringName) -> void:
	set_boss_active(false)
