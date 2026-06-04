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

const CARD_W:   float = 372.0
const CARD_H:   float = 330.0   # tall enough to hold title + image + cost + description
const CARD_GAP: float = 10.0

## Base offer and pick counts — scaled by the Wider Selection permanent upgrade.
## Use _offer_count() and _pick_count() everywhere rather than these directly.
const BASE_OFFER_COUNT: int = 3
const BASE_PICK_COUNT:  int = 2

## Snap Trap and Fogger — affordable, ground-damage traps guaranteed in slot 1.
const TIER_ONE_TRAP_TYPES: Array[int] = [0, 2]

## Probability that each "wildcard" slot (slot 3 onward) offers a boost instead of a trap.
const BOOST_SLOT_CHANCE: float = 0.20


## Returns how many trap/boost cards to display at run start.
## Wider Selection tiers 1-10 progressively increase the offer count (3→6 max)
## and pick count (2→4 max) in paired steps: each even tier adds one more pick,
## each odd tier adds one more offer. Hard caps: 6 offers, 4 picks.
func _offer_count() -> int:
	var t := GameState.wider_selection_tier
	return mini(3 + (t + 1) / 2, 6)   # t=0→3, t=1→4, t=3→5, t=5+→6 (max)

func _pick_count() -> int:
	var t := GameState.wider_selection_tier
	return mini(2 + t / 2, 4)   # t=0→2, t=2→3, t=4+→4 (max)


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

	# Solid background — same dark color as StartScreen so the arena is fully hidden.
	var dim := ColorRect.new()
	dim.color        = Color(0.06, 0.06, 0.10, 1.0)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Header band constants — title and Start button share the same horizontal row.
	const HEADER_H: float = 90.0   # height of the title/button band
	const SUB_H:    float = 34.0   # height of the pick-count row below

	# "CHOOSE YOUR GEAR" — left-aligned, top-left of the screen.
	var header := Label.new()
	header.text                 = "CHOOSE YOUR GEAR"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UIFonts.primary_bold())
	header.add_theme_font_size_override("font_size", 44)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	header.process_mode         = Node.PROCESS_MODE_ALWAYS
	header.position             = Vector2(24.0, 8.0)
	header.size                 = Vector2(880.0, HEADER_H - 10.0)
	add_child(header)

	# "PICK N DEFENSES TO START" — left-aligned, directly below the title.
	var sub := Label.new()
	sub.text                 = "PICK %d DEFENSES TO START" % _pick_count()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UIFonts.primary_bold())
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	sub.process_mode         = Node.PROCESS_MODE_ALWAYS
	sub.position             = Vector2(24.0, HEADER_H)
	sub.size                 = Vector2(880.0, SUB_H)
	add_child(sub)

	# Cards.
	var offer := _offer_count()
	# Derive card width from a fixed side margin so the cards sit well clear of the screen edges.
	# SIDE_MARGIN ≈ 3× the implicit centred margin of the original layout.
	# When Wider Selection offers more than 3 cards the margin shrinks proportionally,
	# but card_w is still capped at CARD_W so extra offers never inflate beyond the default.
	const SIDE_MARGIN: float = 80.0
	var card_w: float = minf(
		(1280.0 - SIDE_MARGIN * 2.0 - CARD_GAP * float(offer - 1)) / float(offer),
		CARD_W
	)
	var total_w := card_w * float(offer) + CARD_GAP * float(offer - 1)
	var start_x := (1280.0 - total_w) * 0.5
	# 24 px gap so the selection ring (8 px outset) clears the sub-header text above.
	var card_y  := HEADER_H + SUB_H + 24.0

	# Font scale is doubled from the original formula so text is large enough for mobile.
	# title_font_scale is reset to 1.0 because font_scale itself is now doubled —
	# applying both multipliers would make the title disproportionately large.
	var width_ratio:      float = card_w / CARD_W
	var card_font_scale:  float = clampf(0.845 * width_ratio, 0.585, 0.845)
	var card_title_scale: float = 1.0

	# Cards fill all remaining vertical space below the header rows.
	var card_h: float = 600.0 - card_y - 16.0

	for i in offer:
		var slot: Dictionary = _offered_slots[i]
		var card := _build_card_for_slot(slot, card_font_scale, card_title_scale)
		card.position     = Vector2(start_x + i * (card_w + CARD_GAP), card_y)
		card.size         = Vector2(card_w, card_h)
		card.process_mode = Node.PROCESS_MODE_ALWAYS
		# Cap image height at 40% above baseline so images are larger but don't
		# crowd out the description text despite the doubled font_scale.
		card.image_h_max  = 122.0
		card.card_selected.connect(_on_card_toggled.bind(card, slot))
		add_child(card)
		_cards.append(card)

	# "Start Buggin'" button — right edge aligned to the right edge of the rightmost panel,
	# vertically centred in the space between the top of the screen and the top of the panels.
	const BTN_W: float = 400.0
	_start_btn = _make_start_button()
	_start_btn.disabled             = true
	_start_btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	_start_btn.custom_minimum_size  = Vector2(BTN_W, 76.0)
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.position = Vector2(start_x + total_w - BTN_W, (card_y - 76.0) * 0.5)
	_start_btn.size     = Vector2(BTN_W, 76.0)
	_offered_count      = offer
	add_child(_start_btn)


