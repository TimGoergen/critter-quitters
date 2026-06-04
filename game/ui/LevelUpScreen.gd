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
const Trap        = preload("res://traps/Trap.gd")
const BoostUnit   = preload("res://boosts/BoostUnit.gd")
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
		"id":              "dmg_all",
		"title":           "Extermination Formula",
		"stat_name":       "Damage",
		"impact_template": "+%s%% Damage to all traps",
		"plain_text":      "Every trap deals more damage per shot. Stacks with trap upgrades and Pheromone Dispenser boosts.",
		"magnitudes":      [0.05, 0.10, 0.20],
	},
	{
		"id":              "range_all",
		"title":           "Extended Reach",
		"stat_name":       "Range",
		"impact_template": "+%s%% Range for all traps",
		"plain_text":      "Every trap covers a wider area. Enemies spend more time inside each trap's kill zone.",
		"magnitudes":      [0.05, 0.10, 0.20],
	},
	{
		"id":              "firerate_all",
		"title":           "Hair Trigger",
		"stat_name":       "Fire Rate",
		"impact_template": "+%s%% Fire Rate for all traps",
		"plain_text":      "Every trap fires more often. Stacks with fire rate upgrades and Compressor boosts.",
		"magnitudes":      [0.05, 0.10, 0.20],
	},
	{
		"id":              "crit_chance_all",
		"title":           "Sharpened Instincts",
		"stat_name":       "Crit Chance",
		"impact_template": "+%s%% Crit Chance for all traps",
		"plain_text":      "Every trap has a higher chance to deal bonus damage on each shot. Applies directly — a trap with 0% crit chance becomes 2% (or more) immediately.",
		"magnitudes":      [0.02, 0.04, 0.08],
	},
	{
		"id":              "crit_dmg_all",
		"title":           "Lethal Potency",
		"stat_name":       "Crit Damage",
		"impact_template": "+%s%% Crit Damage bonus",
		"plain_text":      "Critical hits from every trap hit harder. Combines with per-trap Crit Damage upgrades.",
		"magnitudes":      [0.10, 0.20, 0.40],
	},
	{
		"id":              "bucks_all",
		"title":           "Invoice Padding",
		"stat_name":       "Bug Bucks",
		"impact_template": "+%s%% Bug Bucks per kill",
		"plain_text":      "Every kill pays out more. Applies to all enemy types including boss splits and spawned units.",
		"magnitudes":      [0.10, 0.20, 0.40],
	},
	{
		"id":              "infestation_heal",
		"title":           "Hazmat Protocol",
		"stat_name":       "Infestation",
		# Displayed as a percentage of the 0–100% infestation bar, not a raw fraction.
		# See the format block in _build_campaign_card() — the raw magnitude is multiplied
		# by 100 so "0.002" becomes "0.2", shown as "−0.2% bar per kill".
		"impact_template": "-%s%% bar per kill",
		# Plain text gives the player a concrete anchor: an escaped Ant fills the bar
		# by exactly 5% (1.0 infestation / INFESTATION_MAX 20 = 0.05 = 5%).
		# That lets them calculate roughly how many kills offset one escape.
		"plain_text":      "Each kill quietly trims the infestation bar. An escaped Ant fills it by 5% — this upgrade claws back a share of that with every kill.",
		"magnitudes":      [0.002, 0.004, 0.008],
	},
	{
		"id":              "upgrade_discount",
		"title":           "Bulk Procurement",
		"stat_name":       "Upgrade Costs",
		"impact_template": "-%s%% Upgrade Costs",
		"plain_text":      "All Bug Bucks upgrade costs for traps and boosts are reduced. Applies immediately to all future upgrades this run.",
		"magnitudes":      [0.05, 0.10, 0.20],
	},
]

## Human-readable display names for each upgradeable trap stat.
const STAT_NAMES: Dictionary = {
	"damage":      "Damage",
	"range":       "Range",
	"fire_rate":   "Fire Rate",
	"duration":    "Duration",
	"crit_chance": "Crit Chance",
	"crit_dmg":    "Crit Damage",
}

