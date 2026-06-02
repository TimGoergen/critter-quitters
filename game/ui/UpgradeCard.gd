## UpgradeCard.gd
## A single selectable upgrade card shown during a level-up event.
##
## Layout (top to bottom):
##
##   CAMPAIGN card:                    EQUIPMENT card:
##   ┌──────────────────────────┐      ┌──────────────────────────┐
##   │ ■ PROFESSIONAL           │      │ ■ COMMON                 │
##   │                          │      │                          │
##   │  Hair Trigger            │      │  Snap Trap               │
##   │                          │      │  Fire Rate               │
##   │  +10% fire rate          │      │                          │
##   │  for all traps           │      │  +5% Fire Rate           │
##   │                          │      │                          │
##   │  Every trap fires more   │      │  Reduces the cooldown    │
##   │  often. Stacks with ...  │      │  between shots, ...      │
##   │                          │      │                          │
##   └──────────────────────────┘      └──────────────────────────┘
##
## The card outline always uses the rarity tier color.
## The background derives from the trap/boost identity color when available,
## uses a flat dark gray for campaign cards, and falls back to the tier color otherwise.
## A tier badge sits at the bottom-right (quality: Common/Pro/Rare).
##
## Type strips:  NEW EQUIPMENT = amber    FIELD BULLETIN = teal    MAINTENANCE ORDER = burnt orange
## Tier colors:  Common = green           Professional = blue      Rare = purple
##
## The entire card surface is clickable — tapping anywhere on the card
## selects it. Hover brightens the card slightly for visual feedback.
##
## Visual note: the card frame uses _CardFrame (a draw_polygon-based inner
## class) rather than StyleBoxFlat. The gl_compatibility renderer does not
## support StyleBoxFlat corner_radius rendering; draw_polygon() works in
## every renderer. The approach mirrors _PanelFrame in TrapUpgradePanel.gd.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Tiers
# ---------------------------------------------------------------------------

enum Tier { COMMON = 0, PROFESSIONAL = 1, RARE = 2 }

const TIER_NAMES: Array = ["COMMON", "PROFESSIONAL", "RARE"]
const TIER_COLORS: Array = [
	Color(0.18, 0.68, 0.30, 1.0),   # Common       — green
	Color(0.18, 0.48, 0.90, 1.0),   # Professional — blue
	Color(0.65, 0.18, 0.90, 1.0),   # Rare         — purple
]

## Border thickness in pixels — matches TrapUpgradePanel.BORDER_W.
const BORDER_W: float = 6.0

## Corner radius for all four card corners — matches TrapUpgradePanel's cr.
## Gives the card the same visual weight as the trap upgrade panel.
const CORNER_R: float = 16.0

## Height of the colored type-strip band drawn across the top of every card.
## Matches the height of the old tier-label row so all other content positions are unchanged.
const TYPE_STRIP_HEIGHT: float = 22.0

## Dark background fill for the type strip, keyed by upgrade category.
## Derived from each accent color darkened to complement the card's dark atmosphere.
## Retained here because LevelUpScreen uses these values for the external tag panels.
const TYPE_STRIP_BG_COLORS: Dictionary = {
	"unlock_trap":  Color(0.30, 0.19, 0.01, 1.0),   # dark amber
	"unlock_boost": Color(0.30, 0.19, 0.01, 1.0),   # dark amber
	"campaign":     Color(0.01, 0.22, 0.24, 1.0),   # dark teal
	"equipment":    Color(0.27, 0.13, 0.04, 1.0),   # dark burnt orange
}

## Bright accent color used for the type-strip label text, keyed by upgrade category.
## Retained here because LevelUpScreen uses these values for the external tag panels.
const TYPE_STRIP_ACCENT_COLORS: Dictionary = {
	"unlock_trap":  Color(0.83, 0.52, 0.04, 1.0),   # amber
	"unlock_boost": Color(0.83, 0.52, 0.04, 1.0),   # amber
	"campaign":     Color(0.04, 0.62, 0.66, 1.0),   # teal
	"equipment":    Color(0.75, 0.35, 0.10, 1.0),   # burnt orange
}

