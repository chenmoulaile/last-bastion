extends Node
## AudioManager - four-layer adaptive music, pooled SFX and 2D positional audio.
## Every file is original, procedurally synthesized (see tools/gen_audio.py).

const BUSES := ["Music", "SFX", "Ambience", "Voice"]
const MUSIC_LAYERS := ["calm", "combat", "horde", "tank"]
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"

# --- Sidechain compression (ducking) ---
# The Music bus has a compressor that sidechains from the SFX bus, so gunshots
# and explosions automatically pull down the music volume with a fast attack
# and musical release.
var _duck_target: float = 0.0
var _duck_current: float = 0.0
var _duck_speed: float = 1.0
var _duck_active: bool = false
var _duck_tween: Tween = null

# --- Reverb ---
# Underground/subway areas switch the Ambience bus to a cathedral-style reverb.
var _reverb_active: bool = false
var _reverb: AudioEffectReverb = null
var _reverb_bus_index: int = -1

var _layers: Dictionary = {}
var _layer_tweens: Dictionary = {}
var _menu_player: AudioStreamPlayer
var _result_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx2d_players: Array[AudioStreamPlayer2D] = []
var _voice_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _sfx2d_index: int = 0
var _voice_index: int = 0
var _variants: Dictionary = {}
var _streams: Dictionary = {}
var _theme: String = ""
var _intensity: float = 0.0
var _tank_active: bool = false
var _music_started: bool = false

## 1.7 GHz narrow-band signal noise: generated at runtime so the "someone is
## transmitting" layer can follow archive progression without new assets.
const SIGNAL_FREQ := 1700.0
const SIGNAL_MIX_RATE := 22050.0
var _signal_player: AudioStreamPlayer
var _signal_playback: AudioStreamGeneratorPlayback
var _signal_phase: float = 0.0
var _signal_level: float = 0.0
var _signal_pulse: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_scan_sfx()
	for layer in MUSIC_LAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80.0
		add_child(player)
		_layers[layer] = player
	_menu_player = _make_music_player()
	_result_player = _make_music_player()
	_ambience_player = _make_music_player("Ambience")
	for i in 28:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	for i in 14:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = 900.0
		p2.attenuation = 1.4
		add_child(p2)
		_sfx2d_players.append(p2)
	for i in 8:
		var v := AudioStreamPlayer.new()
		v.bus = "Voice"
		add_child(v)
		_voice_players.append(v)


func _make_music_player(bus: String = "Music") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	# Reverb effect on Ambience bus (wet/dry controlled dynamically)
	var ambience_idx := AudioServer.get_bus_index("Ambience")
	if ambience_idx >= 0:
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.10
		_reverb.damping = 0.9
		_reverb.wet = 0.0
		_reverb.dry = 1.0
		_reverb_bus_index = ambience_idx
		if AudioServer.get_bus_effect_count(ambience_idx) == 0:
			AudioServer.add_bus_effect(ambience_idx, _reverb)


func _scan_sfx() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	for dir_file in dir.get_files():
		var clean := dir_file.trim_suffix(".import").trim_suffix(".remap")
		if not (clean.ends_with(".ogg") or clean.ends_with(".wav")):
			continue
		var base := clean.get_basename()
		var stream: AudioStream = load(SFX_DIR + clean)
		if stream == null:
			continue
		_streams[base] = stream
		var key := base
		var pieces := base.split("_")
		if pieces.size() > 1 and pieces[pieces.size() - 1].is_valid_int():
			key = "_".join(pieces.slice(0, pieces.size() - 1))
		if not _variants.has(key):
			_variants[key] = []
		_variants[key].append(stream)
	print("[Audio] sfx streams=%d variants=%d" % [_streams.size(), _variants.size()])


func play_level_music(theme: String) -> void:
	_theme = theme
	_tank_active = false
	_intensity = 0.0
	_music_started = true
	_menu_player.stop()
	_result_player.stop()
	for layer in MUSIC_LAYERS:
		var player: AudioStreamPlayer = _layers[layer]
		var path: String = MUSIC_DIR + theme + "_" + String(layer) + ".ogg"
		if not ResourceLoader.exists(path):
			path = MUSIC_DIR + "generic_" + layer + ".ogg"
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			stream = load(path)
		if stream == null:
			player.stop()
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
		player.volume_db = 0.0 if layer == "calm" else -80.0
		player.play()
	_fade_layer("combat", -60.0, 2.0)
	_fade_layer("horde", -60.0, 2.0)
	_fade_layer("tank", -60.0, 2.0)


