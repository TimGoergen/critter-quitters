## UpgradeCard.gd
## A single selectable upgrade card shown during a level-up event.
##
## Layout (top to bottom):
##
##   CAMPAIGN card:                    EQUIPMENT card:
##   ┌──────────────────────────┐      ┌──────────────────────────┐
##   │ ■ PROFESSIONAL           │      │ ■ COMMON                 │
##   │ CAMPAIGN BUFF            │      │ FREE UPGRADE             │
##   │                          │      │                          │
##   │  Hair Trigger            │      │  Snap Trap               │
##   │                          │      │  Fire Rate               │
##   │  +10% fire rate          │      │                          │
##   │  for all traps           │      │  0.83/s  →  0.90/s      │
##   │                          │      │                          │
##   │  Every trap fires more   │      │  Reduces the cooldown    │
##   │  often. Stacks with ...  │      │  between shots, ...      │
##   │                          │      │                          │
##   │  ┌──────────────────┐    │      │  ┌──────────────────┐   │
##   │  │     SELECT       │    │      │  │     SELECT       │   │
##   │  └──────────────────┘    │      │  └──────────────────┘   │
##   └──────────────────────────┘      └──────────────────────────┘
##
## Tier colors: Common=green  Professional=blue  Rare=purple
##
## The SELECT button is the only interactive element — clicking anywhere
## else on the card does nothing. This prevents accidental selections.

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

## Height of the SELECT button in virtual pixels.
const BTN_H:      float = 36.0
## Bottom margin below the SELECT button.
const BTN_MARGIN: float = 8.0


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player presses SELECT on this card. upgrade is the
## Dictionary that was passed to setup() — Arena uses it to apply the upgrade.
signal card_selected(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Child nodes (set in _build_card, used in _on_resized)
# ---------------------------------------------------------------------------

var _category_lbl:  Label     = null   # "CAMPAIGN BUFF" / "FREE UPGRADE"
var _tier_lbl:      Label     = null   # "COMMON" / "PROFESSIONAL" / "RARE"
var _title_lbl:     Label     = null   # buff name or trap name
var _stat_lbl:      Label     = null   # stat name (equipment only)
var _impact_lbl:    Label     = null   # "+10% fire rate" or "0.83/s → 0.90/s"
var _plain_lbl:     Label     = null   # plain-English explanation
var _select_btn:    Button    = null   # the SELECT button at the bottom

var _upgrade_data: Dictionary = {}
var _selected:     bool       = false


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Called by LevelUpScreen immediately after instantiation.
## upgrade Dictionary keys (all cards):
##   "category"    String  — "campaign" or "equipment"
##   "tier"        int     — Tier enum value
##   "title"       String  — buff name (campaign) or trap type name (equipment)
##   "plain_text"  String  — plain-English description of what the upgrade does
## Campaign-only keys:
##   "impact_line" String  — formatted impact line, e.g. "+10% fire rate to all traps"
## Equipment-only keys:
##   "stat_name"   String  — human-readable stat name, e.g. "Fire Rate"
##   "current_val" String  — formatted current value, e.g. "0.83/s"
##   "after_val"   String  — formatted value after this upgrade, e.g. "0.90/s"
func setup(upgrade: Dictionary) -> void:
	_upgrade_data = upgrade
	_build_card()


func _build_card() -> void:
	var tier: int          = _upgrade_data.get("tier", Tier.COMMON)
	var tier_color: Color  = TIER_COLORS[tier]
	var is_equipment: bool = _upgrade_data.get("category", "") == "equipment"
	var px                := 10.0   # horizontal padding used throughout

	# --- Full tier-colour border + dark background ---
	# All decorative children use MOUSE_FILTER_IGNORE so they do not swallow
	# click events. The SELECT button is the only node that should receive input.
	#
	# Layering: tier-color rect fills the entire card, then the dark background
	# sits inset by BORDER_W pixels on all four sides, leaving a uniform outline.
	const BORDER_W := 2.0

	var border := ColorRect.new()
	border.color        = tier_color
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(border)

	var bg := ColorRect.new()
	bg.color         = Color(0.12, 0.12, 0.16, 0.96)
	bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	bg.anchor_left   = 0.0
	bg.anchor_top    = 0.0
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left   = BORDER_W
	bg.offset_top    = BORDER_W
	bg.offset_right  = -BORDER_W
	bg.offset_bottom = -BORDER_W
	add_child(bg)

	# --- Tier name ("RARE" etc.) — top-left in tier colour ---
	_tier_lbl = Label.new()
	_tier_lbl.text                 = TIER_NAMES[tier]
	_tier_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tier_lbl.add_theme_color_override("font_color", tier_color)
	_tier_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_tier_lbl.add_theme_font_size_override("font_size", 10)
	add_child(_tier_lbl)

	# --- Category label — top-right, dim ---
	_category_lbl = Label.new()
	_category_lbl.text                 = "FREE UPGRADE" if is_equipment else "CAMPAIGN BUFF"
	_category_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_category_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_category_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
	_category_lbl.add_theme_font_size_override("font_size", 10)
	add_child(_category_lbl)

	# --- Title — main name, large and prominent ---
	_title_lbl = Label.new()
	_title_lbl.text                 = _upgrade_data.get("title", "")
	_title_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_title_lbl.add_theme_font_size_override("font_size", 17)
	add_child(_title_lbl)

	# --- Stat name (equipment only) or spacer ---
	_stat_lbl = Label.new()
	_stat_lbl.text                 = _upgrade_data.get("stat_name", "")
	_stat_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat_lbl.add_theme_color_override("font_color", tier_color)
	_stat_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_stat_lbl.add_theme_font_size_override("font_size", 13)
	add_child(_stat_lbl)

	# --- Impact line — the concrete numerical effect ---
	# For campaign: "+10% fire rate for all traps"
	# For equipment: "0.83/s  →  0.90/s"
	var impact_text: String
	if is_equipment:
		var cur: String = _upgrade_data.get("current_val", "")
		var aft: String = _upgrade_data.get("after_val", "")
		impact_text = "%s  →  %s" % [cur, aft] if cur != "" else ""
	else:
		impact_text = _upgrade_data.get("impact_line", "")

	_impact_lbl = Label.new()
	_impact_lbl.text                 = impact_text
	_impact_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_impact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_impact_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_impact_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	_impact_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_impact_lbl.add_theme_font_size_override("font_size", 14)
	add_child(_impact_lbl)

	# --- Plain-text description — what this upgrade does in plain English ---
	_plain_lbl = Label.new()
	_plain_lbl.text                 = _upgrade_data.get("plain_text", "")
	_plain_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_plain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plain_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_plain_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.72, 1.0))
	_plain_lbl.add_theme_font_size_override("font_size", 11)
	add_child(_plain_lbl)

	# --- SELECT button — the only interactive element on the card ---
	# Styled with the tier color so the button identity visually belongs to the
	# card's tier. Normal state is darkened; hover brightens to full tier color;
	# pressed darkens further to give clear tactile feedback.
	_select_btn = Button.new()
	_select_btn.text = "SELECT"
	_select_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_select_btn.add_theme_font_size_override("font_size", 14)
	_select_btn.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 1.0))
	_select_btn.add_theme_color_override("font_hover_color",   Color(1.0, 1.0, 1.0, 1.0))
	_select_btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	_select_btn.add_theme_stylebox_override("normal",   _make_btn_style(tier_color.darkened(0.25)))
	_select_btn.add_theme_stylebox_override("hover",    _make_btn_style(tier_color))
	_select_btn.add_theme_stylebox_override("pressed",  _make_btn_style(tier_color.darkened(0.45)))
	_select_btn.add_theme_stylebox_override("focus",    _make_btn_style(tier_color.darkened(0.25)))
	_select_btn.pressed.connect(_on_select_pressed)
	add_child(_select_btn)

	resized.connect(_on_resized)
	call_deferred("_on_resized")


