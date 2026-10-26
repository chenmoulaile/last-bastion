class_name MathUtils
extends RefCounted


static func angle_vec(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle))


static func vec8(direction: Vector2) -> Vector2:
	if direction.length_squared() < 0.001:
		return Vector2.RIGHT
	var angle := direction.angle()
	var step := TAU / 8.0
	var snapped := roundi(angle / step) * step
	return Vector2(cos(snapped), sin(snapped))


static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var total := 0.0
	for key in weights:
		total += maxf(0.0, float(weights[key]))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total if rng else randf() * total
	for key in weights:
		roll -= maxf(0.0, float(weights[key]))
		if roll <= 0.0:
			return String(key)
	return String(weights.keys().back())


static func damage_falloff(distance: float, effective_range: float) -> float:
	if distance <= effective_range:
		return 1.0
	var over := distance - effective_range
	var loss := (over / 100.0) * 0.15
	return maxf(0.4, 1.0 - loss)


static func cone_hit(origin: Vector2, facing: int, target: Vector2, radius: float, arc_degrees: float) -> bool:
	var to_target := target - origin
	if to_target.length() > radius:
		return false
	if to_target.length_squared() < 1.0:
		return true
	var facing_vec := Vector2(float(facing), 0.0)
	return absf(rad_to_deg(facing_vec.angle_to(to_target))) <= arc_degrees * 0.5


static func format_score(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
