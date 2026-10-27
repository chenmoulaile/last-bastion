class_name PassiveLucia
extends PassiveAbility
## 露西亚 —「街头直觉」
##
## 进入掩体（group="cover" 的 Area2D）范围时，把半径内所有感染者标记为
## 穿墙显形 3 秒。掩体检测用独立的 Area2D 子节点，避免影响玩家的物理碰撞。

const DETECT_RADIUS := 30.0
const REVEAL_RADIUS := 320.0
const REVEAL_TIME := 3.0
const COOLDOWN := 6.0

var _detector: Area2D = null
var _cooldown: float = 0.0


func _on_activate() -> void:
	if player == null:
		return
	_build_detector()


func _on_deactivate() -> void:
	if _detector != null and is_instance_valid(_detector):
		if _detector.area_entered.is_connected(_on_area_entered):
			_detector.area_entered.disconnect(_on_area_entered)
		_detector.queue_free()
		_detector = null


func _build_detector() -> void:
	_detector = Area2D.new()
	_detector.name = "CoverDetector"
	_detector.collision_layer = 0
	_detector.collision_mask = 64 # INTERACTABLE layer hosts cover volumes
	_detector.monitoring = true
	_detector.monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = DETECT_RADIUS
	shape.shape = circle
	_detector.add_child(shape)
	player.add_child(_detector)
	_detector.area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


func _on_area_entered(area: Area2D) -> void:
	if area == null or not is_instance_valid(area):
		return
	if not area.is_in_group("cover"):
		return
	if _cooldown > 0.0 or player == null or not is_instance_valid(player):
		return
	_cooldown = COOLDOWN
	var count := EnemyPerception.reveal_enemies_in_radius(
		player.global_position, REVEAL_RADIUS, REVEAL_TIME)
	if count > 0:
		EventBus.notify.emit("街头直觉 · %d 个目标显形" % count)
		AudioManager.play_sfx(&"ui_click")
		DialogueManager.play_bark("lucia", "reveal")
