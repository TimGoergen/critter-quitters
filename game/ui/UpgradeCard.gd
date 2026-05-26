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
## Tier colors: Common=green  Professional=blue  Rare=purple
##
## The entire card surface is clickable — tapping anywhere on the card
## selects it. Hover brightens the card slightly for visual feedback.

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


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player selects this card. upgrade is the Dictionary
## passed to setup() — Arena uses it to apply the upgrade.
signal card_selected(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Child nodes (set in _build_card, used in _on_resized)
# ---------------------------------------------------------------------------

var _tier_lbl:   Label = null   # "COMMON" / "PROFESSIONAL" / "RARE"
var _title_lbl:  Label = null   # buff name or trap name
var _stat_lbl:   Label = null   # stat name (equipment only)
var _impact_lbl: Label = null   # "+10% fire rate" or "+5% Fire Rate"
var _plain_lbl:  Label = null   # plain-English explanation

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
##   "impact_line" String  — formatted impact line, e.g. "+10% fire rate to all traps"
##   "plain_text"  String  — plain-English description of what the upgrade does
## Equipment-only keys:
##   "stat_name"   String  — human-readable stat name, e.g. "Fire Rate"
func setup(upgrade: Dictionary) -> void:
	_upgrade_data = upgrade
	_build_card()


func _build_card() -> void:
	var tier: int         = _upgrade_data.get("tier", Tier.COMMON)
	var tier_color: Color = TIER_COLORS[tier]
	var px               := 10.0   # horizontal padding used throughout

	# Make the entire card surface catch input so any tap/click selects it.
	mouse_filter               = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# --- Full tier-colour border + dark background ---
	# All decorative children use MOUSE_FILTER_IGNORE so input passes through
	# to the root Control, which handles the click.
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

	# --- Stat name (equipment only) or empty for campaign cards ---
	_stat_lbl = Label.new()
	_stat_lbl.text                 = _upgrade_data.get("stat_name", "")
	_stat_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat_lbl.add_theme_color_override("font_color", tier_color)
	_stat_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_stat_lbl.add_theme_font_size_override("font_size", 13)
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
	_impact_lbl.add_theme_font_size_override("font_size", 14)
	add_child(_impact_lbl)

	# --- Plain-text description — fills remaining space to the card bottom ---
	_plain_lbl = Label.new()
	_plain_lbl.text                 = _upgrade_data.get("plain_text", "")
	_plain_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_plain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plain_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_plain_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.72, 1.0))
	_plain_lbl.add_theme_font_size_override("font_size", 11)
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
	var y  := 0.0

	# Row 1: tier name — top strip, 22 px tall.
	y = 8.0
	if _tier_lbl:
		_tier_lbl.position = Vector2(px + 6.0, y)   # 6 px left offset aligns with color strip
		_tier_lbl.size     = Vector2(w - px * 2.0, 16.0)

	# Divider line between header row and body (created once on first resize pass).
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

	# Row 3: Stat name (equipment) or empty (campaign).
	y = 80.0
	if _stat_lbl:
		_stat_lbl.position = Vector2(px, y)
		_stat_lbl.size     = Vector2(w - px * 2.0, 20.0)

	# Row 4: Impact line — gold, prominent.
	y = 104.0
	if _impact_lbl:
		_impact_lbl.position = Vector2(px, y)
		_impact_lbl.size     = Vector2(w - px * 2.0, 44.0)

	# Row 5: Plain-text description — fills the remaining card space to the bottom.
	y = 152.0
	if _plain_lbl:
		_plain_lbl.position = Vector2(px, y)
		_plain_lbl.size     = Vector2(w - px * 2.0, h - y - px)


# ---------------------------------------------------------------------------
# Input — entire card surface is the click target
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_select_pressed()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_on_select_pressed()


## Brighten card on hover; restore on exit.
## Gives tactile feedback without relying on a Button node.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not _selected:
				modulate = Color(1.15, 1.15, 1.15, 1.0)
		NOTIFICATION_MOUSE_EXIT:
			if not _selected:
				modulate = Color(1.0, 1.0, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_select_pressed() -> void:
	if _selected:
		return
	_selected = true
	# Block further input immediately — a second tap before the screen dismisses
	# must not trigger a second selection.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_selected.emit(_upgrade_data)
