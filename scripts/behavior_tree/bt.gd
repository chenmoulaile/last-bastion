class_name BT
extends RefCounted
## Tiny behaviour-tree framework (~200 lines) built specifically for this game.
## Nodes return true for success and false for failure/running-down-the-tree.

class BTNode:
	extends RefCounted

	func tick(_agent: Node, _delta: float) -> bool:
		return false


class Selector:
	extends BTNode
	var children: Array = []

	func _init(nodes: Array) -> void:
		children = nodes

	func tick(agent: Node, delta: float) -> bool:
		for child in children:
			if child.tick(agent, delta):
				return true
		return false


class Sequence:
	extends BTNode
	var children: Array = []

	func _init(nodes: Array) -> void:
		children = nodes

	func tick(agent: Node, delta: float) -> bool:
		for child in children:
			if not child.tick(agent, delta):
				return false
		return true


class Parallel:
	extends BTNode
	var children: Array = []

	func _init(nodes: Array) -> void:
		children = nodes

	func tick(agent: Node, delta: float) -> bool:
		var any_success := false
		for child in children:
			if child.tick(agent, delta):
				any_success = true
		return any_success


class Condition:
	extends BTNode
	var predicate: Callable

	func _init(fn: Callable) -> void:
		predicate = fn

	func tick(agent: Node, _delta: float) -> bool:
		return bool(predicate.call(agent))


class Action:
	extends BTNode
	var runner: Callable

	func _init(fn: Callable) -> void:
		runner = fn

	func tick(agent: Node, delta: float) -> bool:
		return bool(runner.call(agent, delta))


class Cooldown:
	extends BTNode
	var seconds: float
	var child: BTNode
	var remaining: float = 0.0

	func _init(duration: float, node: BTNode) -> void:
		seconds = duration
		child = node

	func tick(agent: Node, delta: float) -> bool:
		if remaining > 0.0:
			remaining -= delta
			return false
		if child.tick(agent, delta):
			remaining = seconds
			return true
		return false


class Invert:
	extends BTNode
	var child: BTNode

	func _init(node: BTNode) -> void:
		child = node

	func tick(agent: Node, delta: float) -> bool:
		return not child.tick(agent, delta)


static func selector(nodes: Array) -> Selector:
	return Selector.new(nodes)


static func sequence(nodes: Array) -> Sequence:
	return Sequence.new(nodes)


static func parallel(nodes: Array) -> Parallel:
	return Parallel.new(nodes)


static func cond(fn: Callable) -> Condition:
	return Condition.new(fn)


static func action(fn: Callable) -> Action:
	return Action.new(fn)


static func cooldown(seconds: float, node: BTNode) -> Cooldown:
	return Cooldown.new(seconds, node)


static func invert(node: BTNode) -> Invert:
	return Invert.new(node)