## Plain-text explanation of what each stat upgrade actually does.
const STAT_PLAIN_TEXT: Dictionary = {
	"damage":      "Increases the damage this trap deals per shot.",
	"range":       "Increases the radius of this trap's targeting area.",
	"fire_rate":   "Reduces the cooldown between shots, firing more often.",
	"duration":    "Extends how long the slow or poison effect lasts.",
	"crit_chance": "Adds a chance for each shot to deal bonus critical damage.",
	"crit_dmg":    "Increases the damage multiplier when a critical hit occurs.",
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

## When an unlock card is generated, trap unlock candidates are weighted by this
## multiplier relative to boost candidates. At 4.0 a single trap and single boost
## of equal cost produce an 80/20 split — traps appear far more often than boosts.
const TRAP_CATEGORY_BIAS: float = 4.0

## Displayed percentage for equipment upgrade cards at each tier [common, pro, rare].
## These are shown as "+X%" on the card — a relative label, not an exact formula output,
## since different traps of the same type may have different absolute starting stats.
const EQUIP_DISPLAY_PCT: Array = [5, 10, 20]


# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------

## Width of each upgrade card in virtual pixels — matches TrapSelectionScreen.
const CARD_W: float = 372.0

## Height of each upgrade card in virtual pixels.
## Sized so cards span from card_y=180 to y=565, leaving a 35px bottom margin.
const CARD_H: float = 385.0

## Horizontal gap between cards.
const CARD_GAP: float = 20.0


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _trap_nodes: Array = []   # placed trap nodes passed in from Arena
var _cards:      Array = []   # UpgradeCard nodes — used for mobile touch hit-testing


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

	# "LEVEL N" header label, centred near the top.
	# Font size 128 so the level announcement dominates the screen.
	var header := Label.new()
	header.text                 = "LEVEL %d" % new_level
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UIFonts.primary_bold())
	header.add_theme_font_size_override("font_size", 115)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top    = 5.0
	header.offset_bottom = 115.0   # 115pt font fits in ~110px
	header.process_mode  = Node.PROCESS_MODE_ALWAYS
	add_child(header)

	# "CHOOSE ONE" sub-header — bolder, brighter, and larger than the old "Choose an upgrade".
	var sub := Label.new()
	sub.text                 = "CHOOSE ONE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UIFonts.primary_bold())
	sub.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	sub.add_theme_font_size_override("font_size", 32)
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top    = 130.0   # 15px gap below the header (which ends at 115px)
	sub.offset_bottom = 170.0   # 40px for 32pt font
	sub.process_mode  = Node.PROCESS_MODE_ALWAYS
	add_child(sub)

	# Generate three upgrade cards and lay them out.
	var cards: Array = _generate_cards()
	_spawn_cards(cards)


# ---------------------------------------------------------------------------
# Card generation
# ---------------------------------------------------------------------------

## Generates 3 unique upgrade card data Dictionaries.
##
## Unlock cards (new trap or boost) appear with a probability that starts low
## and decreases as the player already has more items unlocked.  This means
## they are a pleasant surprise rather than a guaranteed outcome every level-up.
##
## The probability per slot is:
##   BASE_UNLOCK_CHANCE × (locked_count / TOTAL_UNLOCKABLE)
## At maximum lock (all 11 items locked) this equals BASE_UNLOCK_CHANCE (~25%).
## As the player accumulates unlocks the chance falls proportionally toward zero.
func _generate_cards() -> Array:
	var result:   Array = []
	var used_ids: Array = []

	# Count how many traps and boosts are still locked for this run.
	var locked_traps: int = 0
	for t in range(6):
		if t not in GameState.unlocked_trap_types:
			locked_traps += 1
	var locked_boosts: int = 0
	for b in range(5):
		if b not in GameState.unlocked_boost_types:
			locked_boosts += 1
	var locked_total: int = locked_traps + locked_boosts

	# 6 trap types + 5 boost types = 11 total unlockable items.
	const TOTAL_UNLOCKABLE:    int   = 11
	const BASE_UNLOCK_CHANCE: float = 0.25

	var unlock_chance: float = BASE_UNLOCK_CHANCE * float(locked_total) / float(TOTAL_UNLOCKABLE)

	while result.size() < 3:
		var tier := _roll_tier()
		var card:  Dictionary

		if locked_total > 0 and randf() < unlock_chance:
			var unlock_card := _build_unlock_card(tier, used_ids)
			# Fall back to a stat card if no distinct unlock candidate could be found.
			if not unlock_card.is_empty():
				card = unlock_card
			else:
				card = _build_equipment_or_campaign_card(tier, used_ids)
		else:
			card = _build_equipment_or_campaign_card(tier, used_ids)

		result.append(card)
		used_ids.append(card.get("id", ""))

	result.shuffle()
	return result


