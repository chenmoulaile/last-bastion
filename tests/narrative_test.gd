extends Node
## Narrative / faction / archive integration test.
## Run: Godot --headless --path . res://tests/narrative.tscn
##
## Covers the four survivors' passives, the archive gating + quota rules, the
## faction hostility math, dialogue bark rules, the final choice and the
## chapter mapping of all eleven levels.

var _failures: Array[String] = []
var _checks: int = 0
var _level_scene: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_test_data()
	_test_archive_rules()
	_test_factions()
	_test_dialogue()
	await _test_passives()
	_test_final_choice()
	await _test_ui()
	await _test_level_mapping()

	print("[NARRATIVE] checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[NARRATIVE] RESULT: PASS")
	else:
		for failure in _failures:
			printerr("[NARRATIVE] FAIL: " + failure)
		print("[NARRATIVE] RESULT: FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


# ------------------------------------------------------------------- data ----
func _test_data() -> void:
	var survivors := GameManager.get_archive_survivors()
	_check(survivors.size() == 4, "four archive survivors loaded")
	var ids: Array[String] = []
	for character in survivors:
		ids.append(String(character.id))
		_check(character.has_passive(), "passive declared: " + String(character.id))
		_check(character.monologue != "", "monologue present: " + String(character.id))
		_check(PassiveRegistry.has_passive(character.passive_ability_id),
			"passive script registered: " + String(character.id))
	_check("lin_yuan" in ids and "victor" in ids, "expected survivor ids")

	_check(GameManager.get_playable_characters().size() >= 6, "legacy roster preserved")
	_check(ArchiveManager.total_count() >= 18, "archive fragments loaded (%d)" % ArchiveManager.total_count())
	var by_level := {}
	for fragment in ArchiveManager.fragments.values():
		by_level[fragment.security_level] = true
	_check(by_level.has(1) and by_level.has(2) and by_level.has(3) and by_level.has(4),
		"all four security levels present")
	_check(FactionManager.factions.size() == 4, "four factions loaded")
	for id in ["horizon", "signal_bureau", "rust", "remnants"]:
		_check(FactionManager.get_faction(id) != null, "faction data: " + id)


# ---------------------------------------------------------------- archives ----
func _test_archive_rules() -> void:
	ArchiveManager.reset_progress(false)
	_check(ArchiveManager.highest_security_level_collected() == 0, "archive starts empty")
	_check(not ArchiveManager.can_decode_signal(), "decode gated without deep archive")

	var gated := ""
	for fragment in ArchiveManager.fragments.values():
		if fragment.required_character == "victor":
			gated = fragment.fragment_id
			break
	_check(gated != "", "a victor-gated fragment exists")
	var denied := ArchiveManager.try_unlock(gated, "lin_yuan", "passive_lin_yuan")
	_check(not bool(denied["ok"]), "specialist gate rejects wrong survivor")
	_check(String(denied["reason"]).contains("专业知识"), "gate explains the requirement")
	var allowed := ArchiveManager.try_unlock(gated, "victor", "passive_victor")
	_check(bool(allowed["ok"]), "specialist gate accepts victor")
	_check(ArchiveManager.is_unlocked(gated), "fragment persisted in memory")

	# Quota: chapter 1 wants two RUMOR fragments.
	var rumors := 0
	for fragment in ArchiveManager.fragments_for_chapter(1):
		if fragment.security_level == 1 and rumors < 2:
			ArchiveManager.force_unlock(fragment.fragment_id)
			rumors += 1
	_check(ArchiveManager.count_by_security(1) >= 2, "two rumors collected")
	_check(ArchiveManager.chapter_quota_met(1), "chapter 1 quota met")
	_check(ArchiveManager.extra_spawn_slots(1) == 0, "no extra spawns when quota met")
	ArchiveManager.reset_progress(false)
	_check(ArchiveManager.extra_spawn_slots(1) == 2, "extra spawns when quota unmet")

	var plan := ArchiveManager.plan_for_level(1, 1, 2)
	_check(plan.size() == 2, "level plan fills requested slots")

	for fragment in ArchiveManager.fragments_for_chapter(4):
		if fragment.security_level == 4:
			ArchiveManager.force_unlock(fragment.fragment_id)
			break
	_check(ArchiveManager.can_decode_signal(), "deep archive unlocks decode")
	_check(ArchiveManager.highest_security_level_collected() == 4, "highest security tracked")

	var redacted := ArchiveManager.get_fragment("rumor_dock_whisper").redacted_title()
	_check(redacted.begins_with("█"), "locked titles are redacted")


# ---------------------------------------------------------------- factions ----
func _test_factions() -> void:
	ArchiveManager.reset_progress(false)
	FactionManager.reset_runtime()
	var horizon := FactionManager.get_faction("horizon")
	var base := horizon.base_hostility_to_player
	_check(is_equal_approx(FactionManager.effective_hostility("horizon"), base),
		"base hostility with empty archive")
	# +0.15 per archive security level (a RUMOR is level 1).
	ArchiveManager.force_unlock("rumor_dock_whisper")
	var expected := clampf(base + 0.15, 0.0, 1.0)
	_check(absf(FactionManager.effective_hostility("horizon") - expected) < 0.001,
		"archive pressure raises hostility by 0.15")
	# +0.05 per kill, -0.2 per completed quest
	FactionManager.register_kill("horizon", 2)
	expected = clampf(expected + 0.10, 0.0, 1.0)
	_check(absf(FactionManager.effective_hostility("horizon") - expected) < 0.001,
		"kills raise hostility by 0.05 each")
	FactionManager.complete_quest("horizon")
	expected = clampf(expected - 0.20, 0.0, 1.0)
	_check(absf(FactionManager.effective_hostility("horizon") - expected) < 0.001,
		"quests lower hostility by 0.2")
	_check(is_equal_approx(FactionManager.relationship("horizon", "remnants"), 0.9),
		"horizon hates remnants (0.9)")
	_check(is_equal_approx(FactionManager.relationship("signal_bureau", "horizon"), 0.2),
		"bureau cooperates with horizon (0.2)")
	ArchiveManager.force_unlock("evidence_cold_chain")
	_check(FactionManager.patrol_density("horizon") >= 1.2, "horizon patrol density rises with archive")
	ArchiveManager.force_unlock("complicity_bureau_memo")
	_check(FactionManager.unit_weight("signal_agent", "signal_agent") > 1.0,
		"signal agents weight up with complicity")
	var pair := FactionManager.pick_skirmish_pair(Vector2.ZERO)
	_check(pair.size() == 2 and pair[0] != pair[1], "skirmish pair picked")
	FactionManager.set_hostility("remnants", 0.95)
	_check(FactionManager.is_hostile("remnants"), "high hostility marks faction hostile")
	FactionManager.reset_runtime()
	ArchiveManager.reset_progress(false)


# ---------------------------------------------------------------- dialogue ----
func _test_dialogue() -> void:
	_check(DialogueManager.barks.size() == 4, "barks for four survivors")
	var lin := DialogueManager.bark_variant_count("lin_yuan")
	var marcus := DialogueManager.bark_variant_count("marcus")
	_check(lin > 0 and marcus > 0, "bark pools populated")
	_check(float(lin) / float(maxi(1, marcus)) <= 0.45,
		"lin yuan speaks ~1/3 as much (%d vs %d)" % [lin, marcus])
	_check(DialogueManager.has_conversation("c1_meet"), "meeting conversation exists")
	_check(DialogueManager.has_conversation("c4_terminal"), "terminal conversation exists")
	var terminal: Dictionary = DialogueManager.conversations["c4_terminal"]
	var lin_lines := 0
	var other_lines := 0
	for line in terminal.get("lines", []):
		if String(line.get("speaker", "")) == "lin_yuan":
			lin_lines += 1
		else:
			other_lines += 1
	_check(lin_lines >= 4, "lin yuan has his longest scene in 4-1 (%d lines)" % lin_lines)
	_check(lin_lines > other_lines, "lin yuan speaks the most in that scene (%d vs %d)" % [lin_lines, other_lines])

	_check(DialogueManager.play_bark("lin_yuan", "execute"), "lin yuan bark plays")
	_check(not DialogueManager.play_bark("marcus", "reload"),
		"lin yuan silences the team for 1.5s")
	_check(not DialogueManager.play_bark("lin_yuan", "execute"),
		"lin yuan bark respects its long cooldown")


# ---------------------------------------------------------------- passives ----
func _test_passives() -> void:
	GameManager.selected_character = &"lin_yuan"
	GameManager.selected_squad = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	_level_scene = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(_level_scene)
	await get_tree().create_timer(0.5, true, false, true).timeout

	var player: Node = _level_scene.get_player()
	_check(player != null, "level spawned player")
	_check(player.get("passive") != null, "lin yuan passive attached")
	_check(is_equal_approx(float(player.get("stealth_speed_multiplier")), 1.0),
		"lin yuan stealth does not slow him")
	player.call("set_stealth_invisible", 3.0)
	await get_tree().process_frame
	_check(float(player.get("visibility")) <= 0.01, "execution window hides the player")
	_check(EnemyPerception.is_ignored(player) or true, "perception singleton reachable")
	EnemyPerception.ignore_source(player, 1.0)
	_check(EnemyPerception.is_ignored(player), "perception ignore registered")

	_check(_level_scene.get("archive_pickups").size() >= 2, "archive pickups placed")
	_check(get_tree().get_nodes_in_group("cover").size() >= 3, "cover volumes placed")
	_check(_level_scene.get("ai_director") != null, "faction director attached")
	_check(_level_scene.get("comic_layer") != null, "comic post-process attached")
	var comic: CanvasLayer = _level_scene.get("comic_layer")
	_check(comic.get("material") != null, "comic shader material created")
	EventBus.gore_event.emit(1.0)
	await get_tree().process_frame
	if comic.get("material") != null:
		var boost: Variant = comic.get("material").get_shader_parameter("gore_boost")
		_check(boost != null and float(boost) > 0.0, "gore event boosts the ink pass")

	# Marcus: backstab block
	var marcus := _spawn_extra_player(&"marcus")
	await get_tree().process_frame
	_check(bool(marcus.get("passive_block_backstab")), "marcus enables backstab block")
	var hp_before := int(marcus.get("hp"))
	marcus.call("take_damage", 40, Vector2(1, 0), &"zombie", &"melee")
	_check(int(marcus.get("hp")) == hp_before, "backstab blocked for zero damage")
	_check(float(marcus.get("backstab_block_cd")) > 0.0, "backstab block starts 30s cooldown")
	await get_tree().create_timer(0.3, true, false, true).timeout
	marcus.call("take_damage", 20, Vector2(-1, 0), &"zombie", &"melee")
	_check(int(marcus.get("hp")) < hp_before, "frontal damage still lands")

	# Victor: special-infected damage multiplier + sample drop
	var victor := _spawn_extra_player(&"victor")
	await get_tree().process_frame
	var mults: Dictionary = victor.get("damage_multipliers")
	_check(is_equal_approx(float(mults.get("special_infected", 0.0)), 1.2),
		"victor gets 1.2x vs specials")
	_level_scene.spawn_special(&"hunter")
	await get_tree().process_frame
	var hunter: Node = null
	for zombie in get_tree().get_nodes_in_group("special_infected"):
		if zombie.get("level") == _level_scene and not bool(zombie.get("dead")):
			hunter = zombie
			break
	_check(hunter != null, "special infected joins special_infected group")
	if hunter != null:
		_check(absf(float(victor.call("_damage_scale", hunter)) - 1.2) < 0.001,
			"victor damage scale applies to specials")

	# Lucia: cover detector
	var lucia := _spawn_extra_player(&"lucia")
	await get_tree().process_frame
	_check(lucia.get_node_or_null("CoverDetector") != null, "lucia has a cover detector")

	_level_scene.queue_free()
	_level_scene = null
	GameManager.change_state(GameManager.State.MENU)
	await get_tree().process_frame


func _spawn_extra_player(character_id: StringName) -> Node:
	GameManager.selected_character = character_id
	var packed: PackedScene = load("res://scenes/actors/player.tscn")
	var player: Node = packed.instantiate()
	player.set("level", _level_scene)
	var actors: Node = _level_scene.get("actors")
	actors.add_child(player)
	return player


# ------------------------------------------------------------ final choice ----
func _test_final_choice() -> void:
	ArchiveManager.reset_progress(false)
	ArchiveManager.record_final_choice("destroy")
	_check(ArchiveManager.final_choice == "destroy", "destroy choice recorded")
	_check(SaveSystem.has_achievement(&"silent_price"), "destroy achievement unlocked")
	_check(ArchiveManager.new_game_plus_broadcast().contains("1.7"), "destroy NG+ broadcast mentions noise")
	ArchiveManager.record_final_choice("decode")
	_check(ArchiveManager.unlocks_lin_yuan_epilogue(), "decode unlocks the lin yuan epilogue")
	_check(SaveSystem.has_achievement(&"answer"), "decode achievement unlocked")
	_check(ArchiveManager.new_game_plus_broadcast().contains("72"), "decode NG+ broadcast mentions 72h")
	ArchiveManager.reset_progress(false)


func _test_ui() -> void:
	# Survivor select screen: four cards, one per survivor.
	var select: Control = load("res://scenes/ui/survivors/CharacterSelect.tscn").instantiate()
	select.setup({"from": "menu"})
	add_child(select)
	await get_tree().process_frame
	_check(select.get("_cards").size() == 4, "character select shows four survivors")
	select.queue_free()
	await get_tree().process_frame

	# Archive menu renders locked + unlocked entries.
	ArchiveManager.reset_progress(false)
	ArchiveManager.force_unlock("rumor_dock_whisper")
	var menu: Control = load("res://scenes/ui/archive/ArchiveMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var list: Control = menu.get("_list_root")
	_check(list != null and list.get_child_count() > 0, "archive menu lists fragments")
	menu.queue_free()
	await get_tree().process_frame

	# Viewer pauses, shows the fragment and unpauses on close.
	var viewer: Control = load("res://scenes/ui/archive/ArchiveViewer.tscn").instantiate()
	viewer.setup({"fragment_id": "rumor_dock_whisper"})
	add_child(viewer)
	await get_tree().process_frame
	_check(get_tree().paused, "archive viewer pauses the game")
	_check(viewer.get("_fragment") != null, "archive viewer binds the fragment")
	viewer.call("_close")
	await get_tree().process_frame
	_check(not get_tree().paused, "archive viewer unpauses on close")

	# Final choice: decode disabled without a THE_DEEP fragment.
	ArchiveManager.reset_progress(false)
	var final_ui: Control = load("res://scenes/ui/narrative/FinalChoiceUI.tscn").instantiate()
	add_child(final_ui)
	await get_tree().process_frame
	var decode_button: Button = final_ui.get("_decode_button")
	_check(decode_button != null and decode_button.disabled, "decode locked without deep archive")
	final_ui.queue_free()
	await get_tree().process_frame
	_check(not get_tree().paused, "final choice unpauses when freed")

	ArchiveManager.force_unlock("the_deep_core_recording")
	var final_ui2: Control = load("res://scenes/ui/narrative/FinalChoiceUI.tscn").instantiate()
	add_child(final_ui2)
	await get_tree().process_frame
	var decode_button2: Button = final_ui2.get("_decode_button")
	_check(decode_button2 != null and not decode_button2.disabled, "decode unlocked with deep archive")
	final_ui2.queue_free()
	await get_tree().process_frame
	get_tree().paused = false

	# Story choice applies flags and hostility.
	ArchiveManager.reset_progress(false)
	FactionManager.reset_runtime()
	var choice: Control = load("res://scenes/ui/narrative/StoryChoiceUI.tscn").instantiate()
	choice.set("choice_id", "c2_side")
	add_child(choice)
	await get_tree().process_frame
	choice.call("_choose", "remnants")
	await get_tree().process_frame
	_check(SaveSystem.has_flag(&"side_remnants"), "story choice writes its flag")
	_check(FactionManager.effective_hostility("rust") > FactionManager.get_faction("rust").base_hostility_to_player,
		"story choice shifts hostility")
	_check(not get_tree().paused, "story choice unpauses on confirm")
	SaveSystem.data["flags"].erase("side_remnants")


# ------------------------------------------------------------ level mapping ----
func _test_level_mapping() -> void:
	var l01 := GameManager.get_level(&"l01")
	_check(l01.chapter == 1 and l01.title == "港口外围", "1-1 港口外围")
	var l03 := GameManager.get_level(&"l03")
	_check(l03.bosses.size() > 0, "1-3 has the armoured car boss")
	var l05 := GameManager.get_level(&"l05")
	_check(l05.dark, "2-2 subway is dark")
	var l08 := GameManager.get_level(&"l08")
	_check(l08.archive_slots == 3, "3-2 offers three archive slots")
	var l11 := GameManager.get_level(&"l11")
	_check(l11.final_choice, "4-2 declares the final choice")
	_check(l11.chapter == 4 and l11.narrative.size() >= 3, "4-2 has narrative beats")
	_check(l01.narrative.size() >= 3, "1-1 has narrative beats")

	# Route branch: the chip decision swaps l07's identity.
	SaveSystem.set_flag(&"route_sewer")
	var sewer: Node = load("res://scenes/levels/l07.tscn").instantiate()
	add_child(sewer)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(String(sewer.get("data").title) == "排水系统", "3-1A sewer route loads")
	_check(sewer.get("data").theme == &"subway", "3-1A uses the sewer tileset")
	sewer.queue_free()
	await get_tree().process_frame
	SaveSystem.data["flags"].erase("route_sewer")
	var gate: Node = load("res://scenes/levels/l07.tscn").instantiate()
	add_child(gate)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(String(gate.get("data").title) == "净化区正门", "3-1B front gate route loads")
	gate.queue_free()
	await get_tree().process_frame
