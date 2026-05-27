## ExperienceBar.gd
## XP progress bar pinned to the top of the arena zone.
##
## Layout:
##
##   ┌──────────────────────────────────────────────────────────────────┐
##   │ ●● ═══════════════════════════════════════░░░░░░░░░░   LVL 4   │
##   └──────────────────────────────────────────────────────────────────┘
##   ^bulb (always filled blue, with pulsing inner glow)
##       ^thin bar track (fills proportionally left-to-right)
##
## The silver border (RECT_BRD = 4px) is positioned flush with the arena's own
## top silver outline so they share pixels and read as one continuous band.
##
## The bulb is a filled ellipse (2:1 width-to-height) on the left end, always
## drawn in the XP fill colour so it acts as a permanent visual landmark — and
## a landing target for the blue XP particles that fly from enemy deaths.
##
## Visual effects applied to the filled portion:
##   Sheen:     A soft highlight panel sweeps left-to-right continuously,
##              giving the bar a glass-gem look (intentionally muted).
##   Sparkles:  Small bright flecks swirl within the fill (half-size, muted),
##              reinforcing a "charged energy" feel.
##   Bulb glow: A pulsing inner glow breathes on the elliptical bulb; rendered
##              as a radial gradient (opaque centre → transparent edge) via
##              concentric circles — no shader needed.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")
const HUD     = preload("res://ui/HUD.gd")


# ---------------------------------------------------------------------------
# Visual constants — PANEL_H and BULB_R are read externally (HUD, Arena)
# ---------------------------------------------------------------------------

## Total height of the control, including the silver border.
const PANEL_H: float = 44.0

## Silver border thickness on all four sides.
## Matches SILVER_BORDER_W in HUD.gd so the two outlines merge when offset_top = 0.
const RECT_BRD: float = 4.0

## Radius of the left-end bulb circle.
## Inner half-height = (PANEL_H - RECT_BRD*2) / 2 = 18. BULB_R = 14 leaves a 4 px
## gap on all sides between the drawn circle and the inner panel edges.
const BULB_R: float = 14.0

## Height of the thin bar track that extends to the right of the bulb.
const BAR_H: float = 14.0

## Left margin between the inner panel edge and the bulb centre.
## The ellipse's left edge sits at (inner_x + BULB_LEFT_MARGIN − BULB_R*2).
## With BULB_R=14 the h-radius is 28; using 36 gives an 8 px gap from the border.
const BULB_LEFT_MARGIN: float = 36.0   # bulb centre is this far from inner_x

## How many pixels the bar track overlaps the right edge of the bulb.
## A small overlap creates a seamless join without hiding the bulb.
const BAR_BULB_OVERLAP: float = 4.0

## The bar track ends at this fraction of the total panel width.
## The right remainder is reserved for the LVL N label.
const BAR_WIDTH_FRACTION: float = 0.86

## Pure electric blue — saturated, minimal green component, reads as "absolute" blue
## rather than the previous periwinkle-leaning tint (which was Color(0.18, 0.55, 1.0)).
const COLOR_FILL        := Color(0.05, 0.25, 1.0, 1.0)

## Silver — interior panel background and border colour.
## Matches HUD.COLOR_SILVER_BORDER so control border and arena outline merge.
const COLOR_OUTLINE     := Color(0.72, 0.72, 0.80, 1.0)

## Slightly darker silver — the unfilled portion of the bar track.
## Must contrast enough against COLOR_OUTLINE to read as a distinct inset trough.
const COLOR_TRACK_EMPTY := Color(0.44, 0.44, 0.50, 1.0)


# ---------------------------------------------------------------------------
# Sheen animation constants
# ---------------------------------------------------------------------------

## Seconds for one full sheen sweep from the left edge to the right edge of the fill.
const SHEEN_PERIOD  : float = 2.0

## Half-width of the sheen column in pixels; controls how wide the glow band is.
const SHEEN_HALF_W  : float = 35.0

## Number of vertical strip samples used to build the soft-edged sheen gradient.
## More steps = smoother appearance; 14 is a good balance for this bar height.
const SHEEN_STEPS   : int   = 14

## Peak colour of the sheen at its centre: bright ice-blue at 25% opacity (intentionally muted).
const COLOR_SHEEN   := Color(0.65, 0.88, 1.0, 0.25)


# ---------------------------------------------------------------------------
# Sparkle animation constants
# ---------------------------------------------------------------------------

## Maximum number of sparkle flecks alive at the same time (reduced for muted look).
const SPARKLE_MAX        : int   = 5

## Min/max lifetime of a single sparkle in seconds.
const SPARKLE_LIFE_MIN   : float = 0.35
const SPARKLE_LIFE_MAX   : float = 1.0

## Min/max radius of a single sparkle circle in pixels (half original size).
const SPARKLE_R_MIN      : float = 0.75
const SPARKLE_R_MAX      : float = 2.0

