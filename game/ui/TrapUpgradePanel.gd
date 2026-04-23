## TrapUpgradePanel.gd
## Appears when the player taps a placed trap. Shows current stats and
## presents upgrade choices. Removed by calling close() or clicking [X].
##
## Normal state (star 0–4):
##   Three buttons — Damage, Range, Fire Rate — each showing the current
##   value and the value after that upgrade, so the choice is informed.
##   All three options share the same Bug Bucks cost.
##
## Tier-up state (star 5):
##   Three dramatic variation buttons replace the standard three. Variation
##   content is placeholder (TODO) until Phase 5 defines per-trap variations.
##   All three tier-up options share the same (higher) Bug Bucks cost.
##
## The panel reconnects when GameState.bug_bucks changes so button
## affordability stays current while kills are earned during a wave.

extends CanvasLayer

signal closed

const PANEL_W:   float = 450.0
const PANEL_H:   float = 310.0
const PADDING:   float = 14.0
const BTN_H:     float = 38.0
const HUD_BOT:   float = 38.0   # keep in sync with HUD.gd bottom bar height

const COLOR_BG         := Color(0.08, 0.08, 0.13, 0.94)
const COLOR_DIVIDER    := Color(0.25, 0.25, 0.30, 1.0)
const COLOR_TEXT       := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM   := Color(0.60, 0.60, 0.65, 1.0)
const COLOR_COST_OK    := Color(0.80, 0.60, 0.10, 1.0)
const COLOR_COST_NO    := Color(0.70, 0.25, 0.20, 1.0)
const COLOR_STARS_FULL := Color(0.85, 0.72, 0.10, 1.0)
const COLOR_BTN_NORMAL  := Color(0.28, 0.28, 0.35, 1.0)
const COLOR_BTN_HOVER   := Color(0.36, 0.36, 0.44, 1.0)
const COLOR_BTN_PRESSED := Color(0.20, 0.20, 0.26, 1.0)
const COLOR_BTN_BORDER  := Color(0.55, 0.55, 0.65, 1.0)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _trap:       Node  = null

var _bg:         ColorRect = null
var _lbl_title:  Label     = null
var _lbl_stars:  Label     = null
var _lbl_damage: Label     = null
var _lbl_range:  Label     = null
var _lbl_rate:   Label     = null
var _lbl_cost:   Label     = null
var _btn_a:      Button    = null
var _btn_b:      Button    = null
var _btn_c:      Button    = null


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wires the panel to trap and builds the UI. Call immediately after instantiation.
func initialize(trap: Node) -> void:
	_trap = trap
	_trap.stats_changed.connect(_refresh)
	GameState.bug_bucks_changed.connect(_on_bug_bucks_changed)
	_build_ui()
	_refresh()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp   := get_viewport().get_visible_rect().size
	var px   := (vp.x - PANEL_W) * 0.5
	var py   := vp.y - PANEL_H - HUD_BOT - 10.0

	# Background panel
	_bg          = ColorRect.new()
	_bg.color    = COLOR_BG
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(PANEL_W, PANEL_H)
	add_child(_bg)

	var inner_w := PANEL_W - PADDING * 2.0
	var y       := PADDING

	# --- Header: trap name + tier | close button ---
	var header := HBoxContainer.new()
	header.position           = Vector2(PADDING, y)
	header.custom_minimum_size = Vector2(inner_w, 28.0)
	_bg.add_child(header)

	_lbl_title = Label.new()
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.add_theme_font_size_override("font_size", 18)
	_lbl_title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(_lbl_title)

	var btn_close := Button.new()
	btn_close.text    = "X"
	btn_close.pressed.connect(_on_close)
	_apply_button_style(btn_close)
	header.add_child(btn_close)

	y += 34.0

	# --- Stars ---
	_lbl_stars          = Label.new()
	_lbl_stars.position = Vector2(PADDING, y)
	_lbl_stars.add_theme_font_size_override("font_size", 20)
	_lbl_stars.add_theme_color_override("font_color", COLOR_STARS_FULL)
	_bg.add_child(_lbl_stars)

	y += 30.0

	# --- Horizontal divider ---
	_add_divider(y)
	y += 10.0

	# --- Current stats ---
	_lbl_damage = _add_stat_label(y); y += 22.0
	_lbl_range  = _add_stat_label(y); y += 22.0
	_lbl_rate   = _add_stat_label(y); y += 28.0

	# --- Upgrade cost ---
	_lbl_cost          = Label.new()
	_lbl_cost.position = Vector2(PADDING, y)
	_lbl_cost.add_theme_font_size_override("font_size", 15)
	_bg.add_child(_lbl_cost)
	y += 26.0

	# --- Horizontal divider ---
	_add_divider(y)
	y += 10.0

	# --- Upgrade buttons ---
	_btn_a = _add_upgrade_button(y); y += BTN_H + 4.0
	_btn_b = _add_upgrade_button(y); y += BTN_H + 4.0
	_btn_c = _add_upgrade_button(y)

	_btn_a.pressed.connect(_on_btn_a)
	_btn_b.pressed.connect(_on_btn_b)
	_btn_c.pressed.connect(_on_btn_c)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

