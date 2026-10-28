class_name SoldierBase
extends CharacterBody2D
## ---------------------------------------------------------------------------
## 职责: 指挥模式士兵基类(重构版)。封装共有逻辑: 生命/倒地/永久阵亡、
##       移动、索敌射击、阵型跟随、指令响应、视觉同步。
##       兵种差异 100% 由 RoleStrategy 子类承担,本文件零兵种分支。
## 依赖(全部可选,独立运行自动降级):
##   EventBus     command_issued(cmd) / formation_changed(id) 订阅(经组件)
##   GameManager  get_weapon(id) 武器数值
##   AudioManager play_sfx_2d 枪声
## 节点结构(见 INTEGRATION_GUIDE §1):
##   SoldierBase (CharacterBody2D, layer=4 ALLY, mask=WORLD|COMMON|SPECIAL|INTERACTABLE)
##   ├── Collision (CollisionShape2D, 12×28 @ (0,-14),代码创建)
##   ├── Renderer  (SoldierRenderer,代码创建或场景预置)
##   └── MuzzlePoint (Marker2D @ (16,-18),代码创建)
## 对外接口:
##   @export soldier_data: ReworkSoldierData / slot_index / is_soldier
##   issue_command(cmd, point) / set_formation(id) / cycle_formation()
##   take_damage / heal / heal_full / die / revive / respawn_at / inspire /
##   apply_bile / apply_burn / enter_control / release_control
##   get_status_text() -> String / get_health_ratio() -> float
##   信号: soldier_state_changed(state, detail) /
##         soldier_order_acknowledged(cmd, state) / shots_fired(pos)
## 兼容字段(现有 LevelRunner/HUD 通过 .get() 读取):
##   hp max_hp temp_hp downs is_downed is_dead is_pinned is_controlled
##   facing command formation state_text data(=soldier_data 别名)
## ---------------------------------------------------------------------------

signal soldier_state_changed(state: StringName, detail: Dictionary)
signal soldier_order_acknowledged(cmd: StringName, state: Dictionary)
signal shots_fired(from_position: Vector2)

const FALLBACK_DATA := "res://characters_rework/data/soldiers/rifleman.tres"
const BLEEDOUT_TIME: float = 20.0

@export var soldier_data: ReworkSoldierData = null
@export var slot_index: int = 0
@export var is_soldier: bool = true

## --- 生命/状态 ---
var max_hp: int = 80
var hp: int = 80
var temp_hp: int = 0
var downs: int = 0
var is_downed: bool = false
var is_dead: bool = false
var is_pinned: bool = false
var is_controlled: bool = false
var control_kind: StringName = &""
var controller: Node = null
var control_immune: float = 0.0
var bleedout: float = BLEEDOUT_TIME
var bile_timer: float = 0.0
var inspire_timer: float = 0.0
var iframes: float = 0.0

## --- 运动/战斗状态 ---
var facing: int = 1
var base_speed: float = 215.0
var enemy: Node2D = null
var state_text: String = "跟随"
var aim_angle: float = 0.0

## --- 组件与策略 ---
var strategy: RoleStrategy = null
var movement_component: ReworkMovementComponent = null
var combat_component: ReworkCombatComponent = null
var order_component: ReworkOrderComponent = null
var formation_component: ReworkFormationComponent = null

var _renderer: SoldierRenderer = null
var _bus: Node = null
var _audio: Node = null
var _game: Node = null
var _detail: Dictionary = {}

## 兼容别名: 现有 HUD 读取 member.get("data")(类型 CharacterData)。
var data: Variant:
	get:
		return soldier_data


func _ready() -> void:
	add_to_group("allies")
	add_to_group("rework_soldiers")
	add_to_group("rework_actors")
	if soldier_data == null:
		soldier_data = load(FALLBACK_DATA) as ReworkSoldierData
	max_hp = soldier_data.max_hp
	hp = max_hp
	base_speed = soldier_data.speed
	collision_layer = 4                       # ALLY(与现有 AllyAgent 一致)
	collision_mask = 1 | 8 | 16 | 64          # WORLD|COMMON|SPECIAL|INTERACTABLE
	floor_snap_length = 8.0
	_bus = _autoload(&"EventBus")
	_audio = _autoload(&"AudioManager")
	_game = _autoload(&"GameManager")
	_build_nodes()
	_build_components()
	EventBusBridge.attach_for(self)
	_emit_state(&"spawn")


