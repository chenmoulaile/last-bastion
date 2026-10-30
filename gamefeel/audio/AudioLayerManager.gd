extends Node
## AudioLayerManager - adds the missing low/tail layers, impact foley and
## reload rhythm on dedicated buses. The existing weapon sample is still played
## by AudioManager (the "body" layer), so no shot is doubled.
##
## Buses: SFX_Combat, SFX_UI, SFX_Ambient. All three route through the legacy
## SFX / Ambience buses, so the existing volume sliders keep working.
##
## Autoload: AudioLayerManager

const RATE := 22050
const COMBAT_VOICES := 12
const UI_VOICES := 6
const AMBIENT_VOICES := 6
const SPATIAL_DIR := "res://assets/audio/sfx/"

const BUS_COMBAT := "SFX_Combat"
const BUS_UI := "SFX_UI"
const BUS_AMBIENT := "SFX_Ambient"

var _combat: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _ambient: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer2D] = []
var _spatial_index: int = 0
var _combat_index: int = 0
var _ui_index: int = 0
var _ambient_index: int = 0
var _streams: Dictionary = {}
var _spatial_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_ensure_buses()
	_build_pool()
	_build_streams()


# ------------------------------------------------------------------ public ---
func play_shot_layer(weapon_id: StringName, heavy: bool, _target_kind: StringName = &"") -> void:
	if not _can_play():
		return
	var weight := SfxManifest.weapon_weight(weapon_id)
	var low: AudioStream = _streams.get(&"low_heavy" if heavy else &"low_light", null)
	var tail: AudioStream = _streams.get(&"tail_long" if weapon_id in [&"sniper", &"lmg", &"shotgun"] else &"tail_short", null)
	if low != null:
		_play(_combat, low, PitchRandomizer.vary(1.0 - weight * 0.10, 0.025), _scaled_db(-13.0 + weight * 5.0))
	if tail != null:
		_play(_combat, tail, PitchRandomizer.vary(1.0, 0.035), _scaled_db(-18.0 + weight * 2.0))


func play_impact(kind: StringName, crit: bool) -> void:
	if not _can_play():
		return
	var sound := SfxManifest.impact_sound(kind)
	var stream: AudioStream = _streams.get(sound, _streams.get(&"meat", null))
	if stream != null:
		var volume := -14.0
		if sound == &"metal":
			volume = -12.0
		elif sound == &"debris":
			volume = -20.0
		_play(_combat, stream, PitchRandomizer.vary(1.0, 0.06), _scaled_db(volume))
	if crit and _streams.has(&"crisp"):
		_play(_combat, _streams[&"crisp"], PitchRandomizer.vary(1.0, 0.03), _scaled_db(-9.0))


func play_kill(kind: StringName, crit: bool) -> void:
	if not _can_play():
		return
	if crit and _streams.has(&"crisp"):
		_play(_ui, _streams[&"crisp"], PitchRandomizer.vary(1.05, 0.02), _scaled_db(-12.0))
	if kind == &"special" or kind == &"boss":
		if _streams.has(&"metal"):
			_play(_ui, _streams[&"metal"], 0.85, _scaled_db(-14.0))


func play_player_impact() -> void:
	if not _can_play():
		return
	if _streams.has(&"meat"):
		_play(_combat, _streams[&"meat"], 0.82, _scaled_db(-8.0))


func play_explosion_layer() -> void:
	if not _can_play():
		return
	if _streams.has(&"boom"):
		_play(_combat, _streams[&"boom"], PitchRandomizer.vary(0.92, 0.04), _scaled_db(-6.0))


func play_spatial_sfx(id: StringName, pos: Vector2, max_dist: float = 900.0, volume_db: float = 0.0) -> void:
	var stream := _pick_spatial(id)
	if stream == null:
		AudioManager.play_sfx_2d(id, pos, max_dist, volume_db)
		return
	if not _can_play():
		AudioManager.play_sfx_2d(id, pos, max_dist, volume_db)
		return
	if _spatial.is_empty():
		AudioManager.play_sfx_2d(id, pos, max_dist, volume_db)
		return
	var player: AudioStreamPlayer2D = _spatial[_spatial_index]
	_spatial_index = (_spatial_index + 1) % _spatial.size()
	player.stream = stream
	player.global_position = pos
	player.max_distance = max_dist
	player.pitch_scale = randf_range(0.94, 1.06)
	player.volume_db = _scaled_db(volume_db)
	player.play()


