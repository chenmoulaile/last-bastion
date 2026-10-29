class_name TracerEffect
extends Node2D
## Pooled bullet tracer: draws a short bright streak between two points,
## fades out over 0.08s, then returns to the pool.

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var life: float = 0.08
var age: float = 0.0
var color: Color = Color(1.0, 0.4, 0.1, 1.0)
var width: float = 2.0

func _init(from: Vector2 = Vector2.ZERO, to: Vector2 = Vector2.ZERO,
		c: Color = Color(1.0, 0.4, 0.1, 1.0)) -> void:
	start_pos = from
	end_pos = to
	color = c

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		_pool_release()
		return
	var a := clampf(1.0 - age / life, 0.0, 1.0)
	modulate = Color(color.r, color.g, color.b, a)

func _draw() -> void:
	if age >= life:
		return
	draw_line(start_pos, end_pos, Color(color.r, color.g, color.b, modulate.a), width)

func _pool_release() -> void:
	age = life
	queue_free()

func reset(from: Vector2, to: Vector2, c: Color) -> void:
	start_pos = from
	end_pos = to
	color = c
	age = 0.0
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
