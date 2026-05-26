## ExperienceBar.gd
## XP progress bar pinned to the top of the arena zone.
##
## Layout:
##
##   ┌──────────────────────────────────────────────────────────────────┐
##   │ ●● ═══════════════════════════════════════░░░░░░░░░░   LVL 4   │
##   └──────────────────────────────────────────────────────────────────┘
##   ^bulb (always filled blue)
##       ^thin bar track (fills proportionally left-to-right)
##
## The silver border (RECT_BRD = 4px) is positioned flush with the arena's own
## top silver outline so they share pixels and read as one continuous band.
##
## The bulb is a filled circle on the left end, always drawn in the XP fill
## colour so it acts as a permanent visual landmark — and a landing target for
## the blue XP particles that fly from enemy deaths.

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
## Larger than BULB_R alone — gives breathing room so the bulb doesn't sit flush
## against the left silver border.
const BULB_LEFT_MARGIN: float = 22.0   # bulb centre is this far from inner_x

## How many pixels the bar track overlaps the right edge of the bulb.
## A small overlap creates a seamless join without hiding the bulb.
const BAR_BULB_OVERLAP: float = 4.0

## The bar track ends at this fraction of the total panel width.
## The right remainder is reserved for the LVL N label.
const BAR_WIDTH_FRACTION: float = 0.86

## Bright saturated blue — chosen to contrast clearly with the gold/amber palette
## elsewhere in the HUD, signalling "progress toward upgrade" at a glance.
const COLOR_FILL        := Color(0.18, 0.55, 1.0, 1.0)

## Silver — interior panel background and border colour.
## Matches HUD.COLOR_SILVER_BORDER so control border and arena outline merge.
const COLOR_OUTLINE     := Color(0.72, 0.72, 0.80, 1.0)

## Slightly darker silver — the unfilled portion of the bar track.
## Must contrast enough against COLOR_OUTLINE to read as a distinct inset trough.
const COLOR_TRACK_EMPTY := Color(0.44, 0.44, 0.50, 1.0)


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


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, PANEL_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PROCESS_MODE_ALWAYS so Tweens created here run even while the LevelUpScreen
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


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var brd := RECT_BRD

	# ── 1. Silver border + silver interior — full panel reads as a silver strip ─
	# Border and interior use the same colour so they merge into one band.
	# The bulb and bar track are drawn on top of this silver field.
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_OUTLINE)   # border + background in one pass

	# ── 2. Bulb — always filled blue, acts as the permanent particle landing target ──
	# Centre is BULB_LEFT_MARGIN pixels from the inner left edge (more than BULB_R alone,
	# so there is visible space between the bulb and the left silver border).
	var inner_x := brd
	var bulb_cx := inner_x + BULB_LEFT_MARGIN
	var bulb_cy := h * 0.5
	draw_circle(Vector2(bulb_cx, bulb_cy), BULB_R, COLOR_FILL)

	# ── 3. Bar track — runs from just past the bulb's right edge to 86% of w ─────
	# BAR_BULB_OVERLAP keeps a small junction so bar and bulb read as connected,
	# while leaving the majority of the bulb clearly visible on the silver background.
	var track_x := bulb_cx + BULB_R - BAR_BULB_OVERLAP
	var track_y := bulb_cy - BAR_H * 0.5
	var track_w := w * BAR_WIDTH_FRACTION - track_x
	if track_w > 0.0:
		draw_rect(Rect2(track_x, track_y, track_w, BAR_H), COLOR_TRACK_EMPTY)

	# ── 4. Blue fill — sweeps left-to-right across the bar track ─────────────
	if _current_fill_pct > 0.0 and track_w > 0.0:
		var fill_w := _current_fill_pct * track_w
		draw_rect(Rect2(track_x, track_y, fill_w, BAR_H), COLOR_FILL)


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
