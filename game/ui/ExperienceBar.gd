## ExperienceBar.gd
## XP progress bar pinned to the top of the arena zone.
##
## Shape: a circular bulb at the left end, taller than the bar track, connected
## to a pill-capped rectangular track — the whole thing drawn as one cohesive
## shape with a thick silver outline.
##
##   ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮
##   bulb (75% h)            bar track (50% h)         ╯
##
## Everything is drawn in _draw() — no child rects or borders. The Label for
## the current level lives on top as a child node (anchored to the right side).

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Visual constants — PANEL_H is referenced by HUD.gd for layout sizing
# ---------------------------------------------------------------------------

## Total height of the control. The bulb and outline may fill the full height.
const PANEL_H: float = 30.0

## Bar track height as a fraction of PANEL_H (50 %).
const BAR_H_FRAC: float = 0.50

## Bulb height as a fraction of PANEL_H (75 %); bulb radius = PANEL_H × 0.375.
const BULB_H_FRAC: float = 0.75

## Silver outline thickness, measured outward from the inner shape on all sides.
const OUTLINE_W: float = 5.0

## Bright neon blue — XP fill colour.
const COLOR_FILL    := Color(0.05, 0.50, 1.00, 1.0)

## Very dark navy — empty-track colour.
const COLOR_EMPTY   := Color(0.03, 0.05, 0.12, 1.0)

## Silver — outline colour.
const COLOR_OUTLINE := Color(0.72, 0.72, 0.80, 1.0)


# ---------------------------------------------------------------------------
# Child nodes
# ---------------------------------------------------------------------------

var _level_lbl: Label = null


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Current fill fraction, 0.0–1.0. Animated by Tween on every XP change.
var _current_fill_pct: float = 0.0
var _tween:            Tween = null
var _level:            int   = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(0.0, PANEL_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Redraw whenever the control is resized (the fill rect depends on size.x).
	resized.connect(queue_redraw)

	# Level label — right-aligned, centred vertically, drawn over the bar track.
	_level_lbl = Label.new()
	_level_lbl.text                  = "LVL 0"
	_level_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_level_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_level_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_level_lbl.add_theme_font_size_override("font_size", 12)
	_level_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96, 1.0))
	_level_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_level_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_level_lbl.add_theme_constant_override("shadow_offset_y", 1)
	# Anchored to the rightmost 20% of the bar; vertically spans the full control.
	_level_lbl.anchor_left   = 0.80
	_level_lbl.anchor_right  = 1.0
	_level_lbl.anchor_top    = 0.0
	_level_lbl.anchor_bottom = 1.0
	_level_lbl.offset_right  = -int(OUTLINE_W) - 2   # keep text clear of the outline ring
	add_child(_level_lbl)

	# Wire up GameState signals.
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_up.connect(_on_level_up)

	# Initialise to the current run state (handles hot-reload / scene re-entry).
	var needed := GameState.exp_for_next_level()
	_current_fill_pct = float(GameState.current_xp) / float(needed) if needed > 0 else 0.0
	_level = GameState.current_player_level
	_level_lbl.text = "LVL %d" % _level
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
#
# The bar is three overlapping layers drawn in order:
#   1. Thick silver outline — slightly larger shapes on all sides.
#   2. Dark empty background — inner shapes, full width.
#   3. Blue XP fill — same inner shapes, but only as far left-to-right as
#      the current fill fraction.
#
# Shapes used: filled circle (bulb left), filled rect (bar body), filled
# circle (right cap).  Overlap at junctions is intentional — it makes the
# shape look cohesive with no seams.
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w  := size.x
	var h  := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var cy     := h * 0.5
	var bulb_r := h * BULB_H_FRAC * 0.5    # e.g. 11.25 at h = 30
	var bar_h  := h * BAR_H_FRAC            # e.g. 15.0  at h = 30
	var bar_top := cy - bar_h * 0.5         # top y of bar track
	var cap_r   := bar_h * 0.5             # right-end cap = full semicircle
	var cap_cx  := w - cap_r               # centre-x of right cap circle
	var o       := OUTLINE_W

	# ── 1. Thick silver outline ───────────────────────────────────────────────
	# Each shape is OUTLINE_W larger than the corresponding inner shape.
	# The bulb and bar outlines overlap at their junction — this naturally
	# blends them into one continuous outline with no visible gap or seam.
	draw_circle(Vector2(bulb_r, cy), bulb_r + o, COLOR_OUTLINE)
	draw_rect(Rect2(bulb_r, bar_top - o, cap_cx - bulb_r, bar_h + o * 2.0), COLOR_OUTLINE)
	draw_circle(Vector2(cap_cx, cy), cap_r + o, COLOR_OUTLINE)

	# ── 2. Dark empty background ──────────────────────────────────────────────
	draw_circle(Vector2(bulb_r, cy), bulb_r, COLOR_EMPTY)
	draw_rect(Rect2(bulb_r, bar_top, cap_cx - bulb_r, bar_h), COLOR_EMPTY)
	draw_circle(Vector2(cap_cx, cy), cap_r, COLOR_EMPTY)

	# ── 3. Blue XP fill ───────────────────────────────────────────────────────
	# fill_right is the x-coordinate where blue ends, mapped over the full width.
	if _current_fill_pct <= 0.0:
		return

	var fill_right := _current_fill_pct * w

	# Bulb: fully lit whenever any fill is present.  The bulb acts as a binary
	# XP indicator — even a tiny amount of XP lights it completely.
	draw_circle(Vector2(bulb_r, cy), bulb_r, COLOR_FILL)

	# Bar body: blue rect from bulb centre to fill_right, capped at cap_cx.
	var rect_right := minf(fill_right, cap_cx)
	if rect_right > bulb_r:
		draw_rect(Rect2(bulb_r, bar_top, rect_right - bulb_r, bar_h), COLOR_FILL)

	# Right cap: filled only once the fill reaches the cap area.
	if fill_right >= cap_cx:
		draw_circle(Vector2(cap_cx, cy), cap_r, COLOR_FILL)


# ---------------------------------------------------------------------------
# GameState signal handlers
# ---------------------------------------------------------------------------

func _on_xp_changed(new_xp: int, xp_needed: int) -> void:
	var target := float(new_xp) / float(xp_needed) if xp_needed > 0 else 0.0
	_animate_to(target)


func _on_level_up(new_level: int) -> void:
	_level = new_level
	_level_lbl.text = "LVL %d" % _level
	# Briefly flash full before the subsequent xp_changed signal resets to
	# the new partial fill for the next level.
	_animate_to(1.0)


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