func _build_nodes() -> void:
	if get_node_or_null("Collision") == null:
		var collision := CollisionShape2D.new()
		collision.name = "Collision"
		var shape := RectangleShape2D.new()
		shape.size = Vector2(12, 28)
		collision.shape = shape
		collision.position = Vector2(0, -14)
		add_child(collision)
	var existing := get_node_or_null("Renderer")
	if existing is SoldierRenderer:
		_renderer = existing
	else:
		_renderer = SoldierRenderer.new()
		_renderer.name = "Renderer"
		_renderer.z_index = 4
		add_child(_renderer)
	_renderer.setup(soldier_data)
	if get_node_or_null("MuzzlePoint") == null:
		var muzzle := Marker2D.new()
		muzzle.name = "MuzzlePoint"
		muzzle.position = Vector2(16, -18)
		add_child(muzzle)


func _build_components() -> void:
	strategy = RoleStrategy.create(soldier_data.strategy_id)
	strategy.on_attached(self)
	order_component = ReworkOrderComponent.new()
	order_component.attach(self)
	order_component.facing_dir = 1.0
	formation_component = ReworkFormationComponent.new()
	movement_component = ReworkMovementComponent.new()
	movement_component.attach(self, order_component, formation_component, strategy)
	combat_component = ReworkCombatComponent.new()
	combat_component.attach(self, strategy)
	order_component.soldier_order_acknowledged.connect(_on_order_acknowledged)
	if _bus != null and _bus.has_signal("formation_changed"):
		_bus.formation_changed.connect(set_formation)
	_sync_state_text()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_tick_timers(delta)
	if is_downed:
		bleedout -= delta
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if not is_on_floor():
			velocity.y += 1500.0 * delta
		move_and_slide()
		if bleedout <= 0.0:
			die()
		_sync_visuals()
		return
	if is_controlled:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += 1500.0 * delta
		move_and_slide()
		_sync_visuals()
		return
	strategy.think(delta)
	order_component.facing_dir = 1.0 # 横版推进方向固定向右(与现有工程一致)
	movement_component.tick(delta)
	combat_component.tick(delta)
	strategy.support_tick(delta)
	strategy.try_special_action(delta)
	strategy.physics_tick(delta)
	move_and_slide()
	_update_aim()
	_sync_visuals()


func _tick_timers(delta: float) -> void:
	if iframes > 0.0:
		iframes -= delta
	if control_immune > 0.0:
		control_immune -= delta
	if bile_timer > 0.0:
		bile_timer -= delta
	if inspire_timer > 0.0:
		inspire_timer -= delta


func _update_aim() -> void:
	if combat_component.enemy != null and is_instance_valid(combat_component.enemy):
		var to: Vector2 = combat_component.enemy.global_position - global_position
		aim_angle = to.angle()
	else:
		aim_angle = 0.0 if facing > 0 else PI


## ------------------------------------------------------------ 指令/阵型 ----

func issue_command(cmd: StringName, point: Vector2 = Vector2.ZERO) -> void:
	order_component.issue(cmd, point)
	_sync_state_text()
	if _bus != null and _bus.has_signal("teammate_status_changed"):
		_bus.teammate_status_changed.emit()


func set_formation(id: StringName) -> void:
	formation_component.set_formation(id)


func cycle_formation() -> StringName:
	return formation_component.cycle_formation()


func get_command() -> StringName:
	return order_component.order


func get_formation() -> StringName:
	return formation_component.formation


func _sync_state_text() -> void:
	state_text = {"follow": "跟随", "advance": "推进", "hold": "防守",
		"focus": "集火"}.get(String(order_component.order), "跟随")


func _on_order_acknowledged(cmd: StringName, state: Dictionary) -> void:
	## 组件指令回执 → 士兵对外信号(桥接层再转发,避免环)。
	_sync_state_text()
	soldier_order_acknowledged.emit(cmd, state)


## ------------------------------------------------------------ 生命流程 ----

