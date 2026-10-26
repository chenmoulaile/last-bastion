extends Node
## AudioManager - four-layer adaptive music, pooled SFX and 2D positional audio.
## Every file is original, procedurally synthesized (see tools/gen_audio.py).

const BUSES := ["Music", "SFX", "Ambience", "Voice"]
const MUSIC_LAYERS := ["calm", "combat", "horde", "tank"]
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"

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


func _scan_sfx() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		var clean := file_name
		if clean.ends_with(".import"):
			clean = clean.trim_suffix(".import")
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
