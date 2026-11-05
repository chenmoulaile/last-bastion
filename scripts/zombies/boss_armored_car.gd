class_name ZombieArmoredCar
extends ZombieBase
## wp7：「铁蹄」改装装甲车 Boss（l05 装甲突进）。正面装甲减伤 + 冲撞撞墙或
## 累计命中暴露弱点 ×4 伤害；由 BossEngine 按 LEVEL_CFG["l05"] 驱动。

var _mind: RefCounted = null
var _bcfg: Dictionary = {}


func _ready() -> void:
	super()
	_bcfg = BossEngine.setup(self)


func _ai_tick(delta: float) -> void:
	if _mind == null:
		super(delta)
		return
	BossEngine.tick(self, delta)


func apply_damage(amount: int, from_dir: Vector2, is_head: bool, source: StringName = &"player",
		damage_type: StringName = &"bullet") -> void:
	if _mind != null:
		amount = BossEngine.mitigate(self, amount, from_dir, damage_type)
		if amount <= 0:
			return
	super(amount, from_dir, is_head, source, damage_type)
	if not dead and _mind != null:
		BossEngine.on_damaged(self)


func _on_death_effect() -> void:
	BossEngine.on_death(self)
