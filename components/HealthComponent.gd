class_name HealthComponent
extends Node
## Damage-signal adapter attached to every damageable enemy.
##
## The legacy combat scripts own the actual health values. This component is a
## one-way observation point: it never changes damage, health, RPM or ammo. The
## game-feel bridge subscribes to `damaged` so every hit can spawn its own
## feedback even when several hits land in the same physics frame.
##
## The component is deliberately mounted by ZombieBase at runtime instead of
## editing every enemy scene. `last_source_id` keeps the legacy StringName
## source (&"player", &"barrel", &"fire", ...) while `source` carries the real
## node when one can be resolved.

signal damaged(amount: float, source: Node, hit_position: Vector2, is_critical: bool)
signal depleted(source: Node)

var last_source_id: StringName = &""
var last_hit_position: Vector2 = Vector2.ZERO
var last_is_critical: bool = false
var damage_event_count: int = 0

var _bridge: Node = null


func _ready() -> void:
	add_to_group("health_components")
	_bridge = get_node_or_null("/root/GameFeelBridge")
	if _bridge != null and _bridge.has_method("register_health_component"):
		_bridge.call("register_health_component", self)


func _exit_tree() -> void:
	if _bridge != null and is_instance_valid(_bridge) \
			and _bridge.has_method("unregister_health_component"):
		_bridge.call("unregister_health_component", self)
	_bridge = null


## Emits one event per successful hit. The return value mirrors the incoming
## amount so callers can keep using this as a pass-through adapter.
func take_damage(amount: float, source: Node, hit_position: Vector2,
		is_critical: bool) -> float:
	last_hit_position = hit_position
	last_is_critical = is_critical
	damage_event_count += 1
	damaged.emit(amount, source, hit_position, is_critical)
	return amount


## Called by ZombieBase immediately before/after the health subtraction so the
## adapter also keeps the original source enum for presentation filtering.
func note_source(source_id: StringName) -> void:
	last_source_id = source_id


func signal_depleted(source: Node) -> void:
	depleted.emit(source)