## Rolls a tier (Common / Professional / Rare) according to the defined probabilities.
func _roll_tier() -> int:
	var r := randf()
	if r < RARE_THRESHOLD:
		return UpgradeCard.Tier.RARE
	elif r < PRO_THRESHOLD:
		return UpgradeCard.Tier.PROFESSIONAL
	return UpgradeCard.Tier.COMMON


## Short display text for each trap and boost type, used on unlock cards.
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


## Builds an equipment or campaign card for the given tier.
## Tries equipment first (50/50 split), falling back to campaign if no traps
## are eligible or the chosen upgrade ID is already in used_ids.
func _build_equipment_or_campaign_card(tier: int, used_ids: Array) -> Dictionary:
	if randf() < 0.50:
		var equip_card := _build_equipment_card(tier, used_ids)
		if not equip_card.is_empty():
			return equip_card

	return _build_campaign_card(tier, used_ids)


## Builds an unlock card for a randomly chosen locked trap or boost type.
## Returns empty if all traps and boosts are already unlocked, or all
## eligible unlock IDs are already in used_ids.
##
## Selection is weighted two ways:
##   1. Within each category, weight = 1 / cost — cheaper items appear more often.
##   2. Between categories, the trap pool's total weight is multiplied by
##      TRAP_CATEGORY_BIAS so traps are strongly favoured over boosts.
func _build_unlock_card(tier: int, used_ids: Array) -> Dictionary:
	# Build weighted candidate lists per category.
	var trap_candidates: Array  = []
	var boost_candidates: Array = []

	for t in range(6):
		var uid := "unlock_trap_%d" % t
		if t not in GameState.unlocked_trap_types and uid not in used_ids:
			var cost: int    = Trap.STATS[t].get("cost", 1)
			var weight: float = 1.0 / float(maxi(cost, 1))
			trap_candidates.append({ "category": "unlock_trap",  "type": t, "uid": uid, "weight": weight })

	for b in range(5):
		var uid := "unlock_boost_%d" % b
		if b not in GameState.unlocked_boost_types and uid not in used_ids:
			var cost: int    = BoostUnit.STATS[b].get("cost", 1)
			var weight: float = 1.0 / float(maxi(cost, 1))
			boost_candidates.append({ "category": "unlock_boost", "type": b, "uid": uid, "weight": weight })

	if trap_candidates.is_empty() and boost_candidates.is_empty():
		return {}

	# Choose category. Apply TRAP_CATEGORY_BIAS to the trap pool's total weight so
	# traps appear far more often when both categories have locked items.
	var chosen_pool: Array
	if trap_candidates.is_empty():
		chosen_pool = boost_candidates
	elif boost_candidates.is_empty():
		chosen_pool = trap_candidates
	else:
		var trap_weight: float  = 0.0
		for c in trap_candidates:
			trap_weight += c["weight"]
		trap_weight *= TRAP_CATEGORY_BIAS

		var boost_weight: float = 0.0
		for c in boost_candidates:
			boost_weight += c["weight"]

		chosen_pool = trap_candidates if randf() * (trap_weight + boost_weight) < trap_weight \
				else boost_candidates

	# Weighted pick within the chosen category.
	var pool_total: float = 0.0
	for c in chosen_pool:
		pool_total += c["weight"]

	var roll := randf() * pool_total
	var accumulated := 0.0
	var chosen: Dictionary = chosen_pool[-1]   # fallback to last entry
	for c in chosen_pool:
		accumulated += c["weight"]
		if roll <= accumulated:
			chosen = c
			break

	var category: String = chosen["category"]
	var item_type: int   = chosen["type"]
	var uid: String      = chosen["uid"]

	if category == "unlock_trap":
		var display: Dictionary = TRAP_DISPLAY.get(item_type, {})
		return {
			"id":           uid,
			"category":     "unlock_trap",
			"tier":         tier,
			"tier_label":   "NEW TRAP",
			"title":        display.get("name", "Trap"),
			"stat_name":    "",
			"impact_line":  "Unlocks for placement",
			"plain_text":   display.get("desc", ""),
			"custom_color": Trap.STATS[item_type].get("color", Color.WHITE),
			"item_type":    item_type,
			"magnitude":    0.0,
			"trap_node":    null,
			"stat":         "",
		}
	else:
		var display: Dictionary = BOOST_DISPLAY.get(item_type, {})
		return {
			"id":           uid,
			"category":     "unlock_boost",
			"tier":         tier,
			"tier_label":   "NEW BOOST",
			"title":        display.get("name", "Boost"),
			"stat_name":    "",
			"impact_line":  "Unlocks for placement",
			"plain_text":   display.get("desc", ""),
			"custom_color": BoostUnit.GLOW_COLORS[item_type],
			"item_type":    item_type,
			"magnitude":    0.0,
			"trap_node":    null,
			"stat":         "",
		}


