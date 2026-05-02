## VanNode.gd
## Procedurally drawn beat-up utility van for the start screen.
## Front of the van faces left (cab on the left, cargo area on the right).
## "Critter Quitters Pest Control" is painted in dark blue on the cargo panel.
##
## Call play_exit_animation() when the player taps Start Buggin'. The van
## accelerates left off screen while exhaust puffs billow from its rear.
## Emits exit_animation_finished when the van has fully cleared the screen.

class_name VanNode
extends Node2D

signal exit_animation_finished

const UIFonts = preload("res://ui/UIFonts.gd")

# --- Colours ---
const COLOR_BODY        := Color(0.93, 0.92, 0.88)        # weathered off-white
const COLOR_BODY_SHADOW := Color(0.80, 0.79, 0.75)        # underside stripe
const COLOR_OUTLINE     := Color(0.18, 0.18, 0.20)
const COLOR_GLASS       := Color(0.52, 0.66, 0.74, 0.85)  # windshield tint
const COLOR_WHEEL       := Color(0.14, 0.14, 0.15)
const COLOR_HUBCAP      := Color(0.70, 0.70, 0.74)
const COLOR_BUMPER      := Color(0.28, 0.28, 0.30)
const COLOR_RUST        := Color(0.68, 0.31, 0.08, 0.65)  # rust patches
const COLOR_PAINT       := Color(0.10, 0.25, 0.52, 0.90)  # painted company lettering

# --- Proportions (local coordinates, origin at centre of the body panel) ---
# Negative X is the front (cab/hood), positive X is the rear.
const BODY_W        := 560.0  # total body width
const BODY_H        := 200.0  # body height (±100 from origin)
const CAB_W         := 160.0  # how far back the cab section extends from the front
const CAB_LIFT      :=  20.0  # extra height the cab roof adds above the cargo roof
const WHEEL_R       :=  52.0  # tyre radius
const WHEEL_Y       := 122.0  # wheel centre Y relative to van origin (partially overlaps body)
const WHEEL_FRONT_X := -160.0
const WHEEL_REAR_X  :=  185.0

var _font: Font


func _ready() -> void:
	# Bebas Neue is bold and condensed — appropriate for van-side signage.
	_font = UIFonts.header()


func _draw() -> void:
	# Draw order matters: wheels first so the body sits on top of them.
	_draw_wheels()
	_draw_body()
	_draw_windshield()
	_draw_bottom_shadow()
	_draw_beat_up_details()
	_draw_company_panel()
	_draw_outlines()


func _draw_wheels() -> void:
	for wx: float in [WHEEL_FRONT_X, WHEEL_REAR_X]:
		var centre := Vector2(wx, WHEEL_Y)
		draw_circle(centre, WHEEL_R, COLOR_WHEEL)
		draw_circle(centre, WHEEL_R * 0.35, COLOR_HUBCAP)
		# Five lug marks around the hubcap.
		for i: int in 5:
			var angle := i * TAU / 5.0
			var lug := centre + Vector2(cos(angle), sin(angle)) * WHEEL_R * 0.60
			draw_circle(lug, 3.5, COLOR_OUTLINE)


func _draw_body() -> void:
	var hw       := BODY_W / 2.0
	var hh       := BODY_H / 2.0
	var cab_end  := -hw + CAB_W  # X where the cab section ends

	# One polygon covers the entire van silhouette: the taller cab on the left
	# and the lower cargo area on the right are joined in a single shape.
	var points := PackedVector2Array([
		Vector2(-hw,           hh),               # front bumper bottom
		Vector2(-hw,           -hh + 12.0),       # hood top
		Vector2(-hw + 50.0,    -hh - CAB_LIFT),   # A-pillar / windshield top
		Vector2(cab_end - 8.0, -hh - CAB_LIFT),   # cab roof rear
		Vector2(cab_end,       -hh),              # B-pillar step down to cargo roof
		Vector2(hw,            -hh),              # rear roof corner
		Vector2(hw,            hh),               # rear bottom
	])
	draw_colored_polygon(points, COLOR_BODY)

	# Dark cab interior visible through the windshield opening.
	var interior := PackedVector2Array([
		Vector2(-hw + 50.0,    -hh - CAB_LIFT),
		Vector2(cab_end - 8.0, -hh - CAB_LIFT),
		Vector2(cab_end - 8.0, -hh),
		Vector2(-hw + 50.0,    -hh),
	])
	draw_colored_polygon(interior, Color(0.25, 0.25, 0.30, 0.9))


