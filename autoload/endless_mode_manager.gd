extends Node
## EndlessModeManager - 无尽尸潮模式管理器。

var is_active = false
var current_wave = 0
var wave_timer = 0.0
var wave_interval = 15.0
var enemies_remaining = 0
var enemies_spawned = 0
var wave_kills = 0
var total_kills = 0
var difficulty_mult = 1.0
var wave_active = false

signal wave_started
signal wave_completed
signal boss_wave
signal game_over
signal wave_info

const BOSS_WAVE_INTERVAL = 5
const BASE_ENEMIES_PER_WAVE = 10
const BASE_ENEMY_HP = 30

const CHALLENGE_MODIFIERS = {}

func _ready():
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.enemy_killed.connect(_on_enemy_killed)

func start_endless_mode(seed = 0):
	is_active = true
	current_wave = 0
	total_kills = 0
	difficulty_mult = 1.0
	wave_active = false
	_next_wave()
	EventBus.level_event.emit("无尽模式开始")

func _next_wave():
	current_wave += 1
	wave_active = false
	enemies_remaining = 0
	enemies_spawned = 0
	wave_kills = 0

	difficulty_mult = 1.0 + (float(current_wave - 1) * 0.15)

	var is_boss_wave = (current_wave % BOSS_WAVE_INTERVAL == 0)

	if is_boss_wave:
		EventBus.boss_wave.emit(current_wave)
		EventBus.wave_info.emit("第 " + str(current_wave) + " 波：Boss 来袭！")
		_enemies_for_wave(int(BASE_ENEMIES_PER_WAVE / 2), true)
	else:
		var enemy_count = int(BASE_ENEMIES_PER_WAVE * difficulty_mult)
		_enemies_for_wave(enemy_count, false)

	wave_active = true
	EventBus.wave_started.emit(current_wave)
	EventBus.wave_info.emit("第 " + str(current_wave) + " 波开始")

func _enemies_for_wave(count, is_boss_wave):
	enemies_remaining = count
	enemies_spawned = 0
	EventBus.director_request_horde.emit(count)
	if is_boss_wave:
		EventBus.director_request_boss.emit()

func _on_level_completed(_score, _rank):
	if is_active:
		_endless_game_over()

func _on_enemy_killed(_kind, _source, _pos):
	if is_active and _source == &"player":
		register_kill()

func _endless_game_over():
	is_active = false
	EventBus.game_over.emit(current_wave, total_kills)
	EventBus.level_event.emit("无尽模式结束：存活 " + str(current_wave) + " 波，击杀 " + str(total_kills))

func register_kill():
	if is_active:
		wave_kills += 1
		total_kills += 1
		enemies_remaining = maxi(0, enemies_remaining - 1)
		if enemies_remaining <= 0 and wave_active:
			_wave_completed()

func _wave_completed():
	wave_active = false
	EventBus.wave_completed.emit(current_wave)
	EventBus.wave_info.emit("第 " + str(current_wave) + " 波完成")
	wave_timer = 5.0

func _process(delta):
	if not is_active or not wave_active:
		return
	if wave_timer > 0.0:
		wave_timer -= delta
		if wave_timer <= 0.0:
			_next_wave()

func get_wave():
	return current_wave

func get_total_kills():
	return total_kills

func get_difficulty_mult():
	return difficulty_mult

func apply_challenge_modifier(modifier_id):
	pass

func get_challenge_effect(modifier_id, default = 1.0):
	return default

func is_endless_active():
	return is_active
