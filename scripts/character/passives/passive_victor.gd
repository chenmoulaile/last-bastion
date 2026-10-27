class_name PassiveVictor
extends PassiveAbility
## 维克多 —「生物学家」
##
## * 对 group="special_infected" 的目标伤害 ×1.2（由 PlayerController 的
##   damage_multipliers 表统一结算，近战/子弹/处决都生效）。
## * 击杀特殊感染者有 50% 概率留下 SamplePickup。

const SPECIAL_GROUP := "special_infected"
const DAMAGE_MULT := 1.2
const SAMPLE_CHANCE := 0.5


func _on_activate() -> void:
	if player == null:
		return
	var mults: Dictionary = player.get("damage_multipliers")
	if mults == null:
		mults = {}
	mults[SPECIAL_GROUP] = DAMAGE_MULT
	player.set("damage_multipliers", mults)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_deactivate() -> void:
	if EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.disconnect(_on_enemy_died)
	if player != null and is_instance_valid(player):
		var mults: Dictionary = player.get("damage_multipliers")
		if mults != null:
			mults.erase(SPECIAL_GROUP)
			player.set("damage_multipliers", mults)


func _on_enemy_died(kind: StringName, pos: Vector2, _score: int) -> void:
	if not _is_special(kind):
		return
	if randf() > SAMPLE_CHANCE:
		return
	var lvl := level()
	if lvl == null:
		return
	if lvl.has_method("spawn_sample"):
		lvl.spawn_sample(pos)
		EventBus.notify.emit("采集到生物样本")


func _is_special(kind: StringName) -> bool:
	var zombie: ZombieData = GameManager.get_zombie(kind)
	if zombie != null:
		return zombie.is_special or zombie.is_boss
	return kind in [&"hunter", &"smoker", &"boomer", &"charger", &"spitter", &"jockey", &"tank", &"witch"]