func play_reload_sequence(weapon_id: StringName, reload_time: float, empty: bool) -> void:
	if not _can_play():
		return
	var total := clampf(reload_time, 0.30, 2.6)
	var first := minf(0.25, total * 0.30)
	var second := minf(0.50, total * 0.62)
	if empty and _streams.has(&"empty_click"):
		_play(_combat, _streams[&"empty_click"], 1.0, _scaled_db(-10.0))
	_schedule(_streams.get(&"reload_out", null), 0.0, weapon_id)
	_schedule(_streams.get(&"reload_in", null), first, weapon_id)
	_schedule(_streams.get(&"reload_bolt", null), second, weapon_id)


func play_streak(tier: int) -> void:
	if not _can_play():
		return
	var key := SfxManifest.streak_stream(tier)
	var stream: AudioStream = _streams.get(key, null)
	if stream != null:
		_play(_ui, stream, 1.0, _scaled_db(-5.0))


func play_heartbeat(intensity: float) -> void:
	if not _can_play() or GameFeelConfig.reduced_motion:
		return
	if _streams.has(&"heartbeat"):
		var volume := -20.0 + clampf(intensity, 0.0, 1.0) * 10.0
		_play(_ambient, _streams[&"heartbeat"], PitchRandomizer.vary(0.98, 0.02), _scaled_db(volume))


func has_bus(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) >= 0


func bus_names() -> Array[String]:
	return [BUS_COMBAT, BUS_UI, BUS_AMBIENT]


func pool_size() -> int:
	return _combat.size() + _ui.size() + _ambient.size()


func stream_count() -> int:
	return _streams.size()


# ------------------------------------------------------------------ internals -
func _can_play() -> bool:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"audio_layers"):
		return false
	return GameFeelConfig.audio_scale > 0.01


func _scaled_db(base: float) -> float:
	var scale := GameFeelConfig.audio_scale
	if scale <= 0.01:
		return -80.0
	return base + linear_to_db(scale)


func _play(pool: Array[AudioStreamPlayer], stream: AudioStream, pitch: float, volume_db: float) -> void:
	if stream == null or pool.is_empty():
		return
	var player: AudioStreamPlayer = pool[0]
	if pool == _combat:
		player = _combat[_combat_index]
		_combat_index = (_combat_index + 1) % _combat.size()
	elif pool == _ui:
		player = _ui[_ui_index]
		_ui_index = (_ui_index + 1) % _ui.size()
	else:
		player = _ambient[_ambient_index]
		_ambient_index = (_ambient_index + 1) % _ambient.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func _schedule(stream: AudioStream, delay: float, _weapon_id: StringName) -> void:
	if stream == null:
		return
	if delay <= 0.0:
		_play(_combat, stream, PitchRandomizer.vary(1.0, 0.04), _scaled_db(-19.0))
		return
	var timer := get_tree().create_timer(delay, true, false, true)
	timer.timeout.connect(func() -> void:
		if is_inside_tree() and _can_play():
			_play(_combat, stream, PitchRandomizer.vary(1.0, 0.04), _scaled_db(-19.0))
	)


func _ensure_buses() -> void:
	_ensure_bus(BUS_COMBAT, "SFX")
	_ensure_bus(BUS_UI, "SFX")
	_ensure_bus(BUS_AMBIENT, "Ambience")
	var index := AudioServer.get_bus_index(BUS_COMBAT)
	if index >= 0 and AudioServer.get_bus_effect_count(index) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.22
		reverb.damping = 0.72
		reverb.wet = 0.10
		reverb.dry = 1.0
		AudioServer.add_bus_effect(index, reverb)


