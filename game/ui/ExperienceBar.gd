## ExperienceBar.gd
## A thin horizontal bar displayed at the top of the arena zone.
##
## Anatomy (left to right):
##   [ ● ══════════════════░░░░░░░░░  LVL 7 ]
##    bulb  ← fill track (80% of width) →   level label
##
## The silver container background is always visible. The fill track is black
## when empty and fills with neon blue as XP is earned. A short Tween animates
## the fill width on each XP change so it feels responsive rather than instant.
##
## HUD.gd creates this and positions it over the arena zone.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------

## Height of the entire bar control (silver container).
const BAR_H: float = 22.0

## The fill track occupies this fraction of the total width.
## The remaining 20% on the right holds the level label.
const TRACK_WIDTH_FRACTION: float = 0.80

## Radius of the circular "bulb" at the left end of the fill track.
const BULB_RADIUS: float = 7.0

## Inner padding between the silver container edge and the fill track.
const INNER_PAD: float = 3.0

## Neon blue fill color — bright and saturated to stand out against the arena.
const COLOR_FILL  := Color(0.0, 0.55, 1.0, 1.0)

## Empty track color.
const COLOR_EMPTY := Color(0.06, 0.06, 0.08, 1.0)

## Silver outer container color.
const COLOR_SILVER := Color(0.72, 0.72, 0.80, 1.0)

## Dark silver inner border just inside the container.
const COLOR_BORDER := Color(0.30, 0.30, 0.35, 1.0)


# ---------------------------------------------------------------------------
# Child nodes
# ---------------------------------------------------------------------------

var _fill_rect:  ColorRect = null   # the animating blue fill
var _level_lbl:  Label     = null   # "LVL N" text on the right


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _current_fill_pct: float = 0.0   # 0.0 – 1.0, animated by Tween
var _tween: Tween = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# This bar lives in a CanvasLayer and needs its own layout size.
	custom_minimum_size = Vector2(0.0, BAR_H)

	_build_bar()

	# Connect to GameState so the bar updates whenever XP changes.
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.level_up.connect(_on_level_up)

	# Initialise to the current run state (handles hot-reload / scene re-entry).
	var needed := GameState.exp_for_next_level()
	_set_fill_immediate(float(GameState.current_xp) / float(needed) if needed > 0 else 0.0)
	_update_level_label(GameState.current_player_level)


func _build_bar() -> void:
	# Silver container background — full width of the control.
	var bg := ColorRect.new()
	bg.color        = COLOR_SILVER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Dark inner border inset by 1 px on each side.
	var border := ColorRect.new()
	border.color = COLOR_BORDER
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.offset_left   = 1.0
	border.offset_right  = -1.0
	border.offset_top    = 1.0
	border.offset_bottom = -1.0
	add_child(border)

	# Track area — from the bulb inset to the right edge of the track fraction.
	# The fill rect is a child of the Control so its position is in local space.

	# Black empty track background.
	var track_bg := ColorRect.new()
	track_bg.color       = COLOR_EMPTY
	track_bg.name        = "TrackBG"
	add_child(track_bg)
	# We position it in _on_resized, but set a placeholder size now.

	# Blue fill rect — width is driven by _current_fill_pct * track width.
	_fill_rect = ColorRect.new()
	_fill_rect.color = COLOR_FILL
	add_child(_fill_rect)

	# Bulb — small circle at the far left of the track.
	# Drawn as a small square ColorRect; a true circle would need a shader.
	# The bulb is always fully lit when any XP is present.
	var bulb := ColorRect.new()
	bulb.name  = "Bulb"
	bulb.color = COLOR_SILVER
	add_child(bulb)

	# Level label — bold, right side.
	_level_lbl = Label.new()
	_level_lbl.text                  = "LVL 1"
	_level_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_level_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_level_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_level_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_level_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_level_lbl.add_theme_font_size_override("font_size", 14)
	add_child(_level_lbl)

	# Listen for size changes so we can re-lay out children.
	resized.connect(_on_resized)
	# Trigger an initial layout pass.
	call_deferred("_on_resized")


# ---------------------------------------------------------------------------
# Layout
#
# Layout is done manually (no Container nodes) because this bar lives directly
# in a CanvasLayer where Control layout nodes don't propagate size automatically.
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	if size.x <= 0.0:
		return

	var w := size.x
	var h := size.y

	# Track area: left side starts after bulb diameter + padding.
	var bulb_diam  := BULB_RADIUS * 2.0
	var track_x    := INNER_PAD + bulb_diam + INNER_PAD
	var track_w    := w * TRACK_WIDTH_FRACTION - track_x - INNER_PAD
	var track_h    := h - INNER_PAD * 2.0
	var track_y    := INNER_PAD

	# Empty track background.
	var track_bg: ColorRect = get_node_or_null("TrackBG")
	if track_bg:
		track_bg.position = Vector2(track_x, track_y)
		track_bg.size     = Vector2(track_w, track_h)

	# Blue fill — same position, width driven by fill pct.
	if _fill_rect:
		_fill_rect.position = Vector2(track_x, track_y)
		_fill_rect.size     = Vector2(track_w * _current_fill_pct, track_h)

	# Bulb — vertically centred, flush with left edge of track area.
	var bulb: ColorRect = get_node_or_null("Bulb")
	if bulb:
		bulb.position = Vector2(INNER_PAD, h * 0.5 - BULB_RADIUS)
		bulb.size     = Vector2(bulb_diam, bulb_diam)
		# Match fill colour when any XP is present.
		bulb.color = COLOR_FILL if _current_fill_pct > 0.0 else COLOR_EMPTY

	# Level label — right portion of the bar.
	if _level_lbl:
		var lbl_x := w * TRACK_WIDTH_FRACTION
		_level_lbl.position = Vector2(lbl_x, 0.0)
		_level_lbl.size     = Vector2(w - lbl_x, h)


# ---------------------------------------------------------------------------
# Signals from GameState
# ---------------------------------------------------------------------------

func _on_xp_changed(new_xp: int, xp_needed: int) -> void:
	var target_pct := float(new_xp) / float(xp_needed) if xp_needed > 0 else 0.0
	_animate_fill_to(target_pct)


func _on_level_up(new_level: int) -> void:
	_update_level_label(new_level)
	# The bar briefly fills to 100%, then resets to the new partial fill.
	# The reset happens because add_experience() emits xp_changed immediately after
	# level_up — the Tween from that signal call will update the bar to the
	# correct post-level-up value automatically.
	_animate_fill_to(1.0)


# ---------------------------------------------------------------------------
# Fill helpers
# ---------------------------------------------------------------------------

func _animate_fill_to(target_pct: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_fill_immediate, _current_fill_pct, target_pct, 0.15)


func _set_fill_immediate(pct: float) -> void:
	_current_fill_pct = clampf(pct, 0.0, 1.0)
	_on_resized()   # re-layout repositions the fill rect and recolors the bulb


func _update_level_label(level: int) -> void:
	if _level_lbl:
		_level_lbl.text = "LVL %d" % level