# ---------------------------------------------------------------------------
# Slot generation
# ---------------------------------------------------------------------------

## Builds OFFER_COUNT slots with three distinct rules:
##
##   Slot 1 — Tier-1 trap (Snap Trap or Fogger): the most affordable and
##             versatile ground-damage options. Weighted by 1/cost.
##   Slot 2 — Any trap, weighted by 1/cost. Cannot duplicate slot 1.
##   Slot 3+ — Wildcard: BOOST_SLOT_CHANCE probability of a cost-weighted
##              boost; otherwise a cost-weighted trap (no trap duplicates).
##              If every trap type is already used, falls back to a boost.
##
## The tier-1 guarantee in slot 1 replaces the old post-hoc ground-damage
## check — the structural rule is clearer and more predictable for the player.
func _generate_slots() -> Array:
	var slots:            Array      = []
	var used_trap_types:  Array[int] = []
	var used_boost_types: Array[int] = []

	# --- Slot 1: always a tier-1 trap ---
	var tier1_candidates: Array = []
	for t in TIER_ONE_TRAP_TYPES:
		tier1_candidates.append({
			"category": "trap", "type": t,
			"weight": 1.0 / float(Trap.STATS[t]["cost"]),
		})
	var tier1_pick := _weighted_pick(tier1_candidates)
	slots.append({ "category": "trap", "type": tier1_pick["type"] })
	used_trap_types.append(tier1_pick["type"])

	# --- Slot 2: any trap, excluding the tier-1 choice ---
	var any_trap_candidates: Array = []
	for t in range(6):
		if t not in used_trap_types:
			any_trap_candidates.append({
				"category": "trap", "type": t,
				"weight": 1.0 / float(Trap.STATS[t]["cost"]),
			})
	var slot2_pick := _weighted_pick(any_trap_candidates)
	slots.append({ "category": "trap", "type": slot2_pick["type"] })
	used_trap_types.append(slot2_pick["type"])

	# --- Slot 3+: wildcard (boost at BOOST_SLOT_CHANCE, otherwise trap) ---
	for _i in range(_offer_count() - 2):
		# Build a boost pool that excludes any boost type already offered.
		var available_boosts: Array = []
		for b in range(5):
			if b not in used_boost_types:
				available_boosts.append({
					"category": "boost", "type": b,
					"weight": 1.0 / float(BoostUnit.STATS[b]["cost"]),
				})

		var remaining_traps: Array = []
		for t in range(6):
			if t not in used_trap_types:
				remaining_traps.append({
					"category": "trap", "type": t,
					"weight": 1.0 / float(Trap.STATS[t]["cost"]),
				})

		var offer_boost := randf() < BOOST_SLOT_CHANCE and not available_boosts.is_empty()

		if offer_boost:
			var boost_pick := _weighted_pick(available_boosts)
			slots.append({ "category": "boost", "type": boost_pick["type"] })
			used_boost_types.append(boost_pick["type"])
		elif not remaining_traps.is_empty():
			var trap_pick := _weighted_pick(remaining_traps)
			slots.append({ "category": "trap", "type": trap_pick["type"] })
			used_trap_types.append(trap_pick["type"])
		elif not available_boosts.is_empty():
			# All trap types are exhausted — fall back to a unique boost.
			var boost_pick := _weighted_pick(available_boosts)
			slots.append({ "category": "boost", "type": boost_pick["type"] })
			used_boost_types.append(boost_pick["type"])
		else:
			# All 6 traps and all 5 boosts are already offered (only possible at
			# very high Wider Selection tiers) — repeat a boost as a last resort.
			var fallback_candidates: Array = []
			for b in range(5):
				fallback_candidates.append({
					"category": "boost", "type": b,
					"weight": 1.0 / float(BoostUnit.STATS[b]["cost"]),
				})
			var boost_pick := _weighted_pick(fallback_candidates)
			slots.append({ "category": "boost", "type": boost_pick["type"] })

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

