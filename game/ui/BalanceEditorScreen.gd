## BalanceEditorScreen.gd
## Full-screen overlay for tweaking all BalanceConfig values before a run.
## Accessible from the Settings dialog on the start screen.
##
## Layout: header → main tab bar → sub-tab bar → scrollable stat rows.
## Main tabs: TRAPS | BOOSTS | ENEMIES | WAVES.
## Sub-tabs show one unit (or one logical group) at a time so each page is
## focused and easy to navigate.
##
## Each row shows a stat name, a one-line hint about what it controls, the
## current value, and [-] / [+] buttons. Changes write back to BalanceConfig's
## live dicts (reference semantics) and call save() immediately.
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
const COLOR_SECTION_BG  := Color(0.04, 0.10, 0.08, 1.0)
const COLOR_SECTION_TXT := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_ROW_A       := Color(0.06, 0.08, 0.15, 1.0)
const COLOR_ROW_B       := Color(0.08, 0.10, 0.19, 1.0)
const COLOR_TEXT        := Color(0.86, 0.88, 0.92, 1.0)
const COLOR_HINT        := Color(0.55, 0.62, 0.72, 1.0)
const COLOR_VALUE       := Color(0.96, 0.88, 0.50, 1.0)

# Main tab colours — green theme
const COLOR_TAB_ACTIVE_BG  := Color(0.06, 0.18, 0.06, 1.0)
const COLOR_TAB_IDLE_BG    := Color(0.02, 0.06, 0.02, 1.0)
const COLOR_TAB_ACTIVE_TXT := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_TAB_IDLE_TXT   := Color(0.45, 0.50, 0.55, 1.0)

# Sub-tab colours — blue/indigo theme, visually subordinate to main tabs
const COLOR_SUB_ACTIVE_BG  := Color(0.06, 0.10, 0.24, 1.0)
const COLOR_SUB_IDLE_BG    := Color(0.02, 0.04, 0.10, 1.0)
const COLOR_SUB_ACTIVE_TXT := Color(0.85, 0.92, 1.00, 1.0)
const COLOR_SUB_IDLE_TXT   := Color(0.30, 0.38, 0.52, 1.0)

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

const COLOR_EXPORT_NORMAL := Color(0.02, 0.16, 0.22, 1.0)
const COLOR_EXPORT_HOVER  := Color(0.04, 0.22, 0.30, 1.0)
const COLOR_EXPORT_PRESS  := Color(0.01, 0.10, 0.15, 1.0)
const COLOR_EXPORT_BORDER := Color(0.10, 0.52, 0.72, 1.0)
const COLOR_EXPORT_TXT    := Color(0.72, 0.92, 1.00, 1.0)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const PADDING:   float = 24.0
const HEADER_H:  float = 66.0
const TAB_H:     float = 50.0
const SUB_TAB_H: float = 40.0
const ROW_H:     float = 72.0   # taller than v1 to fit the hint line
const BTN_W:     float = 56.0
const VAL_W:     float = 120.0

# Vertical position where the scroll area begins.
# Header + divider + main tabs + divider + sub-tabs + divider
const SCROLL_TOP: float = HEADER_H + 2.0 + TAB_H + 1.0 + SUB_TAB_H + 1.0


# ---------------------------------------------------------------------------
# Sub-tab label arrays — one entry per sub-page for each main tab
# ---------------------------------------------------------------------------

# TRAPS: indices 0-5 = individual traps, 6 = global factors / level tables
const _TRAP_SUB_TABS:   Array[String] = ["SNAP", "ZAPPER", "FOGGER", "GLUE", "FLY STRIP", "BAIT", "GLOBAL"]

# BOOSTS: indices 0-4 = individual boosts, 5 = global range factor
const _BOOST_SUB_TABS:  Array[String] = ["PHEROMONE", "COMPRESSOR", "CASH REG.", "AIR FRESH.", "QUARANTINE", "GLOBAL"]

# ENEMIES: indices 0-8 = individual enemies, 9 = HP scaling
const _ENEMY_SUB_TABS:  Array[String] = ["ANT", "GNAT", "CRICKET", "BEETLE", "ROACH", "MOUSE", "MOSQUITO", "RAT KING", "RAT", "HP SCALE"]

# WAVES: 0 = wave parameters, 1 = per-enemy pool config
const _WAVE_SUB_TABS:   Array[String] = ["WAVE CONFIG", "ENEMY POOL"]


# ---------------------------------------------------------------------------
# Unit name tables (full display names, match BalanceConfig enum ordinals)
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

