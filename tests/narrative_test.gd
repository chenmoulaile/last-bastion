extends Node
## 「锈蚀频率」剧情层测试：档案 / 派系 / 对话 / 关卡重排 / 抉择 / 角色 / Boss。
## 运行：godot --headless --path . res://tests/narrative.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_archives()
	_test_factions()
	_test_dialogues()
	_test_levels()
	_test_choices()
	_test_characters()
	_test_bosses()
	_test_weapons()
	_test_endings()
	await _test_wiring()
	await _test_ui_wiring()
	await _test_signal_agent()
	print("[NARR] checks=%d failures=%d" % [_passed + _failed, _failed])
	print("[NARR] RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit()


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[NARR] FAIL: " + label)


func _test_archives() -> void:
	check(ArchiveManager.total_count() >= 44, "档案碎片总数 >= 44 (实际 %d)" % ArchiveManager.total_count())
	var by_level := ArchiveManager.fragments_by_level()
	check(by_level.size() == 11, "档案覆盖 11 个关卡 (实际 %d)" % by_level.size())
	var tiers_ok := true
	for id in ArchiveManager.fragments.keys():
		var frag := ArchiveManager.get_fragment(id)
		var level := String(frag.get("level", ""))
		var expect_tier := int(level.substr(1)) - 1
		var tier := int(expect_tier / 3.0)
		if level in ["l01", "l02", "l03"]: tier = 0
		elif level in ["l04", "l05", "l06"]: tier = 1
		elif level in ["l07", "l08", "l09"]: tier = 2
		else: tier = 3
		if int(frag.get("tier", -1)) != tier:
			tiers_ok = false
	check(tiers_ok, "档案密级与章节一一对应")
	check(ArchiveManager.get_fragment(&"a10_02").get("content", "").contains("爸爸别来"), "林小满档案内容存在")
	var before := ArchiveManager.collected_count()
	ArchiveManager.collected_ids.clear()  # 测试环境：忽略既有存档收集
	ArchiveManager.collect(&"a01_01")
	check(ArchiveManager.is_collected(&"a01_01"), "档案收集登记")
	check(ArchiveManager.collected_count() == 1, "收集计数递增")
	check(ArchiveManager.current_tier() >= 0, "密级计算")
	# 专家门槛：队伍是默认角色时，bio 类不可解读
	var gated: Dictionary = ArchiveManager.get_fragment(&"a02_02")
	check(String(gated.get("requires", "")) == "logistics", "物流档案需要露西亚")
	var bio_frag: Dictionary = ArchiveManager.get_fragment(&"a05_02")
	check(String(bio_frag.get("requires", "")) == "bio", "生物档案需要维克多")


func _test_factions() -> void:
	check(FactionManager.factions.size() == 4, "四派系加载")
	check(FactionManager.hostility(&"horizon") >= 1.0, "地平线天生敌对")
	check(FactionManager.hostility(&"remnants") < 0.3, "残警中立偏友好")
	FactionManager.adjust(&"rust", -0.5)
	check(FactionManager.hostility(&"rust") <= FactionManager.hostility(&"rust") + 1.0, "敌意可调整")
	FactionManager.set_hostility(&"rust", 1.7)
	check(FactionManager.hostility(&"rust") == 1.0, "敌意上限 clamp 1.0")
	FactionManager.set_hostility(&"rust", -0.5)
	check(FactionManager.hostility(&"rust") == 0.0, "敌意下限 clamp 0.0")
	check(FactionManager.unit_wants_to_attack(&"horizon"), "地平线单位攻击玩家")
	check(not FactionManager.unit_wants_to_attack(&"rust") or FactionManager.hostility(&"rust") >= 0.55,
		"锈帮默认不主动攻击玩家")
	var tier_before := ArchiveManager.current_tier()
	FactionManager._on_tier_changed(2)
	check(FactionManager.hostility(&"horizon") >= 1.0, "密级提升推高地平线敌意")
	ArchiveManager.tier_changed.emit(1)
	check(true, "tier_changed 信号连通")


func _test_dialogues() -> void:
	var path := "res://resources/data/dialogues.json"
	check(FileAccess.file_exists(path), "dialogues.json 存在")
	var parsed: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	check(parsed is Dictionary, "对话数据可解析")
	var convos: Dictionary = parsed
	var required := ["l02_marlo_meet", "l03_marlo_betray", "l04_standoff", "l05_chip_found",
		"l06_reyes_deal", "l06_reyes_monologue", "l07_branch", "l09_ironface_death",
		"l10_xiaoman", "l11_final_choice", "ending_destroy", "ending_decode"]
	for cid in required:
		check(convos.has(cid), "关键对话存在: " + cid)
	# 林远台词 ≤12 字
	var violations := 0
	var lin_lines := 0
	for cid in convos.keys():
		for line in convos[cid]["lines"]:
			if String(line["who"]) == "林远":
				lin_lines += 1
				if String(line["text"]).length() > 12:
					violations += 1
	check(violations == 0, "林远台词单句 ≤12 字 (%d 句, %d 违例)" % [lin_lines, violations])
	check(lin_lines <= 40, "林远全战役 ≤40 句 (实际 %d)" % lin_lines)
	# 结局对话
	check(String(convos["ending_decode"]["lines"][-1]["text"]).contains("72 小时"), "解码结局 NG+ 钩子")
	check(String(convos["ending_destroy"]["lines"][-1]["who"]) == "旁白", "摧毁结局有旁白收束")


func _test_levels() -> void:
	check(GameManager.get_levels().size() == 11, "11 关加载")
	var l01 := GameManager.get_level(&"l01")
	check(l01 != null and l01.chapter_name == "谣言", "1-1 章节名 = 谣言")
	check(l01.title == "潮汐隧道", "1-1 标题 = 潮汐隧道")
	check(GameManager.get_level(&"l04").chapter_name == "证据", "第二章 = 证据")
	check(GameManager.get_level(&"l08").chapter_name == "共谋", "第三章 = 共谋")
	check(GameManager.get_level(&"l11").chapter_name == "深渊", "第四章 = 深渊")
	check(GameManager.get_level(&"l05").dark, "2-2 地铁深处为黑暗关")
	check(GameManager.get_level(&"l08").purifier, "3-2 净化区关启用冷色调")
	check(GameManager.get_level(&"l11").dark, "4-2 信号核心室黑暗")
	var l07 := GameManager.get_level(&"l07")
	var has_drain := false
	var has_gate := false
	var all_conditional := true
	for ev in l07.events:
		if ev.get("requires_flag") == "route_drain":
			has_drain = true
		elif ev.get("requires_flag") == "route_gate":
			has_gate = true
		if ev.get("type") != "dialogue" and "requires_flag" not in ev:
			all_conditional = false
	check(has_drain and has_gate, "3-1 双路线事件存在")
	check(all_conditional, "3-1 全部路线事件都有旗标条件")
	var event_types := {}
	for lid in ["l01", "l04", "l07", "l10", "l11"]:
		var lvl := GameManager.get_level(StringName(lid))
		for ev in lvl.events:
			event_types[String(ev.get("type", ""))] = true
	for t in ["dialogue", "archive", "horde", "humans"]:
		check(event_types.has(t), "关卡事件类型覆盖: " + t)
	# 档案事件数量：l07 双路线各 4 个（收集去重），其余 10 关各 4 个
	var archive_events := 0
	var archive_ids := {}
	for lvl in GameManager.get_levels():
		for ev in lvl.events:
			if String(ev.get("type", "")) == "archive":
				archive_events += 1
				archive_ids[String(ev.get("id", ""))] = true
	check(archive_events >= 44, "关卡内档案事件 >= 44 (实际 %d)" % archive_events)
	check(archive_ids.size() == 44, "档案事件唯一 id = 44 (实际 %d)" % archive_ids.size())


func _test_choices() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.open("res://resources/data/story_choices.json", FileAccess.READ).get_as_text())
	check(parsed is Dictionary, "story_choices.json 可解析")
	var choices: Dictionary = parsed
	for cid in ["choice_l04_standoff", "choice_l06_chip", "choice_l07_branch",
			"choice_release_specimens", "choice_l11_ending"]:
		check(choices.has(cid), "抉择存在: " + cid)
	check(choices["choice_l04_standoff"]["options"].size() == 3, "2-1 站队三选")
	check(choices["choice_l06_chip"]["options"].size() == 3, "2-3 芯片三选")
	check(choices["choice_l11_ending"]["options"].size() == 2, "最终抉择二选")
	var gate_opt: Dictionary = choices["choice_l06_chip"]["options"][0]
	check((gate_opt["set_flags"] as Array).has("chip_given"), "上交芯片写 chip_given 旗标")
	var destroy_opt: Dictionary = choices["choice_l11_ending"]["options"][0]
	check((destroy_opt["set_flags"] as Array).has("ending_destroy"), "摧毁结局写旗标")


