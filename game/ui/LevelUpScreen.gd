## LevelUpScreen.gd
## Full-screen overlay shown when the player levels up.
##
## Pauses the game, presents three randomly generated upgrade cards, waits for
## the player to select one, applies it, then unpauses and removes itself.
##
## Extends CanvasLayer so it draws on top of the 3D arena and all other HUD
## elements. PROCESS_MODE_ALWAYS ensures it stays responsive while paused.

extends CanvasLayer

const UIFonts     = preload("res://ui/UIFonts.gd")
const UpgradeCard = preload("res://ui/UpgradeCard.gd")


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

## Emitted when the player selects a card. Arena.gd listens here to apply
## the upgrade. The Dictionary matches the format defined in UpgradeCard.gd.
signal upgrade_chosen(upgrade: Dictionary)


# ---------------------------------------------------------------------------
# Campaign buff definitions
##
## Each entry describes one possible campaign-level upgrade. The "magnitudes"
## array holds [common, professional, rare] bonus values. To add more campaign
## buffs in the future, append another entry here — no other changes required.
# ---------------------------------------------------------------------------

const CAMPAIGN_BUFFS: Array = [
	{
		"id": "dmg_all",
		"title": "Extermination Formula",
		"desc_template": "+%s%% damage to all traps",
		"magnitudes": [0.05, 0.10, 0.20],
	},
	{
		"id": "range_all",
		"title": "Extended Reach",
		"desc_template": "+%s%% range for all traps",
		"magnitudes": [0.05, 0.10, 0.20],
	},
	{
		"id": "firerate_all",
		"title": "Hair Trigger",
		"desc_template": "+%s%% fire rate for all traps",
		"magnitudes": [0.05, 0.10, 0.20],
	},
	{
		"id": "crit_chance_all",
		"title": "Sharpened Instincts",
		"desc_template": "+%s%% crit chance for all traps",
		"magnitudes": [0.02, 0.04, 0.08],
	},
	{
		"id": "crit_dmg_all",
		"title": "Lethal Potency",
		"desc_template": "+%s%% crit damage for all traps",
		"magnitudes": [0.10, 0.20, 0.40],
	},
	{
		"id": "bucks_all",
		"title": "Invoice Padding",
		"desc_template": "+%s%% Bug Bucks from all kills",
		"magnitudes": [0.10, 0.20, 0.40],
	},
	{
		"id": "infestation_heal",
		"title": "Hazmat Protocol",
		"desc_template": "Each kill reduces Infestation by %s",
		"magnitudes": [0.002, 0.004, 0.008],
	},
	{
		"id": "upgrade_discount",
		"title": "Bulk Procurement",
		"desc_template": "-%s%% cost on all trap upgrades",
		"magnitudes": [0.05, 0.10, 0.20],
	},
]

## Human-readable names for the trap stats used in equipment card sub-labels.
const STAT_NAMES: Dictionary = {
	"damage":     "Damage",
	"range":      "Range",
	"fire_rate":  "Fire Rate",
	"duration":   "Duration",
	"crit_chance":"Crit Chance",
	"crit_dmg":   "Crit Damage",
}


# ---------------------------------------------------------------------------
# Tier roll probabilities
# ---------------------------------------------------------------------------

## Probability thresholds for tier selection. Roll a float in [0, 1):
##   roll < RARE_THRESHOLD      → Rare
##   roll < PRO_THRESHOLD       → Professional
##   otherwise                  → Common
const RARE_THRESHOLD: float = 0.01
const PRO_THRESHOLD:  float = 0.16   # 0.01 + 0.15


# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------

## Width of each upgrade card in virtual pixels.
const CARD_W: float = 190.0

## Height of each upgrade card in virtual pixels.
const CARD_H: float = 310.0

## Horizontal gap between cards.
const CARD_GAP: float = 20.0


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _trap_nodes: Array = []   # placed trap nodes passed in from Arena


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Called by Arena._on_level_up() immediately after instantiation.
## new_level is the level just reached (for display).
## trap_nodes_array is _trap_nodes.values() from Arena — used to build equipment cards.
func setup(new_level: int, trap_nodes_array: Array) -> void:
	_trap_nodes = trap_nodes_array
	# Draw on top of the game HUD but below settings dialogs.
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_screen(new_level)


