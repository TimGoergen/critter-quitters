## UpgradeCard.gd
## A single selectable upgrade card shown during a level-up event.
##
## Visual layout (top to bottom):
##   ┌──────────────────────────────┐
##   │ ■ RARE                       │  ← tier badge (colored strip)
##   │                              │
##   │       ● (icon circle)        │
##   │                              │
##   │  Extermination Formula       │  ← upgrade name
##   │  +20% damage to all traps    │  ← description
##   │                              │
##   │  Snap Trap — Damage          │  ← equipment sub-label (campaign cards leave blank)
##   └──────────────────────────────┘
##
## Tier colors:
##   Common      → green   (Color(0.18, 0.68, 0.30))
##   Professional→ blue    (Color(0.18, 0.48, 0.90))
##   Rare        → purple  (Color(0.65, 0.18, 0.90))
##
## When tapped, emits card_selected(upgrade_data) and the card dims to show
## it has been chosen. The LevelUpScreen hides all cards once one is picked.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Tiers
# ---------------------------------------------------------------------------

enum Tier { COMMON = 0, PROFESSIONAL = 1, RARE = 2 }

const TIER_NAMES: Array[String] = ["COMMON", "PROFESSIONAL", "RARE"]
const TIER_COLORS: Array[Color] = [
	Color(0.18, 0.68, 0.30, 1.0),   # Common  — green
	Color(0.18, 0.48, 0.90, 1.0),   # Pro     — blue
	Color(0.65, 0.18, 0.90, 1.0),   # Rare    — purple
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player taps this card. upgrade is the Dictionary that was
## passed to setup() — the caller uses it to apply the upgrade.
signal card_selected(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Child node references
# ---------------------------------------------------------------------------

var _bg:          ColorRect = null
var _tier_strip:  ColorRect = null
var _tier_label:  Label     = null
var _icon_circle: ColorRect = null
var _name_label:  Label     = null
var _desc_label:  Label     = null
var _sub_label:   Label     = null

var _upgrade_data: Dictionary = {}
var _selected: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Call immediately after instantiation.
## upgrade is a Dictionary with keys:
##   "id"         String  — buff id (e.g. "dmg_all") or "equipment"
##   "category"   String  — "campaign" or "equipment"
##   "tier"       int     — Tier enum value
##   "title"      String  — display name
##   "description"String  — one-line description shown on the card
##   "magnitude"  float   — numeric value of the buff
##   "trap_node"  Node3D  — (equipment only) the trap to upgrade
##   "stat"       String  — (equipment only) the stat to upgrade
##   "sub_label"  String  — (optional) secondary label, e.g. "Snap Trap — Damage"
func setup(upgrade: Dictionary) -> void:
	_upgrade_data = upgrade
	_build_card()


func _build_card() -> void:
	var tier: int = _upgrade_data.get("tier", Tier.COMMON)
	var tier_color: Color = TIER_COLORS[tier]

	# Card background — slightly off-white with a colored left border.
	_bg = ColorRect.new()
	_bg.color = Color(0.12, 0.12, 0.16, 0.96)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# Colored tier strip — 6px left border.
	_tier_strip = ColorRect.new()
	_tier_strip.color = tier_color
	_tier_strip.anchor_right  = 0.0
	_tier_strip.anchor_bottom = 1.0
	_tier_strip.offset_right  = 6.0
	add_child(_tier_strip)

	# Tier badge text ("COMMON" / "PROFESSIONAL" / "RARE") top-centre.
	_tier_label = Label.new()
	_tier_label.text                 = TIER_NAMES[tier]
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_color_override("font_color", tier_color)
	_tier_label.add_theme_font_override("font", UIFonts.primary_bold())
	_tier_label.add_theme_font_size_override("font_size", 11)
	_tier_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tier_label.offset_top    = 10.0
	_tier_label.offset_bottom = 28.0
	_tier_label.offset_left   = 8.0
	add_child(_tier_label)

	# Icon circle — colored dot in the tier color, centred horizontally.
	_icon_circle = ColorRect.new()
	_icon_circle.color = tier_color
	# Positioned in _on_resized after we know the card size.
	add_child(_icon_circle)

	# Upgrade name — large bold text below the icon.
	_name_label = Label.new()
	_name_label.text                 = _upgrade_data.get("title", "")
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
	_name_label.add_theme_font_override("font", UIFonts.primary_bold())
	_name_label.add_theme_font_size_override("font_size", 15)
	add_child(_name_label)

	# Description — smaller text below the name.
	_desc_label = Label.new()
	_desc_label.text                 = _upgrade_data.get("description", "")
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80, 1.0))
	_desc_label.add_theme_font_size_override("font_size", 12)
	add_child(_desc_label)

	# Sub-label — dim text at the bottom, used for equipment cards
	# to show which trap and stat are affected.
	_sub_label = Label.new()
	_sub_label.text                 = _upgrade_data.get("sub_label", "")
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_sub_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60, 1.0))
	_sub_label.add_theme_font_size_override("font_size", 11)
	add_child(_sub_label)

	resized.connect(_on_resized)
	call_deferred("_on_resized")


func _on_resized() -> void:
	if size.x <= 0.0:
		return

	var w  := size.x
	var h  := size.y
	var px := 10.0   # horizontal padding

	# Icon circle — 36×36 px, centred horizontally, ~30% from the top.
	var icon_sz  := 36.0
	var icon_x   := (w - icon_sz) * 0.5
	var icon_y   := h * 0.28
	if _icon_circle:
		_icon_circle.position = Vector2(icon_x, icon_y)
		_icon_circle.size     = Vector2(icon_sz, icon_sz)

	# Name label — below icon.
	if _name_label:
		_name_label.position = Vector2(px, icon_y + icon_sz + 10.0)
		_name_label.size     = Vector2(w - px * 2.0, 50.0)

	# Description label — below name.
	if _desc_label:
		_desc_label.position = Vector2(px, icon_y + icon_sz + 65.0)
		_desc_label.size     = Vector2(w - px * 2.0, 60.0)

	# Sub-label — pinned to near the bottom.
	if _sub_label:
		_sub_label.position = Vector2(px, h - 36.0)
		_sub_label.size     = Vector2(w - px * 2.0, 30.0)


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

	# Check if the tap falls within this card's rect.
	var local_pos: Vector2
	if event is InputEventScreenTouch:
		local_pos = to_local(event.position)
	else:
		local_pos = to_local(event.global_position)

	if Rect2(Vector2.ZERO, size).has_point(local_pos):
		_select()
		get_viewport().set_input_as_handled()


func _select() -> void:
	_selected = true
	# Dim the card to give visual feedback before the screen closes.
	modulate = Color(0.6, 0.6, 0.6, 1.0)
	card_selected.emit(_upgrade_data)