## Tries to find an eligible trap type and non-exhausted free-upgrade stat.
## Returns an empty Dictionary if no eligible (type, stat) pair exists.
##
## Equipment upgrades are type-wide: the chosen upgrade applies to every placed
## trap of that type AND all future placements (tracked in GameState).
##
## Eligibility is based on unlocked trap types, not just placed ones — if the player
## has unlocked a Zapper but hasn't placed one yet, Zapper equipment cards can still
## appear and will apply to any Zapper placed later in the run.
func _build_equipment_card(tier: int, used_ids: Array) -> Dictionary:
	# Build a map of {trap_type_int → representative_trap_node} from placed traps.
	# A placed node is preferred because it lets us call get_type_name() directly.
	var type_to_rep: Dictionary = {}
	for trap in _trap_nodes:
		if not is_instance_valid(trap):
			continue
		var t: int = trap.get_type()
		if not type_to_rep.has(t):
			type_to_rep[t] = trap

	# Include every unlocked type even if none of that type are currently placed.
	# Null sentinel signals that we must derive type info from STATS instead of a live node.
	for trap_type: int in GameState.unlocked_trap_types:
		if not type_to_rep.has(trap_type):
			type_to_rep[trap_type] = null

	if type_to_rep.is_empty():
		return {}

	# Collect all eligible (type, stat) pairs where the free pool is not exhausted.
	var eligible: Array = []   # each entry: { "type": int, "stat": String, "rep": Node3D or null }
	for trap_type: int in type_to_rep.keys():
		var rep = type_to_rep[trap_type]   # Node3D or null
		for stat: String in _get_free_upgradeable_stats(rep, trap_type):
			var uid := "equip_%d_%s" % [trap_type, stat]
			if uid not in used_ids:
				eligible.append({ "type": trap_type, "stat": stat, "rep": rep })

	if eligible.is_empty():
		return {}

	eligible.shuffle()
	var chosen: Dictionary = eligible[0]
	var trap_type: int = chosen["type"]
	var stat: String   = chosen["stat"]
	var rep            = chosen["rep"]   # Node3D or null

	# Title is "<Trap Name> Upgrade" so the card is immediately recognisable as a
	# buff to that specific trap type rather than a campaign-wide effect.
	var trap_name: String
	if rep != null and is_instance_valid(rep):
		trap_name = rep.get_type_name()
	else:
		trap_name = TRAP_DISPLAY.get(trap_type, {}).get("name", "Trap")
	var title: String = "%s Upgrade" % trap_name

	var stat_name: String  = STAT_NAMES.get(stat, stat)
	var plain_text: String = STAT_PLAIN_TEXT.get(stat, "")
	var display_pct: int   = EQUIP_DISPLAY_PCT[tier]
	var unique_id: String  = "equip_%d_%s" % [trap_type, stat]

	return {
		"id":        unique_id,
		"category":  "equipment",
		"tier":      tier,
		"title":     title,
		"stat_name": stat_name,
		# Relative label — different traps of the same type may have different base stats,
		# so "+X%" is shown rather than an absolute current-to-after delta.
		"impact_line":  "+%d%% %s" % [display_pct, stat_name],
		"plain_text":   plain_text,
		"custom_color": Trap.STATS.get(trap_type, {}).get("color", Color.TRANSPARENT),
		"current_val": "",
		"after_val":   "",
		"magnitude":   0.0,
		"trap_node":   null,   # upgrade is applied by type, not by instance
		"trap_type":   trap_type,
		"stat":        stat,
	}