## Text shown in the type strip for each upgrade category.
## Retained here because LevelUpScreen uses these values for the external tag panels.
const TYPE_STRIP_LABELS: Dictionary = {
	"unlock_trap":  "★  NEW EQUIPMENT",
	"unlock_boost": "★  NEW EQUIPMENT",
	"campaign":     "◉  FIELD BULLETIN",
	"equipment":    "⚙  MAINTENANCE ORDER",
}


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player selects this card. upgrade is the Dictionary
## passed to setup() — Arena uses it to apply the upgrade.
signal card_selected(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Child nodes (set in _build_card, used in _on_resized)
# ---------------------------------------------------------------------------

var _tier_lbl:   Label = null   # "COMMON" / "PROFESSIONAL" / "RARE" — bottom-right badge
var _title_lbl:  Label = null   # buff name or trap name
var _stat_lbl:   Label = null   # stat name (equipment only)
var _impact_lbl: Label = null   # "+10% fire rate" or "+5% Fire Rate"
var _plain_lbl:  Label = null   # plain-English explanation

var _upgrade_data: Dictionary = {}
var _selected:     bool       = false
var _card_frame:   _CardFrame = null

## When true, tapping the card toggles selection on/off rather than locking
## in and emitting once. Used by TrapSelectionScreen for multi-pick behaviour.
var toggleable: bool = false

## Optional colour override for the card bg tint. When alpha > 0
## this replaces the tier colour, allowing trap-identity colours on trap cards.
var custom_color: Color = Color.TRANSPARENT

## Uniform scale applied to every font size on this card.
## Set before calling setup() to adjust text size without changing the shared
## font-size constants. TrapSelectionScreen sets this to 0.65; LevelUpScreen
## leaves it at the default 1.0.
var font_scale: float = 1.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by LevelUpScreen immediately after instantiation.
## upgrade Dictionary keys (all cards):
##   "category"    String  — "campaign" or "equipment"
##   "tier"        int     — Tier enum value
##   "title"       String  — buff name (campaign) or trap type name (equipment)
##   "impact_line" String  — formatted impact line, e.g. "+10% fire rate to all traps"
##   "plain_text"  String  — plain-English description of what the upgrade does
## Equipment-only keys:
##   "stat_name"   String  — human-readable stat name, e.g. "Fire Rate"
func setup(upgrade: Dictionary) -> void:
	_upgrade_data = upgrade
	_build_card()


func _build_card() -> void:
	var tier: int = _upgrade_data.get("tier", Tier.COMMON)
	var px       := 10.0   # horizontal padding used throughout

	# Make the entire card surface catch input so any tap/click selects it.
	mouse_filter               = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# --- Outline always uses the rarity tier color ---
	var outline_color: Color = TIER_COLORS[tier]

	# --- Background color ---
	# If a trap/boost identity color is supplied, derive the bg from it so the
	# card feels "owned" by that unit type. Campaign cards use a neutral dark gray
	# rather than a tier-tinted dark, since campaign buffs are type-agnostic.
	# All other cards (generic equipment) fall back to a tier-hued dark bg.
	var bg_color: Color
	var category: String = _upgrade_data.get("category", "")
	if custom_color.a > 0.0:
		bg_color = Color.from_hsv(custom_color.h, custom_color.s * 0.70, custom_color.v * 0.22, 0.95)
	elif category == "campaign":
		bg_color = Color(0.10, 0.10, 0.12, 0.95)   # flat dark gray — campaign buffs are type-agnostic
	else:
		bg_color = Color.from_hsv(outline_color.h, outline_color.s * 0.70, outline_color.v * 0.22, 0.95)

	# --- _CardFrame: rounded border ring + tinted dark background ---
	_card_frame = _CardFrame.new()
	_card_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_frame.outline_color = outline_color
	_card_frame.bg_color      = bg_color
	_card_frame.bw            = BORDER_W
	_card_frame.cr            = CORNER_R
	_card_frame.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_card_frame)

	# --- Tier badge — bottom-right corner, dimmed to serve as secondary info ---
	# Shows "COMMON" / "PROFESSIONAL" / "RARE" — quality indicator, not category.
	_tier_lbl = Label.new()
	_tier_lbl.text                 = TIER_NAMES[tier]
	_tier_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tier_lbl.clip_text            = true
	_tier_lbl.add_theme_color_override("font_color", Color(outline_color.r, outline_color.g, outline_color.b, 0.70))
	_tier_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_tier_lbl.add_theme_font_size_override("font_size", roundi(20.0 * font_scale))
	add_child(_tier_lbl)

	# --- Title — main name, large and prominent ---
	_title_lbl = Label.new()
	_title_lbl.text                 = _upgrade_data.get("title", "")
	_title_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_title_lbl.add_theme_font_size_override("font_size", roundi(38.0 * font_scale))
	add_child(_title_lbl)

	# --- Stat name (equipment only) or empty for campaign cards ---
	# Uses custom_color when available so the label matches the trap/boost identity;
	# falls back to the tier color as a neutral quality indicator.
	var stat_color: Color = custom_color if custom_color.a > 0.0 else TIER_COLORS[tier]
	_stat_lbl = Label.new()
	_stat_lbl.text                 = _upgrade_data.get("stat_name", "")
	_stat_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat_lbl.clip_text            = true
	_stat_lbl.add_theme_color_override("font_color", stat_color)
	_stat_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_stat_lbl.add_theme_font_size_override("font_size", roundi(30.0 * font_scale))
	add_child(_stat_lbl)

	# --- Impact line — the concrete effect of this upgrade ---
	# Both campaign and equipment cards store this as "impact_line":
	#   Campaign:  "+10% fire rate for all traps"
	#   Equipment: "+5% Fire Rate"
	var impact_text: String = _upgrade_data.get("impact_line", "")

	_impact_lbl = Label.new()
	_impact_lbl.text                 = impact_text
	_impact_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_impact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_impact_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_impact_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	_impact_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_impact_lbl.add_theme_font_size_override("font_size", roundi(32.0 * font_scale))
	add_child(_impact_lbl)

	# --- Plain-text description — fills remaining space to the card bottom ---
	_plain_lbl = Label.new()
	_plain_lbl.text                 = _upgrade_data.get("plain_text", "")
	_plain_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_plain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plain_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_plain_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_plain_lbl.add_theme_font_size_override("font_size", roundi(24.0 * font_scale))
	add_child(_plain_lbl)

	resized.connect(_on_resized)
	call_deferred("_on_resized")


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	if size.x <= 0.0:
		return

	var w  := size.x
	var h  := size.y
	var px := 10.0

	# Row 1: Title — starts at the top of the card body (no type strip above it).
	if _title_lbl:
		_title_lbl.position = Vector2(px, 6.0)
		_title_lbl.size     = Vector2(w - px * 2.0, 68.0)

	# Row 2: Stat name (equipment) or empty (campaign).
	if _stat_lbl:
		_stat_lbl.position = Vector2(px, 78.0)
		_stat_lbl.size     = Vector2(w - px * 2.0, 30.0)

	# Row 3: Impact line.
	if _impact_lbl:
		_impact_lbl.position = Vector2(px, 112.0)
		_impact_lbl.size     = Vector2(w - px * 2.0, 54.0)

	# Row 4: Plain-text description — fills space above the tier badge.
	if _plain_lbl:
		_plain_lbl.position = Vector2(px, 170.0)
		_plain_lbl.size     = Vector2(w - px * 2.0, h - 192.0)

	# Tier badge — bottom-right corner, below the plain text.
	if _tier_lbl:
		_tier_lbl.position = Vector2(px, h - 22.0)
		_tier_lbl.size     = Vector2(w - px * 2.0 - 6.0, 18.0)


