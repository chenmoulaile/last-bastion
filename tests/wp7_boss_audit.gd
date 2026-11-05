extends Node
## wp7-boss-rework headless 断言：配置表完整性 / Boss 出场（名字/外观/HP 覆写）/
## 招式前摇→telegraph→结算 / 50% 阶段切换 / 死亡奖励掉落 / 远程弹幕 / 多阶段。
## 运行：Godot_console.exe --headless --path "D:/Last Bastion" res://tests/wp7_boss_audit.tscn
## 与 integration_test 同形态（autoload 在场景模式下正常可见）。

var fails: Array[String] = []
var checks: int = 0
var _notifies: Array[String] = []
var _interference: Array[bool] = []
const ENG := "res://scripts/zombies/boss_engine.gd"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	EventBus.notify.connect(func(t: String) -> void: _notifies.append(t))
	EventBus.signal_interference.connect(func(a: bool) -> void: _interference.append(a))
	_static_cfg_checks()
	await _test_l01_melee_boss()
	await _test_l07_ranged_boss()
	await _test_l05_charge_and_armor()
	await _test_l09_ironface_and_common_charger()
	await _test_l11_multiphase_boss()
	print("[WP7-BOSS-AUDIT] checks=%d failures=%d" % [checks, fails.size()])
	for f in fails:
		print("  FAIL: " + f)
	print("[WP7-BOSS-AUDIT] RESULT: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	get_tree().quit(0 if fails.is_empty() else 1)


func _check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)
		print("  [x] " + what)
	else:
		print("  [ok] " + what)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ------------------------------------------------------- 1. 配置表静态 ----
func _static_cfg_checks() -> void:
	print("== static LEVEL_CFG checks")
	var cfg_all: Dictionary = BossEngine.LEVEL_CFG
	_check(cfg_all.size() == 11, "LEVEL_CFG covers 11 levels (got %d)" % cfg_all.size())
	var prev_hp := 0
	for i in range(1, 12):
		var key := "l%02d" % i
		_check(cfg_all.has(key), "%s config exists" % key)
		if not cfg_all.has(key):
			continue
		var cfg: Dictionary = cfg_all[key]
		var hp := int(cfg.get("hp", 0))
		_check(hp >= 2400, "%s hp=%d >= 2400" % [key, hp])
		_check(float(hp) / 39.0 >= 15.0, "%s hp mult %.1fx >= 15x common(39)" % [key, float(hp) / 39.0])
		_check(hp > prev_hp, "%s hp %d > previous %d (per-level increase)" % [key, hp, prev_hp])
		prev_hp = hp
		var moves: Array = cfg.get("moves", [])
		_check(moves.size() >= 2 and moves.size() <= 3,
			"%s has 2-3 signature moves (got %d)" % [key, moves.size()])
		var has_phase := false
		for ph in cfg.get("phases", []):
			if float(ph.get("below", 1.0)) <= 0.5:
				has_phase = true
		_check(has_phase, "%s has <=50%% phase" % key)
		for m in moves:
			_check(float(m.get("windup", 0.0)) > 0.0, "%s/%s windup>0" % [key, m.get("id")])
			_check(String(m.get("hint", "")).length() > 0, "%s/%s has safe-spot hint" % [key, m.get("id")])
	# 每关 boss 事件 kind 接到薄壳脚本
	var scene_map := {
		"ironface": "res://scripts/zombies/boss_ironface.gd",
		"nest_mother": "res://scripts/zombies/boss_nest_mother.gd",
		"signal_core": "res://scripts/zombies/boss_signal_core.gd",
		"tank": "res://scripts/zombies/zombie_tank.gd",
		"armored_car": "res://scripts/zombies/boss_armored_car.gd",
		"charger": "res://scripts/zombies/zombie_charger.gd",
	}
	for i in range(1, 12):
		var txt := String(FileAccess.get_file_as_string("res://resources/data/levels/l%02d.tres" % i))
		var boss_count := 0
		var km_all := RegEx.create_from_string("\\{\"at\": [\\d.]+, \"type\": \"boss\", \"kind\": \"(\\w+)\"")
		for km in km_all.search_all(txt):
			boss_count += 1
			var kind := km.get_string(1)
			_check(scene_map.has(kind), "l%02d boss kind '%s' wired to thin-shell" % [i, kind])
		_check(boss_count >= 1, "l%02d has >=1 boss event (got %d)" % [i, boss_count])