# Damage hint text differs per trap because damage means something different
# for each type (snap vs. pulse vs. DoT vs. poison tick vs. no direct damage).
const _TRAP_DAMAGE_HINTS: Array[String] = [
	"damage dealt when snap closes on contact",
	"damage per electric pulse",
	"damage per second while enemy is inside cloud",
	"no direct damage — slow only; damage stays at 0",
	"damage on strip impact",
	"no direct damage — poison ticks handle damage; keep at 0",
]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _active_tab:     String          = "TRAPS"
var _active_sub_tab: int             = 0
var _tab_btns:       Dictionary      = {}
var _sub_tab_hbox:   HBoxContainer   = null
var _sub_tab_btns:   Array           = []
var _scroll:         ScrollContainer = null
var _vbox:           VBoxContainer   = null
var _row_parity:     int             = 0


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
	_build_main_tab_bar()
	_add_h_divider(HEADER_H + 1.0 + TAB_H)
	_build_sub_tab_bar()
	_add_h_divider(HEADER_H + 2.0 + TAB_H + SUB_TAB_H)
	_build_scroll_area()

	# Populate the initial sub-tab buttons and content for the default tab.
	_rebuild_sub_tabs()
	_populate_content()


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
	title_lbl.text                = "BALANCE EDITOR"
	title_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
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

	var export_btn := _make_text_button("Export MD", 130.0,
		COLOR_EXPORT_NORMAL, COLOR_EXPORT_HOVER, COLOR_EXPORT_PRESS, COLOR_EXPORT_BORDER,
		COLOR_EXPORT_TXT)
	export_btn.pressed.connect(_on_export_pressed)
	hbox.add_child(export_btn)

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
# Main tab bar
# ---------------------------------------------------------------------------

func _build_main_tab_bar() -> void:
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
		_style_main_tab_btn(btn, tab_name == _active_tab)
		btn.pressed.connect(_on_main_tab_pressed.bind(tab_name))
		hbox.add_child(btn)
		_tab_btns[tab_name] = btn


func _style_main_tab_btn(btn: Button, is_active: bool) -> void:
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


func _on_main_tab_pressed(tab_name: String) -> void:
	if tab_name == _active_tab:
		return
	_style_main_tab_btn(_tab_btns[_active_tab], false)
	_active_tab = tab_name
	_style_main_tab_btn(_tab_btns[_active_tab], true)
	_active_sub_tab = 0
	_rebuild_sub_tabs()
	_populate_content()


# ---------------------------------------------------------------------------
# Sub-tab bar
# ---------------------------------------------------------------------------

func _build_sub_tab_bar() -> void:
	var bar := Control.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_top    = HEADER_H + 2.0 + TAB_H
	bar.offset_bottom = HEADER_H + 2.0 + TAB_H + SUB_TAB_H
	bar.anchor_bottom = 0.0
	add_child(bar)

	_sub_tab_hbox = HBoxContainer.new()
	_sub_tab_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sub_tab_hbox.add_theme_constant_override("separation", 0)
	bar.add_child(_sub_tab_hbox)


## Destroys the current sub-tab buttons and rebuilds them for _active_tab.
## Called whenever the main tab changes.
func _rebuild_sub_tabs() -> void:
	for child: Node in _sub_tab_hbox.get_children():
		child.free()   # immediate free — avoids a frame where old + new buttons coexist
	_sub_tab_btns.clear()

	var names: Array[String]
	match _active_tab:
		"TRAPS":   names = _TRAP_SUB_TABS
		"BOOSTS":  names = _BOOST_SUB_TABS
		"ENEMIES": names = _ENEMY_SUB_TABS
		"WAVES":   names = _WAVE_SUB_TABS

	for i: int in range(names.size()):
		var btn := Button.new()
		btn.text                  = names[i]
		btn.focus_mode            = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", UIFonts.primary_bold())
		btn.add_theme_font_size_override("font_size", 14)
		_style_sub_tab_btn(btn, i == 0)
		btn.pressed.connect(_on_sub_tab_pressed.bind(i))
		_sub_tab_hbox.add_child(btn)
		_sub_tab_btns.append(btn)


func _style_sub_tab_btn(btn: Button, is_active: bool) -> void:
	var bg_col  := COLOR_SUB_ACTIVE_BG  if is_active else COLOR_SUB_IDLE_BG
	var txt_col := COLOR_SUB_ACTIVE_TXT if is_active else COLOR_SUB_IDLE_TXT
	btn.add_theme_color_override("font_color", txt_col)
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = bg_col.lightened(0.04) if state == "hover" else \
				(bg_col.darkened(0.04) if state == "pressed" else bg_col)
		box.set_border_width_all(0)
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_sub_tab_pressed(idx: int) -> void:
	if idx == _active_sub_tab:
		return
	_style_sub_tab_btn(_sub_tab_btns[_active_sub_tab], false)
	_active_sub_tab = idx
	_style_sub_tab_btn(_sub_tab_btns[_active_sub_tab], true)
	_populate_content()