# ---------------------------------------------------------------------------
# Input — entire card surface is the click target
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# InputEventMouseButton covers both real mouse clicks (desktop) and touch
	# taps (Android emulates a left-click via emulate_mouse_from_touch).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_select_pressed()
		accept_event()
	elif event is InputEventScreenTouch:
		# The raw touch event arrives alongside the emulated MouseButton above.
		# Consuming it here without acting prevents any other node from seeing
		# a second press and toggling the card back off.
		accept_event()


## Brighten card slightly on hover; restore to full brightness on exit.
## Applies to both selected and unselected cards — on selected cards the gold
## ring brightens with the rest of the card, signalling it can be unselected.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			modulate = Color(1.1, 1.1, 1.1, 1.0)
		NOTIFICATION_MOUSE_EXIT:
			modulate = Color(1.0, 1.0, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_select_pressed() -> void:
	if toggleable:
		# Toggle mode: flip selection, show/hide gold ring, always emit so the
		# parent (TrapSelectionScreen) can update its selection count.
		_selected = not _selected
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		if _card_frame:
			_card_frame.show_selection = _selected
		card_selected.emit(_upgrade_data)
		return
	# Single-select mode: lock in, block further input, dim, emit once.
	if _selected:
		return
	_selected = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_selected.emit(_upgrade_data)


## Forces the card back to an unselected visual state without emitting.
## Called by TrapSelectionScreen when the pick limit is reached and a
## third card tap must be rejected.
func force_deselect() -> void:
	_selected  = false
	modulate   = Color(1.0, 1.0, 1.0, 1.0)
	if _card_frame:
		_card_frame.show_selection = false


func is_card_selected() -> bool:
	return _selected


# ---------------------------------------------------------------------------
# Card frame — draws the tier-coloured border ring and tinted dark background
# via canvas primitives rather than StyleBoxFlat.
#
# Root cause of all previous approaches using StyleBoxFlat:
# Godot's gl_compatibility renderer does not support StyleBoxFlat corner_radius
# rendering — that feature requires a shader not available in gl_compat.
# draw_polygon() is a fundamental canvas call that works in every renderer.
#
# Shape: full rect with all four corners rounded (unlike TrapUpgradePanel's
# top-only rounding, because cards float freely rather than anchoring to an edge).
# The outer polygon is drawn in the tier colour; the inset rect fills with the
# dark background. The visible gap between them forms the border ring.
# ---------------------------------------------------------------------------
class _CardFrame extends Control:
	var outline_color:  Color = Color.WHITE
	var bg_color:       Color = Color.BLACK
	var bw:             float = 6.0    # border width in pixels
	var cr:             float = 16.0   # corner radius for all four corners

	## When true, draws a thin gold ring just outside the card border.
	var show_selection: bool = false:
		set(v):
			show_selection = v
			queue_redraw()

	const SELECTION_COLOR:  Color = Color(1.0, 0.80, 0.10, 1.0)   # gold
	const SELECTION_MARGIN: float = 8.0                           # px outside card edge

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return

		# --- 1. Drop shadow ---
		# Drawn first so every card layer paints over it.
		# Offset (4 right, 6 down) gives cards physical lift off the background.
		var shadow_pts := _rounded_rect_poly(4.0, 6.0, w, h, cr, 10)
		var shadow_c   := PackedColorArray()
		shadow_c.resize(shadow_pts.size())
		shadow_c.fill(Color(0.0, 0.0, 0.0, 0.55))
		draw_polygon(shadow_pts, shadow_c)

		# --- 2. Gold selection ring ---
		# Drawn before the card outline so the outline clips its interior,
		# leaving only the outer band (SELECTION_MARGIN px wide) visible.
		if show_selection:
			var sm     := SELECTION_MARGIN
			var s_poly := _rounded_rect_poly(-sm, -sm, w + sm * 2.0, h + sm * 2.0, cr + sm, 10)
			var sc     := PackedColorArray()
			sc.resize(s_poly.size())
			sc.fill(SELECTION_COLOR)
			draw_polygon(s_poly, sc)

		# --- 3. Outer border ring — bevel gradient ---
		# Per-vertex colors interpolate from a brightened tier color at the top-left
		# to a darkened one at the bottom-right, simulating directional light from
		# the top-left. The inner polygon drawn next covers the interior, leaving
		# only the border ring where the gradient is visible.
		var outer := _rounded_rect_poly(0.0, 0.0, w, h, cr, 10)
		var oc    := PackedColorArray()
		oc.resize(outer.size())
		var bevel_light := Color(
			minf(outline_color.r * 1.45, 1.0),
			minf(outline_color.g * 1.45, 1.0),
			minf(outline_color.b * 1.45, 1.0), 1.0)
		var bevel_dark := Color(
			outline_color.r * 0.45,
			outline_color.g * 0.45,
			outline_color.b * 0.45, 1.0)
		for i in outer.size():
			var t := (outer[i].x / w + outer[i].y / h) * 0.5   # 0 = top-left, 1 = bottom-right
			oc[i] = bevel_light.lerp(bevel_dark, t)
		draw_polygon(outer, oc)

		# --- 4. Inner background ---
		# Rounded corners (radius = cr - bw) keep the border ring uniform thickness
		# all the way into the corners; a plain draw_rect() would cut straight across
		# the curve and make the inner edge look square where the outer edge rounds.
		var inner := _rounded_rect_poly(bw, bw, w - bw * 2.0, h - bw * 2.0, cr - bw, 10)
		var ic    := PackedColorArray()
		ic.resize(inner.size())
		ic.fill(bg_color)
		draw_polygon(inner, ic)

		# --- 5. Surface sheen ---
		# Semi-transparent white gradient fading from the top of the inner area downward.
		# Simulates specular light catching the upper surface of the card.
		var inner_h   := h - bw * 2.0
		var sheen_h   := inner_h * 0.38   # highlight covers the top 38% of the card interior
		var sheen_pts := _rounded_top_rect_poly(bw, bw, w - bw * 2.0, sheen_h, cr - bw, 10)
		var sheen_c   := PackedColorArray()
		sheen_c.resize(sheen_pts.size())
		for i in sheen_pts.size():
			var vert_y := sheen_pts[i].y - bw
			var t      := clampf(vert_y / sheen_h, 0.0, 1.0)
			sheen_c[i] = Color(1.0, 1.0, 1.0, lerpf(0.09, 0.0, t))
		draw_polygon(sheen_pts, sheen_c)

	## Builds a polygon for a rectangle with only the top two corners rounded.
	## Used for the surface sheen gradient that covers the upper portion of the card interior.
	## The bottom two corners are square so the sheen blends into the flat body below.
	static func _rounded_top_rect_poly(
		x: float, y: float, w: float, h: float, r: float, segs: int
	) -> PackedVector2Array:
		var pts  := PackedVector2Array()
		var step := (PI * 0.5) / float(segs)

		# Top-left arc: centre (x+r, y+r), sweeping 180°→270°
		for i in segs + 1:
			var a := PI + step * float(i)
			pts.append(Vector2(x + r + cos(a) * r, y + r + sin(a) * r))

		# Top-right arc: centre (x+w-r, y+r), sweeping 270°→360°
		for i in segs + 1:
			var a := PI * 1.5 + step * float(i)
			pts.append(Vector2(x + w - r + cos(a) * r, y + r + sin(a) * r))

		# Bottom-right: square corner
		pts.append(Vector2(x + w, y + h))

		# Bottom-left: square corner
		pts.append(Vector2(x, y + h))

		return pts


	## Builds a closed polygon approximating a rectangle with all four corners
	## rounded by radius r. All coordinates are in local (Control-relative) space.
	static func _rounded_rect_poly(
		x: float, y: float, w: float, h: float, r: float, segs: int
	) -> PackedVector2Array:
		var pts  := PackedVector2Array()
		var step := (PI * 0.5) / float(segs)

		# Top-left arc: centre (x+r, y+r), sweeping 180°→270°
		for i in segs + 1:
			var a := PI + step * float(i)
			pts.append(Vector2(x + r + cos(a) * r, y + r + sin(a) * r))

		# Top-right arc: centre (x+w-r, y+r), sweeping 270°→360°
		for i in segs + 1:
			var a := PI * 1.5 + step * float(i)
			pts.append(Vector2(x + w - r + cos(a) * r, y + r + sin(a) * r))

		# Bottom-right arc: centre (x+w-r, y+h-r), sweeping 0°→90°
		for i in segs + 1:
			var a := step * float(i)
			pts.append(Vector2(x + w - r + cos(a) * r, y + h - r + sin(a) * r))

		# Bottom-left arc: centre (x+r, y+h-r), sweeping 90°→180°
		for i in segs + 1:
			var a := PI * 0.5 + step * float(i)
			pts.append(Vector2(x + r + cos(a) * r, y + h - r + sin(a) * r))

		return pts