func take_damage(amount: int, source_dir: Vector2 = Vector2.ZERO,
		source: StringName = &"zombie", damage_type: StringName = &"melee") -> void:
	if is_dead or iframes > 0.0 or amount <= 0:
		return
	if is_downed:
		bleedout -= 2.0
		return
	hp -= amount
	iframes = 0.25
	_emit_state(&"hurt")
	if hp <= 0:
		_go_down()


func _go_down() -> void:
	hp = 0
	downs += 1
	is_downed = true
	bleedout = BLEEDOUT_TIME
	velocity = Vector2.ZERO
	enemy = null
	if _renderer:
		_renderer.set_downed(true)
	if _bus != null and _bus.has_signal("ally_downed"):
		_bus.ally_downed.emit(self)
	_emit_state(&"downed")


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_downed = false
	is_controlled = false
	hp = 0
	enemy = null
	velocity = Vector2.ZERO
	if _renderer:
		_renderer.set_dead(true)
	if _bus != null and _bus.has_signal("ally_died"):
		_bus.ally_died.emit(self)
	_emit_state(&"dead")


func revive(_healer: Node) -> void:
	if is_dead or not is_downed:
		return
	is_downed = false
	hp = 30
	temp_hp = 0
	bleedout = BLEEDOUT_TIME
	control_immune = 3.0
	iframes = 1.0
	if _renderer:
		_renderer.set_downed(false)
	if _bus != null and _bus.has_signal("ally_revived"):
		_bus.ally_revived.emit(self)
	_emit_state(&"revived")


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	hp = mini(hp + amount, max_hp)


func heal_full() -> void:
	if is_dead:
		return
	hp = max_hp
	temp_hp = 0


func respawn_at(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	is_dead = false
	is_downed = false
	is_controlled = false
	hp = max_hp
	bleedout = BLEEDOUT_TIME
	if _renderer:
		_renderer.set_dead(false)
		_renderer.set_downed(false)
	_emit_state(&"respawn")


func inspire(duration: float) -> void:
	inspire_timer = maxf(inspire_timer, duration)


func apply_bile(duration: float) -> void:
	bile_timer = maxf(bile_timer, duration)


func apply_burn(_dps: float, _duration: float) -> void:
	pass


func enter_control(kind: StringName, source: Node) -> void:
	if is_dead or control_immune > 0.0 or is_controlled:
		return
	is_controlled = true
	is_pinned = true
	control_kind = kind
	controller = source
	if _bus != null and _bus.has_signal("ally_pinned"):
		_bus.ally_pinned.emit(self)
	_emit_state(&"controlled")


func release_control() -> void:
	if not is_controlled:
		return
	is_controlled = false
	is_pinned = false
	control_kind = &""
	controller = null
	control_immune = 3.0
	if _bus != null and _bus.has_signal("ally_unpinned"):
		_bus.ally_unpinned.emit(self)
	_emit_state(&"control_released")


func get_status_text() -> String:
	if is_dead:
		return "阵亡"
	if is_downed:
		return "倒地"
	if is_controlled:
		return "被控"
	if combat_component != null and combat_component.enemy != null:
		return "交战"
	return state_text


func get_health_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))


## ------------------------------------------------------------ 视觉同步 ----

func _sync_visuals() -> void:
	if _renderer == null:
		return
	var state := CodeRenderer.STATE_IDLE
	if not is_downed and not is_dead:
		if combat_component != null and combat_component.enemy != null:
			state = CodeRenderer.STATE_ATTACK
		elif movement_component != null and movement_component.is_moving():
			state = CodeRenderer.STATE_WALK
	_renderer.set_anim_state(state)
	_renderer.set_facing(facing)
	_renderer.set_aim_angle(aim_angle)
	_renderer.set_health_ratio(get_health_ratio())
	_renderer.set_downed(is_downed)
	_renderer.set_dead(is_dead)


func _emit_state(state: StringName) -> void:
	_detail["hp"] = hp
	_detail["command"] = order_component.order if order_component != null else &"follow"
	soldier_state_changed.emit(state, _detail)


func _autoload(what: StringName) -> Node:
	return get_node_or_null("/root/" + String(what))
