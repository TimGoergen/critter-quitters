## BalanceEditorScreen.gd
## Full-screen overlay for tweaking all BalanceConfig values before a run.
## Accessible from the Settings dialog on the start screen.
##
## Four tabs — TRAPS, BOOSTS, ENEMIES, WAVES — each showing a scrollable list
## of stat rows. Each row has a label, a current-value display, and [-]/[+]
## buttons to adjust the value in a fixed step.
##
## Values are written back to BalanceConfig's mutable dicts on every button
## press (dict/array getters return references, so direct key assignment works)
## and saved to disk immediately via BalanceConfig.save().
##
## Sits on CanvasLayer 25, above PermanentUpgradeScreen (layer 20).

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

const COLOR_BG          := Color(0.04, 0.06, 0.12, 1.0)
const COLOR_PANEL_HDR   := Color(0.06, 0.10, 0.20, 1.0)
const COLOR_DIVIDER     := Color(0.18, 0.20, 0.28, 1.0)
const COLOR_SECTION_BG  := Color(0.04, 0.10, 0.08, 1.0)   # dark teal strip
const COLOR_SECTION_TXT := Color(1.00, 0.82, 0.10, 1.0)   # gold
const COLOR_ROW_A       := Color(0.06, 0.08, 0.15, 1.0)
const COLOR_ROW_B       := Color(0.08, 0.10, 0.19, 1.0)
const COLOR_TEXT        := Color(0.86, 0.88, 0.92, 1.0)
const COLOR_VALUE       := Color(0.96, 0.88, 0.50, 1.0)   # warm gold

const COLOR_TAB_ACTIVE_BG  := Color(0.06, 0.18, 0.06, 1.0)
const COLOR_TAB_IDLE_BG    := Color(0.02, 0.06, 0.02, 1.0)
const COLOR_TAB_ACTIVE_TXT := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_TAB_IDLE_TXT   := Color(0.45, 0.50, 0.55, 1.0)

const COLOR_BTN_MINUS_NORMAL  := Color(0.18, 0.08, 0.08, 1.0)
const COLOR_BTN_MINUS_HOVER   := Color(0.26, 0.12, 0.12, 1.0)
const COLOR_BTN_MINUS_PRESS   := Color(0.12, 0.05, 0.05, 1.0)
const COLOR_BTN_MINUS_BORDER  := Color(0.55, 0.20, 0.20, 1.0)

const COLOR_BTN_PLUS_NORMAL   := Color(0.04, 0.20, 0.04, 1.0)
const COLOR_BTN_PLUS_HOVER    := Color(0.07, 0.28, 0.07, 1.0)
const COLOR_BTN_PLUS_PRESS    := Color(0.02, 0.12, 0.02, 1.0)
const COLOR_BTN_PLUS_BORDER   := Color(0.18, 0.56, 0.18, 1.0)

const COLOR_CLOSE_NORMAL  := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_CLOSE_HOVER   := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_CLOSE_PRESS   := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_CLOSE_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

const COLOR_RESET_NORMAL  := Color(0.28, 0.04, 0.04, 1.0)
const COLOR_RESET_HOVER   := Color(0.38, 0.06, 0.06, 1.0)
const COLOR_RESET_PRESS   := Color(0.18, 0.02, 0.02, 1.0)
const COLOR_RESET_BORDER  := Color(0.70, 0.18, 0.18, 1.0)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const PADDING:  float = 24.0
const HEADER_H: float = 66.0
const TAB_H:    float = 50.0
const ROW_H:    float = 60.0
const BTN_W:    float = 56.0   # width of each [-] / [+] button
const VAL_W:    float = 120.0  # width of the value display label


# ---------------------------------------------------------------------------
# Unit name tables (match BalanceConfig's enum ordinals)
# ---------------------------------------------------------------------------

