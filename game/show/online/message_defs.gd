class_name MessageDefs
extends RefCounted
## The eight quick messages (ARCHITECTURE section 48). Players never type text to each other: a message is an index into
## this table, sent as an integer (`NetProtocol.MSG_COUNT` = 8 on the server side too).
##
## The game font has no emoji, so the three emotes are drawn as neon icons (a laughing face, a surprised face, clapping
## hands) instead of font glyphs. Every message has a spoken name too, so an icon is never the only cue.

## BUBBLE is the picture on the quick-message button itself (not a message).
enum Icon { NONE, LAUGH, WOW, CLAP, BUBBLE }

const COUNT: int = 8
## [string key of the words or spoken name, icon]. Messages with an icon draw it instead of text.
const TABLE: Array = [
	["MSG_NICE_SHOT", Icon.NONE],
	["MSG_OOPS", Icon.NONE],
	["MSG_SO_CLOSE", Icon.NONE],
	["MSG_GG", Icon.NONE],
	["MSG_YOUR_TURN", Icon.NONE],
	["MSG_LAUGH", Icon.LAUGH],
	["MSG_WOW", Icon.WOW],
	["MSG_CLAP", Icon.CLAP],
]
## How long a bubble stays over a tank, and the least gap between two of my own messages.
const BUBBLE_SECONDS: float = 3.0
const COOLDOWN_SECONDS: float = 3.0


static func is_valid(msg: int) -> bool:
	return msg >= 0 and msg < COUNT


static func icon_of(msg: int) -> int:
	return (TABLE[msg] as Array)[1] as int if is_valid(msg) else Icon.NONE


## The words (or, for an emote, its spoken name), translated.
static func text_of(msg: int) -> String:
	return TranslationServer.translate((TABLE[msg] as Array)[0] as String) if is_valid(msg) else ""


static func has_icon(msg: int) -> bool:
	return icon_of(msg) != Icon.NONE


## Draws an emote icon centred at `c` with radius `r` on `ci` (a Control's _draw).
static func draw_icon(ci: CanvasItem, icon: int, c: Vector2, r: float, tint: Color = NeonPalette.WARN) -> void:
	var ink: Color = NeonPalette.BG_DEEP
	var w: float = maxf(1.5, r * 0.12)
	match icon:
		Icon.LAUGH:
			ci.draw_circle(c, r, Color(tint, 0.25))
			ci.draw_circle(c, r * 0.9, tint)
			# Eyes squeezed shut with joy: two small arcs.
			ci.draw_arc(c + Vector2(-r * 0.38, -r * 0.2), r * 0.2, PI * 1.1, PI * 1.9, 8, ink, w, true)
			ci.draw_arc(c + Vector2(r * 0.38, -r * 0.2), r * 0.2, PI * 1.1, PI * 1.9, 8, ink, w, true)
			# A wide open smile (a filled half disc) and a tear on each side.
			var mouth := PackedVector2Array()
			for i: int in range(9):
				var a: float = PI * float(i) / 8.0
				mouth.append(c + Vector2(cos(a) * r * 0.55, r * 0.12 + sin(a) * r * 0.5))
			ci.draw_colored_polygon(mouth, ink)
			ci.draw_circle(c + Vector2(-r * 0.78, r * 0.05), r * 0.13, NeonPalette.CYAN)
			ci.draw_circle(c + Vector2(r * 0.78, r * 0.05), r * 0.13, NeonPalette.CYAN)
		Icon.WOW:
			ci.draw_circle(c, r, Color(tint, 0.25))
			ci.draw_circle(c, r * 0.9, tint)
			ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.2), r * 0.13, ink)
			ci.draw_circle(c + Vector2(r * 0.34, -r * 0.2), r * 0.13, ink)
			ci.draw_arc(c + Vector2(-r * 0.34, -r * 0.45), r * 0.2, PI * 1.15, PI * 1.85, 6, ink, w, true)
			ci.draw_arc(c + Vector2(r * 0.34, -r * 0.45), r * 0.2, PI * 1.15, PI * 1.85, 6, ink, w, true)
			ci.draw_circle(c + Vector2(0.0, r * 0.4), r * 0.2, ink)
		Icon.BUBBLE:
			# A speech bubble with a tail and three dots.
			var body := PackedVector2Array()
			var rx: float = r * 0.95
			var ry: float = r * 0.62
			var cc: Vector2 = c + Vector2(0.0, -r * 0.1)
			for i: int in range(24):
				var a2: float = TAU * float(i) / 24.0
				body.append(cc + Vector2(cos(a2) * rx, sin(a2) * ry))
			ci.draw_colored_polygon(body, Color(tint, 0.22))
			ci.draw_polyline(body + PackedVector2Array([body[0]]), tint, w, true)
			var tail := PackedVector2Array([c + Vector2(-r * 0.35, r * 0.42), c + Vector2(-r * 0.6, r * 0.85), c + Vector2(-r * 0.05, r * 0.5)])
			ci.draw_colored_polygon(tail, tint)
			for k: int in range(3):
				ci.draw_circle(cc + Vector2((float(k) - 1.0) * r * 0.42, 0.0), r * 0.11, tint)
		Icon.CLAP:
			# Two hands meeting, with three lines of "sound" above them.
			for side: float in [-1.0, 1.0]:
				var hand := PackedVector2Array([
					c + Vector2(side * r * 0.05, r * 0.7), c + Vector2(side * r * 0.62, r * 0.38),
					c + Vector2(side * r * 0.78, -r * 0.15), c + Vector2(side * r * 0.5, -r * 0.2),
					c + Vector2(side * r * 0.2, -r * 0.05), c + Vector2(side * r * 0.05, -r * 0.25)])
				ci.draw_colored_polygon(hand, Color(tint, 0.9))
				ci.draw_polyline(hand + PackedVector2Array([hand[0]]), Color(ink, 0.8), w * 0.7, true)
			for k: int in range(3):
				var ang: float = -PI * 0.5 + (float(k) - 1.0) * 0.55
				var from: Vector2 = c + Vector2(0.0, -r * 0.3) + Vector2(cos(ang), sin(ang)) * r * 0.55
				var to: Vector2 = c + Vector2(0.0, -r * 0.3) + Vector2(cos(ang), sin(ang)) * r * 0.95
				ci.draw_line(from, to, NeonPalette.HOT, w, true)
