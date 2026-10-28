extends RoleStrategy
## ---------------------------------------------------------------------------
## 职责: 步枪手策略 —— 中距离均衡;优先点射最近目标(3 发点射 + 0.5s 间歇);
##       基础移速 ×1.0。全部使用 RoleStrategy 默认行为,仅定义点射节奏与
##       最近目标偏好,是四种策略的"基准实现"。
## 依赖: 无额外依赖。
## 对外接口: 覆写 burst_length / burst_pause / prefer_target。
## ---------------------------------------------------------------------------

const BURST: int = 3
const PAUSE: float = 0.5


func movement_speed_mult() -> float:
	return 1.0


func burst_length() -> int:
	return BURST


func burst_pause() -> float:
	return PAUSE


func prefer_target(candidates: Array) -> Node2D:
	## 优先最近目标(candidates 已由 CombatComponent 过滤为可视存活敌人)。
	if candidates.is_empty() or host == null:
		return null
	var origin: Vector2 = host.global_position
	var best: Node2D = null
	var best_dist := 1e9
	for candidate in candidates:
		var node := candidate as Node2D
		if node == null:
			continue
		var dist := origin.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best
