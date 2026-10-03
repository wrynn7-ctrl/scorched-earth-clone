class_name HudFormat
extends RefCounted
## Pure text formatting helpers for the HUD readouts (no translation, numbers only).

const ANGLE_MAX: int = 1800
const POWER_MAX: int = 1000
const WIND_MAX: int = 100


## Which way the barrel leans, from the raw angle (0 = right, 900 = up, 1800 = left).
const FACING_RIGHT: int = 1
const FACING_UP: int = 0
const FACING_LEFT: int = -1


## Side of the screen the barrel points to: FACING_RIGHT below 90.0, FACING_LEFT above, else FACING_UP.
@warning_ignore("integer_division")
static func facing_of(raw_tenths: int) -> int:
	var t: int = clampi(raw_tenths, 0, ANGLE_MAX)
	if t < ANGLE_MAX / 2:
		return FACING_RIGHT
	return FACING_LEFT if t > ANGLE_MAX / 2 else FACING_UP


## Elevation above the horizon on the side the tank faces, in tenths: 450 -> 450, 1350 -> 450.
@warning_ignore("integer_division")
static func elevation_of(raw_tenths: int) -> int:
	var t: int = clampi(raw_tenths, 0, ANGLE_MAX)
	return t if t <= ANGLE_MAX / 2 else ANGLE_MAX - t


## Raw angle (tenths) -> elevation text: 452 -> "45.2°", 1348 -> "45.2°" (the facing is shown
## separately, see facing_of). One helper for every place that shows the angle.
@warning_ignore("integer_division")
static func format_angle(raw_tenths: int) -> String:
	var e: int = elevation_of(raw_tenths)
	return "%d.%d°" % [e / 10, e % 10]


static func power(p: int) -> String:
	return str(clampi(p, 0, POWER_MAX))


## Wind strength without sign (direction is shown by the arrow): -37 -> "37".
static func wind(w: int) -> String:
	return str(absi(clampi(w, -WIND_MAX, WIND_MAX)))


## 12500 -> "$12,500" (grouping is a number format, not translatable text).
static func money(n: int) -> String:
	return "$" + group(n)


## Signed credits for popups: 1500 -> "+$1,500", -300 -> "-$300".
static func money_delta(n: int) -> String:
	return ("+" if n >= 0 else "-") + "$" + group(absi(n))


## 1234567 -> "1,234,567".
static func group(n: int) -> String:
	var digits: String = str(absi(n))
	var out: String = ""
	for i: int in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if n < 0 else "") + out