# ---------------------------------------------------------------------------
# Scroll area
# ---------------------------------------------------------------------------

func _build_scroll_area() -> void:
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top             = SCROLL_TOP
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.process_mode           = Node.PROCESS_MODE_ALWAYS
	add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 0)
	_scroll.add_child(_vbox)


# ---------------------------------------------------------------------------
# Content dispatch
# ---------------------------------------------------------------------------

func _populate_content() -> void:
	for child: Node in _vbox.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	_row_parity             = 0

	match _active_tab:
		"TRAPS":
			if _active_sub_tab < 6:
				_build_trap_page(_active_sub_tab)
			else:
				_build_traps_global_page()
		"BOOSTS":
			if _active_sub_tab < 5:
				_build_boost_page(_active_sub_tab)
			else:
				_build_boosts_global_page()
		"ENEMIES":
			if _active_sub_tab < 9:
				_build_enemy_page(_active_sub_tab)
			else:
				_build_enemies_global_page()
		"WAVES":
			if _active_sub_tab == 0:
				_build_waves_config_page()
			else:
				_build_waves_pool_page()


# ---------------------------------------------------------------------------
# TRAPS — individual trap page
# ---------------------------------------------------------------------------

func _build_trap_page(t: int) -> void:
	var stats := BalanceConfig.get_trap_stats(t)
	var costs := BalanceConfig.get_trap_upgrade_costs(t)

	_add_section("BASE STATS")

	_add_row_dict(_vbox, "Damage", _TRAP_DAMAGE_HINTS[t],
		stats, "damage", 0.5, 0.0, 500.0, false)
	_add_row_dict(_vbox, "Range", "detection radius in grid cells",
		stats, "range", 0.2, 0.5, 25.0, false)
	_add_row_dict(_vbox, "Cooldown", "seconds between activations (0 = contact-only, no recharge)",
		stats, "cooldown", 0.1, 0.0, 15.0, false)
	_add_row_dict(_vbox, "Cost", "Bug Bucks to place on the grid",
		stats, "cost", 5.0, 5.0, 999.0, true)

	# Type-specific fields — only present on the traps that use them.
	if stats.has("pulse_interval"):
		_add_row_dict(_vbox, "Pulse Interval", "seconds between pulses within a burst sequence",
			stats, "pulse_interval", 0.25, 0.25, 30.0, false)
	if stats.has("cloud_duration"):
		_add_row_dict(_vbox, "Cloud Duration", "seconds the fog cloud lingers after each puff",
			stats, "cloud_duration", 0.5, 0.5, 20.0, false)
	if stats.has("adhesion"):
		_add_row_dict(_vbox, "Adhesion", "slow multiplier applied to caught enemy (0 = no slow · 1 = full stop)",
			stats, "adhesion", 0.05, 0.0, 1.0, false)
	if stats.has("poison_damage_per_tick"):
		_add_row_dict(_vbox, "Poison Damage per Tick", "damage applied each tick while enemy is poisoned",
			stats, "poison_damage_per_tick", 0.5, 0.1, 100.0, false)
	if stats.has("poison_duration"):
		_add_row_dict(_vbox, "Poison Duration", "seconds the poison effect lasts after the enemy eats bait",
			stats, "poison_duration", 0.5, 0.5, 30.0, false)
	if stats.has("poison_tick_rate"):
		_add_row_dict(_vbox, "Poison Tick Rate", "seconds between each poison damage tick (lower = faster ticks)",
			stats, "poison_tick_rate", 0.1, 0.1, 5.0, false)

	_add_section("UPGRADE COSTS")

	_add_row_array(_vbox, "Level 1 Cost", "Bug Bucks to purchase the first upgrade",
		costs, 0, 5.0, 5.0, 999.0, true)
	_add_row_array(_vbox, "Level 2 Cost", "Bug Bucks to purchase the second upgrade",
		costs, 1, 5.0, 5.0, 999.0, true)
	_add_row_array(_vbox, "Level 3 Cost", "Bug Bucks to purchase the third upgrade",
		costs, 2, 5.0, 5.0, 999.0, true)


