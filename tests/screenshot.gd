extends Node
## Renders representative screens to build/screens for visual review.
## Run non-headless: Godot --path . res://tests/screenshot.tscn

const OUT := "res://build/screens"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await get_tree().process_frame
	await _capture_screens()
	await _capture_narrative_ui()
	await _capture_archive()
	await _capture_level("res://scenes/levels/l01.tscn", &"SQUAD", "gameplay_l01")
	await _capture_level("res://scenes/levels/l07.tscn", &"COMMAND", "gameplay_l07")
	await _capture_result()
	print("[SHOTS] done")
	get_tree().quit()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
	print("[SHOTS] " + name)


func _capture_screens() -> void:
	var screens := [
		["res://scenes/ui/main_menu.tscn", {}, "main_menu"],
		["res://scenes/ui/level_select.tscn", {"level_id": "l01"}, "level_select"],
		["res://scenes/ui/character_select.tscn", {"from": "levels"}, "character_select"],
		["res://scenes/ui/survivors/CharacterSelect.tscn", {"from": "menu"}, "survivor_select"],
		["res://scenes/ui/archive/ArchiveMenu.tscn", {}, "archive_menu"],
		["res://scenes/ui/settings.tscn", {}, "settings"],
		["res://scenes/ui/achievements.tscn", {}, "achievements"],
		["res://scenes/ui/codex.tscn", {}, "codex"],
		["res://scenes/ui/briefing.tscn", {"level_id": "l01", "mode": "SQUAD", "difficulty": "NORMAL"}, "briefing"],
		["res://scenes/ui/credits.tscn", {}, "credits"],
	]
	for row in screens:
		var inst = load(row[0]).instantiate()
		if inst.has_method("setup"):
			inst.setup(row[1])
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.12, true, false, true).timeout
		await _snap(row[2])
		inst.queue_free()
		await get_tree().process_frame


func _capture_level(path: String, mode: StringName, shot: String) -> void:
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.selected_soldiers = []
	GameManager.start_level(StringName(path.get_file().get_basename()), mode, &"NORMAL")
	var scene: Node = load(path).instantiate()
	add_child(scene)
	await get_tree().create_timer(1.1, true, false, true).timeout
	await _snap(shot + "_start")

	var player: Node2D = scene.get_player()
	Input.action_press("move_right")
	await get_tree().create_timer(1.2, true, false, true).timeout
	Input.action_release("move_right")
	scene.spawn_horde_at(player.global_position + Vector2(170, -20), 10, true)
	scene.spawn_special(&"hunter")
	scene.spawn_special(&"smoker")
	await get_tree().create_timer(1.0, true, false, true).timeout
	Input.action_press("fire")
	await get_tree().create_timer(0.22, true, false, true).timeout
	await _snap(shot + "_combat")
	Input.action_release("fire")
	await get_tree().create_timer(0.25, true, false, true).timeout
	await _snap(shot + "_hud")

	if mode == &"COMMAND":
		scene.call("_cycle_formation")
		EventBus.debug_panel_toggled.emit()
		EventBus.debug_vision_toggled.emit()
		await get_tree().create_timer(0.35, true, false, true).timeout
		await _snap(shot + "_debug")
		EventBus.debug_vision_toggled.emit()
		EventBus.debug_panel_toggled.emit()
		await get_tree().create_timer(0.1, true, false, true).timeout

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.change_state(GameManager.State.MENU)


func _capture_result() -> void:
	GameManager.last_result = {
		"failed": false, "score": 248600, "rank": "S", "time": 318.0,
		"kills": 186, "headshots": 47, "specials": 11, "rescues": 3,
		"max_combo": 42, "squad_alive": 4, "soldiers_start": 0, "soldiers_lost": 0,
		"doors_kicked": 7, "hunter_interrupts": 2, "witch_crowns": 1,
		"barrel_kills": 8, "molotov_kills": 6, "tanks_killed": 2,
		"witch_woken": true, "hidden_rooms": ["l01_hidden"], "codex": ["hunter", "smoker"],
		"level_id": "l01", "level_title": "街道突破口", "mode": "SQUAD",
		"difficulty": "NORMAL", "new_achievements": ["first_blood", "combo_50"],
	}
	var result = load("res://scenes/ui/result.tscn").instantiate()
	if result.has_method("setup"):
		result.setup({})
	add_child(result)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _snap("result")
	result.queue_free()


## Narrative UI screens (v2.0): final choice, mid-campaign choice, archive reader.
func _capture_narrative_ui() -> void:
	var final_ui = load("res://scenes/ui/narrative/FinalChoiceUI.tscn").instantiate()
	add_child(final_ui)
	await get_tree().process_frame
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _snap("final_choice")
	final_ui.queue_free()
	await get_tree().process_frame

	var story = load("res://scenes/ui/narrative/StoryChoiceUI.tscn").instantiate()
	story.set("choice_id", "c2_side")
	add_child(story)
	await get_tree().process_frame
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _snap("story_choice")
	story.queue_free()
	await get_tree().process_frame
	get_tree().paused = false

	var viewer = load("res://scenes/ui/archive/ArchiveViewer.tscn").instantiate()
	viewer.setup({"fragment_id": "the_deep_core_recording"})
	add_child(viewer)
	await get_tree().process_frame
	await get_tree().create_timer(0.12, true, false, true).timeout
	await _snap("archive_viewer")
	viewer.call("_close")
	await get_tree().process_frame
	get_tree().paused = false


## Walk the player next to the first archive pickup to verify its in-world look.
func _capture_archive() -> void:
	GameManager.selected_character = &"lin_yuan"
	GameManager.selected_squad = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	var scene: Node = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(scene)
	await get_tree().create_timer(0.9, true, false, true).timeout
	var player: Node2D = scene.get_player()
	var pickups: Array = scene.get("archive_pickups")
	if player != null and not pickups.is_empty():
		player.global_position = pickups[0].global_position + Vector2(-30, 0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _snap("gameplay_archive")
	DialogueManager.play_conversation("c1_meet")
	await get_tree().create_timer(1.0, true, false, true).timeout
	await _snap("gameplay_dialogue")
	scene.queue_free()
	await get_tree().process_frame