## Returns stat strings whose free-upgrade pool is not yet exhausted for this type.
##
## rep may be a live Node3D or null (when the trap type is unlocked but not placed).
## Passivity — which determines whether fire_rate or duration is the relevant stat —
## is read from the live node when available, and derived from Trap.STATS otherwise.
## A passive trap (cooldown == 0.0) has no fire cycle, so fire_rate doesn't apply;
## it has a linger duration instead.
func _get_free_upgradeable_stats(rep, trap_type: int) -> Array:
	var result: Array = []
	var queue: Dictionary = GameState.type_upgrade_queue.get(trap_type, {})

	var passive: bool
	if rep != null and is_instance_valid(rep):
		passive = rep.is_passive()
	else:
		passive = Trap.STATS[trap_type]["cooldown"] == 0.0

	if queue.get("damage", 0) < Trap.FREE_MAX_LEVEL:
		result.append("damage")
	if queue.get("range", 0) < Trap.FREE_MAX_LEVEL:
		result.append("range")
	if not passive and queue.get("fire_rate", 0) < Trap.FREE_MAX_LEVEL:
		result.append("fire_rate")
	if passive and queue.get("duration", 0) < Trap.FREE_MAX_LEVEL:
		result.append("duration")
	if queue.get("crit_chance", 0) < Trap.FREE_MAX_LEVEL:
		result.append("crit_chance")
	if queue.get("crit_dmg", 0) < Trap.FREE_MAX_LEVEL:
		result.append("crit_dmg")
	return result


## Returns a list of stat strings that are not yet paid-maxed on this trap.
## Used by _build_card() to determine equipment card eligibility (legacy path kept
## for potential future use; type-wide cards now use _get_free_upgradeable_stats).
func _get_upgradeable_stats(trap: Node3D) -> Array:
	var result: Array = []
	if not trap.is_damage_maxed():
		result.append("damage")
	if not trap.is_range_maxed():
		result.append("range")
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

		# Format the impact line.
		# All magnitudes are expressed as a percentage for display (×100).
		# Hazmat Protocol magnitudes (0.002/0.004/0.008) are fractions of the
		# 0.0–1.0 infestation bar; ×100 converts them to bar-percentage per kill
		# (0.2/0.4/0.8), which players can compare to the visible 0–100% bar.
		# One decimal place keeps the small values readable ("0.2%" not "0%").
		# All other buffs are round integers after ×100, so %d is sufficient.
		var display_val: String
		if buff["id"] == "infestation_heal":
			display_val = "%.1f" % (magnitude * 100.0)
		else:
			display_val = "%d" % roundi(magnitude * 100.0)

		return {
			"id":          buff["id"],
			"category":    "campaign",
			"tier":        tier,
			"title":       buff["title"],
			"stat_name":   buff["stat_name"],
			"impact_line": buff["impact_template"] % display_val,
			"plain_text":  buff["plain_text"],
			"current_val": "",
			"after_val":   "",
			"magnitude":   magnitude,
			"trap_node":   null,
			"stat":        "",
		}

	# Safety fallback — should never reach here if the pool has ≥ 3 entries.
	return {
		"id": "dmg_all", "category": "campaign", "tier": tier,
		"title": "Extermination Formula",
		"stat_name": "Damage",
		"impact_line": "+5% Damage to all traps",
		"plain_text": "Every trap deals more damage per shot.",
		"current_val": "", "after_val": "",
		"magnitude": 0.05, "trap_node": null, "stat": "",
	}