func play_menu_music() -> void:
	_music_started = false
	for layer in MUSIC_LAYERS:
		var p: AudioStreamPlayer = _layers[layer]
		p.stop()
	_result_player.stop()
	var stream := _load_stream(MUSIC_DIR + "menu.ogg")
	if stream:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_menu_player.stream = stream
		_menu_player.volume_db = -6.0
		_menu_player.play()


func play_result_sting(rank: String) -> void:
	for layer in MUSIC_LAYERS:
		(_layers[layer] as AudioStreamPlayer).stop()
	_menu_player.stop()
	var candidates := [MUSIC_DIR + "result_" + rank.to_lower() + ".ogg", MUSIC_DIR + "result.ogg", MUSIC_DIR + "menu.ogg"]
	for path in candidates:
		var stream := _load_stream(path)
		if stream:
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = false
			_result_player.stream = stream
			_result_player.volume_db = -3.0
			_result_player.play()
			return


func stop_level_music() -> void:
	for layer in MUSIC_LAYERS:
		(_layers[layer] as AudioStreamPlayer).stop()
	_music_started = false


func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if not _music_started or _tank_active:
		return
	_fade_layer("calm", 0.0, 1.5)
	_fade_layer("combat", 0.0 if _intensity >= 0.30 else -60.0, 1.5)
	_fade_layer("horde", 0.0 if _intensity > 0.60 else -60.0, 1.5)
	_fade_layer("tank", -60.0, 1.5)


func set_tank_active(active: bool) -> void:
	_tank_active = active
	if not _music_started:
		return
	if active:
		_fade_layer("tank", 0.0, 0.4)
		_fade_layer("calm", -60.0, 0.4)
		_fade_layer("combat", -60.0, 0.4)
		_fade_layer("horde", -60.0, 0.4)
	else:
		set_intensity(_intensity)


func _fade_layer(layer: String, db: float, seconds: float) -> void:
	var player: AudioStreamPlayer = _layers.get(layer, null)
	if player == null:
		return
	if _layer_tweens.has(layer):
		var old: Tween = _layer_tweens[layer]
		if old and old.is_valid():
			old.kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", db, seconds)
	_layer_tweens[layer] = tween


func _load_stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		_streams[path] = stream
		return stream
	return null


