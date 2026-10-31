extends Node
## FactionManager - 「锈蚀频率」派系敌意与知情度运行时模型。
## 职责：持有四派系 hostility 数值、按玩家行为与档案密级调整、
##       回答「某派系当前对玩家/彼此的敌意」；不持有节点引用。
## 依赖：EventBus、SaveSystem（flag 存储）、ArchiveManager（密级）。
## 对外接口：hostility(id) / set_hostility(id, v) / adjust(id, delta) /
##           unit_wants_to_attack(faction_id, target_is_player) / debug_state()

const FACTIONS_DIR := "res://resources/data/factions"

var factions: Dictionary = {}                 # id -> FactionData
var _hostility: Dictionary = {}                # id -> float 0..1（对玩家）
var infighting: Dictionary = {}               # "a|b" -> bool（派系间当前交战）

var _signal_agent_timer: float = 0.0


func _ready() -> void:
	_load_factions()
	ArchiveManager.tier_changed.connect(_on_tier_changed)
	ResetState()


func ResetState() -> void:
	for id in factions.keys():
		_hostility[id] = (factions[id] as FactionData).base_hostility
	infighting.clear()


func _load_factions() -> void:
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		var base := String(file_name).trim_suffix(".remap")
		if not base.ends_with(".tres"):
			continue
		var res: Resource = load(FACTIONS_DIR + "/" + base)
		if res is FactionData:
			factions[res.id] = res


func hostility(id: StringName) -> float:
	return clampf(float(_hostility.get(id, 1.0)), 0.0, 1.0)


func set_hostility(id: StringName, value: float) -> void:
	_hostility[id] = clampf(value, 0.0, 1.0)


func adjust(id: StringName, delta: float) -> void:
	set_hostility(id, hostility(id) + delta)


## 派系武装单位是否应当攻击玩家。
func unit_wants_to_attack(faction_id: StringName) -> bool:
	return hostility(faction_id) >= 0.55


## 派系武装单位是否应当攻击僵尸（人类 vs 感染者天然敌对，锈蚀者不算派系）。
func fights_zombies(faction_id: StringName) -> bool:
	return factions.has(faction_id)


## 档案密级驱动：密级越高，地平线与信号局反应越强。
func _on_tier_changed(tier: int) -> void:
	adjust(&"horizon", 0.05)
	if tier >= 2:
		adjust(&"signal_bureau", 0.08)


func tick_signal_agents(delta: float) -> void:
	_signal_agent_timer += delta
	if _signal_agent_timer < 30.0:
		return
	_signal_agent_timer = 0.0
	# 第三章起信号局开始干扰；此处只发出请求，由关卡层落地生成。
	if SaveSystem.has_flag(&"story_ch3_reached") and hostility(&"signal_bureau") >= 0.5:
		EventBus.director_request_special.emit(&"signal_agent")


func debug_state() -> String:
	var out: Array[String] = []
	for id in factions.keys():
		out.append("%s=%.2f" % [id, hostility(id)])
	return " ".join(out)
