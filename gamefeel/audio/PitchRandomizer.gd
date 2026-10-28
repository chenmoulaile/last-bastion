class_name PitchRandomizer
extends RefCounted
## Small deterministic-free helper for pitch jitter. Kept separate so both the
## layered audio manager and future weapon code can share one policy.

static var _rng: RandomNumberGenerator = null


static func vary(pitch: float, fraction: float = 0.03) -> float:
	return pitch * (1.0 + _range(-fraction, fraction))


static func between(min_value: float, max_value: float) -> float:
	return _range(min_value, max_value)


static func _range(min_value: float, max_value: float) -> float:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng.randf_range(min_value, max_value)
