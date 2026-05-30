## StarBar.gd
## Draws a row of up to 3 five-pointed stars using draw_polygon().
## Completely font-independent: no Unicode glyphs, no font assets required.
## Drop-in replacement for Label-based ★★☆ upgrade-level indicators.
##
## Usage:
##   var bar := StarBar.new()
##   bar.set_level(2)   # shows 2 filled gold stars, 1 empty star

extends Control

## Gold — matches the star tint used on the in-world Label3D stars.
const COLOR_FILLED  := Color(0.85, 0.72, 0.10, 1.0)
## Dim gray — empty slot, still legible against any panel background.
const COLOR_EMPTY   := Color(0.35, 0.35, 0.38, 0.85)
## Near-black outline drawn around each star for legibility on light backgrounds.
const COLOR_OUTLINE := Color(0.08, 0.08, 0.08, 0.85)

## Always 3 slots (upgrade level 0–3).
const STAR_COUNT: int = 3

## Outer tip radius in virtual pixels.
const OUTER_R: float = 11.0

## Inner notch radius. The classic 5-pointed star proportion is ≈ 0.382 × outer,
## but 0.42 reads better at small sizes.
const INNER_R: float = 4.6

## Center-to-center horizontal spacing between stars.
const SPACING: float = 26.0

var _level: int = 0


func _ready() -> void:
	# Reserve enough width for 3 stars plus the outer margin on each side.
	custom_minimum_size = Vector2(
		OUTER_R + (STAR_COUNT - 1) * SPACING + OUTER_R,
		OUTER_R * 2.2
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets the number of filled (gold) stars and queues a redraw.
func set_level(n: int) -> void:
	_level = clampi(n, 0, STAR_COUNT)
	queue_redraw()


func _draw() -> void:
	var cy := size.y * 0.5
	for i in STAR_COUNT:
		var cx   := OUTER_R + i * SPACING
		var pts  := _star_verts(Vector2(cx, cy))
		var col  := COLOR_FILLED if i < _level else COLOR_EMPTY
		draw_polygon(pts, PackedColorArray([col]))
		# Thin closed outline — append first point so the polyline loops back.
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		draw_polyline(loop, COLOR_OUTLINE, 1.0, true)


## Returns the 10 boundary vertices of a 5-pointed star centered at `center`.
## Starts at the top tip, proceeds clockwise in 2D canvas space (Y-axis points down).
static func _star_verts(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		# -PI/2 starts at the top; positive angle direction is clockwise on a
		# canvas where Y increases downward.
		var angle := (i * PI / 5.0) - PI / 2.0
		var r     := OUTER_R if (i % 2 == 0) else INNER_R
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	return pts
