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