# ---------------------------------------------------------- 关卡工具 ----
func _open_level(id: StringName) -> Node:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(id, &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/%s.tscn" % String(id)).instantiate()
	add_child(scene)
	await _wait(0.9)
	return scene


func _close_level(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await _frames(3)
	GameManager.change_state(GameManager.State.MENU)
	await _frames(2)


func _boss(scene: Node) -> Node:
	for z in get_tree().get_nodes_in_group("zombies"):
		if z != null and is_instance_valid(z) and z.get("_mind") != null:
			return z
	return null


func _engine_fx(scene: Node) -> Array:
	var out: Array = []
	for c in scene.fx_layer.get_children():
		if is_instance_valid(c) and (c is BossEngine.TelegraphRing \
				or c is BossEngine.TelegraphLine or c is BossEngine.BossLob):
			out.append(c)
	return out


# --------------------------------------------------- 2. l01 近战 Boss ----
func _test_l01_melee_boss() -> void:
	print("== l01 锈钩屠夫 (melee)")
	var scene := await _open_level(&"l01")
	scene.spawn_boss(&"ironface")
	await _frames(3)
	var boss := _boss(scene)
	_check(boss != null, "l01 boss spawned and has BossMind")
	if boss == null:
		await _close_level(scene)
		return
	var mind = boss.get("_mind")
	_check(String(boss.data.display_name) == "锈钩屠夫", "l01 display_name override")
	_check(int(boss.max_health) == 2400, "l01 max_hp=2400 (got %d)" % int(boss.max_health))
	_check(String(boss.data.sprite_prefix) == "riot", "l01 sprite_prefix=riot (visual rework)")
	_check(boss.data.is_boss, "l01 data.is_boss (HUD bar + stagger immunity)")
	# 玩家放到 boss 前方 80px（cleave 带内），锁定单招保证前摇确定性
	var px: float = float(boss.global_position.x) - 80.0
	var gy: float = float(scene.call("get_ground_y", px))
	scene.get_player().global_position = Vector2(px, gy - 2.0)
	await _frames(2)
	var slam: Dictionary = {}
	for m in mind.moves:
		if String(m.get("id")) == "cleave":
			slam = m
	_check(not slam.is_empty(), "l01 cleave move present")
	mind.moves = [slam]
	mind.notified = {}
	slam["cd"] = 0.0
	_notifies.clear()
	var entered_windup := false
	for i in 420:
		await get_tree().physics_frame
		if String(mind.state) == "windup":
			entered_windup = true
			break
	_check(entered_windup, "l01 boss enters windup")
	if not entered_windup:
		await _close_level(scene)
		return
	var player_hp0 := int(scene.get_player().get("hp"))
	var ring_seen := false
	var windup_leak := false
	# 只观察前 12 帧（< windup 0.5s=30 物理帧），此窗口内绝不会有 cast 结算
	for i in 12:
		await get_tree().physics_frame
		if int(scene.get_player().get("hp")) < player_hp0:
			windup_leak = true
		if _engine_fx(scene).size() > 0:
			ring_seen = true
	_check(ring_seen, "l01 telegraph visible during windup")
	_check(not windup_leak, "l01 no damage settles during windup (safe window)")
	var settled := false
	for i in 120:
		await get_tree().physics_frame
		if int(scene.get_player().get("hp")) < player_hp0:
			settled = true
			break
	_check(settled, "l01 slam settles damage after windup (hp %d -> %d)"
		% [player_hp0, int(scene.get_player().get("hp"))])
	# 阶段切换 50%
	var hp1: int = int(boss.health)
	boss.apply_damage(int(ceil(hp1 * 0.55)), Vector2.RIGHT, false, &"player", &"bullet")
	await _frames(3)
	_check(int(mind.phase) == 1, "l01 phase switches at <=50%% (phase=%d)" % int(mind.phase))
	var phase_note_ok := false
	for t in _notifies:
		if t.contains("狂怒"):
			phase_note_ok = true
	_check(phase_note_ok, "l01 phase notify fired")
	_check(mind.moves.size() == 2, "l01 phase adds quake_stomp (moves=%d)" % mind.moves.size())
	# 死亡掉落
	var pickups_before: int = scene.get("pickups").get_child_count()
	_notifies.clear()
	boss.apply_damage(99999, Vector2.RIGHT, false, &"player", &"bullet")
	await _frames(5)
	var loot_note := false
	for t in _notifies:
		if t.contains("掉落了战利品"):
			loot_note = true
	var pickups_after: int = scene.get("pickups").get_child_count()
	_check(pickups_after >= pickups_before + 5,
		"l01 death drops loot (pickups %d -> %d)" % [pickups_before, pickups_after])
	_check(loot_note, "l01 loot notify fired")
	await _close_level(scene)


# --------------------------------------------------- 3. l07 远程 Boss ----
func _test_l07_ranged_boss() -> void:
	print("== l07 泵站迫击兽 (ranged)")
	var scene := await _open_level(&"l07")
	scene.spawn_boss(&"charger")
	await _frames(3)
	var boss := _boss(scene)
	_check(boss != null, "l07 charger spawns as boss via LEVEL_CFG")
	if boss == null:
		await _close_level(scene)
		return
	var mind = boss.get("_mind")
	_check(String(boss.data.display_name) == "泵站迫击兽", "l07 display_name override")
	_check(int(boss.health) == 3240, "l07 hp=3240 (got %d)" % int(boss.health))
	_check(String(boss.data.sprite_prefix) == "spitter", "l07 sprite_prefix=spitter")
	_check(String(mind.cfg.get("role", "")) == "kite", "l07 role=kite (ranged pressure)")
	var px: float = float(boss.global_position.x) - 420.0
	var gy: float = float(scene.call("get_ground_y", px))
	scene.get_player().global_position = Vector2(px, gy - 2.0)
	await _frames(2)
	var volley: Dictionary = {}
	for m in mind.moves:
		if String(m.get("id")) == "mortar_volley":
			volley = m
	mind.moves = [volley]
	mind.notified = {}
	volley["cd"] = 0.0
	var entered := false
	for i in 420:
		await get_tree().physics_frame
		if String(mind.state) == "windup":
			entered = true
			break
	_check(entered, "l07 enters volley windup")
	if not entered:
		await _close_level(scene)
		return
	var player_hp0 := int(scene.get_player().get("hp"))
	var settled := false
	for i in 300:
		await get_tree().physics_frame
		if int(scene.get_player().get("hp")) < player_hp0:
			settled = true
			break
	_check(settled, "l07 volley impacts player after windup (hp %d -> %d)"
		% [player_hp0, int(scene.get_player().get("hp"))])
	var dx: float = absf(float(boss.global_position.x) - float(scene.get_player().global_position.x))
	_check(dx > 180.0, "l07 boss keeps ranged distance (dx=%.0f)" % dx)
	await _close_level(scene)


# --------------------------- 3.4 l05 铁蹄：冲撞命中 + 装甲减伤/弱点 ----
func _test_l05_charge_and_armor() -> void:
	print("== l05 铁蹄 (charge hit + armor)")
	var scene := await _open_level(&"l05")
	scene.spawn_boss(&"armored_car")
	await _frames(3)
	var boss := _boss(scene)
	_check(boss != null, "l05 armored_car spawns as boss")
	if boss == null:
		await _close_level(scene)
		return
	var mind = boss.get("_mind")
	_check(String(boss.data.display_name) == "铁蹄", "l05 display_name override")
	_check(int(boss.max_health) == 3120, "l05 max_hp=3120 (got %d)" % int(boss.max_health))
	# 装甲减伤：非弱点期正面伤害 85% 减伤（100 -> 15）
	var hp0: int = int(boss.health)
	boss.apply_damage(100, Vector2(float(boss.facing), 0.0), false, &"player", &"bullet")
	await _frames(2)
	var dmg_taken := hp0 - int(boss.health)
	_check(dmg_taken >= 1 and dmg_taken <= 40,
		"l05 armor reduces 100 -> %d (front_reduce=0.85)" % dmg_taken)
	# 冲撞命中：玩家放冲撞直线上，锁定 ram
	var px: float = float(boss.global_position.x) - 260.0
	var gy: float = float(scene.call("get_ground_y", px))
	scene.get_player().global_position = Vector2(px, gy - 2.0)
	await _frames(2)
	var ram: Dictionary = {}
	for m in mind.moves:
		if String(m.get("id")) == "ram":
			ram = m
	mind.moves = [ram]
	mind.notified = {}
	ram["cd"] = 0.0
	var entered := false
	for i in 420:
		await get_tree().physics_frame
		if String(mind.state) == "windup":
			entered = true
			break
	_check(entered, "l05 enters ram windup")
	if not entered:
		await _close_level(scene)
		return
	var player_hp0 := int(scene.get_player().get("hp"))
	var hit := false
	for i in 200:
		await get_tree().physics_frame
		if int(scene.get_player().get("hp")) < player_hp0:
			hit = true
			break
	_check(hit, "l05 ram charge hits player after windup (hp %d -> %d)"
		% [player_hp0, int(scene.get_player().get("hp"))])
	await _close_level(scene)


# --------------------------------------- 3.5 l09 铁面 + 普通 charger ----
func _test_l09_ironface_and_common_charger() -> void:
	print("== l09 铁面 (front immunity) + 普通 charger 回归")
	var scene := await _open_level(&"l09")
	scene.spawn_boss(&"ironface")
	await _frames(3)
	var boss := _boss(scene)
	_check(boss != null, "l09 ironface spawns as boss")
	if boss == null:
		await _close_level(scene)
		return
	var mind = boss.get("_mind")
	_check(String(boss.data.display_name) == "铁面", "l09 display_name override")
	_check(int(boss.max_health) == 3420, "l09 max_hp=3420 (got %d)" % int(boss.max_health))
	_check(String(boss.data.sprite_prefix) == "riot", "l09 sprite_prefix=riot")
	# 正面免伤：伤害方向与朝向同向（正面打来）→ 格挡
	var hp0: int = int(boss.health)
	boss.apply_damage(100, Vector2(float(boss.facing), 0.0), false, &"player", &"bullet")
	await _frames(2)
	_check(int(boss.health) == hp0, "l09 front shot blocked (hp %d -> %d)" % [hp0, int(boss.health)])
	# 绕背：方向相反 → 生效
	boss.apply_damage(100, Vector2(-float(boss.facing), 0.0), false, &"player", &"bullet")
	await _frames(2)
	_check(int(boss.health) < hp0, "l09 back shot damages (hp %d -> %d)" % [hp0, int(boss.health)])
	# 50% 丢盾狂暴：绕背方向打大伤害（正面会被免伤格挡，无法降血）
	boss.apply_damage(int(3420 * 0.6), Vector2(-float(boss.facing), 0.0), false, &"player", &"bullet")
	await _frames(3)
	_check(int(mind.phase) == 1, "l09 phase at <=50%% (phase=%d)" % int(mind.phase))
	var hp1: int = int(boss.health)
	boss.apply_damage(100, Vector2(float(boss.facing), 0.0), false, &"player", &"bullet")
	await _frames(2)
	_check(int(boss.health) < hp1, "l09 front immunity OFF after enrage (hp %d -> %d)" % [hp1, int(boss.health)])
	# 普通 charger（l09 special_weights 有 charger）保持普通特感 AI
	scene.spawn_special(&"charger")
	await _frames(3)
	var plain: Node = null
	for z in get_tree().get_nodes_in_group("zombies"):
		if z != null and is_instance_valid(z) and not bool(z.get("dead")) \
				and String(z.data.id) == "charger" and z.get("_mind") == null:
			plain = z
	_check(plain != null, "l09 special charger stays plain AI (no BossMind)")
	_check(plain != null and plain.data.is_special, "l09 special charger keeps data.is_special")
	await _close_level(scene)


# ----------------------------------------------- 4. l11 多阶段 Boss ----
func _test_l11_multiphase_boss() -> void:
	print("== l11 信号核心·终焉体 (multi-phase)")
	var scene := await _open_level(&"l11")
	scene.spawn_boss(&"signal_core")
	await _frames(3)
	var boss := _boss(scene)
	_check(boss != null, "l11 signal_core spawns as boss")
	if boss == null:
		await _close_level(scene)
		return
	var mind = boss.get("_mind")
	_check(String(boss.data.display_name) == "信号核心·终焉体", "l11 display_name override")
	_check(int(boss.max_health) == 4200, "l11 max_hp=4200 (got %d)" % int(boss.max_health))
	var inter_on := false
	for b in _interference:
		if b:
			inter_on = true
	_check(inter_on, "l11 signal interference ON during fight")
	_notifies.clear()
	boss.apply_damage(int(4200 * 0.4), Vector2.RIGHT, false, &"player", &"bullet")
	await _frames(3)
	_check(int(mind.phase) == 1, "l11 phase 2 at <=66%% (phase=%d)" % int(mind.phase))
	_check(mind.moves.size() == 4, "l11 phase2 adds volley+drain (moves=%d)" % mind.moves.size())
	var p2_note := false
	for t in _notifies:
		if t.contains("第二形态"):
			p2_note = true
	_check(p2_note, "l11 phase2 notify fired")
	_notifies.clear()
	boss.apply_damage(int(4200 * 0.32), Vector2.RIGHT, false, &"player", &"bullet")
	await _frames(3)
	_check(int(mind.phase) == 2, "l11 phase 3 at <=33%% (phase=%d)" % int(mind.phase))
	_check(mind.moves.size() == 5, "l11 phase3 adds death_scream (moves=%d)" % mind.moves.size())
	var p3_note := false
	for t in _notifies:
		if t.contains("终焉形态"):
			p3_note = true
	_check(p3_note, "l11 phase3 notify fired")
	_notifies.clear()
	boss.apply_damage(99999, Vector2.RIGHT, false, &"player", &"bullet")
	await _frames(5)
	var off_seen := false
	for b in _interference:
		if not b:
			off_seen = true
	_check(off_seen, "l11 interference OFF after boss death")
	var loot_note := false
	for t in _notifies:
		if t.contains("掉落了战利品"):
			loot_note = true
	_check(loot_note, "l11 loot notify fired")
	await _close_level(scene)
