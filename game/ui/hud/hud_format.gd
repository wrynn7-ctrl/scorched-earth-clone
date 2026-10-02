class_name HudFormat
extends RefCounted
## Pure text formatting helpers for the HUD readouts (no translation, numbers only).

const ANGLE_MAX: int = 1800
const POWER_MAX: int = 1000
const WIND_MAX: int = 100


## 452 -> "45.2°"
@warning_ignore("integer_division")
static func angle(tenths: int) -> String:
	var t: int = clampi(tenths, 0, ANGLE_MAX)
	return "%d.%d°" % [t / 10, t % 10]


static func power(p: int) -> String:
	return str(clampi(p, 0, POWER_MAX))


## Wind strength without sign (direction is shown by the arrow): -37 -> "37".
static func wind(w: int) -> String:
	return str(absi(clampi(w, -WIND_MAX, WIND_MAX)))
