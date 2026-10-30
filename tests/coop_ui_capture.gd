extends Node
## Captures the new online co-op UI and the base menu from a real render.

const OUT := "res://docs/evidence/v3.2.0"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _snap("00_main_menu")
	menu.call("_open_multiplayer_panel")
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _snap("01_main_menu_coop")
	menu.call("_close_multiplayer_panel")
	await get_tree().create_timer(0.2, true, false, true).timeout
	print("COOP UI CAPTURE DONE")
	get_tree().quit(0)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
	image.save_png(path)
	print("[COOP UI SHOT] %s %dx%d" % [name, image.get_width(), image.get_height()])
