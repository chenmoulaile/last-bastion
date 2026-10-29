class_name ItemComponent
extends Node
## Shared throwable / medkit / pill logic for the legacy PlayerController and
## PlayerControllerV2. Extracted verbatim from scripts/player/player.gd; all
## timings, counts and heal fractions are the original values.

const MEDKIT_TIME: float = 4.0
const MEDKIT_HEAL_FRACTION: float = 0.8
const PILL_TEMP_HP: int = 50
const THROWABLE_KEYS: Array[String] = ["grenade", "molotov", "bile"]
const THROWABLE_NAMES: Dictionary = {
	"grenade": "手雷", "molotov": "燃烧瓶", "bile": "胆汁瓶",
}

var medkit_using: bool = false
var medkit_channel: float = 0.0
var last_throw_kind: String = ""

var _player: Node = null


func setup(player: Node) -> void:
	_player = player


func tick(delta: float) -> void:
	if medkit_using:
		medkit_channel -= delta
		if medkit_channel <= 0.0:
			finish_medkit()


# ------------------------------------------------------------------ throw ----
func throw_current() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var throwables: Dictionary = _player.get("throwables")
	var index := int(_player.get("throw_index"))
	index = posmod(index, THROWABLE_KEYS.size())
	var kind: String = THROWABLE_KEYS[index]
	if int(throwables.get(kind, 0)) <= 0:
		cycle_throwable()
		index = posmod(int(_player.get("throw_index")), THROWABLE_KEYS.size())
		kind = THROWABLE_KEYS[index]
		if int(throwables.get(kind, 0)) <= 0:
			EventBus.notify.emit("没有投掷物")
			return false
	var level: Variant = _player.get("level")
	if level == null or not (level as Node).has_method("spawn_throwable"):
		return false
	throwables[kind] = int(throwables[kind]) - 1
	_player.set("throwables", throwables)
	last_throw_kind = kind
	var facing := int(_player.get("facing"))
	var aim: Vector2 = _player.get("aim_dir")
	var origin: Vector2 = (_player as Node2D).global_position \
		+ Vector2(float(facing) * 10.0, -22.0)
	(level as Node).call("spawn_throwable", kind, origin, aim)
	AudioManager.play_sfx(&"throw")
	_emit_ammo_changed()
	return true


func cycle_throwable() -> int:
	if _player == null:
		return 0
	var index := posmod(int(_player.get("throw_index")) + 1, THROWABLE_KEYS.size())
	_player.set("throw_index", index)
	EventBus.notify.emit("投掷物：" + String(THROWABLE_NAMES[THROWABLE_KEYS[index]]))
	return index


# ----------------------------------------------------------------- medkit ----
func start_medkit() -> bool:
	if _player == null or bool(_player.get("is_dead")) or medkit_using:
		return false
	if int(_player.get("medkits")) <= 0:
		return false
	var black_white := bool(_player.get("black_white"))
	var hp := int(_player.get("hp"))
	var max_hp := int(_player.get("max_hp"))
	var temp_hp := int(_player.get("temp_hp"))
	if not black_white and hp >= max_hp and temp_hp >= PILL_TEMP_HP:
		return false
	medkit_using = true
	medkit_channel = MEDKIT_TIME
	AudioManager.play_sfx(&"medkit_use")
	return true


func finish_medkit() -> void:
	if _player == null:
		return
	medkit_using = false
	medkit_channel = 0.0
	_player.set("medkits", maxi(0, int(_player.get("medkits")) - 1))
	if bool(_player.get("black_white")):
		_player.set("black_white", false)
		var restored := _character_max_hp()
		if restored > 0:
			_player.set("max_hp", restored)
	var max_hp := int(_player.get("max_hp"))
	var hp := int(_player.get("hp"))
	var missing := maxi(0, max_hp - hp)
	var heal := int(ceil(float(missing) * MEDKIT_HEAL_FRACTION))
	_player.set("hp", mini(max_hp, hp + heal))
	_player.set("temp_hp", 0)
	EventBus.health_changed.emit(int(_player.get("hp")), 0, max_hp)
	EventBus.notify.emit("使用医疗包")
	AudioManager.play_sfx(&"heal")


func cancel_medkit() -> void:
	medkit_using = false
	medkit_channel = 0.0


# ------------------------------------------------------------------ pills ----
func use_pills() -> bool:
	if _player == null or bool(_player.get("is_dead")):
		return false
	if int(_player.get("pills")) <= 0:
		return false
	_player.set("pills", maxi(0, int(_player.get("pills")) - 1))
	_player.set("temp_hp", mini(100, int(_player.get("temp_hp")) + PILL_TEMP_HP))
	EventBus.health_changed.emit(int(_player.get("hp")), int(_player.get("temp_hp")),
		int(_player.get("max_hp")))
	AudioManager.play_sfx(&"pills")
	EventBus.notify.emit("使用药丸 +50 临时生命")
	return true


# ------------------------------------------------------------------ utils ----
func _character_max_hp() -> int:
	var character: Variant = _player.get("character")
	if character == null:
		return 0
	var value: Variant = character.get("max_health")
	if value == null:
		value = character.get("max_hp")
	return int(value) if value != null else 0


func _emit_ammo_changed() -> void:
	var weapon: Variant = null
	if _player.has_method("_current_weapon"):
		weapon = _player.call("_current_weapon")
	if weapon == null:
		EventBus.ammo_changed.emit(0, 0)
		return
	var wid: StringName = &""
	var id_value: Variant = weapon.get("id")
	if id_value != null:
		wid = StringName(id_value)
	var ammo: Variant = _player.get("ammo")
	var state: Dictionary = {"mag": 0, "reserve": 0}
	if ammo is Dictionary:
		state = (ammo as Dictionary).get(wid, state)
	EventBus.ammo_changed.emit(int(state.get("mag", 0)), int(state.get("reserve", 0)))
