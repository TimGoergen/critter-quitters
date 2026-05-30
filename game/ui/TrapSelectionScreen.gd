## TrapSelectionScreen.gd
## Full-screen overlay shown at the start of each run, before wave 1.
##
## Presents 3 randomly chosen trap types as toggle-select cards. The player
## picks exactly 2, then taps "Start Buggin'" to begin the run. The chosen
## trap types are emitted via traps_selected so Arena can unlock them.
##
## Visual design mirrors LevelUpScreen: same card dimensions, dim overlay,
## header, and card layout. Cards use each trap's identity colour instead
## of upgrade-tier colours.
##
## The pick and offer counts are constants here. The Wider Selection meta
## upgrade will increase them in a future pass.

extends CanvasLayer

const UIFonts     = preload("res://ui/UIFonts.gd")
const Trap        = preload("res://traps/Trap.gd")
const UpgradeCard = preload("res://ui/UpgradeCard.gd")


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player confirms their choices.
## types contains exactly PICK_COUNT TrapType int values.
signal traps_selected(types: Array[int])


# ---------------------------------------------------------------------------
# Layout constants — match LevelUpScreen for visual consistency
# ---------------------------------------------------------------------------

const CARD_W:   float = 190.0
const CARD_H:   float = 310.0
const CARD_GAP: float = 20.0

## How many trap types are offered and how many the player must pick.
## Scaled by the Wider Selection meta upgrade in a future pass.
const OFFER_COUNT: int = 3
const PICK_COUNT:  int = 2


# ---------------------------------------------------------------------------
# Static display data — name and short description per trap type.
# Descriptions are condensed from Trap.get_description() for card readability.
# ---------------------------------------------------------------------------

const TRAP_DISPLAY: Dictionary = {
	0: { "name": "Snap Trap",          "desc": "Targets the nearest pest. Fast fire rate, low damage. The only ground trap that can also hit flying pests." },
	1: { "name": "Zapper",             "desc": "Targets the pest farthest along the path. Very slow rate, very high damage. Cannot hit flying pests." },
	2: { "name": "Fogger",             "desc": "Fires an expanding cloud that damages all pests from closest to farthest. Cannot hit flying pests." },
	3: { "name": "Glue Board",         "desc": "Pulses adhesive every few seconds, slowing all ground pests in range at the moment of each pulse." },
	4: { "name": "Fly Strip Launcher", "desc": "Targets flying pests only. Releases a sticky cloud on impact that slows and damages over time." },
	5: { "name": "Bait Station",       "desc": "Enemies walk straight over it. Pulses poison onto every pest in range, dealing damage over time." },
}


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _offered_types:  Array[int]     = []
var _selected_types: Array[int]     = []
var _cards:          Array          = []   # Array of UpgradeCard nodes
var _start_btn:      Button         = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_screen()


func _build_screen() -> void:
	# Pick OFFER_COUNT random trap types.
	var all_types: Array[int] = range(Trap.TrapType.size())
	all_types.shuffle()
	for i in OFFER_COUNT:
		_offered_types.append(all_types[i])

	# Dim overlay — covers the full virtual viewport.
	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.70)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# "CHOOSE YOUR GEAR" header.
	var header := Label.new()
	header.text                 = "CHOOSE YOUR GEAR"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UIFonts.primary_bold())
	header.add_theme_font_size_override("font_size", 80)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	header.process_mode         = Node.PROCESS_MODE_ALWAYS
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top    = 5.0
	header.offset_bottom = 100.0
	add_child(header)

	# "PICK 2" sub-header.
	var sub := Label.new()
	sub.text                 = "PICK %d" % PICK_COUNT
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UIFonts.primary_bold())
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	sub.process_mode         = Node.PROCESS_MODE_ALWAYS
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top    = 103.0
	sub.offset_bottom = 140.0
	add_child(sub)

	# Three trap cards, horizontally centred.
	var total_w := CARD_W * float(OFFER_COUNT) + CARD_GAP * float(OFFER_COUNT - 1)
	var start_x := (1280.0 - total_w) * 0.5
	var card_y  := 148.0

	for i in OFFER_COUNT:
		var trap_type: int = _offered_types[i]
		var card := _build_trap_card(trap_type)
		card.position    = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card.size        = Vector2(CARD_W, CARD_H)
		card.process_mode = Node.PROCESS_MODE_ALWAYS
		card.card_selected.connect(_on_card_toggled.bind(trap_type, card))
		# Start dimmed — cards are "unselected" until tapped.
		card.modulate = Color(0.65, 0.65, 0.65, 1.0)
		add_child(card)
		_cards.append(card)

	# "Start Buggin'" button — disabled until PICK_COUNT cards are selected.
	_start_btn = Button.new()
	_start_btn.text              = "START BUGGIN'"
	_start_btn.disabled          = true
	_start_btn.focus_mode        = Control.FOCUS_NONE
	_start_btn.custom_minimum_size = Vector2(260.0, 54.0)
	_start_btn.process_mode      = Node.PROCESS_MODE_ALWAYS
	_start_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_start_btn.add_theme_font_size_override("font_size", 22)
	_start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_start_btn.pressed.connect(_on_start_pressed)
	# Position centred horizontally, near the bottom of the virtual viewport.
	var btn_x := (1280.0 - 260.0) * 0.5
	var btn_y := card_y + CARD_H + 18.0
	_start_btn.position = Vector2(btn_x, btn_y)
	_start_btn.size     = Vector2(260.0, 54.0)
	add_child(_start_btn)


# ---------------------------------------------------------------------------
# Card building
# ---------------------------------------------------------------------------

## Builds one UpgradeCard configured as a toggleable trap card.
func _build_trap_card(trap_type: int) -> UpgradeCard:
	var display: Dictionary = TRAP_DISPLAY.get(trap_type, {})
	var trap_name: String   = display.get("name", "Trap")
	var trap_desc: String   = display.get("desc", "")
	var cost: int           = Trap.STATS[trap_type].get("cost", 0)
	var trap_color: Color   = Trap.STATS[trap_type].get("color", Color.WHITE)

	var data := {
		"id":          "trap_%d" % trap_type,
		"category":    "trap",
		"tier":        UpgradeCard.Tier.COMMON,
		"tier_label":  trap_name.to_upper(),
		"title":       trap_name,
		"stat_name":   "",
		"impact_line": "Cost: %d Bug Bucks" % cost,
		"plain_text":  trap_desc,
		"trap_type":   trap_type,
	}

	var card := UpgradeCard.new()
	card.toggleable   = true
	card.custom_color = trap_color
	card.setup(data)
	return card


# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------

## Called whenever a trap card is tapped. Enforces the PICK_COUNT limit:
## if the player tries to select a third card, revert the tap immediately.
func _on_card_toggled(_data: Dictionary, trap_type: int, card: UpgradeCard) -> void:
	if card.is_card_selected():
		if _selected_types.size() >= PICK_COUNT:
			# At the limit — reject this selection without giving feedback.
			card.force_deselect()
			return
		_selected_types.append(trap_type)
	else:
		_selected_types.erase(trap_type)

	_start_btn.disabled = _selected_types.size() < PICK_COUNT


# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	traps_selected.emit(_selected_types.duplicate())
	queue_free()


# ---------------------------------------------------------------------------
# Input blocking — same rationale as LevelUpScreen
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch \
			or event is InputEventMouseButton \
			or event is InputEventScreenDrag \
			or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