func _draw_windshield() -> void:
	var hw := BODY_W / 2.0
	var hh := BODY_H / 2.0
	var ws := PackedVector2Array([
		Vector2(-hw,        -hh + 12.0),
		Vector2(-hw + 50.0, -hh - CAB_LIFT),
		Vector2(-hw + 50.0, -hh),
		Vector2(-hw,        -hh),
	])
	draw_colored_polygon(ws, COLOR_GLASS)
	# Diagonal glare streak to sell the glass look.
	draw_line(
		Vector2(-hw + 8.0,  -hh),
		Vector2(-hw + 38.0, -hh - CAB_LIFT + 5.0),
		Color(1.0, 1.0, 1.0, 0.28), 3.5, true
	)


func _draw_bottom_shadow() -> void:
	# A thin dark stripe along the lower edge of the cargo area adds depth and
	# visually separates the van floor from the background.
	var hw := BODY_W / 2.0
	var hh := BODY_H / 2.0
	draw_rect(Rect2(-hw + CAB_W, hh - 16.0, BODY_W - CAB_W, 16.0), COLOR_BODY_SHADOW)


func _draw_beat_up_details() -> void:
	# Rust cluster at the rear lower corner.
	draw_circle(Vector2(205.0, 60.0), 20.0, COLOR_RUST)
	draw_circle(Vector2(222.0, 44.0), 11.0, COLOR_RUST)
	draw_circle(Vector2(190.0, 75.0),  8.0, COLOR_RUST)

	# Smaller rust spot mid-panel.
	draw_circle(Vector2(-55.0, 72.0), 10.0, COLOR_RUST)

	# A dent: a lighter disc (pushed-in metal) with a faint highlight arc.
	draw_circle(Vector2(150.0, 15.0), 28.0, Color(0.88, 0.87, 0.84))
	draw_arc(Vector2(150.0, 15.0), 26.0,
			 deg_to_rad(190.0), deg_to_rad(340.0), 12,
			 Color(0.97, 0.97, 0.95, 0.7), 2.0)

	# Scratch marks.
	draw_line(Vector2(-15.0, -35.0), Vector2( 45.0, -10.0), Color(0.68, 0.68, 0.68, 0.55), 1.5)
	draw_line(Vector2( -5.0, -22.0), Vector2( 35.0,   3.0), Color(0.68, 0.68, 0.68, 0.40), 1.0)

	# Grime strip along the lower cargo sill.
	draw_rect(
		Rect2(-BODY_W / 2.0 + CAB_W + 5.0, 66.0, BODY_W - CAB_W - 40.0, 12.0),
		Color(0.76, 0.74, 0.68, 0.65)
	)

	# Front and rear bumpers.
	draw_rect(Rect2(-BODY_W / 2.0 - 6.0, 38.0, 10.0, 46.0), COLOR_BUMPER)
	draw_rect(Rect2( BODY_W / 2.0 - 4.0, 38.0, 10.0, 46.0), COLOR_BUMPER)


func _draw_company_panel() -> void:
	if _font == null:
		return

	# The sign occupies the cargo panel between the B-pillar and the rear.
	var panel_cx := 70.0   # horizontal centre of the sign in local space
	var panel_w  := 310.0  # available width for text

	# Thin painted border frames the sign panel.
	draw_rect(
		Rect2(panel_cx - panel_w / 2.0 - 6.0, -56.0, panel_w + 12.0, 106.0),
		Color(COLOR_PAINT, 0.22), false, 1.5
	)

	# "CRITTER QUITTERS" on the top line, larger.
	draw_string(
		_font,
		Vector2(panel_cx - panel_w / 2.0, -12.0),
		"CRITTER QUITTERS",
		HORIZONTAL_ALIGNMENT_CENTER, panel_w, 44,
		COLOR_PAINT
	)

	# "PEST CONTROL" on the bottom line, smaller.
	draw_string(
		_font,
		Vector2(panel_cx - panel_w / 2.0, 38.0),
		"PEST CONTROL",
		HORIZONTAL_ALIGNMENT_CENTER, panel_w, 30,
		COLOR_PAINT
	)