func _build_screen(new_level: int) -> void:
	# Pause the game tree. This screen's PROCESS_MODE_ALWAYS keeps it responsive.
	get_tree().paused = true

	# Dim overlay — covers the full virtual viewport.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.60)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dim)

	# "LEVEL UP!" header label, centred near the top.
	var header := Label.new()
	header.text                 = "LEVEL %d" % new_level
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UIFonts.primary_bold())
	header.add_theme_font_size_override("font_size", 32)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top    = 60.0
	header.offset_bottom = 100.0
	header.process_mode  = Node.PROCESS_MODE_ALWAYS
	add_child(header)

	# Sub-header: "Choose an upgrade"
	var sub := Label.new()
	sub.text                 = "Choose an upgrade"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85, 1.0))
	sub.add_theme_font_size_override("font_size", 16)
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top    = 100.0
	sub.offset_bottom = 125.0
	sub.process_mode  = Node.PROCESS_MODE_ALWAYS
	add_child(sub)

	# Generate three upgrade cards and lay them out.
	var cards: Array = _generate_cards()
	_spawn_cards(cards)


# ---------------------------------------------------------------------------
# Card generation
# ---------------------------------------------------------------------------

## Generates 3 unique upgrade card data Dictionaries.
## Tiers are rolled independently per card. Category (equipment vs campaign)
## is chosen randomly, with a fallback to campaign if no eligible traps exist.
func _generate_cards() -> Array:
	var result: Array = []
	# Track which upgrade IDs have already been offered to avoid duplicates.
	var used_ids: Array = []

	for _i in 3:
		var tier   := _roll_tier()
		var card   := _build_card(tier, used_ids)
		result.append(card)
		used_ids.append(card.get("id", ""))

	return result


## Rolls a tier (Common / Professional / Rare) according to the defined probabilities.
func _roll_tier() -> int:
	var r := randf()
	if r < RARE_THRESHOLD:
		return UpgradeCard.Tier.RARE
	elif r < PRO_THRESHOLD:
		return UpgradeCard.Tier.PROFESSIONAL
	return UpgradeCard.Tier.COMMON


## Builds a card Dictionary for the given tier.
## Tries equipment first (50/50 split), falling back to campaign if no traps
## are eligible or the chosen upgrade ID is already in used_ids.
func _build_card(tier: int, used_ids: Array) -> Dictionary:
	# Try equipment first with a 50% probability.
	if randf() < 0.50:
		var equip_card := _build_equipment_card(tier, used_ids)
		if not equip_card.is_empty():
			return equip_card

	# Fall back to (or always choose) a campaign card.
	return _build_campaign_card(tier, used_ids)


## Tries to find an eligible placed trap and a non-maxed stat for an equipment card.
## Returns null if no eligible trap/stat combination exists.
func _build_equipment_card(tier: int, used_ids: Array) -> Dictionary:
	# Collect all placed traps that have at least one stat that can still be upgraded.
	var eligible: Array = []
	for trap in _trap_nodes:
		if not is_instance_valid(trap):
			continue
		if _get_upgradeable_stats(trap).size() > 0:
			eligible.append(trap)

	if eligible.is_empty():
		return {}   # no eligible traps — caller will use campaign instead

	# Pick a random trap, then a random upgradeable stat on that trap.
	eligible.shuffle()
	var trap = eligible[0]
	var stats := _get_upgradeable_stats(trap)
	stats.shuffle()
	var stat: String = stats[0]

	# Build a unique ID for this card so duplicate-prevention works.
	var unique_id := "equip_%s_%s" % [trap.get_instance_id(), stat]
	if unique_id in used_ids:
		# Already offered this exact upgrade — try a different stat on this trap.
		# GDScript has no for…else, so use a flag to detect whether we found one.
		var found := false
		for s in stats.slice(1):
			var alt_id := "equip_%s_%s" % [trap.get_instance_id(), s]
			if alt_id not in used_ids:
				stat = s
				unique_id = alt_id
				found = true
				break
		if not found:
			return {}   # no unique option found on this trap

	var trap_name: String  = trap.get_type_name()
	var stat_name: String  = STAT_NAMES.get(stat, stat)
	var tier_label: String = UpgradeCard.TIER_NAMES[tier]

	return {
		"id":          unique_id,
		"category":    "equipment",
		"tier":        tier,
		"title":       "Free Upgrade",
		"description": "%s — %s" % [trap_name, stat_name],
		"sub_label":   "%s quality" % tier_label,
		"magnitude":   0.0,       # not used for equipment cards
		"trap_node":   trap,
		"stat":        stat,
	}