const TRAP_NAMES: Array[String] = [
	"Snap Trap", "Zapper", "Fogger", "Glue Board", "Fly Strip Launcher", "Bait Station"
]
const BOOST_NAMES: Array[String] = [
	"Pheromone Dispenser", "Compressor", "Cash Register", "Air Freshener", "Quarantine Marker"
]
const ENEMY_NAMES: Array[String] = [
	"Ant", "Gnat", "Cricket", "Beetle", "Cockroach", "Mouse", "Mosquito", "Rat King", "Rat"
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _active_tab: String        = "TRAPS"
var _tab_btns:   Dictionary    = {}   # tab name → Button
var _scroll:     ScrollContainer = null
var _vbox:       VBoxContainer = null
var _row_parity: int           = 0   # alternates 0/1 per row for subtle striping


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color        = COLOR_BG
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_header()
	_add_h_divider(HEADER_H)
	_build_tab_bar()
	_add_h_divider(HEADER_H + 1.0 + TAB_H)
	_build_scroll_area()
	_populate_tab(_active_tab)


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header() -> void:
	var hdr := Control.new()
	hdr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hdr.offset_bottom = HEADER_H
	hdr.anchor_bottom = 0.0
	add_child(hdr)

	var panel := ColorRect.new()
	panel.color        = COLOR_PANEL_HDR
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(panel)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	hdr.add_child(row)

	var title_margin := MarginContainer.new()
	title_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_margin.add_theme_constant_override("margin_left", int(PADDING))
	row.add_child(title_margin)

	var title_lbl := Label.new()
	title_lbl.text               = "BALANCE EDITOR"
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_override("font", UIFonts.header())
	title_lbl.add_theme_font_size_override("font_size", 32)
	title_lbl.add_theme_color_override("font_color", COLOR_SECTION_TXT)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_margin.add_child(title_lbl)

	var btn_margin := MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_right",  int(PADDING))
	btn_margin.add_theme_constant_override("margin_top",    int((HEADER_H - 44.0) * 0.5))
	btn_margin.add_theme_constant_override("margin_bottom", int((HEADER_H - 44.0) * 0.5))
	btn_margin.add_theme_constant_override("margin_left",   8)
	row.add_child(btn_margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	btn_margin.add_child(hbox)

	var reset_btn := _make_text_button("Reset to Defaults", 170.0,
		COLOR_RESET_NORMAL, COLOR_RESET_HOVER, COLOR_RESET_PRESS, COLOR_RESET_BORDER,
		Color(0.95, 0.88, 0.88, 1.0))
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var close_btn := _make_text_button("Close", 110.0,
		COLOR_CLOSE_NORMAL, COLOR_CLOSE_HOVER, COLOR_CLOSE_PRESS, COLOR_CLOSE_BORDER,
		COLOR_TEXT)
	close_btn.pressed.connect(_on_close_pressed)
	hbox.add_child(close_btn)


# ---------------------------------------------------------------------------
# Tab bar
# ---------------------------------------------------------------------------

func _build_tab_bar() -> void:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_top    = HEADER_H + 1.0
	bar.offset_bottom = HEADER_H + 1.0 + TAB_H
	bar.anchor_bottom = 0.0
	add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	bar.add_child(hbox)

	for tab_name: String in ["TRAPS", "BOOSTS", "ENEMIES", "WAVES"]:
		var btn := Button.new()
		btn.text                  = tab_name
		btn.focus_mode            = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", UIFonts.primary_bold())
		btn.add_theme_font_size_override("font_size", 22)
		_style_tab_btn(btn, tab_name == _active_tab)
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		hbox.add_child(btn)
		_tab_btns[tab_name] = btn


func _style_tab_btn(btn: Button, is_active: bool) -> void:
	var bg_col  := COLOR_TAB_ACTIVE_BG  if is_active else COLOR_TAB_IDLE_BG
	var txt_col := COLOR_TAB_ACTIVE_TXT if is_active else COLOR_TAB_IDLE_TXT
	btn.add_theme_color_override("font_color", txt_col)
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg_col.lightened(0.05) if state == "hover" else \
				(bg_col.darkened(0.05) if state == "pressed" else bg_col)
		box.set_border_width_all(0)
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_tab_pressed(tab_name: String) -> void:
	if tab_name == _active_tab:
		return
	_style_tab_btn(_tab_btns[_active_tab], false)
	_active_tab = tab_name
	_style_tab_btn(_tab_btns[_active_tab], true)
	_populate_tab(_active_tab)


# ---------------------------------------------------------------------------
# Scroll area
# ---------------------------------------------------------------------------

func _build_scroll_area() -> void:
	var scroll_top: float = HEADER_H + 1.0 + TAB_H + 1.0

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top              = scroll_top
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.process_mode            = Node.PROCESS_MODE_ALWAYS
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 0)
	_scroll.add_child(_vbox)


# ---------------------------------------------------------------------------
# Tab population
# ---------------------------------------------------------------------------

func _populate_tab(tab_name: String) -> void:
	# Clear existing rows.
	for child in _vbox.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	_row_parity             = 0

	match tab_name:
		"TRAPS":   _build_traps_tab()
		"BOOSTS":  _build_boosts_tab()
		"ENEMIES": _build_enemies_tab()
		"WAVES":   _build_waves_tab()


# ---------------------------------------------------------------------------
# TRAPS tab
# ---------------------------------------------------------------------------

func _build_traps_tab() -> void:
	for t: int in range(TRAP_NAMES.size()):
		_add_section(TRAP_NAMES[t].to_upper())
		var stats := BalanceConfig.get_trap_stats(t)
		var costs := BalanceConfig.get_trap_upgrade_costs(t)

		_add_row_dict(_vbox, "Damage",   stats, "damage",   0.5,  0.1,  500.0, false)
		_add_row_dict(_vbox, "Range",    stats, "range",    0.2,  0.5,   25.0, false)
		_add_row_dict(_vbox, "Cooldown (0 = passive)", stats, "cooldown", 0.1, 0.0, 15.0, false)
		_add_row_dict(_vbox, "Cost (BB)", stats, "cost",    5.0,  5.0,  999.0, true)

		# Type-specific stats present only for certain trap types.
		if stats.has("pulse_interval"):
			_add_row_dict(_vbox, "Pulse Interval (s)", stats, "pulse_interval", 0.5, 0.5, 30.0, false)
		if stats.has("cloud_duration"):
			_add_row_dict(_vbox, "Cloud Duration (s)", stats, "cloud_duration", 0.5, 0.5, 20.0, false)
		if stats.has("adhesion"):
			_add_row_dict(_vbox, "Adhesion (0–1)", stats, "adhesion", 0.05, 0.0, 1.0, false)
		if stats.has("poison_damage_per_tick"):
			_add_row_dict(_vbox, "Poison Dmg/Tick", stats, "poison_damage_per_tick", 0.5, 0.1, 100.0, false)
		if stats.has("poison_duration"):
			_add_row_dict(_vbox, "Poison Duration (s)", stats, "poison_duration", 0.5, 0.5, 30.0, false)
		if stats.has("poison_tick_rate"):
			_add_row_dict(_vbox, "Poison Tick Rate (s)", stats, "poison_tick_rate", 0.1, 0.1, 5.0, false)

		_add_row_array(_vbox, "Upgrade Cost L1 (BB)", costs, 0, 5.0, 5.0, 999.0, true)
		_add_row_array(_vbox, "Upgrade Cost L2 (BB)", costs, 1, 5.0, 5.0, 999.0, true)
		_add_row_array(_vbox, "Upgrade Cost L3 (BB)", costs, 2, 5.0, 5.0, 999.0, true)

	# Global upgrade factors apply across all trap types.
	_add_section("GLOBAL UPGRADE FACTORS")
	var f := BalanceConfig.get_trap_upgrade_factors()
	_add_row_dict(_vbox, "Damage per Level",     f, "damage",              0.01, 0.01, 2.0, false)
	_add_row_dict(_vbox, "Range per Level",      f, "range",               0.01, 0.01, 1.0, false)
	_add_row_dict(_vbox, "Fire Rate per Level",  f, "fire_rate",           0.01, 0.01, 1.0, false)
	_add_row_dict(_vbox, "Crit Chance per Level", f, "crit_chance_per_level", 0.01, 0.0, 0.5, false)
	_add_row_dict(_vbox, "Crit Damage per Level", f, "crit_damage_per_level", 0.05, 0.0, 3.0, false)

	# Per-level upgrade tables for traps with non-standard progression.
	_add_section("PER-LEVEL TABLES")
	var ga := BalanceConfig.get_glue_adhesion_levels()
	var gd := BalanceConfig.get_glue_duration_levels()
	var fa := BalanceConfig.get_fly_strip_adhesion_levels()
	var bd := BalanceConfig.get_bait_poison_duration_levels()
	for i: int in range(4):
		_add_row_array(_vbox, "Glue Adhesion L%d" % i, ga, i, 0.05, 0.0, 1.0, false)
	for i: int in range(4):
		_add_row_array(_vbox, "Glue Duration L%d (s)" % i, gd, i, 0.5, 0.5, 30.0, false)
	for i: int in range(4):
		_add_row_array(_vbox, "Fly Strip Adhesion L%d" % i, fa, i, 0.05, 0.0, 1.0, false)
	for i: int in range(4):
		_add_row_array(_vbox, "Bait Poison Duration L%d (s)" % i, bd, i, 0.5, 0.5, 30.0, false)


# ---------------------------------------------------------------------------
# BOOSTS tab
# ---------------------------------------------------------------------------

func _build_boosts_tab() -> void:
	for b: int in range(BOOST_NAMES.size()):
		_add_section(BOOST_NAMES[b].to_upper())
		var stats := BalanceConfig.get_boost_stats(b)
		var costs := BalanceConfig.get_boost_upgrade_costs(b)

		_add_row_dict(_vbox, "Range", stats, "range", 0.2, 0.5, 20.0, false)
		_add_row_dict(_vbox, "Cost (BB)", stats, "cost", 5.0, 5.0, 999.0, true)

		# Primary stat (stat B) — label and key vary by boost type.
		match b:
			0:  # PHEROMONE_DISPENSER
				_add_row_dict(_vbox, "Damage Bonus", stats, "damage_bonus", 0.05, 0.0, 3.0, false)
			1:  # COMPRESSOR
				_add_row_dict(_vbox, "Fire Rate Bonus", stats, "fire_rate_bonus", 0.05, 0.0, 3.0, false)
			2:  # CASH_REGISTER
				_add_row_dict(_vbox, "Income per Wave (BB)", stats, "income_per_wave", 1.0, 0.0, 200.0, true)
				_add_row_dict(_vbox, "Kill Bonus (BB)", stats, "kill_bonus", 1.0, 0.0, 100.0, true)
			3:  # AIR_FRESHENER
				_add_row_dict(_vbox, "Infestation Reduction", stats, "reduction", 0.05, 0.0, 1.0, false)
				_add_row_dict(_vbox, "Capacity", stats, "capacity", 5.0, 10.0, 500.0, false)
			4:  # QUARANTINE_MARKER
				_add_row_dict(_vbox, "Restore per Kill", stats, "restore_per_kill", 0.5, 0.0, 50.0, false)
				_add_row_dict(_vbox, "Capacity", stats, "capacity", 5.0, 10.0, 500.0, false)

		_add_row_array(_vbox, "Upgrade Cost L1 (BB)", costs, 0, 5.0, 5.0, 999.0, true)
		_add_row_array(_vbox, "Upgrade Cost L2 (BB)", costs, 1, 5.0, 5.0, 999.0, true)
		_add_row_array(_vbox, "Upgrade Cost L3 (BB)", costs, 2, 5.0, 5.0, 999.0, true)

		# Stat B delta (increment per upgrade level for the primary stat).
		_add_row_callable(_vbox, "Stat B Upgrade Delta",
			func(): return BalanceConfig.get_boost_stat_b_delta(b),
			func(v: float): BalanceConfig.set_boost_stat_b_delta(b, v),
			0.05, 0.0, 50.0, false)

		# Stat C delta — only for boost types that have a third stat.
		if b in [2, 3, 4]:
			_add_row_callable(_vbox, "Stat C Upgrade Delta",
				func(): return BalanceConfig.get_boost_stat_c_delta(b),
				func(v: float): BalanceConfig.set_boost_stat_c_delta(b, v),
				1.0, 0.0, 100.0, false)

	_add_section("GLOBAL BOOST FACTORS")
	_add_row_callable(_vbox, "Range Factor per Level",
		func(): return BalanceConfig.get_boost_range_factor(),
		func(v: float): BalanceConfig.set_boost_range_factor(v),
		0.01, 0.01, 1.0, false)


# ---------------------------------------------------------------------------
# ENEMIES tab
# ---------------------------------------------------------------------------

func _build_enemies_tab() -> void:
	for e: int in range(ENEMY_NAMES.size()):
		_add_section(ENEMY_NAMES[e].to_upper())
		var stats := BalanceConfig.get_enemy_stats(e)

		_add_row_dict(_vbox, "HP",          stats, "hp",          5.0,  1.0, 5000.0, true)
		_add_row_dict(_vbox, "Speed (cells/s)", stats, "speed",   0.1,  0.1,   20.0, false)
		_add_row_dict(_vbox, "Infestation",  stats, "infestation", 1.0,  1.0,  200.0, false)
		_add_row_dict(_vbox, "Bounty (BB)",  stats, "bounty",     1.0,  0.0,  500.0, true)
		_add_row_dict(_vbox, "XP",           stats, "xp",         1.0,  0.0,  200.0, true)

		if stats.has("bug_bucks_steal"):
			_add_row_dict(_vbox, "BB Steal on Exit", stats, "bug_bucks_steal", 5.0, 0.0, 500.0, true)

	_add_section("HP SCALING")
	_add_row_callable(_vbox, "HP Scale per Wave Tier (+%/tier)",
		func(): return BalanceConfig.get_hp_scaling_per_tier(),
		func(v: float): BalanceConfig.set_hp_scaling_per_tier(v),
		0.05, 0.0, 3.0, false)


# ---------------------------------------------------------------------------
# WAVES tab
# ---------------------------------------------------------------------------

func _build_waves_tab() -> void:
	_add_section("WAVE PARAMETERS")
	var wc := BalanceConfig.get_wave_config()
	_add_row_dict(_vbox, "Base Wave Size",         wc, "wave_size",             1.0,  1.0, 200.0, true)
	_add_row_dict(_vbox, "Size Step Every N Waves", wc, "wave_size_step_waves", 1.0,  1.0,  50.0, true)
	_add_row_dict(_vbox, "Size Step Amount",        wc, "wave_size_step_amount", 1.0, 0.0,  20.0, true)
	_add_row_dict(_vbox, "Spawn Interval (s)",      wc, "spawn_interval",       0.02, 0.05,  5.0, false)
	_add_row_dict(_vbox, "Spawn Gap (cells)",        wc, "spawn_gap_cells",     0.05, 0.0,   5.0, false)
	_add_row_dict(_vbox, "Boss Wave Interval",       wc, "boss_wave_interval",  1.0,  1.0,  50.0, true)

	_add_section("ENEMY WAVE POOL")
	for e: int in range(ENEMY_NAMES.size()):
		var ewc := BalanceConfig.get_enemy_wave_config(e)
		var label_prefix: String = ENEMY_NAMES[e]
		_add_row_dict(_vbox, "%s — First Wave"  % label_prefix, ewc, "first_wave",      1.0, 0.0, 100.0, true)
		_add_row_dict(_vbox, "%s — Pool Weight" % label_prefix, ewc, "weight",          1.0, 0.0,  20.0, true)
		_add_row_dict(_vbox, "%s — Phase Out After Wave (0=never)" % label_prefix, ewc, "phase_out_after", 1.0, 0.0, 100.0, true)


# ---------------------------------------------------------------------------
# Row builders
# ---------------------------------------------------------------------------

## Creates a stat row that reads from and writes to a dictionary key.
## Because GDScript dicts are reference types, d[key] accesses the live
## BalanceConfig internal dict directly — no setter method required.
func _add_row_dict(parent: VBoxContainer, label: String, d: Dictionary, key: String,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:
	_add_row_callable(parent, label,
		func(): return float(d[key]),
		func(v: float): d[key] = int(v) if is_int else v,
		step, min_val, max_val, is_int)


## Creates a stat row that reads from and writes to an array element.
## GDScript arrays are also reference types, so arr[idx] reaches the live data.
func _add_row_array(parent: VBoxContainer, label: String, arr: Array, idx: int,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:
	_add_row_callable(parent, label,
		func(): return float(arr[idx]),
		func(v: float): arr[idx] = int(v) if is_int else v,
		step, min_val, max_val, is_int)


## Core row builder. getter/setter are Callables so this works for both
## dict-backed and scalar-backed values.
func _add_row_callable(parent: VBoxContainer, label: String,
		getter: Callable, setter: Callable,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var row_sty := StyleBoxFlat.new()
	row_sty.bg_color = COLOR_ROW_B if (_row_parity % 2 == 0) else COLOR_ROW_A
	row_sty.set_border_width_all(0)
	row.add_theme_stylebox_override("panel", row_sty)
	_row_parity += 1
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	row.add_child(hbox)

	# Label
	var lbl_margin := MarginContainer.new()
	lbl_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_margin.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	lbl_margin.add_theme_constant_override("margin_left", int(PADDING))
	hbox.add_child(lbl_margin)

	var lbl := Label.new()
	lbl.text             = label
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	lbl_margin.add_child(lbl)

	# Value display
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size    = Vector2(VAL_W, 0.0)
	val_lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.size_flags_vertical    = Control.SIZE_SHRINK_CENTER
	val_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	val_lbl.add_theme_font_size_override("font_size", 22)
	val_lbl.add_theme_color_override("font_color", COLOR_VALUE)
	val_lbl.text                   = _fmt(getter.call(), is_int)
	val_lbl.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(val_lbl)

	# [-] button
	var minus_btn := _make_adj_btn("−",
		COLOR_BTN_MINUS_NORMAL, COLOR_BTN_MINUS_HOVER,
		COLOR_BTN_MINUS_PRESS,  COLOR_BTN_MINUS_BORDER)
	hbox.add_child(minus_btn)

	# [+] button
	var plus_btn := _make_adj_btn("+",
		COLOR_BTN_PLUS_NORMAL, COLOR_BTN_PLUS_HOVER,
		COLOR_BTN_PLUS_PRESS,  COLOR_BTN_PLUS_BORDER)
	hbox.add_child(plus_btn)

	# Right margin
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(PADDING, 0.0)
	right_pad.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_pad)

	# Wire buttons — clamp, set, display, persist.
	minus_btn.pressed.connect(func() -> void:
		var current: float = getter.call()
		var next_val: float = snappedf(current - step, step)
		next_val = clampf(next_val, min_val, max_val)
		setter.call(next_val)
		val_lbl.text = _fmt(getter.call(), is_int)
		BalanceConfig.save()
	)
	plus_btn.pressed.connect(func() -> void:
		var current: float = getter.call()
		var next_val: float = snappedf(current + step, step)
		next_val = clampf(next_val, min_val, max_val)
		setter.call(next_val)
		val_lbl.text = _fmt(getter.call(), is_int)
		BalanceConfig.save()
	)


# ---------------------------------------------------------------------------
# Section header
# ---------------------------------------------------------------------------

func _add_section(text: String) -> void:
	_row_parity = 0   # reset alternation so first row after header is always the same colour

	var strip := Panel.new()
	strip.custom_minimum_size   = Vector2(0.0, 40.0)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = COLOR_SECTION_BG
	sty.set_border_width_all(0)
	strip.add_theme_stylebox_override("panel", sty)
	_vbox.add_child(strip)

	var lbl := Label.new()
	lbl.text                 = text
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_SECTION_TXT)
	strip.add_child(lbl)


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _add_h_divider(top: float) -> void:
	var div := ColorRect.new()
	div.color        = COLOR_DIVIDER
	div.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	div.offset_top    = top
	div.offset_bottom = top + 1.0
	div.anchor_bottom = 0.0
	div.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(div)


func _make_adj_btn(label: String,
		bg_n: Color, bg_h: Color, bg_p: Color, border: Color) -> Button:
	var btn := Button.new()
	btn.text                  = label
	btn.focus_mode            = Control.FOCUS_NONE
	btn.custom_minimum_size   = Vector2(BTN_W, 0.0)
	btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(0.90, 0.90, 0.92, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [["normal", bg_n], ["hover", bg_h], ["pressed", bg_p]]:
		var box := StyleBoxFlat.new()
		box.bg_color = state[1]
		box.border_color = border
		box.set_border_width_all(1)
		btn.add_theme_stylebox_override(state[0], box)
	return btn


func _make_text_button(text: String, min_w: float,
		bg_n: Color, bg_h: Color, bg_p: Color, border: Color,
		font_color: Color) -> Button:
	var btn := Button.new()
	btn.text                  = text
	btn.focus_mode            = Control.FOCUS_NONE
	btn.custom_minimum_size   = Vector2(min_w, 44.0)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [["normal", bg_n], ["hover", bg_h], ["pressed", bg_p]]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = border
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8.0)
		btn.add_theme_stylebox_override(state[0], box)
	return btn


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

## Shows integers without decimals; floats with two decimal places.
func _fmt(value: float, is_int: bool) -> String:
	if is_int:
		return str(int(value))
	# Suppress trailing zeros on values that happen to be whole numbers
	# (e.g. a range of 4.0 shows as "4.00" — readable but unambiguous).
	return "%.2f" % value


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_close_pressed() -> void:
	AudioManager.play_ui("button")
	queue_free()


func _on_reset_pressed() -> void:
	AudioManager.play_ui("button")
	BalanceConfig.reset_to_defaults()
	_populate_tab(_active_tab)