# ---------------------------------------------------------------------------
# Card layout
# ---------------------------------------------------------------------------

## Instantiates three UpgradeCard controls, connects their signals, and lays
## them out horizontally centred in the virtual viewport (1280×600).
func _spawn_cards(cards: Array) -> void:
	var total_w := CARD_W * 3.0 + CARD_GAP * 2.0
	var start_x := (1280.0 - total_w) * 0.5   # centred in 1280px virtual width
	# 10px gap below the sub-header (which ends at 170px). Tag panels render above this line.
	var card_y  := 180.0

	for i in 3:
		var card_ctrl := UpgradeCard.new()
		# Apply identity colour for unlock cards before setup() reads it.
		card_ctrl.custom_color  = cards[i].get("custom_color", Color.TRANSPARENT)
		card_ctrl.font_scale    = 0.65   # match TrapSelectionScreen text density
		card_ctrl.image_h_max   = 65.0   # 25% smaller than the 87px baseline
		card_ctrl.setup(cards[i])
		card_ctrl.position    = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card_ctrl.size        = Vector2(CARD_W, CARD_H)
		card_ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
		card_ctrl.card_selected.connect(_on_card_selected)
		add_child(card_ctrl)
		_cards.append(card_ctrl)

	# Tag panels for unlock cards — drawn in a second pass so they render on top of all cards.
	# Each tag is a raised amber banner sitting just above the card border.
	# A drop shadow behind and highlight/shadow edge strips simulate a 3D pressed-in label.
	const TAG_H:         float = 30.0    # taller than the old 22px to fit the larger font
	const TAG_W:         float = 260.0   # slightly wider to accommodate the larger text
	const CARD_BORDER_W: float = 6.0     # matches UpgradeCard.BORDER_W
	const TAG_BG:        Color = Color(0.30, 0.19, 0.01, 1.0)   # dark amber body
	const TAG_FG:        Color = Color(0.83, 0.52, 0.04, 1.0)   # amber text
	const TAG_HI:        Color = Color(0.62, 0.40, 0.05, 0.90)  # top-edge highlight (lighter)
	const TAG_DK:        Color = Color(0.10, 0.05, 0.00, 1.00)  # bottom-edge shadow (darker)
	const TAG_SHADOW:    Color = Color(0.00, 0.00, 0.00, 0.55)  # drop shadow behind the tag
	const BEVEL:         float = 2.5     # thickness of the top/bottom bevel strips in px
	const FONT_SIZE:     int   = 18      # 13 × 1.4 ≈ 18 — 40% larger than previous

	for i in 3:
		var cat: String = cards[i].get("category", "")
		if cat != "unlock_trap" and cat != "unlock_boost":
			continue

		var cx: float  = start_x + i * (CARD_W + CARD_GAP)
		var tag_x: float = cx + (CARD_W - TAG_W) * 0.5
		# Vertically: the tag overlaps the top border of the card — bottom of tag
		# aligns with the bottom of the border ring so content starts flush below.
		var tag_y: float = card_y - TAG_H + CARD_BORDER_W

		# Drop shadow — offset 3px right and 3px down; drawn first so every
		# tag layer paints over it.
		var shadow := ColorRect.new()
		shadow.color        = TAG_SHADOW
		shadow.position     = Vector2(tag_x + 3.0, tag_y + 3.0)
		shadow.size         = Vector2(TAG_W, TAG_H)
		shadow.z_index      = 1
		shadow.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(shadow)

		# Main amber body.
		var tag_bg := ColorRect.new()
		tag_bg.color        = TAG_BG
		tag_bg.position     = Vector2(tag_x, tag_y)
		tag_bg.size         = Vector2(TAG_W, TAG_H)
		tag_bg.z_index      = 2
		tag_bg.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(tag_bg)

		# Top highlight strip — simulates light catching the upper face.
		var hi := ColorRect.new()
		hi.color        = TAG_HI
		hi.position     = Vector2(tag_x, tag_y)
		hi.size         = Vector2(TAG_W, BEVEL)
		hi.z_index      = 3
		hi.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(hi)

		# Bottom shadow strip — simulates the underside receding into shadow.
		var dk := ColorRect.new()
		dk.color        = TAG_DK
		dk.position     = Vector2(tag_x, tag_y + TAG_H - BEVEL)
		dk.size         = Vector2(TAG_W, BEVEL)
		dk.z_index      = 3
		dk.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(dk)

		var tag_lbl := Label.new()
		tag_lbl.text                 = "★  NEW EQUIPMENT"
		tag_lbl.position             = Vector2(tag_x, tag_y)
		tag_lbl.size                 = Vector2(TAG_W, TAG_H)
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		tag_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		tag_lbl.add_theme_color_override("font_color", TAG_FG)
		tag_lbl.add_theme_font_override("font", UIFonts.primary_bold())
		tag_lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		tag_lbl.z_index              = 4
		tag_lbl.process_mode         = Node.PROCESS_MODE_ALWAYS
		add_child(tag_lbl)