## Returns a list of stat strings that are not yet maxed on this trap.
func _get_upgradeable_stats(trap: Node3D) -> Array:
	var result: Array = []
	if not trap.is_damage_maxed():
		result.append("damage")
	if not trap.is_range_maxed():
		result.append("range")
	# Fire rate is not applicable to passive traps (Glue Board, Bait Station).
	if not trap.is_passive() and not trap.is_rate_maxed():
		result.append("fire_rate")
	if trap.is_passive() and not trap.is_duration_maxed():
		result.append("duration")
	if not trap.is_crit_chance_maxed():
		result.append("crit_chance")
	if not trap.is_crit_damage_maxed():
		result.append("crit_dmg")
	return result


## Picks a campaign buff that has not already been offered this level-up.
## Returns a fully populated card Dictionary.
func _build_campaign_card(tier: int, used_ids: Array) -> Dictionary:
	# Shuffle a copy of the buff list and find the first one not already used.
	var pool := CAMPAIGN_BUFFS.duplicate()
	pool.shuffle()

	for buff in pool:
		if buff["id"] in used_ids:
			continue
		var magnitude: float = buff["magnitudes"][tier]

		# Format the description.
		# Magnitudes expressed as percentages are multiplied by 100 for display.
		# The Hazmat Protocol buff is a raw float (e.g. 0.002), shown as-is.
		var display_val: String
		if buff["id"] == "infestation_heal":
			display_val = "%.3f" % magnitude
		else:
			display_val = "%d" % roundi(magnitude * 100.0)

		return {
			"id":          buff["id"],
			"category":    "campaign",
			"tier":        tier,
			"title":       buff["title"],
			"description": buff["desc_template"] % display_val,
			"sub_label":   "",
			"magnitude":   magnitude,
			"trap_node":   null,
			"stat":        "",
		}

	# Safety fallback — should never reach here if the pool has ≥ 3 entries.
	return {
		"id": "dmg_all", "category": "campaign", "tier": tier,
		"title": "Extermination Formula", "description": "+5% damage to all traps",
		"sub_label": "", "magnitude": 0.05, "trap_node": null, "stat": "",
	}


# ---------------------------------------------------------------------------
# Card layout
# ---------------------------------------------------------------------------

## Instantiates three UpgradeCard controls, connects their signals, and lays
## them out horizontally centred in the virtual viewport (1280×600).
func _spawn_cards(cards: Array) -> void:
	var total_w := CARD_W * 3.0 + CARD_GAP * 2.0
	var start_x := (1280.0 - total_w) * 0.5   # centred in 1280px virtual width
	var card_y  := (600.0  - CARD_H)  * 0.5 + 20.0   # slightly above centre

	for i in 3:
		var card_ctrl := UpgradeCard.new()
		card_ctrl.setup(cards[i])
		card_ctrl.position    = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card_ctrl.size        = Vector2(CARD_W, CARD_H)
		card_ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
		card_ctrl.card_selected.connect(_on_card_selected)
		add_child(card_ctrl)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_card_selected(upgrade: Dictionary) -> void:
	# Emit before unpausing so Arena can apply the upgrade while still paused.
	upgrade_chosen.emit(upgrade)

	# Short delay so the player sees the card dim before it disappears.
	await get_tree().create_timer(0.20, false).timeout

	get_tree().paused = false
	queue_free()