func _ensure_bus(bus_name: String, send_to: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	var target := send_to
	if AudioServer.get_bus_index(target) == -1:
		target = "Master"
	AudioServer.set_bus_send(index, target)


func _build_pool() -> void:
	for i in COMBAT_VOICES:
		_combat.append(_make_player(BUS_COMBAT))
	for i in UI_VOICES:
		_ui.append(_make_player(BUS_UI))
	for i in AMBIENT_VOICES:
		_ambient.append(_make_player(BUS_AMBIENT))
	for i in 8:
		_spatial.append(_make_spatial_player(BUS_COMBAT))


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	return player


func _make_spatial_player(bus_name: String) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.bus = bus_name
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.attenuation = 1.0
	player.unit_size = 160.0
	add_child(player)
	return player


func _pick_spatial(id: StringName) -> AudioStream:
	if _spatial_cache.has(id):
		return _spatial_cache[id] as AudioStream
	var path := SPATIAL_DIR + String(id) + ".ogg"
	if ResourceLoader.exists(path):
		var stream: AudioStream = ResourceLoader.load(path)
		_spatial_cache[id] = stream
		return stream
	return null


# ----------------------------------------------------------- sound synthesis --
func _build_streams() -> void:
	_streams[&"low_light"] = _tone(0.075, 150.0, 82.0, 2.4, 0.10, 0.72)
	_streams[&"low_heavy"] = _tone(0.115, 110.0, 52.0, 2.0, 0.16, 0.92)
	_streams[&"tail_short"] = _noise(0.16, 900.0, 2.6, 0.38, 0.16)
	_streams[&"tail_long"] = _noise(0.28, 620.0, 2.0, 0.42, 0.20)
	_streams[&"meat"] = _tone(0.10, 120.0, 54.0, 2.8, 0.34, 0.70)
	_streams[&"squish"] = _noise(0.14, 380.0, 2.2, 0.55, 0.18)
	_streams[&"metal"] = _tone(0.22, 1850.0, 1560.0, 3.2, 0.08, 0.46)
	_streams[&"crisp"] = _tone(0.055, 1750.0, 2400.0, 3.0, 0.20, 0.34)
	_streams[&"debris"] = _noise(0.12, 1450.0, 3.0, 0.42, 0.14)
	_streams[&"reload_out"] = _noise(0.045, 620.0, 4.0, 0.65, 0.20)
	_streams[&"reload_in"] = _noise(0.060, 380.0, 3.6, 0.70, 0.24)
	_streams[&"reload_bolt"] = _tone(0.070, 880.0, 540.0, 3.4, 0.30, 0.26)
	_streams[&"empty_click"] = _noise(0.035, 1200.0, 4.0, 0.55, 0.26)
	_streams[&"heartbeat"] = _tone(0.18, 62.0, 44.0, 1.7, 0.04, 0.90)
	_streams[&"boom"] = _tone(0.38, 78.0, 32.0, 1.4, 0.42, 0.95)
	_streams[&"streak_3"] = _sweep(0.18, 600.0, 900.0, 0.30)
	_streams[&"streak_5"] = _sweep(0.24, 720.0, 1180.0, 0.32)
	_streams[&"streak_10"] = _sweep(0.36, 520.0, 1600.0, 0.36)


func _tone(duration: float, freq_start: float, freq_end: float, decay: float,
		noise_amount: float, gain: float) -> AudioStreamWAV:
	var count := maxi(1, int(duration * RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var progress := clampf(t / duration, 0.0, 1.0)
		var freq := lerpf(freq_start, freq_end, progress)
		phase += TAU * freq / float(RATE)
		var envelope := pow(maxf(0.0, 1.0 - progress), decay)
		var sample := (sin(phase) * (1.0 - noise_amount) + _rng.randf_range(-1.0, 1.0) * noise_amount) * envelope * gain
		_write_sample(data, i, sample)
	return _wav(data)


func _noise(duration: float, cutoff: float, decay: float, gain: float,
		low_mix: float) -> AudioStreamWAV:
	var count := maxi(1, int(duration * RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var coefficient := clampf(cutoff / float(RATE), 0.02, 0.85)
	for i in count:
		var progress := clampf(float(i) / float(count), 0.0, 1.0)
		var envelope := pow(maxf(0.0, 1.0 - progress), decay)
		var white := _rng.randf_range(-1.0, 1.0)
		low += (white - low) * coefficient
		var sample := (white * (1.0 - low_mix) + low * low_mix) * envelope * gain
		_write_sample(data, i, sample)
	return _wav(data)


func _sweep(duration: float, freq_start: float, freq_end: float, gain: float) -> AudioStreamWAV:
	var count := maxi(1, int(duration * RATE))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var progress := clampf(float(i) / float(count), 0.0, 1.0)
		var freq := lerpf(freq_start, freq_end, progress * progress)
		phase += TAU * freq / float(RATE)
		var envelope := sin(progress * PI)
		var sample := (sin(phase) * 0.8 + sin(phase * 2.0) * 0.2) * envelope * gain
		_write_sample(data, i, sample)
	return _wav(data)


func _write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
	data[index * 2] = value & 0xFF
	data[index * 2 + 1] = (value >> 8) & 0xFF


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
