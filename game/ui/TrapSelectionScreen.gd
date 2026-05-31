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

## Base offer and pick counts — scaled by the Wider Selection permanent upgrade.
## Use _offer_count() and _pick_count() everywhere rather than these directly.
const BASE_OFFER_COUNT: int = 3
const BASE_PICK_COUNT:  int = 2

## Probability that the last slot is a boost rather than a trap.
const BOOST_SLOT_CHANCE: float = 0.5


func _offer_count() -> int:
	return 4 if GameState.wider_selection_tier >= 1 else BASE_OFFER_COUNT

func _pick_count() -> int:
	return 3 if GameState.wider_selection_tier >= 2 else BASE_PICK_COUNT


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
var _offered_count:   int        = 0
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

	# "PICK N" sub-header.
	var sub := Label.new()
	sub.text                 = "PICK %d" % _pick_count()
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
	var offer      := _offer_count()
	var total_w    := CARD_W * float(offer) + CARD_GAP * float(offer - 1)
	var start_x    := (1280.0 - total_w) * 0.5
	var card_y     := 148.0

	for i in offer:
		var slot: Dictionary = _offered_slots[i]
		var card := _build_card_for_slot(slot)
		card.position     = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card.size         = Vector2(CARD_W, CARD_H)
		card.process_mode = Node.PROCESS_MODE_ALWAYS
		card.card_selected.connect(_on_card_toggled.bind(card, slot))
		add_child(card)
		_cards.append(card)

	# "Start Buggin'" button — disabled until PICK_COUNT cards are selected.
	# Styled and structured identically to the hub screen's Start Buggin' button.
	_start_btn = _make_start_button()
	_start_btn.disabled     = true
	_start_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.position = Vector2((1280.0 - 280.0) * 0.5, card_y + CARD_H + 18.0)
	# store offer count for use in _on_card_toggled
	_offered_count = offer
	_start_btn.size     = Vector2(280.0, 54.0)
	add_child(_start_btn)


# ---------------------------------------------------------------------------
# Slot generation
# ---------------------------------------------------------------------------

## Builds OFFER_COUNT slots: always 2 traps, third slot is boost or trap.
##
## Selection is cost-weighted: weight = 1/cost, so cheaper units appear more
## often. Picks are without replacement so the same type cannot appear twice.
##
## Ground-damage guarantee: at least one offered trap must deal direct HP
## damage to ground enemies. Glue Board (utility slow) and Fly Strip Launcher
## (flying-only) do not qualify. The check is explicit so it holds if more
## utility or flying-only traps are added to the roster later.
func _generate_slots() -> Array:
	# Build candidate lists with per-item weights.
	var trap_candidates: Array = []
	for t in range(6):
		trap_candidates.append({
			"category": "trap", "type": t,
			"weight": 1.0 / float(Trap.STATS[t]["cost"]),
		})

	var boost_candidates: Array = []
	for b in range(5):
		boost_candidates.append({
			"category": "boost", "type": b,
			"weight": 1.0 / float(BoostUnit.STATS[b]["cost"]),
		})

	# Fill all but the last slot with traps (without replacement).
	var slots: Array = []
	for _i in range(_offer_count() - 1):
		var pick := _weighted_pick(trap_candidates)
		slots.append({ "category": pick["category"], "type": pick["type"] })

	# Last slot: boost or trap at the configured probability.
	var last_pick: Dictionary
	if randf() < BOOST_SLOT_CHANCE:
		last_pick = _weighted_pick(boost_candidates)
	else:
		last_pick = _weighted_pick(trap_candidates)
	slots.append({ "category": last_pick["category"], "type": last_pick["type"] })

	# Ground-damage guarantee: at least one offered trap must deal direct HP
	# damage to ground enemies. Glue Board (slow only) and Fly Strip Launcher
	# (flying-only) do not qualify. If no qualifying trap was selected, replace
	# one non-qualifying trap slot with a weighted pick from the qualifying set.
	var has_ground_damage_trap := false
	for slot in slots:
		if slot["category"] == "trap" and slot["type"] in Trap.GROUND_DAMAGE_TYPES:
			has_ground_damage_trap = true
			break

	if not has_ground_damage_trap:
		var ground_candidates: Array = []
		for t in Trap.GROUND_DAMAGE_TYPES:
			ground_candidates.append({
				"category": "trap", "type": t,
				"weight": 1.0 / float(Trap.STATS[t]["cost"]),
			})
		var replacement := _weighted_pick(ground_candidates)
		for i in slots.size():
			if slots[i]["category"] == "trap" and not (slots[i]["type"] in Trap.GROUND_DAMAGE_TYPES):
				slots[i] = { "category": "trap", "type": replacement["type"] }
				break

	slots.shuffle()
	return slots


