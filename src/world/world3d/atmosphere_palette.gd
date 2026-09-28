class_name AtmospherePalette
extends RefCounted

## Pure presentation state from saved inputs. Never draw simulation randomness
## or maintain a second calendar that can drift after pause, speed or load.
static func sample(world_seed: int, day: int, fraction: float) -> Dictionary:
	var hour: float = clampf(fraction, 0.0, 1.0) * 24.0
	var absolute_hour: float = (day - 1) * 24.0 + hour
	var front: int = floori(absolute_hour / 4.0)
	var blend: float = smoothstep(0.0, 0.85, fposmod(absolute_hour, 4.0))
	var previous: Vector3 = _weather(world_seed, front - 1)
	var current: Vector3 = _weather(world_seed, front)
	var weather: Vector3 = previous.lerp(current, blend)
	var daylight: float = smoothstep(5.8, 9.0, hour) * (1.0 - smoothstep(17.5, 21.0, hour))
	var warmth: float = (1.0 - absf(daylight * 2.0 - 1.0)) * (1.0 - weather.x * 0.65)
	return {
		"hour": hour, "daylight": daylight, "warmth": warmth,
		"cloud": weather.x, "rain": weather.y, "wind": weather.z,
		"name": "Rain" if weather.y > 0.25 else ("Overcast" if weather.x > 0.5 else "Clear"),
	}


static func _weather(world_seed: int, front: int) -> Vector3:
	# A stable integer pattern provides clear, cloudy and rainy fronts. Each
	# transition spans 51 game minutes rather than snapping on the hour.
	var roll: int = posmod(world_seed * 37 + front * 73 + posmod(front, 11) * front * 19, 100)
	if roll < 40:
		return Vector3(0.08, 0.0, 0.18)
	if roll < 70:
		return Vector3(0.75, 0.0, 0.5)
	return Vector3(1.0, 1.0, 0.85)
