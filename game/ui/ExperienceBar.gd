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
## Inner height = PANEL_H - RECT_BRD*2 = 36; BULB_R = 18 fills the full inner height.
const BULB_R: float = 18.0

## Height of the thin bar track that extends to the right of the bulb.
const BAR_H: float = 14.0

## Bright saturated blue — chosen to contrast clearly with the gold/amber palette
## elsewhere in the HUD, signalling "progress toward upgrade" at a glance.
const COLOR_FILL    := Color(0.18, 0.55, 1.0, 1.0)

## Very dark navy — empty track and bar background.
const COLOR_EMPTY   := Color(0.03, 0.05, 0.12, 1.0)

## Silver — border colour.  Matches HUD.COLOR_SILVER_BORDER exactly so the
## control border and the arena outline appear as a single continuous line.
const COLOR_OUTLINE := Color(0.72, 0.72, 0.80, 1.0)


# ---------------------------------------------------------------------------
# Bulb-centre helpers
# Used by Arena.gd to aim XP particles at the bulb's screen position.
# ---------------------------------------------------------------------------

## Screen-space X coordinate of the bulb centre.
## Assumes HUD.gd positions the bar with offset_left = HUD.LEFT_PANEL_W.
static func bulb_screen_x() -> float:
	return HUD.LEFT_PANEL_W + RECT_BRD + BULB_R

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
	_level_lbl.anchor_left   = 0.80
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

	# ── 1. Silver border rectangle (full control) ─────────────────────────────
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_OUTLINE)

	# ── 2. Dark interior ──────────────────────────────────────────────────────
	var inner_x := brd
	var inner_y := brd
	var inner_w := w - brd * 2.0
	var inner_h := h - brd * 2.0
	draw_rect(Rect2(inner_x, inner_y, inner_w, inner_h), COLOR_EMPTY)

	# ── 3. Bulb — always filled blue, acts as the permanent landing target ─────
	# Centred at (inner_x + BULB_R, h/2). Radius = BULB_R fills the full inner height.
	var bulb_cx := inner_x + BULB_R
	var bulb_cy := h * 0.5
	draw_circle(Vector2(bulb_cx, bulb_cy), BULB_R, COLOR_FILL)

	# ── 4. Thin bar track background (dark) ───────────────────────────────────
	# Starts at the bulb's centre X and runs to the right inner edge so the
	# filled circle overlaps the left half of the track, creating a seamless join.
	var track_x  := bulb_cx
	var track_w  := (inner_x + inner_w) - track_x
	var track_y  := bulb_cy - BAR_H * 0.5
	draw_rect(Rect2(track_x, track_y, track_w, BAR_H), COLOR_EMPTY)

	# ── 5. Blue fill — sweeps left-to-right across the bar track ─────────────
	if _current_fill_pct > 0.0:
		var fill_w := _current_fill_pct * track_w
		draw_rect(Rect2(track_x, track_y, fill_w, BAR_H), COLOR_FILL)


# ---------------------------------------------------------------------------
# GameState signal handlers
# ---------------------------------------------------------------------------

func _on_xp_changed(new_xp: int, xp_needed: int) -> void:
	var target := float(new_xp) / float(xp_needed) if xp_needed > 0 else 0.0
	_animate_to(target)


func _on_level_up(new_level: int) -> void:
	_level = new_level
	_level_lbl.text = "LVL %d" % _level
	# Briefly flash full bar; the subsequent xp_changed resets to the new partial fill.
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
