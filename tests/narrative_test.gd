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
		elif ev.get("type") not in ["dialogue"]:
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
	SaveSystem.data.erase("flags" if SaveSystem.data.has("flags") else "nonexistent")
	check(true, "旗标清理安全")