## Selects one candidate by weight, removes it from candidates, and returns it.
## Weight = 1/cost means cheaper items have proportionally higher selection odds.
## Modifies candidates in-place so the same entry cannot be chosen twice.
func _weighted_pick(candidates: Array) -> Dictionary:
	var total: float = 0.0
	for item in candidates:
		total += item["weight"]
	var roll := randf() * total
	var accumulated := 0.0
	for i in candidates.size():
		accumulated += candidates[i]["weight"]
		if roll <= accumulated:
			var chosen: Dictionary = candidates[i]
			candidates.remove_at(i)
			return chosen
	# Floating-point safety: roll landed exactly on total — return the last entry.
	var last: Dictionary = candidates[-1]
	candidates.remove_at(candidates.size() - 1)
	return last


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

## Called when any card is tapped. Updates selection lists then refreshes all
## card states — dimming and blocking unchosen cards when the limit is reached,
## restoring them if a previously chosen card is deselected.
func _on_card_toggled(_data: Dictionary, card: UpgradeCard, slot: Dictionary) -> void:
	var category: String = slot["category"]
	var item_type: int   = slot["type"]

	if card.is_card_selected():
		var total: int = _selected_traps.size() + _selected_boosts.size()
		if total >= _pick_count():
			# Safety net — at-limit cards have mouse_filter=IGNORE so this
			# normally won't fire, but guard just in case.
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
	_start_btn.disabled = picked < _pick_count()
	_refresh_card_states(picked)


## Updates each card's input filter based on how many picks have been made.
## Selected gold ring is owned by UpgradeCard._on_select_pressed().
##   Selected:                  full brightness, input on (can deselect)
##   Unselected, picks left:    full brightness, input on (can select)
##   Unselected, at pick limit: dimmed (0.4),    input off (blocked)
func _refresh_card_states(picked: int) -> void:
	var at_limit: bool = picked >= PICK_COUNT
	for c in _cards:
		var card := c as UpgradeCard
		if card.is_card_selected():
			card.modulate     = Color(1.0, 1.0, 1.0, 1.0)
			card.mouse_filter = Control.MOUSE_FILTER_STOP
		elif at_limit:
			card.modulate     = Color(0.4, 0.4, 0.4, 1.0)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			card.modulate     = Color(1.0, 1.0, 1.0, 1.0)
			card.mouse_filter = Control.MOUSE_FILTER_STOP


# ---------------------------------------------------------------------------
# Button factory — mirrors StartScreen._make_icon_button / _apply_green_btn_style
# ---------------------------------------------------------------------------

func _make_start_button() -> Button:
	var btn := Button.new()
	btn.text       = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(280.0, 54.0)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_apply_green_btn_style(btn)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment   = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := TextureRect.new()
	icon.texture             = load("res://assets/uninfested.png") as Texture2D
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text                = "Start Buggin'"
	lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90, 1.0))
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	return btn


func _apply_green_btn_style(btn: Button) -> void:
	const BORDER := Color(0.22, 0.60, 0.04, 1.0)
	const BORDER_DIM := Color(0.12, 0.35, 0.02, 0.55)
	for state: Array in [
		["normal",   Color(0.04, 0.25, 0.00, 1.0),  BORDER],
		["hover",    Color(0.07, 0.33, 0.01, 1.0),  BORDER],
		["pressed",  Color(0.02, 0.16, 0.00, 1.0),  BORDER],
		["disabled", Color(0.02, 0.12, 0.00, 0.55), BORDER_DIM],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = state[2]
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)


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
