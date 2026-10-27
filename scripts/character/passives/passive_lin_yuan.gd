class_name PassiveLinYuan
extends PassiveAbility
## 林远 —「山猫步」
##
## * 潜行不减速：由 CharacterData.stealth_speed_multiplier = 1.0 驱动，
##   这里再写一次是为了让被动脚本自身可独立验证。
## * 背后处决不惊动房间：把尸体从其他感染者的感知里临时摘掉，并把周围
##   的“噪音传播”静音 3 秒。
## * 处决后 3 秒内 visibility = 0，感染者完全看不见他。

const INVISIBLE_TIME := 3.0
const QUIET_RADIUS := 420.0


func _on_activate() -> void:
	if player == null:
		return
	player.set("stealth_speed_multiplier", 1.0)
	player.connect(&"silent_execution", _on_silent_execution)


func _on_deactivate() -> void:
	if player != null and is_instance_valid(player) \
			and player.is_connected(&"silent_execution", _on_silent_execution):
		player.disconnect(&"silent_execution", _on_silent_execution)


func _on_silent_execution(victim: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var at: Vector2 = player.global_position
	if victim != null and is_instance_valid(victim):
		at = victim.global_position
		# The body itself stops existing for the hive for a moment.
		EnemyPerception.ignore_source(victim, INVISIBLE_TIME)
	EnemyPerception.suppress_noise(at, QUIET_RADIUS, INVISIBLE_TIME)
	EnemyPerception.ignore_source(player, INVISIBLE_TIME)
	if player.has_method("set_stealth_invisible"):
		player.set_stealth_invisible(INVISIBLE_TIME)
	EventBus.notify.emit("无声处决")
	DialogueManager.play_bark("lin_yuan", "execute")