func _draw_outlines() -> void:
	var hw      := BODY_W / 2.0
	var hh      := BODY_H / 2.0
	var cab_end := -hw + CAB_W

	# Main silhouette — same path as the body fill polygon, drawn on top to seal the edges.
	var pts := PackedVector2Array([
		Vector2(-hw,           hh),
		Vector2(-hw,           -hh + 12.0),
		Vector2(-hw + 50.0,    -hh - CAB_LIFT),
		Vector2(cab_end - 8.0, -hh - CAB_LIFT),
		Vector2(cab_end,       -hh),
		Vector2(hw,            -hh),
		Vector2(hw,            hh),
	])
	draw_polyline(pts, COLOR_OUTLINE, 2.0, true)

	# B-pillar seam between cab and cargo.
	draw_line(Vector2(cab_end, -hh), Vector2(cab_end, hh), COLOR_OUTLINE, 2.0)

	# Rear door seam.
	draw_line(Vector2(hw - 28.0, -hh), Vector2(hw - 28.0, hh), COLOR_OUTLINE, 1.5)

	# Wheel-arch arcs at the body bottom.
	for wx: float in [WHEEL_FRONT_X, WHEEL_REAR_X]:
		draw_arc(
			Vector2(wx, hh), WHEEL_R + 10.0,
			deg_to_rad(200.0), deg_to_rad(340.0),
			16, COLOR_OUTLINE, 2.5, true
		)


# --- Animation ---

# Triggers the van driving off screen to the left.
# Call this when the player taps Start Buggin'. Disable the buttons before calling.
func play_exit_animation() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	# Target is far enough left that the full van width clears the screen edge.
	var target_x := position.x - vw - BODY_W

	# Stagger exhaust puffs across the first two-thirds of the drive-off.
	_spawn_exhaust_puffs()
	get_tree().create_timer(0.35).timeout.connect(_spawn_exhaust_puffs)
	get_tree().create_timer(0.65).timeout.connect(_spawn_exhaust_puffs)

	var tween := create_tween()
	tween.tween_property(self, "position:x", target_x, 1.1) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func(): exit_animation_finished.emit())


func _spawn_exhaust_puffs() -> void:
	# Puffs are added to the parent (not to the van) so they stay in place
	# as the van moves left, forming a trail of grey cloud behind it.
	var rear_x := position.x + BODY_W / 2.0
	for i: int in 2:
		var puff         := _ExhaustPuff.new()
		puff.position    =  Vector2(
			rear_x + randf_range(-25.0, 25.0),
			position.y + randf_range(-15.0, 30.0)
		)
		puff.max_radius  = randf_range(48.0, 78.0)
		puff.start_delay = i * 0.10
		get_parent().add_child(puff)


# One transient exhaust cloud puff. Expands from a small point, fades, then frees itself.
class _ExhaustPuff extends Node2D:
	var start_delay: float = 0.0
	var max_radius:  float = 65.0

	var _radius: float = 0.0
	var _alpha:  float = 0.0

	func _ready() -> void:
		var tween := create_tween()
		if start_delay > 0.0:
			tween.tween_interval(start_delay)
		tween.tween_method(_update, 0.0, 1.0, 0.6)
		tween.tween_callback(queue_free)

	func _update(t: float) -> void:
		_radius = lerp(10.0, max_radius, t)
		_alpha  = sin(t * PI)  # smooth bell: 0 at start, peak at midpoint, 0 at end
		queue_redraw()

	func _draw() -> void:
		if _alpha > 0.0:
			draw_circle(Vector2.ZERO, _radius, Color(0.65, 0.65, 0.65, _alpha * 0.65))