func play_sfx(id: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _pick(id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.volume_db = volume_db
	player.play()


func play_sfx_2d(id: StringName, pos: Vector2, max_dist: float = 900.0, volume_db: float = 0.0) -> void:
	var stream := _pick(id)
	if stream == null:
		return
	var player: AudioStreamPlayer2D = _sfx2d_players[_sfx2d_index]
	_sfx2d_index = (_sfx2d_index + 1) % _sfx2d_players.size()
	player.stream = stream
	player.global_position = pos
	player.max_distance = max_dist
	player.pitch_scale = randf_range(0.94, 1.06)
	player.volume_db = volume_db
	player.play()


func play_voice(id: StringName) -> void:
	var stream := _pick(id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _voice_players[_voice_index]
	_voice_index = (_voice_index + 1) % _voice_players.size()
	player.stream = stream
	player.pitch_scale = randf_range(0.92, 1.08)
	player.volume_db = -2.0
	player.play()


func play_ambience(id: StringName) -> void:
	var stream := _load_stream(SFX_DIR + "ambience_" + String(id) + ".ogg")
	if stream == null:
		_ambience_player.stop()
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambience_player.stream = stream
	_ambience_player.volume_db = -12.0
	_ambience_player.play()


func _pick(id: StringName) -> AudioStream:
	var key := String(id)
	if _variants.has(key):
		var list: Array = _variants[key]
		if not list.is_empty():
			return list.pick_random()
	if _streams.has(key):
		return _streams[key]
	return null


# ------------------------------------------------------- signal noise layer ----
## 0..1 archive pressure -> volume + pulse rate. Called by ArchiveManager.
func set_signal_noise(level: float) -> void:
	_signal_level = clampf(level, 0.0, 1.0)
	if _signal_player == null:
		_build_signal_player()
	if _signal_player == null:
		return
	var target_db := -42.0 + _signal_level * 24.0
	_signal_player.volume_db = target_db
	if not _signal_player.playing and _signal_level > 0.01:
		_signal_player.play()
		_signal_playback = _signal_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _build_signal_player() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SIGNAL_MIX_RATE
	generator.buffer_length = 0.25
	_signal_player = AudioStreamPlayer.new()
	_signal_player.stream = generator
	_signal_player.bus = "Ambience"
	_signal_player.volume_db = -42.0
	add_child(_signal_player)
	_signal_playback = null


func _process(delta: float) -> void:
	if _signal_playback == null or _signal_player == null or not _signal_player.playing:
		return
	var frames := _signal_playback.get_frames_available()
	if frames <= 0:
		return
	# Higher archive levels make the pulse audible as a rhythm, not just hiss.
	var pulse_rate := 0.6 + _signal_level * 2.2
	_signal_pulse += delta * pulse_rate
	var pulse := 0.45 + 0.55 * maxf(0.0, sin(_signal_pulse * TAU))
	var amp := 0.06 + _signal_level * 0.12
	var step := TAU * SIGNAL_FREQ / SIGNAL_MIX_RATE
	for i in frames:
		_signal_phase = fmod(_signal_phase + step, TAU)
		var tone := sin(_signal_phase) * 0.35
		var noise := randf_range(-1.0, 1.0) * 0.65
		var sample := (tone + noise) * amp * pulse
		_signal_playback.push_frame(Vector2(sample, sample * 0.92))

	# --- sidechain ducking for music ---
	if _duck_active:
		_duck_current = move_toward(_duck_current, _duck_target, _duck_speed * delta)
		_apply_duck()
		if _duck_current <= 0.001 and _duck_target <= 0.0:
			_duck_active = false


# -------------------------------------------------- sidechain ducking ----
## Duck the Music bus volume when a loud transient (gunshot, explosion)
## fires. This simulates sidechain compression: the music gets out of the
## way for the SFX, then smoothly returns.
func duck_music(amount_db: float = 16.0, duration: float = 0.35) -> void:
	if not _music_started:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_target = amount_db
	_duck_current = 0.0
	_duck_speed = amount_db / 0.05  # fast attack, 50ms
	_duck_active = true
	_apply_duck()
	_duck_tween = create_tween()
	_duck_tween.tween_callback(func() -> void:
		_duck_speed = amount_db / duration
		_duck_target = 0.0
		_duck_active = true
	).set_delay(0.06)


func _apply_duck() -> void:
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx < 0:
		return
	var db := -_duck_current  # negative means quieter
	for layer in MUSIC_LAYERS:
		var player: AudioStreamPlayer = _layers.get(layer, null)
		if player != null and player.is_playing():
			player.volume_db = db
	if _menu_player.playing:
		_menu_player.volume_db = db
	if _result_player.playing:
		_result_player.volume_db = db


# -------------------------------------------------- reverb ----
## Toggle reverb on the Ambience and SFX buses for enclosed/underground spaces.
func set_reverb(enabled: bool, room_size: float = 0.55, damp: float = 0.7) -> void:
	if _reverb == null:
		return
	_reverb_active = enabled
	if enabled:
		_reverb.room_size = room_size
		_reverb.damping = damp
		_reverb.wet = 0.35
		_reverb.dry = 0.8
	else:
		_reverb.room_size = 0.10
		_reverb.damping = 0.9
		_reverb.wet = 0.0
		_reverb.dry = 1.0
	# Also apply reverb to the SFX bus for spatial gunshots/footsteps
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		for i in AudioServer.get_bus_effect_count(sfx_idx):
			var effect := AudioServer.get_bus_effect(sfx_idx, i)
			if effect is AudioEffectReverb:
				if enabled:
					effect.room_size = room_size * 0.7
					effect.damping = damp
					effect.wet = 0.22
					effect.dry = 0.9
				else:
					effect.wet = 0.0
					effect.dry = 1.0


func set_ambience_reverb_for_theme(theme: String) -> void:
	match theme:
		"subway", "underground", "sewers":
			set_reverb(true, 0.72, 0.65)
		"military", "bunker":
			set_reverb(true, 0.55, 0.5)
		_:
			set_reverb(false)
