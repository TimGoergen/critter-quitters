## ExperienceBar.gd
## XP progress bar pinned to the top of the arena zone.
##
## A simple blue fill bar inside a panel with a thick silver border:
##
##   ┌────────────────────────────────────────────────────────────────┐
##   │ █████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   LVL 4   │
##   └────────────────────────────────────────────────────────────────┘
##
## The silver rectangle is the full control rect. The dark interior fills
## everything inside the border. The blue fill sweeps left-to-right inside
## the dark area. No circles, no caps, no special shapes.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Visual constants — PANEL_H is referenced by HUD.gd for layout sizing
# ---------------------------------------------------------------------------

## Total height of the control, including the silver border.
const PANEL_H: float = 30.0

## Silver border thickness on all four sides.
const RECT_BRD: float = 8.0

## Warm amber-gold fill — matches the Bug Bucks / upgrade-reward palette so the
## bar visually signals "progress toward a reward you can act on" rather than
## neutral information.
const COLOR_FILL    := Color(0.96, 0.74, 0.08, 1.0)

## Very dark navy — empty-track colour.
const COLOR_EMPTY   := Color(0.03, 0.05, 0.12, 1.0)

## Silver — border colour.
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

	# ── 1. Silver border rectangle ────────────────────────────────────────────
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_OUTLINE)

	# ── 2. Dark interior ──────────────────────────────────────────────────────
	var inner_x := brd
	var inner_y := brd
	var inner_w := w - brd * 2.0
	var inner_h := h - brd * 2.0
	draw_rect(Rect2(inner_x, inner_y, inner_w, inner_h), COLOR_EMPTY)

	# ── 3. Blue fill — left-aligned rect sized to the fill fraction ───────────
	if _current_fill_pct > 0.0:
		var fill_w := _current_fill_pct * inner_w
		draw_rect(Rect2(inner_x, inner_y, fill_w, inner_h), COLOR_FILL)


# ---------------------------------------------------------------------------
# GameState signal handlers
# ---------------------------------------------------------------------------

func _on_xp_changed(new_xp: int, xp_needed: int) -> void:
	var target := float(new_xp) / float(xp_needed) if xp_needed > 0 else 0.0
	_animate_to(target)


func _on_level_up(new_level: int) -> void:
	_level = new_level
	_level_lbl.text = "LVL %d" % _level
	# Briefly flash full; the subsequent xp_changed resets to the new partial fill.
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
