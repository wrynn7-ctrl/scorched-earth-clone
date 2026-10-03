class_name BattleFraming
extends RefCounted
## Pure helper: how the 1600x900 world is framed in the visible rectangle.
## The world always fits the screen *width*; taller screens show more sky above,
## and the world's bottom edge stays anchored to the bottom of the screen.

const WORLD_W: float = 1600.0
const WORLD_H: float = 900.0
## Never crop the world to less than this much height (very wide screens).
const MIN_VISIBLE_H: float = 640.0


## Returns {"zoom": float, "center": Vector2} for a Camera2D (anchor centre) given the
## visible rectangle size in canvas units (virtual px).
static func frame(visible_size: Vector2) -> Dictionary:
	var zoom: float = visible_size.x / WORLD_W
	var vis_h: float = visible_size.y / zoom
	if vis_h < MIN_VISIBLE_H:
		zoom = visible_size.y / MIN_VISIBLE_H
		vis_h = MIN_VISIBLE_H
	var vis_w: float = visible_size.x / zoom
	var center := Vector2(WORLD_W * 0.5, WORLD_H - vis_h * 0.5)
	# Keep the world horizontally centred when the screen is wider than the world.
	if vis_w > WORLD_W:
		center.x = WORLD_W * 0.5
	return {"zoom": zoom, "center": center}


## Smallest zoom the follow camera may reach: the whole world width just fits. (The rest
## framing is never below it, so on most screens it equals the rest zoom and the follow
## camera pans instead of zooming.)
static func min_zoom(visible_size: Vector2) -> float:
	return minf(visible_size.x / WORLD_W, float(frame(visible_size)["zoom"]))


## The world rectangle a Camera2D with this zoom and centre shows.
static func visible_rect(visible_size: Vector2, zoom: float, center: Vector2) -> Rect2:
	var size: Vector2 = visible_size / maxf(zoom, 0.0001)
	return Rect2(center - size * 0.5, size)