# ---------------------------------------------------------------------------
# TRAPS — global factors and per-level tables page
# ---------------------------------------------------------------------------

func _build_traps_global_page() -> void:
	var f := BalanceConfig.get_trap_upgrade_factors()

	_add_section("UPGRADE MULTIPLIERS")
	_add_row_dict(_vbox, "Damage per Level", "fraction of base damage added per upgrade level (0.20 = +20%)",
		f, "damage", 0.01, 0.01, 2.0, false)
	_add_row_dict(_vbox, "Range per Level", "fraction of base range added per upgrade level",
		f, "range", 0.01, 0.01, 1.0, false)
	_add_row_dict(_vbox, "Fire Rate per Level", "fraction of base fire rate added per upgrade level",
		f, "fire_rate", 0.01, 0.01, 1.0, false)
	_add_row_dict(_vbox, "Crit Chance per Level", "flat crit chance added per level (0.02 = +2% per level)",
		f, "crit_chance_per_level", 0.01, 0.0, 0.5, false)
	_add_row_dict(_vbox, "Crit Damage per Level", "crit damage multiplier added per upgrade level",
		f, "crit_damage_per_level", 0.05, 0.0, 3.0, false)

	# Per-level tables: adhesion and duration values at each of the four upgrade tiers.
	var ga := BalanceConfig.get_glue_adhesion_levels()
	var gd := BalanceConfig.get_glue_duration_levels()
	var fa := BalanceConfig.get_fly_strip_adhesion_levels()
	var bd := BalanceConfig.get_bait_poison_duration_levels()

	_add_section("GLUE BOARD — ADHESION PER UPGRADE LEVEL")
	for i: int in range(4):
		_add_row_array(_vbox, "Level %d Adhesion" % i,
			"slow multiplier at upgrade level %d (0 = no slow · 1 = full stop)" % i,
			ga, i, 0.05, 0.0, 1.0, false)

	_add_section("GLUE BOARD — DURATION PER UPGRADE LEVEL")
	for i: int in range(4):
		_add_row_array(_vbox, "Level %d Duration" % i,
			"seconds the slow lasts at upgrade level %d" % i,
			gd, i, 0.5, 0.5, 30.0, false)

	_add_section("FLY STRIP — ADHESION PER UPGRADE LEVEL")
	for i: int in range(4):
		_add_row_array(_vbox, "Level %d Adhesion" % i,
			"slow multiplier applied on impact at upgrade level %d" % i,
			fa, i, 0.05, 0.0, 1.0, false)

	_add_section("BAIT STATION — POISON DURATION PER UPGRADE LEVEL")
	for i: int in range(4):
		_add_row_array(_vbox, "Level %d Duration" % i,
			"seconds the poison lasts at upgrade level %d" % i,
			bd, i, 0.5, 0.5, 30.0, false)


# ---------------------------------------------------------------------------
# BOOSTS — individual boost page
# ---------------------------------------------------------------------------

