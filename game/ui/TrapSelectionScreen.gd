## TrapSelectionScreen.gd
## Full-screen overlay shown at the start of each run, before wave 1.
##
## Presents 3 cards: always 2 trap types, plus a third slot that is a boost
## 50% of the time and a third trap otherwise. The player picks exactly 2,
## then taps "Start Buggin'" to confirm. Chosen traps and boosts are emitted
## via loadout_selected so Arena can unlock them in GameState.
##
## Visual design mirrors LevelUpScreen: same card dimensions, dim overlay,
## header, and card layout. Cards use each unit's identity colour.
##
## The pick and offer counts are constants here. The Wider Selection meta
## upgrade will increase them in a future pass.

extends CanvasLayer

const UIFonts     = preload("res://ui/UIFonts.gd")
const Trap        = preload("res://traps/Trap.gd")
const BoostUnit   = preload("res://boosts/BoostUnit.gd")
const UpgradeCard = preload("res://ui/UpgradeCard.gd")


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player confirms their choices.
## trap_types and boost_types contain the chosen int values (either may be empty).
signal loadout_selected(trap_types: Array[int], boost_types: Array[int])


# ---------------------------------------------------------------------------
# Layout constants — match LevelUpScreen for visual consistency
# ---------------------------------------------------------------------------

const CARD_W:   float = 190.0
const CARD_H:   float = 310.0
const CARD_GAP: float = 20.0

## Cards offered and cards the player must pick.
## Scaled by the Wider Selection meta upgrade in a future pass.
const OFFER_COUNT: int = 3
const PICK_COUNT:  int = 2

## Probability that the third slot is a boost rather than a third trap.
const BOOST_SLOT_CHANCE: float = 0.5


# ---------------------------------------------------------------------------
# Static display data per trap and boost type.
# Descriptions condensed for card readability.
# ---------------------------------------------------------------------------

const TRAP_DISPLAY: Dictionary = {
	0: { "name": "Snap Trap",          "desc": "Targets the nearest pest. Fast fire rate, low damage. The only ground trap that can also hit flying pests." },
	1: { "name": "Zapper",             "desc": "Targets the pest farthest along the path. Very slow rate, very high damage. Cannot hit flying pests." },
	2: { "name": "Fogger",             "desc": "Fires an expanding cloud that damages all pests from closest to farthest. Cannot hit flying pests." },
	3: { "name": "Glue Board",         "desc": "Pulses adhesive every few seconds, slowing all ground pests in range at the moment of each pulse." },
	4: { "name": "Fly Strip Launcher", "desc": "Targets flying pests only. Releases a sticky cloud on impact that slows and damages over time." },
	5: { "name": "Bait Station",       "desc": "Enemies walk straight over it. Pulses poison onto every pest in range, dealing damage over time." },
}

const BOOST_DISPLAY: Dictionary = {
	0: { "name": "Pheromone Dispenser", "desc": "Aura boost. All traps within range deal increased damage." },
	1: { "name": "Compressor",          "desc": "Aura boost. All traps within range fire more often." },
	2: { "name": "Cash Register",       "desc": "Earns Bug Bucks each wave and pays a bonus per kill inside its aura." },
	3: { "name": "Air Freshener",       "desc": "Absorbs infestation from pests that escape through its aura. Perishable." },
	4: { "name": "Quarantine Marker",   "desc": "Restores infestation for every kill inside its aura. Perishable." },
}


# ---------------------------------------------------------------------------
# Internal state
#
# Each offered slot: { "category": "trap"|"boost", "type": int }
# ---------------------------------------------------------------------------

var _offered_slots:   Array      = []
var _selected_traps:  Array[int] = []
var _selected_boosts: Array[int] = []
var _cards:           Array      = []   # UpgradeCard nodes, parallel to _offered_slots
var _start_btn:       Button     = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_screen()


