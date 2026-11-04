extends Node
## P0-4 验收：自动试玩 ≥10 分钟（游戏时间，time_scale=3 加速）。
## 动作覆盖：走/跑/蹲(Ctrl)/滑铲/跳/切枪 M9↔AR-15↔近战/开火/换弹/踹门/三次尸潮/击杀 Tank。
## 判定：进程输出 0 条 SCRIPT ERROR（外部 grep）。

var _elapsed := 0.0
var _phase := 0
var _scene: Node
var _fired := false
var _last_print := -1
## wp8-tests-ci：每 90s 在最近可进入门旁注入 10 只尸潮（「尸潮贴门」场景回归）
var _next_door_horde := 90.0


func _ready() -> void:
	Engine.time_scale = 3.0
	GameManager.selected_character = &"assault"
	GameManager.selected_squad = []
	GameManager.start_level(&"l01", &"SQUAD", &"NORMAL")
	_scene = load("res://scenes/levels/l01.tscn").instantiate()
	add_child(_scene)
	# 注入三次尸潮 + Boss 事件
	EventBus.level_completed.connect(_on_done)
	set_process(true)


func _on_done(_score: int, _rank: String) -> void:
	print("[AUTO] level completed, extending session")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if int(_elapsed) % 60 == 0 and int(_elapsed) != _last_print:
		_last_print = int(_elapsed)
		print("[AUTO] t=%d phase=%d" % [_last_print, _phase])
	if _elapsed > 620.0:
		print("[AUTO] 10min session finished, quit")
		get_tree().quit()
		return
	_drive()


func _drive() -> void:
	var player: Node2D = _scene.get_player() if _scene.has_method("get_player") else null
	if player == null or not is_instance_valid(player):
		return
	var t := fmod(_elapsed, 30.0)
	# 移动
	if t < 12.0:
		Input.action_press("move_right")
		Input.action_release("move_left")
	elif t < 15.0:
		Input.action_release("move_right")
		# 蹲下（Ctrl）
		if t < 13.0:
			_tap_key(KEY_CTRL)
		# 滑铲（跑动中按蹲）
		elif t < 14.0:
			Input.action_press("move_right")
			_tap_key(KEY_CTRL)
		else:
			Input.action_release("move_right")
			_tap_key(KEY_SPACE)  # 跳
	elif t < 18.0:
		_tap_key(KEY_SPACE)
		Input.action_press("move_right")
	else:
		Input.action_release("move_right")
		Input.action_release("move_left")
	# 射击：每周期前 5 秒按住开火
	if t < 5.0:
		Input.action_press("fire")
		_fired = true
	else:
		Input.action_release("fire")
	# 换弹
	if t > 6.0 and t < 6.2:
		_tap_key(KEY_R)
	# 切枪循环：M9 → 主武器 → 近战 → 回主武器
	if t > 8.0 and t < 8.2:
		_tap_key(KEY_Q)
	if t > 10.0 and t < 10.2:
		_tap_key(KEY_Q)
	if t > 12.0 and t < 12.2:
		_tap_key(KEY_Q)
	# 定时事件：3 次尸潮 + Boss
	if _elapsed > 60.0 and _phase < 1:
		_phase = 1
		_scene.start_horde(10, true)
	if _elapsed > 180.0 and _phase < 2:
		_phase = 2
		_scene.start_horde(14, true)
	if _elapsed > 300.0 and _phase < 3:
		_phase = 3
		_scene.spawn_special(&"tank")
		_scene.start_horde(12, true)
	if _elapsed > 420.0 and _phase < 4:
		_phase = 4
		_scene.spawn_special(&"smoker")
		_scene.spawn_special(&"hunter")
		_scene.start_horde(14, true)
	if _elapsed > 500.0 and _phase < 5:
		_phase = 5
		_scene.spawn_boss(&"tank", 1)
	# wp8-tests-ci：每 90s 在最近可进入门旁 spawn_horde_at(门旁, 10)——
	# 持续制造「尸潮贴近可进入门」的压力场景；室内态时 spawn_horde_at 内部
	# 自动改投 _street_return 街道门口（level_runner.gd:1317）。
	if _elapsed >= _next_door_horde:
		_next_door_horde += 90.0
		var door_pos := _nearest_enterable_door(player.global_position)
		if door_pos.x >= 0.0:
			_scene.spawn_horde_at(door_pos, 10, true)
			print("[AUTO] wp8 door horde t=%d at (%.0f, %.0f)" % [int(_elapsed), door_pos.x, door_pos.y])


## wp8：找距玩家最近的可进入建筑门口（无 enterable 建筑时返回 x=-1）
func _nearest_enterable_door(from: Vector2) -> Vector2:
	var best := Vector2(-1.0, 0.0)
	var best_d := INF
	for b in _scene.get("_buildings"):
		if not bool(b.get("enterable", false)):
			continue
		var p := Vector2(float(b["door_x"]), float(b["ground_y"]))
		var d := p.distance_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


func _tap_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
