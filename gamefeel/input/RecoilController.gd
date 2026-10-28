extends Node
## RecoilController - visual muzzle climb and reticle spread.
##
## Only the weapon Sprite2D offset is written. Aim direction, bullet spread and
## every combat value stay untouched, which keeps the module netcode-safe and
## purely cosmetic.
##
## Autoload: RecoilController

const RECOVERY_DEG_PER_SEC := 8.0
const SPREAD_MIN := 4.0
const SPREAD_MAX := 12.0
const SPREAD_RECOVERY := 26.0
const SPREAD_IDLE_DELAY := 0.30
const PIXELS_PER_DEGREE := 22.0

const DEGREES := {
	&"m9": 0.9,
	&"smg": 0.6,
	&"ar15": 0.8,
	&"shotgun": 3.0,
	&"lmg": 1.2,
	&"sniper": 2.5,
	&"katana": 0.8,
	&"axe": 1.2,
	&"chainsaw": 0.3,
	&"default": 0.8,
}

var recoil_degrees: float = 0.0
var spread_radius: float = SPREAD_MIN
var current_weapon: StringName = &""

var _player: Node = null
var _sprite: Sprite2D = null
var _base_offset: Vector2 = Vector2.ZERO
var _last_shot_usec: int = 0
var _retry_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 120
	EventBus.weapon_changed.connect(_on_weapon_changed)


func _process(delta: float) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"recoil"):
		if recoil_degrees != 0.0 or spread_radius != SPREAD_MIN:
			reset()
		return
	_acquire()
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var now := Time.get_ticks_usec()
	recoil_degrees = move_toward(recoil_degrees, 0.0, RECOVERY_DEG_PER_SEC * delta)
	if now - _last_shot_usec > int(SPREAD_IDLE_DELAY * 1_000_000.0):
		spread_radius = move_toward(spread_radius, SPREAD_MIN, SPREAD_RECOVERY * delta)
	var lift := tan(deg_to_rad(recoil_degrees)) * PIXELS_PER_DEGREE
	_sprite.offset = _base_offset + Vector2(0.0, -lift)


func kick(weapon_id: StringName) -> void:
	if not GameFeelConfig.enabled or not GameFeelConfig.is_module_enabled(&"recoil"):
		return
	if weapon_id != &"":
		current_weapon = weapon_id
	var profile: float = float(DEGREES.get(weapon_id, DEGREES[&"default"]))
	recoil_degrees = clampf(recoil_degrees + profile, 0.0, 7.0)
	spread_radius = clampf(spread_radius + profile * 2.1, SPREAD_MIN, SPREAD_MAX)
	_last_shot_usec = Time.get_ticks_usec()


func set_weapon(weapon_id: StringName) -> void:
	current_weapon = weapon_id


func spread_pixels() -> float:
	return spread_radius


func reset() -> void:
	recoil_degrees = 0.0
	spread_radius = SPREAD_MIN
	_last_shot_usec = 0
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.offset = _base_offset


func _on_weapon_changed(id: StringName, _display_name: String) -> void:
	current_weapon = id


func _acquire() -> void:
	if _player != null and is_instance_valid(_player):
		if _sprite != null and is_instance_valid(_sprite):
			return
	_sprite = null
	var now := Time.get_ticks_usec()
	if now - _retry_usec < 250_000:
		return
	_retry_usec = now
	_player = null
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node is Node and is_instance_valid(node):
			_player = node
			break
	if _player == null:
		return
	var candidate: Variant = _player.get("weapon_sprite")
	if candidate is Sprite2D:
		_sprite = candidate as Sprite2D
		_base_offset = _sprite.offset
