extends Node
## DirectorSystem - reads run statistics and emits spawn requests. It owns no
## level nodes; LevelRunner executes every request. One tick per second.

var intensity: float = 0.15
var active: bool = false
var boss_active: bool = false
var safe_room: bool = false
var horde_active: bool = false

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
	_special_timer = randf_range(18.0, 28.0) * _difficulty_mult
	_rest_timer = 3.0
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
	# Intensity model from the design spec.
	intensity += 0.02
	intensity += 0.10 * float(_hits_this_second)
	if _rest_timer > 0.0:
		_rest_timer -= 1.0
		intensity -= 0.15
	if safe_room:
		intensity -= 0.05
	intensity = clampf(intensity, 0.0, 1.0)
	_hits_this_second = 0
	EventBus.director_intensity_changed.emit(intensity)
	AudioManager.set_intensity(intensity)

	if boss_active or safe_room or horde_active:
		return

	# Horde probability table.
	if intensity >= 0.30 and _rest_timer <= 0.0:
		var chance := 0.0
		if intensity < 0.60:
			chance = 0.08
		elif intensity < 0.85:
			chance = 0.15
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
				_rest_timer = 8.0

	# Director 2.0: 玩家状态驱动的动态事件。
	# 血量过低时刷精英敌人施压，状态良好时刷尸潮考验输出。
	var player := get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player) and not horde_active and not boss_active:
		var hp_val: Variant = player.get("hp")
		var max_hp_val: Variant = player.get("max_hp")
		var hp_pct: float = 1.0
		if hp_val != null and max_hp_val != null:
			hp_pct = float(hp_val) / maxf(1.0, float(max_hp_val))
		var ammo_pct: float = 1.0
		var weapon: Variant = player.get("current_weapon")
		if weapon != null:
			var ammo_state: Variant = player.get("ammo")
			if ammo_state is Dictionary:
				var wid_val: Variant = weapon.get("id")
				var wid: StringName = StringName(wid_val) if wid_val != null else &""
				var st: Variant = ammo_state.get(wid)
				if st == null:
					st = {}
				var mag_val: Variant = st.get("mag")
				var mag: int = int(mag_val) if mag_val != null else 0
				var mag_size_val: Variant = weapon.get("mag_size")
				var mag_size: int = int(mag_size_val) if mag_size_val != null else 30
				ammo_pct = float(mag) / maxf(1.0, float(mag_size))
		if hp_pct < 0.30 and _rest_timer <= 0.0 and randf() < 0.06:
			# 濒死施压: 刷精英特感。
			EventBus.director_request_special.emit([&"tank", &"charger", &"smoker"].pick_random())
			_rest_timer = 10.0
			intensity = clampf(intensity + 0.15, 0.0, 1.0)
		elif hp_pct > 0.80 and ammo_pct > 0.50 and _rest_timer <= 0.0 and randf() < 0.04:
			# 状态良好: 刷小型尸潮考验输出。
			EventBus.director_request_horde.emit(randi_range(10, 16))
			_rest_timer = 6.0

	# Special infected timer.
	if intensity >= 0.30:
		_special_timer -= 1.0
		if _special_timer <= 0.0:
			var kind := _pick_special()
			if kind != &"":
				EventBus.director_request_special.emit(kind)
			var base := 25.0
			var variance := 8.0
			if intensity < 0.30:
				base = 32.0
				variance = 10.0
			elif intensity >= 0.85:
				base = 12.0
				variance = 4.0
			elif intensity >= 0.60:
				base = 18.0
				variance = 6.0
			_special_timer = maxf(6.0, randf_range(base - variance, base + variance) * _difficulty_mult / _density)
	else:
		_special_timer = minf(_special_timer, 32.0 * _difficulty_mult)


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
	_rest_timer = 8.0
	intensity = maxf(0.0, intensity - 0.10)


func _on_boss_spawned(_kind: StringName) -> void:
	set_boss_active(true)


func _on_boss_killed(_kind: StringName) -> void:
	set_boss_active(false)
