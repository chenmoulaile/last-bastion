class_name PassiveMarcus
extends PassiveAbility
## 马库斯 —「老兵直觉」
##
## 背后 120° 扇形内受到的伤害被完全格挡，冷却 30 秒。
## 几何判定放在 PlayerController.take_damage() 里（伤害结算的唯一入口），
## 这个脚本只负责打开开关、接管冷却与反馈。

func _on_activate() -> void:
	if player == null:
		return
	player.set("passive_block_backstab", true)
	player.set("passive_block_cooldown", data.passive_cooldown if data != null else 30.0)
	player.connect(&"backstab_blocked", _on_backstab_blocked)


func _on_deactivate() -> void:
	if player != null and is_instance_valid(player):
		if player.is_connected(&"backstab_blocked", _on_backstab_blocked):
			player.disconnect(&"backstab_blocked", _on_backstab_blocked)
		player.set("passive_block_backstab", false)


func _on_backstab_blocked() -> void:
	AudioManager.play_sfx(&"ricochet")
	EventBus.notify.emit("老兵直觉 · 格挡背后袭击")
	DialogueManager.play_bark("marcus", "block")
