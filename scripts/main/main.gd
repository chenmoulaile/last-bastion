extends Node
## Main - application shell and screen router. Gameplay and menus are separate
## views; GameManager owns progression state, Main only swaps what is on screen.

const SCREENS := {
	&"menu": "res://scenes/ui/main_menu.tscn",
	&"loading": "res://scenes/ui/loading_screen.tscn",
	&"levels": "res://scenes/ui/level_select.tscn",
	&"briefing": "res://scenes/ui/briefing.tscn",
	&"characters": "res://scenes/ui/character_select.tscn",
	&"survivors": "res://scenes/ui/survivors/CharacterSelect.tscn",
	&"archives": "res://scenes/ui/archive/ArchiveMenu.tscn",
	&"settings": "res://scenes/ui/settings.tscn",
	&"achievements": "res://scenes/ui/achievements.tscn",
	&"codex": "res://scenes/ui/codex.tscn",
	&"result": "res://scenes/ui/result.tscn",
	&"credits": "res://scenes/ui/credits.tscn",
}

var current_view: Node = null
var _fade_rect: ColorRect
var _fade_layer: CanvasLayer
var _flow_token: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fade()
	EventBus.start_level_requested.connect(_on_start_level_requested)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.level_failed.connect(_on_level_failed)
	EventBus.return_to_menu_requested.connect(_on_return_to_menu)
	call_deferred("_boot")


func _boot() -> void:
	AudioManager.play_menu_music()
	_show_screen(&"menu")


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 90
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.015, 0.02, 0.025, 0.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _swap_view(view: Node) -> void:
	_flow_token += 1
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
	current_view = view
	add_child(view)
	_fade_rect.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.22)


func _show_screen(screen: StringName, payload: Dictionary = {}) -> void:
	if not SCREENS.has(screen):
		push_error("Unknown screen: " + String(screen))
		return
	var packed: PackedScene = load(SCREENS[screen])
	if packed == null:
		push_error("Missing screen scene: " + String(SCREENS[screen]))
		return
	var instance := packed.instantiate()
	if instance.has_method("setup"):
		instance.setup(payload)
	if instance.has_signal("navigate"):
		instance.navigate.connect(_on_navigate)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_swap_view(instance)


func _on_navigate(target: StringName, payload: Dictionary = {}) -> void:
	match target:
		&"menu":
			_show_menu()
		&"levels":
			_show_screen(&"levels", payload)
		&"briefing":
			_show_screen(&"briefing", payload)
		&"characters":
			_show_screen(&"characters", payload)
		&"survivors":
			_show_screen(&"survivors", payload)
		&"archives":
			_show_screen(&"archives", payload)
		&"settings":
			_show_screen(&"settings")
		&"achievements":
			_show_screen(&"achievements")
		&"codex":
			_show_screen(&"codex")
		&"credits":
			_show_screen(&"credits")
		&"result":
			_show_screen(&"result")
		&"retry":
			EventBus.retry_level_requested.emit()
		&"next":
			EventBus.next_level_requested.emit()
		&"quit":
			get_tree().quit()
		_:
			push_warning("Unhandled navigation: " + String(target))


func _show_menu() -> void:
	if GameManager.state == GameManager.State.PLAYING or GameManager.state == GameManager.State.PAUSED:
		GameManager.return_to_menu()
	AudioManager.play_menu_music()
	_show_screen(&"menu")


func _on_start_level_requested() -> void:
	var level_id := String(GameManager.current_level_id)
	var path := "res://scenes/levels/%s.tscn" % level_id
	if not ResourceLoader.exists(path):
		push_error("Missing level scene: " + path)
		return
	# Show loading screen and load asynchronously
	_fade_rect.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.22)
	var level_packed: PackedScene = load(SCREENS[&"loading"])
	var loader := level_packed.instantiate()
	if loader.has_method("setup"):
		loader.setup(level_id, path)
	loader.loading_complete.connect(_on_loading_complete)
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
	current_view = loader
	add_child(loader)
	AudioManager.play_ambience(&"wind")
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


var _loading_token: int = 0
var _loaded_level: Node = null


func _on_loading_complete(level_id: StringName) -> void:
	var path := "res://scenes/levels/%s.tscn" % level_id
	var packed: PackedScene = ResourceLoader.load(path)
	if packed == null:
		push_error("Failed to load level: " + path)
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	var level := packed.instantiate()
	current_view.queue_free()
	current_view = level
	add_child(level)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _on_level_completed(_score: int, rank: String) -> void:
	AudioManager.play_result_sting(rank)
	var token := _flow_token
	await get_tree().create_timer(0.55, true, false, true).timeout
	if token != _flow_token:
		return
	_show_screen(&"result")


func _on_level_failed(_reason: String) -> void:
	AudioManager.play_result_sting("f")
	var token := _flow_token
	await get_tree().create_timer(0.45, true, false, true).timeout
	if token != _flow_token:
		return
	_show_screen(&"result")


func _on_return_to_menu() -> void:
	_show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		EventBus.debug_panel_toggled.emit()
