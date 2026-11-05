class_name ZombieTank
extends ZombieBase
## wp7：坦克 Boss（l10 样本库 / l04 废墟暴君共用本场景入口）。行为/数值/外观
## 统一由 BossEngine 按 LEVEL_CFG 关卡配置驱动；配置未命中时回退基础追逐攻击。

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
	AudioManager.set_tank_active(false)
	BossEngine.on_death(self)