## Approximate number of new sparkles spawned per second while the bar has fill.
const SPARKLE_SPAWN_RATE : float = 4.0

## Peak colour of a sparkle — white-blue at 55% opacity (intentionally muted).
## The lifecycle alpha ramp (0→1→0) is multiplied by this constant's alpha component.
const COLOR_SPARKLE      := Color(0.85, 0.95, 1.0, 0.55)


# ---------------------------------------------------------------------------
# Bulb glow constants
# ---------------------------------------------------------------------------

## Seconds for one full pulse cycle of the bulb's inner glow ring.
const GLOW_PERIOD     : float = 1.4

## Colour of the bulb's inner glow at peak brightness (muted to 25% alpha).
## The radial gradient further modulates alpha, so the effective centre alpha
## at peak pulse is COLOR_BULB_GLOW.a * glow_alpha ≈ 0.25.
const COLOR_BULB_GLOW := Color(0.45, 0.75, 1.0, 0.25)

## Steps used to render the radial gradient on the bulb's inner glow.
## More steps = smoother falloff; 10 is sufficient for this circle size.
const GLOW_GRAD_STEPS : int   = 10


# ---------------------------------------------------------------------------
# Bulb-centre helpers
# Used by Arena.gd to aim XP particles at the bulb's screen position.
# ---------------------------------------------------------------------------

## Screen-space X coordinate of the bulb centre.
## Assumes HUD.gd positions the bar with offset_left = HUD.LEFT_PANEL_W.
static func bulb_screen_x() -> float:
	return HUD.LEFT_PANEL_W + RECT_BRD + BULB_LEFT_MARGIN

## Screen-space Y coordinate of the bulb centre.
static func bulb_screen_y() -> float:
	return PANEL_H * 0.5


# ---------------------------------------------------------------------------
# Child nodes
# ---------------------------------------------------------------------------

var _level_lbl: Label = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Current fill fraction for the bar track, 0.0–1.0. Animated by Tween.
var _current_fill_pct: float = 0.0
var _tween:            Tween = null
var _level:            int   = 0

## Phase angle (0.0–1.0) for the sweeping sheen. Advances continuously in _process().
var _sheen_pct: float = 0.0

## Phase angle (0.0–1.0) for the bulb glow pulse. Advances continuously in _process().
var _glow_pct: float = 0.0

## Active sparkle flecks. Each is a Dictionary:
##   pct         : float — base x position 0–1 across the fill width
##   drift       : float — slow x drift per second (fraction of fill width)
##   orbit_r     : float — y orbit amplitude in pixels (swirl radius)
##   angle       : float — initial swirl phase in radians
##   angular_vel : float — swirl rotation speed in radians per second
##   age         : float — elapsed lifetime in seconds
##   max_life    : float — total lifetime in seconds
##   radius      : float — drawn circle radius
var _sparkles: Array = []

## Fractional accumulator for spawning sparkles smoothly between frames.
var _spawn_accum: float = 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, PANEL_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PROCESS_MODE_ALWAYS so Tweens and animations run even while the LevelUpScreen
	# has the tree paused — otherwise the post-level-up bar reset never plays.
	process_mode = Node.PROCESS_MODE_ALWAYS

	resized.connect(queue_redraw)

	# Level label — right-aligned inside the bar, vertically centred.
	_level_lbl = Label.new()
	_level_lbl.text                  = "LVL 0"
	_level_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_level_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_level_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_level_lbl.add_theme_font_size_override("font_size", 22)   # large enough to visually fill the 44px panel
	# Black text — legible against the silver panel background.
	# No drop shadow needed; the high contrast between black and silver makes the
	# label stand out without it, and the shadow made it look embossed/cluttered.
	_level_lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
	_level_lbl.anchor_left   = 0.86
	_level_lbl.anchor_right  = 1.0
	_level_lbl.anchor_top    = 0.0
	_level_lbl.anchor_bottom = 1.0
	_level_lbl.offset_right  = -int(RECT_BRD) - 2
	add_child(_level_lbl)

	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_up.connect(_on_level_up)

	var needed := GameState.exp_for_next_level()
	_current_fill_pct = float(GameState.current_xp) / float(needed) if needed > 0 else 0.0
	_level = GameState.current_player_level
	_level_lbl.text = "LVL %d" % _level
	queue_redraw()


