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

## Displayed percentage for equipment upgrade cards at each tier [common, pro, rare].
## These are shown as "+X%" on the card — a relative label, not an exact formula output,
## since different traps of the same type may have different absolute starting stats.
const EQUIP_DISPLAY_PCT: Array = [5, 10, 20]


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

	# "LEVEL N" header label, centred near the top.
	# Font size 128 so the level announcement dominates the screen.
	var header := Label.new()
	header.text                 = "LEVEL %d" % new_level
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", UIFonts.primary_bold())
	header.add_theme_font_size_override("font_size", 128)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.20, 1.0))
	header.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	header.add_theme_constant_override("shadow_offset_x", 2)
	header.add_theme_constant_override("shadow_offset_y", 2)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top    = 5.0
	header.offset_bottom = 160.0   # 155px for 128pt font
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
	sub.offset_top    = 163.0
	sub.offset_bottom = 205.0   # 42px for 32pt font
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


## Tries to find an eligible trap type and non-exhausted free-upgrade stat.
## Returns an empty Dictionary if no eligible (type, stat) pair exists.
##
## Equipment upgrades are now type-wide: the chosen upgrade applies to every
## placed trap of that type AND all future placements (tracked in GameState).
## The free pool (FREE_MAX_LEVEL = 3) is independent of the paid Bug-Bucks pool,
## so a stat can be offered here even if already paid-maxed, and vice-versa.
func _build_equipment_card(tier: int, used_ids: Array) -> Dictionary:
	# Build a map of {trap_type_int → representative_trap_node} from placed traps.
	# One entry per type — we need only one instance to check passive-ness and naming.
	var type_to_rep: Dictionary = {}
	for trap in _trap_nodes:
		if not is_instance_valid(trap):
			continue
		var t: int = trap.get_type()
		if not type_to_rep.has(t):
			type_to_rep[t] = trap

	if type_to_rep.is_empty():
		return {}

	# Collect all eligible (type, stat) pairs where the free pool is not exhausted.
	var eligible: Array = []   # each entry: { "type": int, "stat": String, "rep": Node3D }
	for trap_type: int in type_to_rep.keys():
		var rep: Node3D = type_to_rep[trap_type]
		for stat: String in _get_free_upgradeable_stats(rep, trap_type):
			var uid := "equip_%d_%s" % [trap_type, stat]
			if uid not in used_ids:
				eligible.append({ "type": trap_type, "stat": stat, "rep": rep })

	if eligible.is_empty():
		return {}

	eligible.shuffle()
	var chosen: Dictionary = eligible[0]
	var trap_type: int  = chosen["type"]
	var stat: String    = chosen["stat"]
	var rep: Node3D     = chosen["rep"]

	var stat_name: String  = STAT_NAMES.get(stat, stat)
	var plain_text: String = STAT_PLAIN_TEXT.get(stat, "")
	var display_pct: int   = EQUIP_DISPLAY_PCT[tier]
	var unique_id: String  = "equip_%d_%s" % [trap_type, stat]

	return {
		"id":        unique_id,
		"category":  "equipment",
		"tier":      tier,
		"title":     rep.get_type_name(),
		"stat_name": stat_name,
		# Impact line mirrors campaign card format: "+X% Stat" — relative, not absolute.
		# Different traps of the same type may have different base stats, so we show a
		# relative label rather than a precise current-to-after delta.
		"impact_line": "+%d%% %s" % [display_pct, stat_name],
		"plain_text":  plain_text,
		"current_val": "",   # not shown for equipment cards
		"after_val":   "",
		"magnitude":   0.0,
		"trap_node":   null,   # unused — upgrade is applied by type, not by instance
		"trap_type":   trap_type,
		"stat":        stat,
	}


## Returns stat strings whose free-upgrade pool is not yet exhausted for this type.
## Uses the representative trap instance only to check passive status and naming;
## the actual cap is checked against GameState.type_upgrade_queue.
func _get_free_upgradeable_stats(rep: Node3D, trap_type: int) -> Array:
	var result: Array = []
	var queue: Dictionary = GameState.type_upgrade_queue.get(trap_type, {})

	if queue.get("damage", 0) < Trap.FREE_MAX_LEVEL:
		result.append("damage")
	if queue.get("range", 0) < Trap.FREE_MAX_LEVEL:
		result.append("range")
	# Fire rate is not applicable to passive traps (Glue Board, Bait Station).
	if not rep.is_passive() and queue.get("fire_rate", 0) < Trap.FREE_MAX_LEVEL:
		result.append("fire_rate")
	if rep.is_passive() and queue.get("duration", 0) < Trap.FREE_MAX_LEVEL:
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
	# Pushed down to clear the taller 128pt header + 32pt sub-header.
	var card_y  := 213.0

	for i in 3:
		var card_ctrl := UpgradeCard.new()
		card_ctrl.setup(cards[i])
		card_ctrl.position    = Vector2(start_x + i * (CARD_W + CARD_GAP), card_y)
		card_ctrl.size        = Vector2(CARD_W, CARD_H)
		card_ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
		card_ctrl.card_selected.connect(_on_card_selected)
		add_child(card_ctrl)


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
