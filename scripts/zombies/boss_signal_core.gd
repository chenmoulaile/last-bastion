class_name ZombieSignalCore
extends ZombieBase
## wp7：信号核心系 Boss（l03 锈蚀尖啸者 / l11 信号核心·终焉体共用本场景入口）。
## l03 尖啸减速+召唤+回声波；l11 三阶段换招（干扰/弹幕/吸尸/终焉尖啸）+
## 战斗期间信号干扰特效；由 BossEngine 按 LEVEL_CFG 驱动。

var _mind: RefCounted = null
var _bcfg: Dictionary = {}


func _ready() -> void:
	super()
	_bcfg = BossEngine.setup(self)


func _exit_tree() -> void:
	# 干扰特效兜底清理（正常死亡由 BossEngine.on_death 关闭）
	if _bcfg.get("interference", false):
		EventBus.signal_interference.emit(false)


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
