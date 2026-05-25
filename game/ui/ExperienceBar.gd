## ExperienceBar.gd
## XP progress bar pinned to the top of the arena zone.
##
## Visual structure:
##   ┌──────────────────────────────────────────────────────────────────┐
##   │  ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮   │
##   │  bulb (75% inner h)         bar track (50% inner h)         ╯   │
##   └──────────────────────────────────────────────────────────────────┘
##
## The silver rectangle spans the full control width and height.
## A dark interior fills the inside. The thermometer shape (bulb + bar track
## + right cap) is drawn inside it as the blue XP fill.
##
## Everything is drawn in _draw() — no child rects or borders. The level
## label is a child Label anchored to the right side of the bar.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Visual constants — PANEL_H is referenced by HUD.gd for layout sizing
# ---------------------------------------------------------------------------

## Total height of the control, including the silver rectangle border.
const PANEL_H: float = 30.0

## Thickness of the silver rectangle border on all four sides.
const RECT_BRD: float = 4.0

## Bar track height as a fraction of the inner height (PANEL_H − 2 × RECT_BRD).
const BAR_H_FRAC: float = 0.50

## Bulb height as a fraction of the inner height. The bulb radius is clamped
## so it never protrudes outside the inner rect.
const BULB_H_FRAC: float = 0.75

## Bright neon blue — XP fill colour.
const COLOR_FILL    := Color(0.05, 0.50, 1.00, 1.0)

## Very dark navy — empty-track colour (also used for the inner background).
const COLOR_EMPTY   := Color(0.03, 0.05, 0.12, 1.0)

## Silver — rectangle border colour.
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

	# Redraw whenever the control is resized (fill rect depends on size.x).
	resized.connect(queue_redraw)

	# Level label — right-aligned inside the bar, vertically centred.
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
	# Rightmost 20% of bar, full height — stays vertically centred automatically.
	_level_lbl.anchor_left   = 0.80
	_level_lbl.anchor_right  = 1.0
	_level_lbl.anchor_top    = 0.0
	_level_lbl.anchor_bottom = 1.0
	_level_lbl.offset_right  = -int(RECT_BRD) - 2
	add_child(_level_lbl)

	# Wire up GameState signals.
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_up.connect(_on_level_up)

	# Initialise to current run state (handles hot-reload / scene re-entry).
	var needed := GameState.exp_for_next_level()
	_current_fill_pct = float(GameState.current_xp) / float(needed) if needed > 0 else 0.0
	_level = GameState.current_player_level
	_level_lbl.text = "LVL %d" % _level
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
#
# Three layers in order:
#   1. Silver rectangle — the full control rect, forms the border.
#   2. Dark interior    — inset by RECT_BRD on all sides; fills everything inside
#                         the border, including areas above/below the bar track.
#   3. Blue XP fill     — thermometer shapes (bulb circle + bar rect + right cap)
#                         drawn on top of the dark interior, left-to-right up to
#                         the current fill fraction.
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var brd := RECT_BRD
	var cy  := h * 0.5

	# ── 1. Silver rectangle ───────────────────────────────────────────────────
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_OUTLINE)

	# ── 2. Dark interior ──────────────────────────────────────────────────────
	draw_rect(Rect2(brd, brd, w - brd * 2.0, h - brd * 2.0), COLOR_EMPTY)

	# Thermometer geometry, sized against the inner height so the shapes
	# never protrude past the silver border.
	var inner_h := h - brd * 2.0
	# Clamp bulb radius to exactly half the inner height so the bulb is
	# tangent to the inner rect top and bottom at its widest point.
	var bulb_r  := minf(inner_h * BULB_H_FRAC * 0.5, inner_h * 0.5)
	var bar_h   := inner_h * BAR_H_FRAC
	var bar_top := cy - bar_h * 0.5
	var cap_r   := bar_h * 0.5   # right end: full semicircle

	# Bulb left edge is flush with the inner rect left edge (x = brd).
	var bulb_cx := brd + bulb_r
	# Cap right edge is flush with the inner rect right edge (x = w − brd).
	var cap_cx  := w - brd - cap_r

	# ── 3. Blue XP fill ───────────────────────────────────────────────────────
	if _current_fill_pct <= 0.0:
		return

	# fill_right maps the fill fraction across the inner width.
	var fill_right := brd + _current_fill_pct * (w - brd * 2.0)

	# Bulb: fully lit whenever any fill is present (binary XP indicator).
	draw_circle(Vector2(bulb_cx, cy), bulb_r, COLOR_FILL)

	# Bar body: from bulb centre to fill_right, capped at the cap centre.
	var rect_right := minf(fill_right, cap_cx)
	if rect_right > bulb_cx:
		draw_rect(Rect2(bulb_cx, bar_top, rect_right - bulb_cx, bar_h), COLOR_FILL)

	# Right cap: filled only when the fill reaches the cap area.
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
	# Briefly flash full before the subsequent xp_changed resets to the new
	# partial fill for the next level.
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