func _build_card_for_slot(slot: Dictionary, f_scale: float, t_scale: float) -> UpgradeCard:
	if slot["category"] == "boost":
		return _build_boost_card(slot["type"], f_scale, t_scale)
	return _build_trap_card(slot["type"], f_scale, t_scale)


func _build_trap_card(trap_type: int, f_scale: float, t_scale: float) -> UpgradeCard:
	var display: Dictionary = TRAP_DISPLAY.get(trap_type, {})
	var data := {
		"id":          "trap_%d" % trap_type,
		"category":    "trap",
		"item_type":   trap_type,   # enables the SVG preview image in UpgradeCard
		"tier":        UpgradeCard.Tier.COMMON,
		"tier_label":  display.get("name", "Trap").to_upper(),
		"title":       display.get("name", "Trap"),
		"stat_name":   "",          # no stat label — saves layout space for the image
		"bucks_cost":  Trap.STATS[trap_type].get("cost", 0),
		"impact_line": "",   # cost is displayed as coin icon + number via bucks_cost
		"plain_text":  display.get("desc", ""),
	}
	var card := UpgradeCard.new()
	card.toggleable           = true
	card.custom_color         = Trap.STATS[trap_type].get("color", Color.WHITE)
	card.font_scale           = f_scale
	card.title_font_scale     = t_scale
	card.use_identity_outline = true
	card.show_tier_badge      = false
	card.setup(data)
	return card


func _build_boost_card(boost_type: int, f_scale: float, t_scale: float) -> UpgradeCard:
	var display: Dictionary = BOOST_DISPLAY.get(boost_type, {})
	var data := {
		"id":          "boost_%d" % boost_type,
		"category":    "boost",
		"item_type":   boost_type,  # enables the SVG preview image in UpgradeCard
		"tier":        UpgradeCard.Tier.COMMON,
		"tier_label":  display.get("name", "Boost").to_upper(),
		"title":       display.get("name", "Boost"),
		"stat_name":   "",          # no stat label — saves layout space for the image
		"bucks_cost":  BoostUnit.STATS[boost_type].get("cost", 0),
		"impact_line": "",   # cost is displayed as coin icon + number via bucks_cost
		"plain_text":  display.get("desc", ""),
	}
	var card := UpgradeCard.new()
	card.toggleable           = true
	card.custom_color         = BoostUnit.GLOW_COLORS[boost_type]
	card.font_scale           = f_scale
	card.title_font_scale     = t_scale
	card.use_identity_outline = true
	card.show_tier_badge      = false
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
	var at_limit: bool = picked >= _pick_count()
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
	btn.custom_minimum_size = Vector2(392.0, 76.0)
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
	icon.custom_minimum_size = Vector2(45, 45)
	icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text                = "Start"
	lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 31)
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
	# Handle the start button as a safety net — Button._gui_input handles
	# emulated mouse events, but this fallback covers any gap on mobile.
	if event is InputEventScreenTouch and event.pressed:
		if _start_btn and not _start_btn.disabled:
			if Rect2(_start_btn.position, _start_btn.size).has_point(event.position):
				_on_start_pressed()
				get_viewport().set_input_as_handled()
				return

	# Swallow all pointer events so Arena never receives them while this screen is open.
	if event is InputEventScreenTouch \
			or event is InputEventMouseButton \
			or event is InputEventScreenDrag \
			or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