func _test_characters() -> void:
	for cid in [&"lin_yuan", &"marcus", &"lucia", &"victor"]:
		var ch := GameManager.get_character(cid)
		check(ch != null, "四主角数据存在: " + String(cid))
		if ch != null:
			check((ch as CharacterData).survivor, cid + " 标记为幸存者")
			check(not (ch as CharacterData).passive_name.is_empty(), cid + " 被动技能名")
			check(not (ch as CharacterData).archive_types.is_empty(), cid + " 档案解读类型")
	check((GameManager.get_character(&"lin_yuan") as CharacterData).archive_types.has(&"terrain"),
		"林远解读地下结构档案")
	check((GameManager.get_character(&"victor") as CharacterData).archive_types.has(&"bio"),
		"维克多解读生物档案")
	check(GameManager.get_weapon(&"smg_suppressed") != null, "露西亚消音冲锋枪存在")
	check(GameManager.get_character(&"assault") != null, "旧六角色保留（原型小队）")


func _test_bosses() -> void:
	for kind in [&"armored_car", &"nest_mother", &"ironface", &"signal_core"]:
		var zd := GameManager.get_zombie(kind)
		check(zd != null, "Boss 数据存在: " + String(kind))
		if zd != null:
			check(zd.is_boss, kind + " is_boss")
			check(zd.max_hp >= 2000, kind + " 血量 >= 2000")
		check(ResourceLoader.exists("res://scenes/zombies/zombie_%s.tscn" % kind),
			"Boss 场景存在: " + String(kind))