func _build_boost_page(b: int) -> void:
	var stats := BalanceConfig.get_boost_stats(b)
	var costs := BalanceConfig.get_boost_upgrade_costs(b)

	_add_section("BASE STATS")

	_add_row_dict(_vbox, "Range", "aura radius in grid cells; traps within range receive the buff",
		stats, "range", 0.2, 0.5, 20.0, false)
	_add_row_dict(_vbox, "Cost", "Bug Bucks to place on the grid",
		stats, "cost", 5.0, 5.0, 999.0, true)

	match b:
		0:  # PHEROMONE_DISPENSER
			_add_row_dict(_vbox, "Damage Bonus",
				"damage multiplier bonus to nearby traps (0.25 = each trap deals +25% damage)",
				stats, "damage_bonus", 0.05, 0.0, 3.0, false)
		1:  # COMPRESSOR
			_add_row_dict(_vbox, "Fire Rate Bonus",
				"fire rate multiplier bonus to nearby traps (0.20 = each trap fires +20% faster)",
				stats, "fire_rate_bonus", 0.05, 0.0, 3.0, false)
		2:  # CASH_REGISTER
			_add_row_dict(_vbox, "Income per Wave",
				"Bug Bucks added to your income at the start of each wave",
				stats, "income_per_wave", 1.0, 0.0, 200.0, true)
			_add_row_dict(_vbox, "Kill Bonus",
				"extra Bug Bucks earned per enemy killed within the aura",
				stats, "kill_bonus", 1.0, 0.0, 100.0, true)
		3:  # AIR_FRESHENER
			_add_row_dict(_vbox, "Infestation Reduction",
				"fraction of infestation damage blocked while active (0.5 = −50%)",
				stats, "reduction", 0.05, 0.0, 1.0, false)
			_add_row_dict(_vbox, "Capacity",
				"total infestation points this unit can absorb before depleting",
				stats, "capacity", 5.0, 10.0, 500.0, false)
		4:  # QUARANTINE_MARKER
			_add_row_dict(_vbox, "Restore per Kill",
				"capacity points restored each time an enemy is killed within range",
				stats, "restore_per_kill", 0.5, 0.0, 50.0, false)
			_add_row_dict(_vbox, "Capacity",
				"total infestation points this unit can absorb before depleting",
				stats, "capacity", 5.0, 10.0, 500.0, false)

	_add_section("UPGRADE COSTS")

	_add_row_array(_vbox, "Level 1 Cost", "Bug Bucks to purchase the first upgrade",
		costs, 0, 5.0, 5.0, 999.0, true)
	_add_row_array(_vbox, "Level 2 Cost", "Bug Bucks to purchase the second upgrade",
		costs, 1, 5.0, 5.0, 999.0, true)
	_add_row_array(_vbox, "Level 3 Cost", "Bug Bucks to purchase the third upgrade",
		costs, 2, 5.0, 5.0, 999.0, true)

	_add_section("UPGRADE DELTAS")

	# Stat B delta — what the primary stat (damage/fire rate/income etc.) gains per upgrade.
	var stat_b_hint: String
	match b:
		0: stat_b_hint = "damage bonus added per upgrade level"
		1: stat_b_hint = "fire rate bonus added per upgrade level"
		2: stat_b_hint = "income per wave added per upgrade level (Bug Bucks)"
		3: stat_b_hint = "infestation reduction fraction added per upgrade level"
		4: stat_b_hint = "restore-per-kill added per upgrade level"
		_: stat_b_hint = "primary stat increase per upgrade level"

	_add_row_callable(_vbox, "Primary Stat Delta", stat_b_hint,
		func(): return BalanceConfig.get_boost_stat_b_delta(b),
		func(v: float): BalanceConfig.set_boost_stat_b_delta(b, v),
		0.05, 0.0, 50.0, false)

	# Stat C delta only applies to boost types that have a secondary numeric stat.
	if b in [2, 3, 4]:
		var stat_c_hint: String
		match b:
			2: stat_c_hint = "kill bonus (BB) added per upgrade level"
			3: stat_c_hint = "capacity added per upgrade level"
			4: stat_c_hint = "capacity added per upgrade level"
			_: stat_c_hint = "secondary stat increase per upgrade level"

		_add_row_callable(_vbox, "Secondary Stat Delta", stat_c_hint,
			func(): return BalanceConfig.get_boost_stat_c_delta(b),
			func(v: float): BalanceConfig.set_boost_stat_c_delta(b, v),
			1.0, 0.0, 100.0, false)


# ---------------------------------------------------------------------------
# BOOSTS — global factors page
# ---------------------------------------------------------------------------

func _build_boosts_global_page() -> void:
	_add_section("GLOBAL BOOST FACTORS")
	_add_row_callable(_vbox, "Range Factor per Level",
		"fraction of base range added per range upgrade level (shared by all boost types)",
		func(): return BalanceConfig.get_boost_range_factor(),
		func(v: float): BalanceConfig.set_boost_range_factor(v),
		0.01, 0.01, 1.0, false)


# ---------------------------------------------------------------------------
# ENEMIES — individual enemy page
# ---------------------------------------------------------------------------

func _build_enemy_page(e: int) -> void:
	var stats := BalanceConfig.get_enemy_stats(e)
	var ewc   := BalanceConfig.get_enemy_wave_config(e)

	_add_section("COMBAT STATS")

	_add_row_dict(_vbox, "HP",
		"base hit points at wave tier 0 — scales upward each tier (every 5 waves)",
		stats, "hp", 5.0, 1.0, 5000.0, true)
	_add_row_dict(_vbox, "Speed",
		"movement speed in grid cells per second along the path",
		stats, "speed", 0.1, 0.1, 20.0, false)
	_add_row_dict(_vbox, "Infestation",
		"infestation points lost when this enemy reaches the exit",
		stats, "infestation", 1.0, 0.0, 200.0, false)
	_add_row_dict(_vbox, "Bounty",
		"Bug Bucks earned per kill",
		stats, "bounty", 1.0, 0.0, 500.0, true)
	_add_row_dict(_vbox, "XP",
		"XP points earned per kill",
		stats, "xp", 1.0, 0.0, 200.0, true)

	if stats.has("bug_bucks_steal"):
		_add_row_dict(_vbox, "Bug Bucks Steal",
			"Bug Bucks stolen from the player if this enemy escapes (in addition to infestation damage)",
			stats, "bug_bucks_steal", 5.0, 0.0, 500.0, true)

	_add_section("WAVE POOL CONFIG")

	_add_row_dict(_vbox, "First Wave",
		"wave number when this enemy first appears (0 = not determined by this field; see weight)",
		ewc, "first_wave", 1.0, 0.0, 100.0, true)
	_add_row_dict(_vbox, "Pool Weight",
		"relative probability in the random spawn pool — set to 0 for boss-only enemies",
		ewc, "weight", 1.0, 0.0, 20.0, true)
	_add_row_dict(_vbox, "Phase Out After Wave",
		"stop spawning after this wave number (0 = never phase out)",
		ewc, "phase_out_after", 1.0, 0.0, 100.0, true)


