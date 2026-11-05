class_name ZombieIronface
extends ZombieBase
## wp7：铁面系 Boss（l01 锈钩屠夫 / l09 铁面共用本场景入口）。l01 近战压制
##（钩链拉拽/横扫/践踏），l09 保留正面免伤 + 盾击/点射/呼叫残党、50% 丢盾狂暴；
## 由 BossEngine 按 LEVEL_CFG 驱动。铁面临死台词仍由 level_runner 的
## boss_killed 流程接管。

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
