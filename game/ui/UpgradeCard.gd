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
##   └──────────────────────────┘      └──────────────────────────┘
##
## Tier colors: Common=green  Professional=blue  Rare=purple

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

## Emitted when the player taps this card. upgrade is the Dictionary that was
## passed to setup() — Arena uses it to apply the correct upgrade.
signal card_selected(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Child nodes (set in _build_card, used in _on_resized)
# ---------------------------------------------------------------------------

var _category_lbl:  Label     = null   # "CAMPAIGN BUFF" / "FREE UPGRADE"
var _tier_lbl:      Label     = null   # "COMMON" / "PROFESSIONAL" / "RARE"
var _tier_strip:    ColorRect = null   # colored left border
var _title_lbl:     Label     = null   # buff name or trap name
var _stat_lbl:      Label     = null   # stat name (equipment only)
var _impact_lbl:    Label     = null   # "+10% fire rate" or "0.83/s → 0.90/s"
var _plain_lbl:     Label     = null   # plain-English explanation

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
	var tier: int       = _upgrade_data.get("tier", Tier.COMMON)
	var tier_color      := TIER_COLORS[tier]
	var is_equipment    := _upgrade_data.get("category", "") == "equipment"
	var px              := 10.0   # horizontal padding used throughout

	# --- Background ---
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.16, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- Tier colour strip — 6 px left border ---
	_tier_strip = ColorRect.new()
	_tier_strip.color         = tier_color
	_tier_strip.anchor_right  = 0.0
	_tier_strip.anchor_bottom = 1.0
	_tier_strip.offset_right  = 6.0
	add_child(_tier_strip)

	# --- Tier name ("RARE" etc.) — top-left in tier colour ---
	_tier_lbl = Label.new()
	_tier_lbl.text                 = TIER_NAMES[tier]
	_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tier_lbl.add_theme_color_override("font_color", tier_color)
	_tier_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_tier_lbl.add_theme_font_size_override("font_size", 10)
	add_child(_tier_lbl)

	# --- Category label — top-right, dim ---
	_category_lbl = Label.new()
	_category_lbl.text                 = "FREE UPGRADE" if is_equipment else "CAMPAIGN BUFF"
	_category_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_category_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
	_category_lbl.add_theme_font_size_override("font_size", 10)
	add_child(_category_lbl)

	# --- Title — main name, large and prominent ---
	_title_lbl = Label.new()
	_title_lbl.text                 = _upgrade_data.get("title", "")
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_title_lbl.add_theme_font_size_override("font_size", 17)
	add_child(_title_lbl)

	# --- Stat name (equipment only) or spacer ---
	_stat_lbl = Label.new()
	_stat_lbl.text                 = _upgrade_data.get("stat_name", "")
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
	_impact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_impact_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_impact_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	_impact_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_impact_lbl.add_theme_font_size_override("font_size", 14)
	add_child(_impact_lbl)

	# --- Plain-text description — what this upgrade does in plain English ---
	_plain_lbl = Label.new()
	_plain_lbl.text                 = _upgrade_data.get("plain_text", "")
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
		div.name  = "Divider"
		div.color = Color(0.30, 0.30, 0.35, 1.0)
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

	# Row 5: Plain-text description — fills remaining space above the bottom margin.
	y = 152.0
	if _plain_lbl:
		_plain_lbl.position = Vector2(px, y)
		_plain_lbl.size     = Vector2(w - px * 2.0, h - y - 8.0)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _selected:
		return
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return

	var is_press := false
	if event is InputEventScreenTouch:
		is_press = event.pressed
	elif event is InputEventMouseButton:
		is_press = event.pressed and event.button_index == MOUSE_BUTTON_LEFT

	if not is_press:
		return

	# get_global_rect() is in the same canvas coordinate space as touch/mouse events.
	var event_pos: Vector2
	if event is InputEventScreenTouch:
		event_pos = event.position
	else:
		event_pos = event.global_position

	if get_global_rect().has_point(event_pos):
		_select()
		get_viewport().set_input_as_handled()


func _select() -> void:
	_selected = true
	modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_selected.emit(_upgrade_data)