# ---------------------------------------------------------------------------
# ENEMIES — global HP scaling page
# ---------------------------------------------------------------------------

func _build_enemies_global_page() -> void:
	_add_section("HP SCALING")
	_add_row_callable(_vbox, "HP Scale per Wave Tier",
		"fraction of base HP added per tier — tier increases every 5 waves (e.g. 0.30 = +30% per tier)",
		func(): return BalanceConfig.get_hp_scaling_per_tier(),
		func(v: float): BalanceConfig.set_hp_scaling_per_tier(v),
		0.05, 0.0, 3.0, false)


# ---------------------------------------------------------------------------
# WAVES — wave config page
# ---------------------------------------------------------------------------

func _build_waves_config_page() -> void:
	var wc := BalanceConfig.get_wave_config()

	_add_section("ENEMY COUNT")
	_add_row_dict(_vbox, "Base Wave Size",
		"number of enemies in the very first wave",
		wc, "wave_size", 1.0, 1.0, 200.0, true)
	_add_row_dict(_vbox, "Size Step Every N Waves",
		"the enemy count grows by the step amount every N waves",
		wc, "wave_size_step_waves", 1.0, 1.0, 50.0, true)
	_add_row_dict(_vbox, "Size Step Amount",
		"enemies added to the wave size each time the step triggers",
		wc, "wave_size_step_amount", 1.0, 0.0, 20.0, true)

	_add_section("SPAWN TIMING")
	_add_row_dict(_vbox, "Spawn Interval",
		"seconds between each enemy entering the path; lower = enemies arrive faster",
		wc, "spawn_interval", 0.02, 0.05, 5.0, false)
	_add_row_dict(_vbox, "Spawn Gap",
		"minimum path distance (in grid cells) kept between consecutive enemies",
		wc, "spawn_gap_cells", 0.05, 0.0, 5.0, false)

	_add_section("BOSS WAVES")
	_add_row_dict(_vbox, "Boss Wave Interval",
		"a boss enemy spawns on every Nth wave (e.g. 10 = waves 10, 20, 30, …)",
		wc, "boss_wave_interval", 1.0, 1.0, 50.0, true)


# ---------------------------------------------------------------------------
# WAVES — enemy pool page
# ---------------------------------------------------------------------------

func _build_waves_pool_page() -> void:
	for e: int in range(ENEMY_NAMES.size()):
		_add_section(ENEMY_NAMES[e].to_upper())
		var ewc := BalanceConfig.get_enemy_wave_config(e)

		_add_row_dict(_vbox, "First Wave",
			"wave number when this enemy type can first appear",
			ewc, "first_wave", 1.0, 0.0, 100.0, true)
		_add_row_dict(_vbox, "Pool Weight",
			"relative probability in the random spawn pool — 0 = boss-only, never in normal waves",
			ewc, "weight", 1.0, 0.0, 20.0, true)
		_add_row_dict(_vbox, "Phase Out After Wave",
			"stop including this enemy in the pool after this wave (0 = never phase out)",
			ewc, "phase_out_after", 1.0, 0.0, 100.0, true)


# ---------------------------------------------------------------------------
# Row builders
# ---------------------------------------------------------------------------