## Returns a flat rounded StyleBoxFlat with the given background color.
## Used to style the SELECT button's normal / hover / pressed states.
func _make_btn_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color                  = color
	sb.corner_radius_top_left    = 4
	sb.corner_radius_top_right   = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	if size.x <= 0.0:
		return

	var w  := size.x
	var h  := size.y
	var px := 10.0
	var y  := 0.0

	# Row 1: tier name left, category label right — top strip, 22 px tall.
	y = 8.0
	if _tier_lbl:
		_tier_lbl.position = Vector2(px + 6.0, y)   # 6 px offset for the color strip
		_tier_lbl.size     = Vector2(w * 0.45, 16.0)
	if _category_lbl:
		_category_lbl.position = Vector2(w * 0.45, y)
		_category_lbl.size     = Vector2(w * 0.55 - px, 16.0)

	# Divider line between header row and body (drawn as a very short ColorRect).
	# We only create it once on the first resize pass.
	var div: ColorRect = get_node_or_null("Divider")
	if div == null:
		div = ColorRect.new()
		div.name         = "Divider"
		div.color        = Color(0.30, 0.30, 0.35, 1.0)
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(div)
	div.position = Vector2(px, 26.0)
	div.size     = Vector2(w - px * 2.0, 1.0)

	# Row 2: Title — bold, centred.
	y = 32.0
	if _title_lbl:
		_title_lbl.position = Vector2(px, y)
		_title_lbl.size     = Vector2(w - px * 2.0, 46.0)

	# Row 3: Stat name (equipment) or empty line (campaign).
	y = 80.0
	if _stat_lbl:
		_stat_lbl.position = Vector2(px, y)
		_stat_lbl.size     = Vector2(w - px * 2.0, 20.0)

	# Row 4: Impact line — gold, prominent.
	y = 104.0
	if _impact_lbl:
		_impact_lbl.position = Vector2(px, y)
		_impact_lbl.size     = Vector2(w - px * 2.0, 44.0)

	# Row 5: Plain-text description — fills space above the SELECT button.
	# Bottom boundary is (button top) - 8 px gap = h - BTN_MARGIN - BTN_H - 8.
	y = 152.0
	var btn_top := h - BTN_MARGIN - BTN_H
	if _plain_lbl:
		_plain_lbl.position = Vector2(px, y)
		_plain_lbl.size     = Vector2(w - px * 2.0, btn_top - y - 8.0)

	# Row 6: SELECT button — pinned to the bottom of the card.
	if _select_btn:
		_select_btn.position = Vector2(px, btn_top)
		_select_btn.size     = Vector2(w - px * 2.0, BTN_H)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_select_pressed() -> void:
	if _selected:
		return
	_selected = true
	# Disable the button immediately so a second tap before the screen dismisses
	# cannot trigger a double-selection.
	_select_btn.disabled = true
	modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_selected.emit(_upgrade_data)