func _build_screen() -> void:
	_offered_slots = _generate_slots()

	# Dim overlay.
	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.70)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Header.
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

	# Cards.
	var total_w := CARD_W * float(OFFER_COUNT) + CARD_GAP * float(OFFER_COUNT - 1)
	var start_x := (1280.0 - total_w) * 0.5
	var card_y  := 148.0

	for i in OFFER_COUNT:
		var slot: Dictionary = _offered_slots[i]
		var card := _build_card_for_slot(slot)
		card.position     = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card.size         = Vector2(CARD_W, CARD_H)
		card.process_mode = Node.PROCESS_MODE_ALWAYS
		card.modulate     = Color(0.65, 0.65, 0.65, 1.0)   # start dimmed until selected
		card.card_selected.connect(_on_card_toggled.bind(card, slot))
		add_child(card)
		_cards.append(card)

	# "Start Buggin'" button — disabled until PICK_COUNT cards are selected.
	_start_btn = Button.new()
	_start_btn.text                = "START BUGGIN'"
	_start_btn.disabled            = true
	_start_btn.focus_mode          = Control.FOCUS_NONE
	_start_btn.custom_minimum_size = Vector2(260.0, 54.0)
	_start_btn.process_mode        = Node.PROCESS_MODE_ALWAYS
	_start_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_start_btn.add_theme_font_size_override("font_size", 22)
	_start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.position = Vector2((1280.0 - 260.0) * 0.5, card_y + CARD_H + 18.0)
	_start_btn.size     = Vector2(260.0, 54.0)
	add_child(_start_btn)


# ---------------------------------------------------------------------------
# Slot generation
# ---------------------------------------------------------------------------

## Builds OFFER_COUNT slots: always 2 traps, third slot is boost or trap.
func _generate_slots() -> Array:
	var trap_pool:  Array[int] = [0, 1, 2, 3, 4, 5]
	var boost_pool: Array[int] = [0, 1, 2, 3, 4]
	trap_pool.shuffle()
	boost_pool.shuffle()

	var slots: Array = []
	slots.append({ "category": "trap", "type": trap_pool[0] })
	slots.append({ "category": "trap", "type": trap_pool[1] })

	if randf() < BOOST_SLOT_CHANCE:
		slots.append({ "category": "boost", "type": boost_pool[0] })
	else:
		slots.append({ "category": "trap",  "type": trap_pool[2] })

	slots.shuffle()
	return slots


# ---------------------------------------------------------------------------
# Card building
# ---------------------------------------------------------------------------

func _build_card_for_slot(slot: Dictionary) -> UpgradeCard:
	if slot["category"] == "boost":
		return _build_boost_card(slot["type"])
	return _build_trap_card(slot["type"])


func _build_trap_card(trap_type: int) -> UpgradeCard:
	var display: Dictionary = TRAP_DISPLAY.get(trap_type, {})
	var data := {
		"id":          "trap_%d" % trap_type,
		"category":    "trap",
		"tier":        UpgradeCard.Tier.COMMON,
		"tier_label":  display.get("name", "Trap").to_upper(),
		"title":       display.get("name", "Trap"),
		"stat_name":   "TRAP",
		"impact_line": "Cost: %d Bug Bucks" % Trap.STATS[trap_type].get("cost", 0),
		"plain_text":  display.get("desc", ""),
	}
	var card := UpgradeCard.new()
	card.toggleable   = true
	card.custom_color = Trap.STATS[trap_type].get("color", Color.WHITE)
	card.setup(data)
	return card


func _build_boost_card(boost_type: int) -> UpgradeCard:
	var display: Dictionary = BOOST_DISPLAY.get(boost_type, {})
	var data := {
		"id":          "boost_%d" % boost_type,
		"category":    "boost",
		"tier":        UpgradeCard.Tier.COMMON,
		"tier_label":  display.get("name", "Boost").to_upper(),
		"title":       display.get("name", "Boost"),
		"stat_name":   "BOOST",
		"impact_line": "Cost: %d Bug Bucks" % BoostUnit.STATS[boost_type].get("cost", 0),
		"plain_text":  display.get("desc", ""),
	}
	var card := UpgradeCard.new()
	card.toggleable   = true
	card.custom_color = BoostUnit.GLOW_COLORS[boost_type]
	card.setup(data)
	return card


# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------

## Called when any card is tapped. Enforces the PICK_COUNT limit across both
## traps and boosts — rejects a third selection immediately via force_deselect.
func _on_card_toggled(_data: Dictionary, card: UpgradeCard, slot: Dictionary) -> void:
	var category: String = slot["category"]
	var item_type: int   = slot["type"]

	if card.is_card_selected():
		var total: int = _selected_traps.size() + _selected_boosts.size()
		if total >= PICK_COUNT:
			card.force_deselect()
			return
		if category == "boost":
			_selected_boosts.append(item_type)
		else:
			_selected_traps.append(item_type)
	else:
		if category == "boost":
			_selected_boosts.erase(item_type)
		else:
			_selected_traps.erase(item_type)

	var picked: int = _selected_traps.size() + _selected_boosts.size()
	_start_btn.disabled = picked < PICK_COUNT


# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	loadout_selected.emit(_selected_traps.duplicate(), _selected_boosts.duplicate())
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