## Convenience wrapper: read/write through a Dictionary reference.
## GDScript dicts are reference types, so d[key] modifies the live BalanceConfig
## internal dict directly without needing a setter method.
func _add_row_dict(parent: VBoxContainer, label: String, hint: String,
		d: Dictionary, key: String,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:
	_add_row_callable(parent, label, hint,
		func(): return float(d[key]),
		func(v: float): d[key] = int(v) if is_int else v,
		step, min_val, max_val, is_int)


## Convenience wrapper: read/write through an Array reference.
func _add_row_array(parent: VBoxContainer, label: String, hint: String,
		arr: Array, idx: int,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:
	_add_row_callable(parent, label, hint,
		func(): return float(arr[idx]),
		func(v: float): arr[idx] = int(v) if is_int else v,
		step, min_val, max_val, is_int)


## Core row builder. getter/setter Callables allow this to work for both
## dict/array-backed values and standalone scalar values.
func _add_row_callable(parent: VBoxContainer, label: String, hint: String,
		getter: Callable, setter: Callable,
		step: float, min_val: float, max_val: float, is_int: bool) -> void:

	var row := Panel.new()
	row.custom_minimum_size   = Vector2(0.0, ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var row_sty               := StyleBoxFlat.new()
	row_sty.bg_color          = COLOR_ROW_B if (_row_parity % 2 == 0) else COLOR_ROW_A
	row_sty.set_border_width_all(0)
	row.add_theme_stylebox_override("panel", row_sty)
	_row_parity += 1
	parent.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	row.add_child(hbox)

	# Label column: stat name on top, hint text on bottom.
	var lbl_margin := MarginContainer.new()
	lbl_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_margin.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	lbl_margin.add_theme_constant_override("margin_left",   int(PADDING))
	lbl_margin.add_theme_constant_override("margin_top",    8)
	lbl_margin.add_theme_constant_override("margin_bottom", 8)
	hbox.add_child(lbl_margin)

	var lbl_vbox := VBoxContainer.new()
	lbl_vbox.add_theme_constant_override("separation", 2)
	lbl_margin.add_child(lbl_vbox)

	var name_lbl := Label.new()
	name_lbl.text         = label
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_vbox.add_child(name_lbl)

	if not hint.is_empty():
		var hint_lbl := Label.new()
		hint_lbl.text              = hint
		hint_lbl.mouse_filter      = Control.MOUSE_FILTER_IGNORE
		hint_lbl.autowrap_mode     = TextServer.AUTOWRAP_OFF
		hint_lbl.clip_text         = true
		hint_lbl.add_theme_font_size_override("font_size", 13)
		hint_lbl.add_theme_color_override("font_color", COLOR_HINT)
		lbl_vbox.add_child(hint_lbl)

	# Current value display.
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size  = Vector2(VAL_W, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	val_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	val_lbl.add_theme_font_size_override("font_size", 22)
	val_lbl.add_theme_color_override("font_color", COLOR_VALUE)
	val_lbl.text                 = _fmt(getter.call(), is_int)
	val_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
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

	# Right padding to mirror the left margin.
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(PADDING, 0.0)
	right_pad.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_pad)

	# Wire buttons: clamp value, write back, refresh display, persist to disk.
	minus_btn.pressed.connect(func() -> void:
		var next_val: float = clampf(snappedf(getter.call() - step, step), min_val, max_val)
		setter.call(next_val)
		val_lbl.text = _fmt(getter.call(), is_int)
		BalanceConfig.save()
	)
	plus_btn.pressed.connect(func() -> void:
		var next_val: float = clampf(snappedf(getter.call() + step, step), min_val, max_val)
		setter.call(next_val)
		val_lbl.text = _fmt(getter.call(), is_int)
		BalanceConfig.save()
	)


# ---------------------------------------------------------------------------
# Section header
# ---------------------------------------------------------------------------

func _add_section(text: String) -> void:
	_row_parity = 0   # restart stripe alternation after each section header

	var strip := Panel.new()
	strip.custom_minimum_size   = Vector2(0.0, 38.0)
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
	lbl.add_theme_font_size_override("font_size", 17)
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
	btn.text                = label
	btn.focus_mode          = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(BTN_W, 0.0)
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", Color(0.90, 0.90, 0.92, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [["normal", bg_n], ["hover", bg_h], ["pressed", bg_p]]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = border
		box.set_border_width_all(1)
		btn.add_theme_stylebox_override(state[0], box)
	return btn


func _make_text_button(text: String, min_w: float,
		bg_n: Color, bg_h: Color, bg_p: Color, border: Color,
		font_color: Color) -> Button:
	var btn := Button.new()
	btn.text                = text
	btn.focus_mode          = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(min_w, 44.0)
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

## Integers display without decimals; floats always show two decimal places
## so the column width stays stable as values change.
func _fmt(value: float, is_int: bool) -> String:
	return str(int(value)) if is_int else "%.2f" % value


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_export_pressed() -> void:
	AudioManager.play_ui("button")
	var markdown: String = BalanceConfig.export_to_markdown()

	# Save to user data directory so it survives game updates.
	const SAVE_NAME := "balance_export.md"
	var file := FileAccess.open("user://" + SAVE_NAME, FileAccess.WRITE)
	var save_ok: bool = file != null
	if save_ok:
		file.store_string(markdown)
		file.close()

	# Resolve the user:// path to a real OS path for display.
	var os_path: String = ProjectSettings.globalize_path("user://" + SAVE_NAME)

	_show_export_dialog(os_path, markdown, save_ok)


## Shows a modal overlay with options for what to do with the exported markdown.
func _show_export_dialog(os_path: String, markdown: String, save_ok: bool) -> void:
	const DIALOG_W: float = 800.0
	const DIALOG_H: float = 240.0

	# Full-screen blocker — intercepts all clicks so the editor is inaccessible while the
	# dialog is open.  Mouse filter STOP ensures nothing behind it receives input.
	var blocker := Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)

	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.add_child(dim)

	# Centered dialog panel.
	var panel := Panel.new()
	panel.position = Vector2((1280.0 - DIALOG_W) * 0.5, (600.0 - DIALOG_H) * 0.5)
	panel.size     = Vector2(DIALOG_W, DIALOG_H)
	var panel_sty  := StyleBoxFlat.new()
	panel_sty.bg_color = Color(0.06, 0.10, 0.20, 1.0)
	panel_sty.border_color = Color(0.10, 0.52, 0.72, 1.0)
	panel_sty.set_border_width_all(2)
	panel_sty.set_corner_radius_all(8)
	panel_sty.set_content_margin_all(24.0)
	panel.add_theme_stylebox_override("panel", panel_sty)
	blocker.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text                = "BALANCE SHEET EXPORTED" if save_ok else "EXPORT FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIFonts.primary_bold())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_EXPORT_TXT if save_ok else Color(1.0, 0.4, 0.4, 1.0))
	vbox.add_child(title)

	# File path (or error message).
	var path_lbl := Label.new()
	path_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	path_lbl.add_theme_font_size_override("font_size", 15)
	path_lbl.add_theme_color_override("font_color", COLOR_HINT)
	path_lbl.text = os_path if save_ok else "Could not write to user data directory."
	path_lbl.clip_text = true
	vbox.add_child(path_lbl)

	# Hint about what to do next.
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", COLOR_HINT)
	if save_ok:
		hint.text = "Open the file in any text or markdown editor, or copy to clipboard and paste into a doc."
	else:
		hint.text = "Use Copy to Clipboard to save the markdown manually."
	vbox.add_child(hint)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var clipboard_lbl: Label = null   # updated after copy

	var copy_btn := _make_text_button("Copy to Clipboard", 190.0,
		COLOR_EXPORT_NORMAL, COLOR_EXPORT_HOVER, COLOR_EXPORT_PRESS, COLOR_EXPORT_BORDER,
		COLOR_EXPORT_TXT)
	btn_row.add_child(copy_btn)

	# Show in file manager only makes sense where the OS exposes the filesystem.
	if save_ok and OS.get_name() in ["Windows", "macOS", "Linux"]:
		var show_btn := _make_text_button("Show in Explorer", 180.0,
			Color(0.06, 0.12, 0.06, 1.0), Color(0.10, 0.18, 0.10, 1.0),
			Color(0.03, 0.07, 0.03, 1.0), Color(0.22, 0.55, 0.22, 1.0),
			Color(0.80, 0.95, 0.80, 1.0))
		show_btn.pressed.connect(func() -> void:
			OS.shell_show_in_file_manager(os_path)
		)
		btn_row.add_child(show_btn)

	var dismiss_btn := _make_text_button("Dismiss", 110.0,
		COLOR_CLOSE_NORMAL, COLOR_CLOSE_HOVER, COLOR_CLOSE_PRESS, COLOR_CLOSE_BORDER,
		COLOR_TEXT)
	dismiss_btn.pressed.connect(func() -> void:
		blocker.queue_free()
	)
	btn_row.add_child(dismiss_btn)

	# Clipboard copy with visual confirmation — button text changes to "Copied!" briefly.
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(markdown)
		copy_btn.text = "Copied!"
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(copy_btn):
			copy_btn.text = "Copy to Clipboard"
	)


func _on_close_pressed() -> void:
	AudioManager.play_ui("button")
	queue_free()


func _on_reset_pressed() -> void:
	AudioManager.play_ui("button")
	BalanceConfig.reset_to_defaults()
	_populate_content()