func _process(delta: float) -> void:
	# Advance the sheen sweep; wraps 0→1 each SHEEN_PERIOD seconds.
	_sheen_pct = fmod(_sheen_pct + delta / SHEEN_PERIOD, 1.0)

	# Advance the bulb glow pulse; wraps 0→1 each GLOW_PERIOD seconds.
	_glow_pct = fmod(_glow_pct + delta / GLOW_PERIOD, 1.0)

	# Age existing sparkles; remove any that have exceeded their lifetime.
	for i in range(_sparkles.size() - 1, -1, -1):
		_sparkles[i]["age"] += delta
		if _sparkles[i]["age"] >= _sparkles[i]["max_life"]:
			_sparkles.remove_at(i)

	# Spawn new sparkles into the filled region.
	# _spawn_accum accumulates fractional spawns so the rate stays consistent
	# regardless of frame duration.
	if _current_fill_pct > 0.01 and _sparkles.size() < SPARKLE_MAX:
		_spawn_accum += delta * SPARKLE_SPAWN_RATE
		while _spawn_accum >= 1.0 and _sparkles.size() < SPARKLE_MAX:
			_spawn_accum -= 1.0
			_spawn_sparkle()

	queue_redraw()


func _spawn_sparkle() -> void:
	# orbit_r is the amplitude of the y oscillation; capping at half_bar keeps
	# sparkles within the bar track's vertical extent.
	var half_bar := BAR_H * 0.5 - 2.0
	_sparkles.append({
		"pct":         randf(),                              # base x position (0–1 across fill)
		"drift":       randf_range(-0.04, 0.04),             # slow x drift per second
		"orbit_r":     randf_range(0.0, half_bar),           # y orbit amplitude in pixels
		"angle":       randf_range(0.0, TAU),                # initial swirl phase
		"angular_vel": randf_range(-TAU * 0.9, TAU * 0.9),  # swirl speed (rad/s)
		"age":         0.0,
		"max_life":    randf_range(SPARKLE_LIFE_MIN, SPARKLE_LIFE_MAX),
		"radius":      randf_range(SPARKLE_R_MIN, SPARKLE_R_MAX),
	})


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var brd     := RECT_BRD
	var inner_x := brd
	var bulb_cx := inner_x + BULB_LEFT_MARGIN
	var bulb_cy := h * 0.5

	# ── 1. Silver border + silver interior ───────────────────────────────────
	# Border and interior share the same colour so they merge into one band.
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_OUTLINE)

	# ── 2. Bulb — always filled blue (elliptical, 2:1 width-to-height) ─────────
	# Stretching x by 2.0 around the bulb centre makes draw_circle render as an ellipse.
	draw_set_transform(Vector2(bulb_cx, bulb_cy), 0.0, Vector2(2.0, 1.0))
	draw_circle(Vector2.ZERO, BULB_R, COLOR_FILL)

	# Pulsing inner glow: radial gradient, opaque at centre fading to transparent
	# at the edge.  Drawn outer-to-inner so each ring overwrites the centre of
	# the one before it, creating a smooth gradient without a shader.
	var glow_alpha  := 0.5 + 0.5 * sin(_glow_pct * TAU)   # 0.0–1.0 pulse cycle
	var glow_r_size := BULB_R * 0.65
	for step in range(GLOW_GRAD_STEPS, 0, -1):
		var t          := float(step) / float(GLOW_GRAD_STEPS)  # 1.0 = outermost ring
		var ring_r     := glow_r_size * t
		# Quadratic falloff: outer edge (t=1) is fully transparent;
		# centre (t→0) reaches peak brightness of COLOR_BULB_GLOW.a * glow_alpha.
		var ring_alpha := COLOR_BULB_GLOW.a * glow_alpha * (1.0 - t * t)
		var glow_step_c := Color(COLOR_BULB_GLOW.r, COLOR_BULB_GLOW.g, COLOR_BULB_GLOW.b,
				ring_alpha)
		draw_circle(Vector2.ZERO, ring_r, glow_step_c)

	# Reset the extra transform before drawing the track and all subsequent elements.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ── 3. Bar track ──────────────────────────────────────────────────────────
	# The ellipse's right edge is BULB_R*2 from the centre (x-scale = 2.0).
	var track_x := bulb_cx + BULB_R * 2.0 - BAR_BULB_OVERLAP
	var track_y := bulb_cy - BAR_H * 0.5
	var track_w := w * BAR_WIDTH_FRACTION - track_x
	if track_w <= 0.0:
		return
	draw_rect(Rect2(track_x, track_y, track_w, BAR_H), COLOR_TRACK_EMPTY)

	# Nothing more to draw if the bar is empty.
	if _current_fill_pct <= 0.0:
		return

	var fill_w := _current_fill_pct * track_w

	# ── 4. Blue fill ──────────────────────────────────────────────────────────
	draw_rect(Rect2(track_x, track_y, fill_w, BAR_H), COLOR_FILL)

	# ── 5. Top-edge highlight ─────────────────────────────────────────────────
	# A thin permanent bright stripe along the top of the fill gives the bar a
	# "glass tube" depth even when the sheen is elsewhere in its sweep.
	draw_rect(Rect2(track_x, track_y, fill_w, 3.0), Color(0.55, 0.80, 1.0, 0.35))

	# ── 6. Animated sheen sweep ───────────────────────────────────────────────
	# A soft bright column sweeps from left to right across the fill. It is built
	# from SHEEN_STEPS thin vertical strips whose alpha follows a bell curve
	# peaked at the column's centre. This approximates a Gaussian glow without
	# needing a shader or gradient texture.
	var sheen_cx := track_x + _sheen_pct * fill_w
	var strip_w  := (SHEEN_HALF_W * 2.0) / float(SHEEN_STEPS)
	for step in range(SHEEN_STEPS):
		var t      := (float(step) + 0.5) / float(SHEEN_STEPS)   # 0…1 across the band
		var offset := (t - 0.5) * (SHEEN_HALF_W * 2.0)           # pixels from centre
		var sx     := sheen_cx + offset
		# Skip strips that fall entirely outside the filled region.
		if sx + strip_w * 0.5 < track_x or sx - strip_w * 0.5 > track_x + fill_w:
			continue
		# Bell-curve alpha: 1.0 at centre, 0.0 at the band's edges.
		# norm_d is -1…+1; squaring it gives a smooth parabolic falloff.
		var norm_d := offset / SHEEN_HALF_W
		var bell   := maxf(0.0, 1.0 - norm_d * norm_d)
		var col    := Color(COLOR_SHEEN.r, COLOR_SHEEN.g, COLOR_SHEEN.b,
				COLOR_SHEEN.a * bell)
		draw_rect(Rect2(sx - strip_w * 0.5, track_y, strip_w, BAR_H), col)

	# ── 7. Sparkle flecks ────────────────────────────────────────────────────
	# Small bright circles that swirl within the filled region.
	# x drifts slowly; y oscillates via the orbit angle to produce a swirling path.
	# Alpha follows a three-phase ramp: fade-in (0–30%), hold (30–70%), fade-out (70–100%).
	# Peak alpha is multiplied by COLOR_SPARKLE.a so the constant governs overall brightness.
	for sp in _sparkles:
		# Explicit float types required — sp is a Dictionary value (Variant),
		# so := cannot infer the type from sp.key lookups.
		var sp_x_pct : float = clampf(
				float(sp["pct"]) + float(sp["drift"]) * float(sp["age"]), 0.0, 1.0)
		var sp_x     : float = track_x + sp_x_pct * fill_w
		# Discard sparkles whose position now falls beyond the current fill edge
		# (can happen if fill shrinks after a level-up reset).
		if sp_x > track_x + fill_w:
			continue
		# Swirl: y oscillates around the bar centreline using orbit radius and phase.
		var sp_angle : float = float(sp["angle"]) + float(sp["angular_vel"]) * float(sp["age"])
		var sp_y     : float = bulb_cy + float(sp["orbit_r"]) * sin(sp_angle)
		var life_t   : float = float(sp["age"]) / float(sp["max_life"])
		var alpha    : float = 0.0
		if life_t < 0.3:
			alpha = life_t / 0.3          # fade in
		elif life_t > 0.7:
			alpha = (1.0 - life_t) / 0.3 # fade out
		else:
			alpha = 1.0                    # hold at peak
		var sp_col := Color(COLOR_SPARKLE.r, COLOR_SPARKLE.g, COLOR_SPARKLE.b,
				alpha * COLOR_SPARKLE.a)
		draw_circle(Vector2(sp_x, sp_y), float(sp["radius"]), sp_col)