## Rebuilds all labels and button states from the trap's current values.
func _refresh() -> void:
	if _trap == null or not is_instance_valid(_trap):
		_on_close()
		return

	var star: int      = _trap.get_star()
	var tier: int      = _trap.get_tier()
	var cost: int      = _trap.get_upgrade_cost()
	var affordable: bool = GameState.bug_bucks >= cost

	_lbl_title.text = "%s  —  Tier %d" % [_trap.get_type_name(), tier]
	_lbl_stars.text = "★".repeat(star) + "☆".repeat(5 - star)

	_lbl_damage.text = "Damage:     %.1f" % _trap.get_damage()
	_lbl_range.text  = "Range:      %.1f" % _trap.get_range_radius()

	if not _trap.is_passive():
		_lbl_rate.text    = "Fire Rate:  %.2f /s" % _trap.get_shots_per_sec()
		_lbl_rate.visible = true
	else:
		_lbl_rate.text    = "Fire Rate:  passive"
		_lbl_rate.visible = true

	_lbl_cost.text = "%d Bug Bucks" % cost
	_lbl_cost.add_theme_color_override("font_color", COLOR_COST_OK if affordable else COLOR_COST_NO)

	if star < 5:
		# Normal upgrade options — show current and post-upgrade values.
		_btn_a.text = "Damage      %.1f  →  %.1f" % [_trap.get_damage(), _trap.get_damage_after_upgrade()]
		_btn_b.text = "Range       %.1f  →  %.1f" % [_trap.get_range_radius(), _trap.get_range_after_upgrade()]

		if not _trap.is_passive():
			_btn_c.text    = "Fire Rate   %.2f  →  %.2f /s" % [_trap.get_shots_per_sec(), _trap.get_shots_per_sec_after_upgrade()]
			_btn_c.visible = true
		else:
			_btn_c.visible = false
	else:
		# Star 5 — tier-up variation options.
		# Variation names and effects are defined in Phase 5.
		_btn_a.text    = "Variation A  —  [TODO]"
		_btn_b.text    = "Variation B  —  [TODO]"
		_btn_c.text    = "Variation C  —  [TODO]"
		_btn_c.visible = true

	_btn_a.disabled = not affordable
	_btn_b.disabled = not affordable
	_btn_c.disabled = not affordable


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_btn_a() -> void:
	if not GameState.spend_bug_bucks(_trap.get_upgrade_cost()):
		return
	if _trap.get_star() < 5:
		_trap.apply_damage_upgrade()
	else:
		_trap.apply_tier_up(0)


func _on_btn_b() -> void:
	if not GameState.spend_bug_bucks(_trap.get_upgrade_cost()):
		return
	if _trap.get_star() < 5:
		_trap.apply_range_upgrade()
	else:
		_trap.apply_tier_up(1)


func _on_btn_c() -> void:
	if not GameState.spend_bug_bucks(_trap.get_upgrade_cost()):
		return
	if _trap.get_star() < 5:
		_trap.apply_fire_rate_upgrade()
	else:
		_trap.apply_tier_up(2)


func _on_close() -> void:
	if GameState.bug_bucks_changed.is_connected(_on_bug_bucks_changed):
		GameState.bug_bucks_changed.disconnect(_on_bug_bucks_changed)
	closed.emit()
	queue_free()


func _on_bug_bucks_changed(_amount: int) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _add_stat_label(y: float) -> Label:
	var lbl          := Label.new()
	lbl.position      = Vector2(PADDING, y)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_bg.add_child(lbl)
	return lbl


func _add_upgrade_button(y: float) -> Button:
	var btn               := Button.new()
	btn.position           = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, BTN_H)
	btn.add_theme_font_size_override("font_size", 14)
	_apply_button_style(btn)
	_bg.add_child(btn)
	return btn


func _add_divider(y: float) -> void:
	var line       := ColorRect.new()
	line.color      = COLOR_DIVIDER
	line.position   = Vector2(PADDING, y)
	line.size       = Vector2(PANEL_W - PADDING * 2.0, 1.0)
	_bg.add_child(line)


func _apply_button_style(btn: Button) -> void:
	for state: Array in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 10.0
		box.content_margin_right  = 10.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
