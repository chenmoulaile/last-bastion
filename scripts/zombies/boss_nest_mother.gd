class_name ZombieNestMother
extends ZombieBase
## wp7：巢母系 Boss（l02 码头巢母 / l06 沼气母巢共用本场景入口）。站桩召唤 +
## 范围减速/毒雾，50% 血前本体减伤；由 BossEngine 按 LEVEL_CFG 驱动。

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