# ---------------------------------------------------------------------------
# GameState signal handlers
# ---------------------------------------------------------------------------

func _on_xp_changed(new_xp: int, xp_needed: int) -> void:
	var target := float(new_xp) / float(xp_needed) if xp_needed > 0 else 0.0

	if _current_fill_pct >= 1.0:
		# The bar is full because a level-up just fired in the same frame.
		# Delay the reset animation so the full bar stays visible while the level-up
		# screen is appearing. The timer is process_always=true (Godot 4 default) so
		# it fires even after the tree is paused by the LevelUpScreen.
		get_tree().create_timer(0.6).timeout.connect(func(): _animate_to(target))
	else:
		_animate_to(target)


func _on_level_up(new_level: int) -> void:
	_level = new_level
	_level_lbl.text = "LVL %d" % _level
	# Set the bar to full INSTANTLY (bypass the tween) so the fill is visible in the
	# current frame. Using _animate_to(1.0) here would create a tween that gets
	# immediately cancelled by the xp_changed signal that follows in the same frame.
	_set_fill(1.0)


# ---------------------------------------------------------------------------
# Animation helpers
# ---------------------------------------------------------------------------

func _animate_to(target: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_fill, _current_fill_pct, target, 0.15)


func _set_fill(pct: float) -> void:
	_current_fill_pct = clampf(pct, 0.0, 1.0)
	queue_redraw()