# ---------------------------------------------------------------------------
# Input blocking
# ---------------------------------------------------------------------------

## Swallows every pointer event that was not already consumed by a card's
## _gui_input() or by the dim overlay's MOUSE_FILTER_STOP.
##
## Why this is necessary:
##   Screen-touch events (InputEventScreenTouch / InputEventScreenDrag) bypass
##   the GUI mouse-filter system on mobile and reach _unhandled_input directly.
##   Mouse motion / mouse button events outside the card area also need a
##   fallback catch.  Arena._unhandled_input() would otherwise interpret the
##   same event as a trap-select or enemy-follow tap on the arena behind us.
##
## Order guarantee: LevelUpScreen is a child of Arena (see Arena._show_level_up_screen),
## so Godot's depth-first _unhandled_input traversal calls this method BEFORE
## Arena._unhandled_input() — the event is marked handled and Arena never sees it.
func _unhandled_input(event: InputEvent) -> void:
	# Cards handle their own touch via UpgradeCard._input.
	# Swallow all remaining pointer events so Arena never receives them.
	if event is InputEventScreenTouch \
			or event is InputEventMouseButton \
			or event is InputEventScreenDrag \
			or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _on_card_selected(upgrade: Dictionary) -> void:
	# Emit before unpausing so Arena can apply the upgrade while still paused.
	upgrade_chosen.emit(upgrade)

	# Short delay so the player sees the card dim before it disappears.
	# process_always=true so the timer keeps running while the tree is paused.
	await get_tree().create_timer(0.20, true).timeout

	get_tree().paused = false
	queue_free()


# ---------------------------------------------------------------------------
# Stat value formatters
# ---------------------------------------------------------------------------

## Returns a formatted string for the current value of the given stat on trap.
func _format_stat_current(trap: Node3D, stat: String) -> String:
	match stat:
		"damage":      return "%.1f" % trap.get_effective_damage()
		"range":       return "%.1f" % trap.get_range_radius()
		"fire_rate":   return "%.2f/s" % trap.get_effective_shots_per_sec()
		"duration":    return "%.1fs" % trap.get_duration()
		"crit_chance": return "%d%%" % roundi(trap.get_crit_chance() * 100.0)
		"crit_dmg":    return "%d%%" % roundi(trap.get_crit_damage_bonus() * 100.0)
	return ""


## Returns a formatted string for the value after one upgrade of stat on trap.
func _format_stat_after(trap: Node3D, stat: String) -> String:
	match stat:
		"damage":      return "%.1f" % trap.get_effective_damage_after_upgrade()
		"range":       return "%.1f" % trap.get_range_after_upgrade()
		"fire_rate":   return "%.2f/s" % trap.get_effective_shots_per_sec_after_upgrade()
		"duration":    return "%.1fs" % trap.get_duration_after_upgrade()
		"crit_chance": return "%d%%" % roundi(trap.get_crit_chance_after_upgrade() * 100.0)
		"crit_dmg":    return "%d%%" % roundi(trap.get_crit_damage_after_upgrade() * 100.0)
	return ""
