## UpgradeCard.gd
## A single selectable upgrade card shown during a level-up event.
##
## Layout (top to bottom):
##
##   CAMPAIGN card:                    EQUIPMENT card:
##   ┌──────────────────────────┐      ┌──────────────────────────┐
##   │ ■ PROFESSIONAL      [🚐] │      │ ■ COMMON          [trap] │
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
## Both card types place a small image in the top-right corner of the title row:
## campaign cards show the company van; equipment cards show the trap thumbnail.
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

## SVG idle-frame path for each trap type (index = trap type int from Trap.gd).
## Shown on unlock cards so the player can see what they're unlocking.
const TRAP_TEXTURE_PATHS: Dictionary = {
	0: "res://assets/snap_trap_idle.svg",
	1: "res://assets/zapper_idle.svg",
	2: "res://assets/fogger_idle.svg",
	3: "res://assets/glue_board_idle.svg",
	4: "res://assets/fly_strip_idle.svg",
	5: "res://assets/bait_station_idle.svg",
}

## SVG frame-1 path for each boost type (index = boost type int from BoostUnit.gd).
## Shown on unlock cards so the player can see what they're unlocking.
const BOOST_TEXTURE_PATHS: Dictionary = {
	0: "res://assets/pheromone_dispenser_1.svg",
	1: "res://assets/compressor_1.svg",
	2: "res://assets/cash_register_1.svg",
	3: "res://assets/air_freshener_1.svg",
	4: "res://assets/quarantine_marker_1.svg",
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

var _title_lbl:  Label       = null   # buff name or trap name
var _image_rect: TextureRect = null   # trap/boost SVG image (unlock cards only)
var _thumb_rect:    TextureRect = null   # small trap SVG or van thumbnail
var _is_van_thumb:  bool        = false  # true for campaign cards; drives larger thumb size
var _stat_lbl:   Label       = null   # stat name (equipment only)
var _impact_lbl: Label       = null   # "+10% fire rate" or "+5% Fire Rate"
var _plain_lbl:  Label       = null   # plain-English explanation

var _bucks_row:    HBoxContainer = null   # coin icon + cost number; replaces _impact_lbl on gear cards
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

## Additional multiplier applied only to the title label. Used by
## TrapSelectionScreen to make trap/boost names dominate the card visually
## without scaling all other text (stats, descriptions) by the same amount.
var title_font_scale: float = 1.0

## When true the card border uses custom_color (trap/boost identity colour)
## rather than the rarity tier colour. Set by TrapSelectionScreen, where cards
## represent unit types rather than rarity-tiered rewards.
var use_identity_outline: bool = false

## Retained for API compatibility; no longer has any effect.
## Tier is now rendered as a separate external sign by LevelUpScreen.
var show_tier_badge: bool = false

## When >= 0, caps the image area height in _on_resized() so that a larger
## font_scale does not inflate the image region disproportionately.
## TrapSelectionScreen sets this to 87.0 (the baseline image height) when
## it doubles font_scale so the layout remains balanced.
var image_h_max: float = -1.0

## Left/right content margin inside the card border used throughout _on_resized().
## Default 14 px gives comfortable breathing room on the level-up screen.
## TrapSelectionScreen overrides this to 7 px for its denser card layout.
var horizontal_padding: float = 14.0


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
	# Do NOT clip children — the selection ring (_CardFrame) is drawn 8 px
	# outside the card boundary and must not be clipped to a square.
	# Labels are sized to stay within the card, so no visual overflow occurs.

	var category: String = _upgrade_data.get("category", "")
	var is_unlock: bool  = category == "unlock_trap" or category == "unlock_boost"

	# --- Outline ---
	# Unlock cards (new equipment reveal) use white — visually distinct from
	# rarity-coloured equipment upgrades and trap-identity-coloured gear cards.
	# Gear screen cards use the trap/boost identity colour (use_identity_outline).
	# All other cards use the rarity tier colour.
	var outline_color: Color
	if is_unlock:
		outline_color = Color.WHITE
	elif use_identity_outline and custom_color.a > 0.0:
		outline_color = custom_color
	else:
		outline_color = TIER_COLORS[tier]

	# --- Background color ---
	# If a trap/boost identity color is supplied, derive the bg from it so the
	# card feels "owned" by that unit type. Campaign cards use a neutral dark gray
	# rather than a tier-tinted dark, since campaign buffs are type-agnostic.
	# All other cards (generic equipment) fall back to a tier-hued dark bg.
	# v * 0.35 keeps the background dark but visibly in tune with the unit's color theme;
	# the previous 0.22 was noticeably darker than the type strip accent colors.
	var bg_color: Color
	if custom_color.a > 0.0:
		bg_color = Color.from_hsv(custom_color.h, custom_color.s * 0.65, custom_color.v * 0.35, 0.95)
	elif category == "campaign":
		bg_color = Color(0.22, 0.22, 0.22, 0.95)   # pure neutral gray — campaign buffs are type-agnostic
	else:
		bg_color = Color.from_hsv(outline_color.h, outline_color.s * 0.65, outline_color.v * 0.35, 0.95)

	# --- _CardFrame: rounded border ring + tinted dark background ---
	_card_frame = _CardFrame.new()
	_card_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_frame.outline_color = outline_color
	_card_frame.bg_color      = bg_color
	_card_frame.bw            = BORDER_W
	_card_frame.cr            = CORNER_R
	_card_frame.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_card_frame)

	# --- Title — main name, large and prominent ---
	_title_lbl = Label.new()
	_title_lbl.text                 = _upgrade_data.get("title", "")
	_title_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_title_lbl.add_theme_font_size_override("font_size", roundi(38.0 * font_scale * title_font_scale))
	add_child(_title_lbl)

	# --- Image — shown on unlock and gear-selection cards ---
	# "unlock_trap"/"unlock_boost" are used by LevelUpScreen; "trap"/"boost" are
	# used by TrapSelectionScreen. Both contexts display the unit's SVG preview.
	var item_type: int = _upgrade_data.get("item_type", -1)
	var is_trap_img:  bool = (category == "unlock_trap"  or category == "trap")  and item_type >= 0
	var is_boost_img: bool = (category == "unlock_boost" or category == "boost") and item_type >= 0
	if is_trap_img or is_boost_img:
		var tex_path: String = TRAP_TEXTURE_PATHS.get(item_type, "") if is_trap_img \
				else BOOST_TEXTURE_PATHS.get(item_type, "")
		if tex_path != "" and ResourceLoader.exists(tex_path):
			_image_rect = TextureRect.new()
			_image_rect.texture             = load(tex_path)
			# EXPAND_IGNORE_SIZE keeps minimum_size at 0×0 so the TextureRect never
			# tries to grow beyond the size we assign in _on_resized().  The alternative
			# EXPAND_FIT_HEIGHT_PROPORTIONAL inflates minimum_size to match the SVG's
			# natural dimensions (which include large transparent padding), causing the
			# image to expand to fill the entire card when clip_contents is off.
			_image_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
			_image_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_image_rect.custom_minimum_size = Vector2.ZERO
			_image_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
			add_child(_image_rect)

	# --- Thumbnail — small image in the top-right corner ---
	# Equipment cards: shows the trap SVG so the player knows which trap is upgraded.
	# Campaign cards: shows the company van — same corner position as equipment thumbnails
	# so the top-right slot is consistently used as the "what this card is about" indicator.
	var eq_trap_type: int = _upgrade_data.get("trap_type", -1)
	var thumb_path: String = ""
	if category == "equipment" and eq_trap_type >= 0:
		thumb_path = TRAP_TEXTURE_PATHS.get(eq_trap_type, "")
	elif category == "campaign":
		thumb_path    = "res://assets/van_small.png"
		_is_van_thumb = true
	if thumb_path != "" and ResourceLoader.exists(thumb_path):
		_thumb_rect = TextureRect.new()
		_thumb_rect.texture             = load(thumb_path)
		_thumb_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		_thumb_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_thumb_rect.custom_minimum_size = Vector2.ZERO
		_thumb_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		add_child(_thumb_rect)

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

	var bucks_cost: int = _upgrade_data.get("bucks_cost", -1)
	if bucks_cost >= 0:
		# Gear-selection cards show cost as a coin icon + number rather than plain text.
		_bucks_row = HBoxContainer.new()
		_bucks_row.alignment    = BoxContainer.ALIGNMENT_CENTER
		_bucks_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bucks_row.add_theme_constant_override("separation", 8)
		add_child(_bucks_row)

		var bucks_icon := TextureRect.new()
		bucks_icon.texture             = load("res://assets/bug_buck_coin_medium.png") as Texture2D
		bucks_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		bucks_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bucks_icon.custom_minimum_size = Vector2(40, 40)
		bucks_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bucks_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_bucks_row.add_child(bucks_icon)

		var bucks_lbl := Label.new()
		bucks_lbl.text                 = "%d" % bucks_cost
		bucks_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		bucks_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		bucks_lbl.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
		bucks_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.18, 1.0))
		bucks_lbl.add_theme_font_override("font", UIFonts.primary_bold())
		bucks_lbl.add_theme_font_size_override("font_size", roundi(67.0 * font_scale))
		_bucks_row.add_child(bucks_lbl)
	else:
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
	var px := horizontal_padding

	# title_h must always fit a 2-line title (long names in narrow cards wrap).
	# formula_h preserves the compact title-to-image gap when title_font_scale > 1.0;
	# min_2line guarantees the label region is never shorter than 2 lines of title text.
	var font_px   := 38.0 * font_scale * title_font_scale
	var formula_h := (68.0 + (title_font_scale - 1.0) * 80.0) * font_scale
	var title_h   := maxf(formula_h, font_px * 2.7)

	# No bottom badge — tier is displayed as an external sign by LevelUpScreen.
	var badge_reserve := 0.0

	# Row 1: Title — narrowed when a thumbnail occupies the top-right corner.
	if _title_lbl:
		const THUMB_SIZE: float = 44.0
		var title_w := w - px * 2.0
		if _thumb_rect != null:
			var effective_thumb_sz: float = 77.0 if _is_van_thumb else THUMB_SIZE
			title_w -= effective_thumb_sz + 4.0   # 4 px gap between title text and thumbnail
		_title_lbl.position = Vector2(px, 7.0)
		_title_lbl.size     = Vector2(title_w, title_h)

	# Cursor tracks where the next row starts below the title.
	var cursor := 7.0 + title_h + 2.0

	# Row 2 (unlock/gear cards): trap/boost preview image.
	# image_h scales proportionally with font_scale so narrow many-card layouts don't
	# give a disproportionate fraction of card height to the image.
	# Baseline: 87 px at font_scale 0.65 (50% larger than the original 58 px).
	var image_h := 87.0 * font_scale / 0.65
	if image_h_max >= 0.0:
		image_h = minf(image_h, image_h_max)
	if _image_rect:
		_image_rect.position = Vector2(px, cursor)
		_image_rect.size     = Vector2(w - px * 2.0, image_h)
		cursor += image_h + 4.0

	# Skip the stat row height when stat_name is empty (unlock and gear cards).
	# Equipment and campaign cards carry a stat label ("Fire Rate", "Damage", etc.)
	# that needs the space; unlock/gear cards set stat_name="" to keep layout compact.
	var has_stat: bool = _stat_lbl != null and not _stat_lbl.text.is_empty()
	var stat_y   := cursor
	var impact_y := stat_y + (34.0 if has_stat else 0.0)   # 30px label + 4px gap
	# Bucks row is taller than the standard 54 px impact label because its font is larger.
	# Compute the height from the actual label size so plain_y always clears the row.
	var bucks_h  := float(roundi(67.0 * font_scale)) + 20.0
	var plain_y  := impact_y + (bucks_h if _bucks_row != null else 54.0) + 8.0

	# Stat name row (equipment/campaign) or skipped when empty (unlock/gear).
	if _stat_lbl:
		_stat_lbl.position = Vector2(px, stat_y)
		_stat_lbl.size     = Vector2(w - px * 2.0, 30.0)

	# Impact line (or bucks cost display for gear-selection cards).
	if _impact_lbl:
		_impact_lbl.position = Vector2(px, impact_y)
		_impact_lbl.size     = Vector2(w - px * 2.0, 54.0)
	if _bucks_row:
		_bucks_row.position = Vector2(px, impact_y)
		_bucks_row.size     = Vector2(w - px * 2.0, bucks_h)

	# Plain-text description — fills remaining space above the badge area.
	# 7 px bottom padding matches the 7 px top offset for a symmetric feel.
	if _plain_lbl:
		_plain_lbl.position = Vector2(px, plain_y)
		_plain_lbl.size     = Vector2(w - px * 2.0, h - plain_y - badge_reserve - 7.0)

	# Thumbnail — top-right corner, centred vertically within the title row.
	# Van (campaign) cards use a 75% larger thumbnail than equipment cards.
	if _thumb_rect:
		var thumb_sz: float = 77.0 if _is_van_thumb else 44.0
		_thumb_rect.position = Vector2(w - px - thumb_sz, 7.0 + (title_h - thumb_sz) * 0.5)
		_thumb_rect.size     = Vector2(thumb_sz, thumb_sz)



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

		# --- 1. Drop shadow — three concentric layers, outermost drawn first ---
		# Drawing outer→inner means each successive layer paints on top, so the
		# alpha values accumulate toward the card edge, producing a soft gradient:
		# barely visible at the outer halo, slightly more opaque at the core.
		# Overall alpha is intentionally low to keep the shadow subtle.
		var outer_halo_pts := _rounded_rect_poly(-2.0, 1.0, w + 16.0, h + 16.0, cr + 8.0, 10)
		var outer_halo_c   := PackedColorArray()
		outer_halo_c.resize(outer_halo_pts.size())
		outer_halo_c.fill(Color(0.0, 0.0, 0.0, 0.05))
		draw_polygon(outer_halo_pts, outer_halo_c)

		var mid_halo_pts := _rounded_rect_poly(1.0, 3.0, w + 8.0, h + 8.0, cr + 4.0, 10)
		var mid_halo_c   := PackedColorArray()
		mid_halo_c.resize(mid_halo_pts.size())
		mid_halo_c.fill(Color(0.0, 0.0, 0.0, 0.08))
		draw_polygon(mid_halo_pts, mid_halo_c)

		var core_pts := _rounded_rect_poly(3.0, 5.0, w, h, cr, 10)
		var core_c   := PackedColorArray()
		core_c.resize(core_pts.size())
		core_c.fill(Color(0.0, 0.0, 0.0, 0.13))
		draw_polygon(core_pts, core_c)

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

		# --- 3. Outer border ring — flat fill ---
		# The tier/identity colour is used as-is; no per-vertex gradient so the
		# card background reads as a flat tinted surface rather than a lit one.
		var outer := _rounded_rect_poly(0.0, 0.0, w, h, cr, 10)
		var oc    := PackedColorArray()
		oc.resize(outer.size())
		oc.fill(outline_color)
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