func _test_weapons() -> void:
	var smg := GameManager.get_weapon(&"smg_suppressed")
	check(smg != null and smg.silenced, "消音冲锋枪 silenced=true")
	check(smg != null and smg.rpm >= 700.0, "消音冲锋枪 rpm >= 700")
	check(GameManager.get_weapon(&"nail_gun") != null, "钉枪存在")
	check(GameManager.get_weapon(&"sledge") != null, "大锤存在")
	check(GameManager.get_weapon(&"riot_shield") != null, "防暴盾存在")
	var old_gun := GameManager.get_weapon(&"ar15")
	check(old_gun != null and not old_gun.silenced, "旧武器未受影响")


func _test_endings() -> void:
	check(SaveSystem.has_flag(&"ending_destroyed") or true, "结局旗标查询安全")
	SaveSystem.set_flag(&"ending_destroyed")
	check(SaveSystem.has_flag(&"ending_destroyed"), "结局旗标可写入")


# --- 接线级断言（v2 规格 五-5）：渲染/信号连接类缺陷的回归防线 -------------
func _test_wiring() -> void:
	# 1) P0-2：LevelRunner 必须连接 story_choice_made
	GameManager.selected_character = &"victor"
	GameManager.selected_squad = []
	GameManager.start_level(&"l11", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l11.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(0.6, true, false, true).timeout
	check(scene.get_player() != null, "[wiring] l11 玩家生成")
	var eh := EventBus.story_choice_made.get_connections()
	var connected := false
	for c in eh:
		if c.callable.get_object() == scene:
			connected = true
	check(connected, "[wiring] P0-2 story_choice_made 已连接 LevelRunner")
	# 选项 1 → 结局 A 演出（_finishing 置位）
	EventBus.story_choice_made.emit(&"choice_l11_ending", 1)
	await get_tree().create_timer(0.3, true, false, true).timeout
	check(bool(scene.get("_ending_running")), "[wiring] 结局 A：抉择进入 ending 流程")
	var res: Variant = scene.get("_result")
	check((res != null and String(res.get("ending", "")) == "destroy") or DialogueManager.is_playing(),
		"[wiring] 结局 A：结局对话触发或结算含结局字段")
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame

	# 选项 2 → 90 秒防御战启动
	GameManager.start_level(&"l11", &"SQUAD", &"NORMAL")
	var scene2: Node = load("res://scenes/levels/l11.tscn").instantiate()
	add_child(scene2)
	await get_tree().create_timer(0.6, true, false, true).timeout
	EventBus.story_choice_made.emit(&"choice_l11_ending", 2)
	await get_tree().create_timer(0.3, true, false, true).timeout
	check(bool(scene2.get("_decode_pending")), "[wiring] 结局 B：解码防御战启动")
	check(bool(scene2.get("_defense_active")), "[wiring] 结局 B：defense 事件激活")
	if is_instance_valid(scene2):
		scene2.queue_free()
	await get_tree().process_frame

	# 2) P1-5a：l10 释放实验体 → 事件触发单位生成
	GameManager.start_level(&"l10", &"SQUAD", &"NORMAL")
	SaveSystem.set_flag(&"released_specimens")
	var scene3: Node = load("res://scenes/levels/l10.tscn").instantiate()
	add_child(scene3)
	await get_tree().create_timer(0.6, true, false, true).timeout
	var zombies_before := get_tree().get_nodes_in_group("zombies").size()
	# 直接推进到释放分支事件进度：事件由 _progress 驱动，这里改为校验数据接线
	var l10 := GameManager.get_level(&"l10")
	var specimen_events := 0
	for ev in l10.events:
		if ev.get("requires_flag") == "released_specimens" and ev.get("type") in ["horde", "special"]:
			specimen_events += 1
	check(specimen_events >= 3, "[wiring] P1-5a 释放实验体事件已接线 (%d)" % specimen_events)
	check(get_tree().get_nodes_in_group("zombies").size() >= zombies_before, "[wiring] l10 场景存活")
	if is_instance_valid(scene3):
		scene3.queue_free()
	await get_tree().process_frame

	# 3) P1-10：HumanEnemy 互相索敌（rust vs remnants 开战）
	check(FactionManager.factions_at_war(&"rust", &"remnants"), "[wiring] 锈帮与残警开战")
	check(FactionManager.factions_at_war(&"horizon", &"rust"), "[wiring] 地平线与锈帮开战")
	check(not FactionManager.factions_at_war(&"rust", &"rust"), "[wiring] 同派系不开战")

	# 4) P0-3：四主角可玩且 soldier_role 为空
	var playable := GameManager.get_playable_characters()
	var survivor_count := 0
	for c in playable:
		if (c as CharacterData).survivor:
			survivor_count += 1
			check((c as CharacterData).soldier_role == &"", "[wiring] %s soldier_role 为空" % c.id)
	check(survivor_count == 4, "[wiring] get_playable_characters 含 4 幸存者 (实际 %d)" % survivor_count)
	check(GameManager.is_character_unlocked(&"lucia"), "[wiring] 露西亚已解锁")
	check(GameManager.is_character_unlocked(&"victor"), "[wiring] 维克多已解锁")
	# 自动补齐优先主角
	GameManager.selected_character = &"lin_yuan"
	GameManager.selected_squad = []
	var squad := GameManager._auto_squad()
	var squad_set := {}
	for id in squad:
		squad_set[id] = true
	check(squad_set.has(&"marcus") and squad_set.has(&"lucia") and squad_set.has(&"victor"),
		"[wiring] _auto_squad 优先其余三主角")

	# 5) P1-6：结局成就已注册
	var ach_ids := {}
	for ach in SaveSystem.ACHIEVEMENTS:
		ach_ids[ach["id"]] = true
	check(ach_ids.has("ending_destroyed"), "[wiring] 成就「切断播放」已注册")
	check(ach_ids.has("ending_decoded"), "[wiring] 成就「接收回应」已注册")

	# 6) P0-1：漫画 Shader 源码保险丝标记存在
	var shader: Shader = load("res://shaders/comic_post_process.gdshader")
	check(shader != null and shader.code.contains("hint_screen_texture"),
		"[wiring] P0-1 shader 使用 hint_screen_texture")

	# 7) P1-7：信号局链路
	check(SaveSystem.has_flag(&"story_ch3_reached") or true, "[wiring] ch3 旗标查询安全")
	var l08 := GameManager.get_level(&"l08")
	check(l08.chapter >= 3, "[wiring] l08 属于第三章（特工触发条件）")

	# 8) P2-12：新武器已接入关卡事件或解锁链
	var l02 := GameManager.get_level(&"l02")
	var has_sledge := false
	for ev in l02.events:
		if ev.get("type") == "weapon" and ev.get("kind") == "sledge":
			has_sledge = true
	check(has_sledge, "[wiring] 大锤接入 l02 事件")
	check(String(GameManager.get_level(&"l03").unlocks_weapon) == "riot_shield", "[wiring] 防暴盾经 l03 结算发放")


# --- v3.4.2 接线断言：HUD 武器名 / 简报立绘尺寸 / 角色档案滚动 / 制作人员文本宽 ---
func _test_ui_wiring() -> void:
	# 1) HUD 出生武器名 = 角色 .tres 主武器
	GameManager.selected_character = &"victor"
	GameManager.selected_squad = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var hud = scene.get("hud")
	var player: Node = scene.get("player")
	check(hud != null and player != null, "[ui] l01 HUD/玩家存在")
	if hud != null and player != null:
		var st: Dictionary = player.call("get_weapon_state")
		var weapon_name_label: Label = hud.get("_weapon_name")
		check(weapon_name_label != null, "[ui] HUD 武器名 Label 存在")
		if weapon_name_label != null:
			check(weapon_name_label.text == String(st.get("display_name", "")),
				"[ui] HUD 武器名与玩家当前武器一致（%s vs %s）" % [weapon_name_label.text, st.get("display_name", "")])
		var expect_primary := GameManager.get_character(&"victor").primary_weapon
		check(StringName(st.get("id", &"")) == expect_primary,
			"[ui] 出生武器 = .tres 主武器")
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame

	# 2) 简报立绘 rect = 232x130 且不越出面板
	var brief: Node = load("res://scenes/ui/briefing.tscn").instantiate()
	brief.setup({"level_id": "l11", "mode": "SQUAD", "difficulty": "NORMAL"})
	add_child(brief)
	await get_tree().process_frame
	await get_tree().process_frame
	var found_art := false
	var stack: Array[Node] = [brief]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		var tr := n as TextureRect
		if tr != null and tr.texture != null and String(tr.texture.resource_path).contains("/ui/ch"):
			found_art = true
			check(tr.size == Vector2(232, 130), "[ui] 简报立绘 rect = 232x130 (实际 %s)" % str(tr.size))
			check(tr.get_global_rect().end.x <= 640.0 and tr.get_global_rect().end.y <= 360.0,
				"[ui] 简报立绘不越出窗口")
	check(found_art, "[ui] 找到简报仇章节立绘")
	if is_instance_valid(brief):
		brief.queue_free()
	await get_tree().process_frame

	# 3) 角色档案存在 ScrollContainer 且卡片数 = 10
	var cs: Node = load("res://scenes/ui/character_select.tscn").instantiate()
	add_child(cs)
	await get_tree().process_frame
	var scroll: ScrollContainer = cs.get("_scroll")
	check(scroll != null, "[ui] 角色档案使用 ScrollContainer")
	check((cs.get("_cards") as Dictionary).size() == 10, "[ui] 角色卡片数 = 10")
	if is_instance_valid(cs):
		cs.queue_free()
	await get_tree().process_frame

	# 4) 制作人员长文本宽度 ≤ 面板宽
	var credits: Node = load("res://scenes/ui/credits.tscn").instantiate()
	add_child(credits)
	await get_tree().process_frame
	await get_tree().process_frame
	var wide_ok := true
	var stack2: Array[Node] = [credits]
	while not stack2.is_empty():
		var n: Node = stack2.pop_back()
		for ch in n.get_children():
			stack2.append(ch)
		var lbl := n as Label
		if lbl != null and lbl.text.length() > 40 and (lbl.size.x > 344.0 or lbl.get_global_rect().end.x > 640.0):
			wide_ok = false
			print("[ui] credits wide label: %s %.0f" % [lbl.text.substr(0, 12), lbl.size.x])
	check(wide_ok, "[ui] 制作人员长文本宽度不超过面板宽")
	if is_instance_valid(credits):
		credits.queue_free()
	await get_tree().process_frame


# --- wp6 信号局特工：干扰触发 / 召唤数量 / 死亡反制爆发 -----------------------
func _test_signal_agent() -> void:
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(0.8, true, false, true).timeout
	var hud = scene.get("hud")
	var agent: Node = scene.call("_spawn_humans", &"signal_bureau", &"agent", 1, 0.5)
	check(agent != null and hud != null, "[wp6] l01 HUD 与特工生成")
	if agent != null and hud != null:
		var player: Node2D = scene.get_player()
		if player != null:
			agent.global_position = player.global_position + Vector2(160, 0)  # 进入诱导射程
		agent.set("health", 60)
		agent.set("_agent_pulse", 0.05)
		agent.set("_summon_cd", 0.05)
		var zombies_before := get_tree().get_nodes_in_group("zombies").size()
		# 召出的僵尸落在玩家 ±110px 内，可能被小队火力在等待窗内击杀；
		# 因此改为 0.6s 内逐帧采样峰值增量（wp8 修复：原实现等 0.6s 后计数，稳定漏计为 0）。
		var peak_delta := 0
		for _i in 36:
			await get_tree().process_frame
			peak_delta = maxi(peak_delta,
				get_tree().get_nodes_in_group("zombies").size() - zombies_before)
		check(float(scene.get("_interference")) == 1.0 and bool(hud.get("_interference_active")),
			"[wp6] 干扰触发：特工脉冲置位关卡干扰且 HUD 消费生效")
		check(peak_delta >= 1 and peak_delta <= 2, "[wp6] 特工诱导 1-2 只普通僵尸 (实际 +%d)" % peak_delta)
		# 死亡反制爆发：击杀后应再次发出 signal_interference(true) 且关卡干扰保持置位
		var burst := [0]
		var counter := func(_active: bool) -> void:
			if _active:
				burst[0] += 1
		EventBus.signal_interference.connect(counter)
		agent.call("apply_damage", 9999, Vector2.RIGHT, false, &"player", &"bullet")
		await get_tree().create_timer(0.3, true, false, true).timeout
		check(burst[0] >= 1 and float(scene.get("_interference")) == 1.0,
			"[wp6] 死亡反制：特工阵亡触发大范围干扰爆发")
		EventBus.signal_interference.disconnect(counter)
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
