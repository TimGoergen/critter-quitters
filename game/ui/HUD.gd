## HUD.gd
## In-run overlay: left trap selector panel and right info/control panel,
## flanking the arena on both sides.  Landscape-only layout.
## Built procedurally — no scene file required.
##
## Left panel (LEFT_PANEL_W wide):  vertical stack of 4 trap rows.
##   Each row: static info panel (left, brand-colored) + draggable trap icon (right).
##   Press the icon and move to begin drag-and-drop placement.
## Right panel (RIGHT_PANEL_W wide, same width as left): wave, bug bucks, infestation bar,
##   INCOMING label, send-wave button, and a bottom row of two control buttons
##   (zoom, play/speed).  Exit and Restart live inside the Settings dialog.

extends CanvasLayer

const Trap           = preload("res://traps/Trap.gd")
const BoostUnit      = preload("res://boosts/BoostUnit.gd")
const UIFonts        = preload("res://ui/UIFonts.gd")
const ExperienceBar  = preload("res://ui/ExperienceBar.gd")
const LevelUpScreen  = preload("res://ui/LevelUpScreen.gd")

const GEAR_OUTLINE_SHADER = preload("res://assets/gear_outline.gdshader")

const COLOR_PANEL_BG    := Color(0.144, 0.144, 0.235, 0.88)
const COLOR_BAR_BG      := Color(0.20, 0.04, 0.04, 1.0)
const COLOR_BAR_FILL    := Color(0.85, 0.22, 0.22, 1.0)
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM    := Color(0.60, 0.60, 0.65, 1.0)
const COLOR_COUNTDOWN        := Color(1.00, 1.00, 1.00, 1.00)
const COLOR_COUNTDOWN_SHADOW := Color(0.00, 0.00, 0.00, 0.70)
const COLOR_INCOMING         := Color(1.00, 1.00, 1.00, 1.00)
const COLOR_INFESTED    := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_GOLD_OUTLINE := Color(0.85, 0.62, 0.00, 1.0)  # outline for bucks icon, bucks label, wave label
const COLOR_OVERLAY_BG  := Color(0.04, 0.02, 0.02, 0.82)

const COLOR_GREEN_NORMAL  := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_GREEN_HOVER   := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_GREEN_PRESSED := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_GREEN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

const COLOR_BTN_NORMAL  := Color(0.30, 0.30, 0.30, 1.0)
const COLOR_BTN_HOVER   := Color(0.38, 0.38, 0.38, 1.0)
const COLOR_BTN_PRESSED := Color(0.22, 0.22, 0.22, 1.0)
const COLOR_BTN_BORDER  := Color(0.68, 0.68, 0.68, 1.0)

const COLOR_GOLD_BG_NORMAL  := Color(0.72, 0.55, 0.04, 1.0)
const COLOR_GOLD_BG_HOVER   := Color(0.85, 0.66, 0.06, 1.0)
const COLOR_GOLD_BG_PRESSED := Color(0.55, 0.41, 0.02, 1.0)
const COLOR_GOLD_BORDER     := Color(1.00, 0.92, 0.35, 1.0)
const COLOR_GOLD_TEXT       := Color(0.08, 0.05, 0.00, 1.0)

const COLOR_HAZARD_YELLOW         := Color(1.00, 0.84, 0.00, 1.0)
const COLOR_BTN_SHADOW            := Color(0.00, 0.00, 0.00, 0.80)
const COLOR_UNAFFORDABLE_MODULATE := Color(0.58, 0.55, 0.52, 0.80)

const TRAP_BRAND: Array = [
	{"normal": Color(0.52, 0.20, 0.07), "hover": Color(0.64, 0.26, 0.09), "sel": Color(0.68, 0.28, 0.10), "badge": "PRO GRADE"},
	{"normal": Color(0.07, 0.25, 0.60), "hover": Color(0.10, 0.33, 0.76), "sel": Color(0.09, 0.30, 0.68), "badge": "+-1000V"},
	{"normal": Color(0.09, 0.38, 0.18), "hover": Color(0.12, 0.48, 0.24), "sel": Color(0.11, 0.44, 0.20), "badge": "SAFE*"},
	{"normal": Color(0.56, 0.27, 0.03), "hover": Color(0.70, 0.34, 0.04), "sel": Color(0.63, 0.30, 0.04), "badge": "STICKY"},
	{"normal": Color(0.52, 0.10, 0.38), "hover": Color(0.66, 0.14, 0.48), "sel": Color(0.60, 0.12, 0.44), "badge": "FLYAWAY"},
	{"normal": Color(0.25, 0.12, 0.32), "hover": Color(0.32, 0.16, 0.40), "sel": Color(0.29, 0.14, 0.37), "badge": "TOXIC"},
]

const TRAP_LABELS: Array = [
	["SNAP TRAP",          "$%d  *  SINCE 1952"],
	["ZAPPER",             "$%d  *  GUARANTEED"],
	["FOGGER",             "$%d  *  MOSTLY SAFE"],
	["GLUE BOARD",         "$%d  *  NO ESCAPE"],
	["FLY STRIP",          "$%d  *  AIRBORNE"],
	["BAIT STATION",       "$%d  *  SNEAKY"],
]

# Colors match BoostUnit._spawn_visual() for visual consistency.
const BOOST_BRAND: Array = [
	{"normal": Color(0.48, 0.27, 0.05), "hover": Color(0.60, 0.34, 0.07), "sel": Color(0.55, 0.30, 0.06), "badge": "+25% DMG"},
	{"normal": Color(0.05, 0.35, 0.45), "hover": Color(0.07, 0.44, 0.57), "sel": Color(0.06, 0.40, 0.51), "badge": "+20% RATE"},
	{"normal": Color(0.10, 0.40, 0.15), "hover": Color(0.13, 0.50, 0.19), "sel": Color(0.12, 0.46, 0.17), "badge": "INCOME"},
	{"normal": Color(0.22, 0.36, 0.46), "hover": Color(0.28, 0.45, 0.58), "sel": Color(0.25, 0.41, 0.52), "badge": "SHIELD"},
	{"normal": Color(0.45, 0.45, 0.05), "hover": Color(0.57, 0.57, 0.07), "sel": Color(0.51, 0.51, 0.06), "badge": "RESTORE"},
]

const BOOST_LABELS: Array = [
	["PHEROMONE",     "+25% DAMAGE"],
	["COMPRESSOR",    "+20% RATE"],
	["CASH REGISTER", "PASSIVE INCOME"],
	["AIR FRESHENER", "EXIT SHIELD"],
	["QUARANTINE",    "KILL RESTORE"],
]

# Panel dimensions — read by Arena.gd to compute the usable arena area.
const LEFT_PANEL_W:   float = 242.0
const RIGHT_PANEL_W:  float = 242.0
const ARENA_MARGIN_PX: float = 4.0

const MARGIN: float = 10.0             # inner padding for both panels
const SCREEN_EDGE_MARGIN: float = 24.0 # extra inset on the screen-edge side and top/bottom to clear rounded corners
const RIGHT_BTN_H: float = 52.0        # fixed height for all right-panel buttons
const INNER_BORDER_W: float = 2.0      # black separator line at the arena-facing edge of each panel
const ROW_H:          float = 56.0     # fixed height for every trap and boost selector row
const COLOR_SILVER_BORDER := Color(0.72, 0.72, 0.80, 1.0)
const SILVER_BORDER_W: float = 4.0    # thickness of the silver panel border lines
# Outer corner radius for each side panel — mimics the rounded edge of a phone display.
# Only the screen-edge corners (top-left/bottom-left for the left panel; top-right/bottom-right
# for the right panel) are rounded; the inner corners facing the arena remain sharp.
const PANEL_CORNER_RADIUS: int = 20

const PAUSE_BANNER_H:      float = 50.0
# How many px each side angles inward from the top edge to the bottom edge.
const PAUSE_BANNER_TAPER:  float = 25.0
# ~31% of the arena width (25% × 1.25); wide top edge, bottom edge is 2×TAPER narrower.
const PAUSE_BANNER_W:      float = (1280.0 - LEFT_PANEL_W - RIGHT_PANEL_W) * 0.3125
const COLOR_PAUSE_BANNER_BG    := Color(0.48, 0.04, 0.04, 0.92)  # deep crimson
const COLOR_INCOMING_FLASH     := Color(0.76, 0.10, 0.10, 0.97)  # brighter flash red

# Incoming wave banner — slides up from the bottom during the between-wave countdown.
# Reverse trapezoid: wide bottom edge flush with the screen, narrow top edge visible.
# Same width as the pause banner; TAPER matches so the slope is visually identical.
const INCOMING_BANNER_W:     float = PAUSE_BANNER_W    * 1.25
const INCOMING_BANNER_H:     float = PAUSE_BANNER_H    * 1.25
const INCOMING_BANNER_TAPER: float = PAUSE_BANNER_TAPER * 1.25

# Incoming wave banner — slides up from the bottom of the screen during the countdown.
var _incoming_banner:         Control = null
var _incoming_banner_shape:   Control = null
var _incoming_banner_tween:   Tween   = null
var _incoming_flash_tween:    Tween   = null
var _countdown_seconds_label: Label

var _send_wave_btn:           Button           # fast-forward button inside the send-wave panel
var _multiplier_btn:          Button           # small gold button cycling ×1 → ×5 → ×10
var _multiplier_label:        Label
var _send_wave_header_label:  Label            # "SEND 1 WAVE" / "SEND 5 WAVES" — updates with multiplier
var _call_early_label:        Label            # left-aligned "Call Early Reward" text
var _send_wave_reward_label:  Label            # right-aligned bucks amount
var _reward_bar_overlay:      HBoxContainer    # row containing both labels; hidden when no reward
var _max_countdown_seconds:   int = 0         # first seconds_remaining of the countdown; bar denominator
var _early_bonus_particles:   CPUParticles2D
var _wave_multiplier:        int = 1   # current send-wave multiplier; cycles 1 → 5 → 10 → 1
var _last_countdown_seconds: int = 0   # last received countdown value; used to refresh reward text when multiplier changes
var _current_wave_reward:    int = 0   # last value from early_send_reward_changed; drives the reward label

const SEND_WAVE_COOLDOWN_SEC: float = 1.0
var _send_wave_cooldown: float = 0.0   # seconds remaining before the send-wave button is usable again

var _play_pause_btn:  Button          # toggles paused ↔ playing
var _play_pause_icon: _PlayPauseIcon  # always shows triangle + bars; gold = what pressing will do
var _speed_btn:       Button          # cycles 1× → 2× → 3× → 1× (no pause)
var _speed_icon:      _PlaySpeedIcon  # shows 1–3 triangles + "Nx" label for current speed
var _last_play_speed: int = 1         # remembers speed when toggling pause
var _pause_banner:       Control = null
var _pause_banner_tween: Tween   = null
var _exit_btn:       Button
var _restart_btn:    Button
var _zoom_btn:       Button  # toggles overview ↔ zoomed-in
var _zoom_icon:      Control # procedural magnifying glass inside _zoom_btn

var _wave_label:        Label
var _bucks_label:       Label
var _infestation_fill:  Panel
var _infestation_label: Label

## Combined play/speed state: 0=paused, 1=play 1×, 2=play 2×, 3=play 3×.
## Replaces the old separate _is_paused and _speed_state fields.
var _play_speed_state: int  = 1
var _countdown_active: bool = false

var _music_slider: HSlider
var _sfx_slider:   HSlider

var _settings_btn:          Button  = null
var _settings_dialog:       Control = null
var _reset_confirm_overlay: Control = null

var _grid_lines_overview_toggle: CheckButton = null
var _grid_lines_zoomed_toggle:   CheckButton = null

var _settings_tab_btn:   Button  = null
var _upgrades_tab_btn:   Button  = null
var _settings_content:   Control = null
var _upgrades_content:   Control = null
var _active_settings_tab: String = "Settings"
# Saved when Settings opens so we can restore it on close rather than
# unconditionally unpausing — the user may have already paused manually.
var _was_paused_before_settings: bool = false

# One Control per trap type — the full-width row panel.
# Used by _refresh_trap_selector() to update affordability dimming.
var _icon_controls: Array[Control] = []

# Inner icon-area Control per trap type — the 3D preview widget inside each panel.
# Used by _start_drag() to find the icon's screen position for the floating icon tween.
var _icon_area_controls: Array[Control] = []

# Cost label per trap/boost type — updated by _refresh_trap_selector() whenever
# bug_bucks or placed counts change so the displayed cost stays current.
var _trap_cost_labels:  Array[Label] = []
var _boost_cost_labels: Array[Label] = []

# Parallel arrays for the boost selector tab.
var _boost_icon_controls:      Array[Control] = []
var _boost_icon_area_controls: Array[Control] = []

# Left-panel tab state.
var _trap_scroll:  Control = null
var _boost_scroll: Control = null
var _active_tab:   int             = 0     # 0 = Traps, 1 = Boosts
var _tab_btns:     Array[Button]   = []

# Cached reference to Arena (our parent node) for calling the drag placement API.
var _arena: Node = null

# Press-and-move detection for drag initiation.
var _hold_trap:  int = -1   # trap index currently pressed; -1 = none
var _hold_boost: int = -1   # boost index currently pressed; -1 = none

# Drag state — active while the user is dragging a trap or boost icon toward the arena.
var _drag_active:    bool    = false
var _drag_is_boost:  bool    = false
var _drag_type:      int     = -1
var _drag_cursor_pos: Vector2 = Vector2.ZERO

var _drag_overlay:   Control = null  # full-viewport pass-through container for the floating icon
var _drag_icon_ctrl: Control = null  # the floating trap image widget
var _drag_tween:     Tween   = null

# SubViewport render resolution for trap preview icons (panel and floating).
const DRAG_ICON_SIZE: float = 90.0
# Screen-space size of the floating drag icon (20% smaller than the panel icon).
const DRAG_ICON_DISPLAY: float = 45.0
# Offset from the cursor/finger to the placement-zone center sent to Arena.
# Above-and-left so the ghost preview is not hidden under the finger.
const DRAG_OFFSET: Vector2 = Vector2(-26.25, -83.125)
# Additional offset applied only to the floating icon's screen position, not to Arena.
# Shifts the opaque cursor image further up-left so the ghost preview behind it stays readable.
const DRAG_ICON_EXTRA_OFFSET: Vector2 = Vector2(-15.0, -15.0)



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	_arena = get_parent()
	_build_ui()
	GameState.bug_bucks_changed.connect(_on_bucks_changed)
	GameState.infestation_changed.connect(_on_infestation_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.wave_countdown_changed.connect(_on_wave_countdown_changed)
	GameState.early_wave_bonus_awarded.connect(_on_early_bonus_awarded)
	GameState.early_send_reward_changed.connect(_on_early_send_reward_changed)
	GameState.wave_spawn_progress_changed.connect(_on_wave_spawn_progress_changed)
	GameState.run_ended.connect(_on_run_ended)
	GameState.zoom_state_changed.connect(_on_zoom_state_changed)
	_on_bucks_changed(GameState.bug_bucks)
	_on_infestation_changed(GameState.infestation_level)
	_on_wave_changed(GameState.current_wave)
	get_viewport().size_changed.connect(_on_viewport_resized)



func _build_ui() -> void:
	_build_left_panel()
	_build_right_panel()
	_build_incoming_overlay()  # arena overlay; drawn above panels, below dialogs
	_build_panel_borders()     # drawn after panels so borders sit on top of panel content
	_build_pause_banner()      # drawn after borders so it slides over the top edge
	_build_experience_bar()    # overlaid on the arena zone, above all panel content
	_build_settings_dialog()   # must be last — full-screen overlay must draw above everything


# ---------------------------------------------------------------------------
# Left panel — trap selector
# ---------------------------------------------------------------------------

func _build_left_panel() -> void:
	var bg := ColorRect.new()
	bg.color        = COLOR_PANEL_BG
	bg.anchor_left  = 0.0
	bg.anchor_right = 0.0
	bg.anchor_top   = 0.0
	bg.anchor_bottom = 1.0
	bg.offset_right = LEFT_PANEL_W
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",  10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top",    MARGIN + SCREEN_EDGE_MARGIN)  # rounded corner
	margin.add_theme_constant_override("margin_bottom", MARGIN + SCREEN_EDGE_MARGIN)  # rounded corner
	bg.add_child(margin)

	# Black separator line at the inner (arena-facing) edge.
	var border := ColorRect.new()
	border.color         = Color.BLACK
	border.anchor_left   = 1.0
	border.anchor_right  = 1.0
	border.anchor_top    = 0.0
	border.anchor_bottom = 1.0
	border.offset_left   = -INNER_BORDER_W
	border.offset_right  = 0.0
	bg.add_child(border)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# --- Tab bar: TRAPS | BOOSTS ---
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 2)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_bar)

	for tab_label in ["TRAPS", "BOOSTS"]:
		var btn := Button.new()
		btn.text                  = tab_label
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, 48)
		btn.focus_mode            = Control.FOCUS_NONE
		btn.add_theme_font_override("font", UIFonts.primary_bold())
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tab_bar.add_child(btn)
		_tab_btns.append(btn)

	_tab_btns[0].pressed.connect(_on_trap_tab_pressed)
	_tab_btns[1].pressed.connect(_on_boost_tab_pressed)

	# Thin separator between tab bar and scroll content.
	var tab_sep := ColorRect.new()
	tab_sep.color               = Color(0.50, 0.52, 0.56, 0.80)
	tab_sep.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(tab_sep)

	# Small gap between separator and first row.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(gap)

	# --- Trap tab ---
	_trap_scroll = VBoxContainer.new()
	_trap_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_trap_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trap_scroll.add_theme_constant_override("separation", 0)
	vbox.add_child(_trap_scroll)

	var trap_vbox := VBoxContainer.new()
	trap_vbox.add_theme_constant_override("separation", 8)
	trap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trap_scroll.add_child(trap_vbox)

	for i in range(TRAP_LABELS.size()):
		var row_panel := _build_trap_row(trap_vbox, i)
		_icon_controls.append(row_panel)

	# All trap rows start hidden — TrapSelectionScreen sets the unlocked
	# types before the first wave and fires unlocked_traps_set to reveal them.
	_refresh_trap_visibility()
	GameState.unlocked_traps_set.connect(_on_unlocked_traps_set)

	# --- Boost tab (hidden until Boosts tab is selected) ---
	_boost_scroll = VBoxContainer.new()
	_boost_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_boost_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boost_scroll.add_theme_constant_override("separation", 0)
	_boost_scroll.visible              = false
	vbox.add_child(_boost_scroll)

	var boost_vbox := VBoxContainer.new()
	boost_vbox.add_theme_constant_override("separation", 8)
	boost_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boost_scroll.add_child(boost_vbox)

	for i in range(BOOST_LABELS.size()):
		var row_panel := _build_boost_row(boost_vbox, i)
		_boost_icon_controls.append(row_panel)

	# All boost rows start hidden — shown when unlocked_boosts_set fires.
	_refresh_boost_visibility()
	GameState.unlocked_boosts_set.connect(_on_unlocked_boosts_set)

	_update_tab_styles()


# ---------------------------------------------------------------------------
# Right panel — info and controls
# ---------------------------------------------------------------------------

## Returns the StyleBoxFlat used for the wave and bug bucks panel borders:
## transparent fill, 2px gold outline, 6px corner radius.
## extra_left adds to the base 8px left margin — used so the WAVE label
## sits as far from the border as the coin icon does in the bucks panel.
func _gold_panel_style(extra_left: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center           = false
	style.border_color          = COLOR_GOLD_OUTLINE
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left   = 8.0 + extra_left
	style.content_margin_right  = 8.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	return style


func _build_right_panel() -> void:
	var bg := ColorRect.new()
	bg.color         = COLOR_PANEL_BG
	bg.anchor_left   = 1.0
	bg.anchor_right  = 1.0
	bg.anchor_top    = 0.0
	bg.anchor_bottom = 1.0
	bg.offset_left   = -RIGHT_PANEL_W
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   SCREEN_EDGE_MARGIN)
	margin.add_theme_constant_override("margin_right",  SCREEN_EDGE_MARGIN)
	margin.add_theme_constant_override("margin_top",    MARGIN + SCREEN_EDGE_MARGIN)  # rounded corner
	margin.add_theme_constant_override("margin_bottom", int(MARGIN + SCREEN_EDGE_MARGIN))
	bg.add_child(margin)

	# Black separator line at the inner (arena-facing) edge.
	var border := ColorRect.new()
	border.color         = Color.BLACK
	border.anchor_left   = 0.0
	border.anchor_right  = 0.0
	border.anchor_top    = 0.0
	border.anchor_bottom = 1.0
	border.offset_left   = 0.0
	border.offset_right  = INNER_BORDER_W
	bg.add_child(border)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# --- Top row: Zoom button on the left, Settings button on the right.
	# Zoom is pinned to the top-left corner of the right panel, next to settings.
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	top_row.add_theme_constant_override("separation", 4)
	vbox.add_child(top_row)

	_zoom_btn = Button.new()
	_zoom_btn.text                    = ""
	_zoom_btn.custom_minimum_size     = Vector2(0, 60.0)
	_zoom_btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	_zoom_btn.size_flags_stretch_ratio = 3.0   # 60% of the row (3 out of 3+2 parts)
	_zoom_btn.size_flags_vertical     = Control.SIZE_SHRINK_CENTER
	_apply_gold_button_style(_zoom_btn)
	_zoom_btn.pressed.connect(_on_zoom_btn_pressed)
	top_row.add_child(_zoom_btn)

	_zoom_icon = _ZoomIcon.new()
	_zoom_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zoom_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_btn.add_child(_zoom_icon)

	_settings_btn = Button.new()
	_settings_btn.text                    = ""
	_settings_btn.custom_minimum_size     = Vector2(0, 60.0)
	_settings_btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	_settings_btn.size_flags_stretch_ratio = 2.0   # 40% of the row (2 out of 3+2 parts)
	_settings_btn.size_flags_vertical     = Control.SIZE_SHRINK_CENTER
	_apply_gear_button_style(_settings_btn)
	_settings_btn.pressed.connect(_on_settings_btn_pressed)
	top_row.add_child(_settings_btn)

	var gear_rect := TextureRect.new()
	gear_rect.texture      = load("res://assets/gear_icon.png") as Texture2D
	gear_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gear_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gear_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	gear_rect.offset_left   = 8.0
	gear_rect.offset_top    = 8.0
	gear_rect.offset_right  = -8.0
	gear_rect.offset_bottom = -8.0
	gear_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_settings_btn.add_child(gear_rect)

	# --- Wave row: "WAVE" left-aligned, number right-aligned ---
	# PanelContainer sizes itself from the HBoxContainer's minimum height,
	# draws the gold rounded border, and insets the content by the border width.
	var wave_panel := PanelContainer.new()
	wave_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_panel.add_theme_stylebox_override("panel", _gold_panel_style(6.0))
	vbox.add_child(wave_panel)

	var wave_row := HBoxContainer.new()
	wave_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_row.add_theme_constant_override("separation", 0)
	wave_panel.add_child(wave_row)

	var wave_text_lbl := Label.new()
	wave_text_lbl.text                  = "WAVE"
	wave_text_lbl.add_theme_font_size_override("font_size", 34)
	wave_text_lbl.add_theme_font_override("font", UIFonts.header())
	wave_text_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	wave_text_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	wave_text_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wave_text_lbl.size_flags_vertical   = Control.SIZE_SHRINK_END
	wave_row.add_child(wave_text_lbl)

	_wave_label = Label.new()
	_wave_label.text                  = "1"
	_wave_label.add_theme_font_size_override("font_size", 42)
	_wave_label.add_theme_font_override("font", UIFonts.header())
	_wave_label.add_theme_color_override("font_color", COLOR_TEXT)
	_wave_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_row.add_child(_wave_label)

	# --- Bug Bucks row ---
	var bucks_panel := PanelContainer.new()
	bucks_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bucks_panel.add_theme_stylebox_override("panel", _gold_panel_style())
	vbox.add_child(bucks_panel)

	var bucks_row := HBoxContainer.new()
	bucks_row.add_theme_constant_override("separation", 4)
	bucks_panel.add_child(bucks_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin_medium.png")
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.custom_minimum_size = Vector2(44, 44)
	coin_icon.size_flags_vertical = Control.SIZE_FILL
	bucks_row.add_child(coin_icon)

	_bucks_label = Label.new()
	_bucks_label.text = "0"
	_bucks_label.add_theme_font_size_override("font_size", 36)
	_bucks_label.add_theme_font_override("font", UIFonts.primary_bold())
	_bucks_label.add_theme_color_override("font_color", Color(1.00, 0.82, 0.18))
	_bucks_label.size_flags_vertical    = Control.SIZE_SHRINK_CENTER
	_bucks_label.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_bucks_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	bucks_row.add_child(_bucks_label)

	# --- Infestation section — single bar element ---
	# The fill grows from the left; icon and percentage are overlaid on top;
	# the border overlay is the last child so it always renders above the fill.
	# clip_children prevents any child from rendering outside this rectangle.
	var inf_container := Control.new()
	inf_container.custom_minimum_size   = Vector2(0, 62)
	inf_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inf_container.clip_children         = CanvasItem.CLIP_CHILDREN_ONLY
	vbox.add_child(inf_container)

	var inf_track := Panel.new()
	inf_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	inf_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inf_track_style := StyleBoxFlat.new()
	inf_track_style.bg_color = COLOR_BAR_BG
	inf_track_style.set_border_width_all(0)
	inf_track_style.set_corner_radius_all(6)
	inf_track.add_theme_stylebox_override("panel", inf_track_style)
	inf_container.add_child(inf_track)

	# Fill is inset by the border width (3px) on all sides so its rounded arcs are
	# concentric with the border's arcs — same center point, inner radius = outer − 3.
	# This prevents the antialiasing fringe from bleeding past the dark red outline.
	_infestation_fill               = Panel.new()
	_infestation_fill.anchor_bottom = 1.0
	_infestation_fill.offset_top    = 3.0
	_infestation_fill.offset_bottom = -3.0
	_infestation_fill.offset_left   = 3.0
	_infestation_fill.offset_right  = 3.0   # zero initial width; grows via _on_infestation_changed
	_infestation_fill.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_BAR_FILL
	fill_style.set_border_width_all(0)
	fill_style.set_corner_radius_all(3)   # inner radius = outer(6) − border_width(3)
	_infestation_fill.add_theme_stylebox_override("panel", fill_style)
	inf_container.add_child(_infestation_fill)

	# Overlay: icon on the left, percentage on the right, both centered vertically.
	# offset_left/right add a small inset so neither element touches the bar edge.
	var inf_overlay := HBoxContainer.new()
	inf_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	inf_overlay.offset_left  =  6.0
	inf_overlay.offset_right = -6.0
	inf_overlay.add_theme_constant_override("separation", 4)
	inf_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inf_container.add_child(inf_overlay)

	var inf_icon := TextureRect.new()
	inf_icon.texture             = load("res://assets/infestation_level.png")
	inf_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inf_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	inf_icon.custom_minimum_size = Vector2(44, 44)
	inf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inf_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	# Outline shader: samples 4 cardinal neighbours; draws black on transparent
	# pixels that border an opaque pixel, leaving the image itself unchanged.
	var outline_shader := Shader.new()
	outline_shader.code = """
shader_type canvas_item;
uniform float outline_px = 1.5;
void fragment() {
	vec2 step = outline_px / vec2(textureSize(TEXTURE, 0));
	vec4 col = texture(TEXTURE, UV);
	if (col.a < 0.5) {
		float n = texture(TEXTURE, UV + vec2( step.x,     0.0)).a
		        + texture(TEXTURE, UV + vec2(-step.x,     0.0)).a
		        + texture(TEXTURE, UV + vec2(    0.0,  step.y)).a
		        + texture(TEXTURE, UV + vec2(    0.0, -step.y)).a;
		if (n > 0.0) { COLOR = vec4(0.0, 0.0, 0.0, 1.0); return; }
	}
	COLOR = col;
}
"""
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = outline_shader
	inf_icon.material  = outline_mat
	inf_overlay.add_child(inf_icon)

	_infestation_label = Label.new()
	_infestation_label.text = "0%"
	_infestation_label.add_theme_font_size_override("font_size", 32)
	_infestation_label.add_theme_font_override("font", UIFonts.primary_bold())
	_infestation_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.86, 1.0))
	_infestation_label.add_theme_color_override("font_outline_color", Color(0.25, 0.25, 0.25, 1.0))
	_infestation_label.add_theme_constant_override("outline_size", 3)
	_infestation_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_infestation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_infestation_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_infestation_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	inf_overlay.add_child(_infestation_label)

	# Border overlay — last child so it renders above the fill and icon at all times.
	# draw_center=false keeps the interior transparent; only the outline is drawn.
	var inf_border := Panel.new()
	inf_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	inf_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inf_border_style := StyleBoxFlat.new()
	inf_border_style.draw_center  = false
	inf_border_style.border_color = Color(0.50, 0.04, 0.04, 1.0)
	inf_border_style.set_border_width_all(3)
	inf_border_style.set_corner_radius_all(6)
	inf_border.add_theme_stylebox_override("panel", inf_border_style)
	inf_container.add_child(inf_border)

	# --- Send Wave panel — gray panel with silver border, three visual thirds:
	# "SEND WAVE" header, ">>" + multiplier buttons, and a green reward bar.
	var send_spacer_top := Control.new()
	send_spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(send_spacer_top)

	var send_panel := Panel.new()
	send_panel.custom_minimum_size   = Vector2(0, 155)
	send_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_panel.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color           = COLOR_BTN_NORMAL
	panel_style.border_color       = COLOR_SILVER_BORDER
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(5)
	send_panel.add_theme_stylebox_override("panel", panel_style)
	vbox.add_child(send_panel)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner_vbox.add_theme_constant_override("separation", 0)
	send_panel.add_child(inner_vbox)

	# Top — "SEND WAVE" header. SIZE_SHRINK_CENTER so it takes only the height
	# the text needs; the button row below hugs up close rather than floating
	# in the middle of a third of the panel.
	var top_margin := MarginContainer.new()
	top_margin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_margin.add_theme_constant_override("margin_left",   12)
	top_margin.add_theme_constant_override("margin_right",  12)
	top_margin.add_theme_constant_override("margin_top",    10)
	top_margin.add_theme_constant_override("margin_bottom", 4)
	inner_vbox.add_child(top_margin)

	_send_wave_header_label = Label.new()
	_send_wave_header_label.text                 = "SEND 1 WAVE"
	_send_wave_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_send_wave_header_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_send_wave_header_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_send_wave_header_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_header_label.add_theme_font_size_override("font_size", 22)
	_send_wave_header_label.add_theme_color_override("font_color", COLOR_TEXT)
	top_margin.add_child(_send_wave_header_label)

	# Middle section — >> send button on the left, ×N multiplier toggle on the right.
	# Both buttons share the same fixed height (50px) so their vertical centers are
	# guaranteed identical regardless of the row's total allocated height.
	# Both labels use the same Bebas Neue font + embolden so font-metric offsets
	# from VERTICAL_ALIGNMENT_CENTER are identical, keeping text visually aligned.
	var mid_margin := MarginContainer.new()
	mid_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_margin.add_theme_constant_override("margin_left",   12)
	mid_margin.add_theme_constant_override("margin_right",  12)
	mid_margin.add_theme_constant_override("margin_top",    4)
	mid_margin.add_theme_constant_override("margin_bottom", 4)
	inner_vbox.add_child(mid_margin)

	var mid_hbox := HBoxContainer.new()
	mid_hbox.add_theme_constant_override("separation", 8)
	mid_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_hbox.alignment             = BoxContainer.ALIGNMENT_CENTER
	mid_margin.add_child(mid_hbox)

	# Lightly-emboldened Bebas Neue — used for ALL text in this section so that
	# VERTICAL_ALIGNMENT_CENTER produces the same visual offset in every label.
	# Embolden kept low (0.4) so ×5 and ×10 remain legible at small sizes.
	var bold_font := FontVariation.new()
	bold_font.base_font          = UIFonts.header()
	bold_font.variation_embolden = 0.8

	# Send-wave button — dark background with gold border, same 50px height as
	# the multiplier pill. Icon is a TextureRect child so it scales with the button.
	_send_wave_btn = Button.new()
	_send_wave_btn.text                  = ""
	_send_wave_btn.custom_minimum_size   = Vector2(0, 50)
	_send_wave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_wave_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_apply_ff_button_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	mid_hbox.add_child(_send_wave_btn)

	var ff_texture := TextureRect.new()
	ff_texture.texture      = load("res://assets/SendWave.svg")
	# EXPAND_IGNORE_SIZE lets the rect be sized by anchors rather than by the
	# SVG's natural pixel dimensions; STRETCH_KEEP_ASPECT_CENTERED then draws
	# the image centered within whatever rect the button gives us.
	ff_texture.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	ff_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ff_texture.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	# Fill full width; vertically centered at 56% of button height (22% inset top and bottom).
	# 56% = 70% target × 0.8 (user-requested 20% reduction).
	ff_texture.anchor_left   = 0.0
	ff_texture.anchor_right  = 1.0
	ff_texture.anchor_top    = 0.22
	ff_texture.anchor_bottom = 0.78
	_send_wave_btn.add_child(ff_texture)

	# Multiplier button — gold filled, true square (50×50) matching the >> button height.
	_multiplier_btn = Button.new()
	_multiplier_btn.text                  = ""
	_multiplier_btn.custom_minimum_size   = Vector2(50, 50)
	_multiplier_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_multiplier_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_apply_toggle_btn_style(_multiplier_btn)
	_multiplier_btn.pressed.connect(_on_multiplier_btn_pressed)
	mid_hbox.add_child(_multiplier_btn)

	# HBoxContainer fills the button via PRESET_FULL_RECT; labels use
	# SIZE_EXPAND_FILL vertical + VERTICAL_ALIGNMENT_CENTER so Godot's font-metric
	# centering math handles the positioning rather than geometric assumptions.
	var mult_hbox := HBoxContainer.new()
	# Same 4px downward shift as ff_label — identical font so identical bias.
	mult_hbox.anchor_left   = 0.0
	mult_hbox.anchor_right  = 1.0
	mult_hbox.anchor_top    = 0.0
	mult_hbox.anchor_bottom = 1.0
	mult_hbox.offset_top    = 4
	mult_hbox.offset_bottom = 4
	mult_hbox.add_theme_constant_override("separation", 0)
	mult_hbox.alignment   = BoxContainer.ALIGNMENT_CENTER
	mult_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multiplier_btn.add_child(mult_hbox)

	var mult_x_lbl := Label.new()
	mult_x_lbl.text                 = "×"
	mult_x_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	mult_x_lbl.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	mult_x_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	mult_x_lbl.add_theme_font_override("font", bold_font)
	mult_x_lbl.add_theme_font_size_override("font_size", 38)
	mult_x_lbl.add_theme_color_override("font_color",        COLOR_GOLD_TEXT)
	mult_x_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	mult_hbox.add_child(mult_x_lbl)

	_multiplier_label = Label.new()
	_multiplier_label.text                = "1"
	_multiplier_label.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	_multiplier_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_multiplier_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_multiplier_label.add_theme_font_override("font", bold_font)
	_multiplier_label.add_theme_font_size_override("font_size", 28)
	_multiplier_label.add_theme_color_override("font_color",        COLOR_GOLD_TEXT)
	_multiplier_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	mult_hbox.add_child(_multiplier_label)

	# Bottom — "Call Early Reward" row: left label + right-aligned amount.
	# Hidden until a reward is available; no bar, text only.
	var bar_margin := MarginContainer.new()
	bar_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_margin.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	bar_margin.add_theme_constant_override("margin_left",   12)
	bar_margin.add_theme_constant_override("margin_right",  12)
	bar_margin.add_theme_constant_override("margin_top",    4)
	bar_margin.add_theme_constant_override("margin_bottom", 10)
	inner_vbox.add_child(bar_margin)

	_reward_bar_overlay = HBoxContainer.new()
	_reward_bar_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_bar_overlay.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_reward_bar_overlay.modulate.a            = 0.0   # hidden until a reward is available
	bar_margin.add_child(_reward_bar_overlay)

	_call_early_label = Label.new()
	_call_early_label.text                  = "Call Early Reward"
	_call_early_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_call_early_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_call_early_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_call_early_label.add_theme_font_override("font", UIFonts.primary_bold())
	_call_early_label.add_theme_font_size_override("font_size", 15)
	_call_early_label.add_theme_color_override("font_color", COLOR_TEXT)
	_reward_bar_overlay.add_child(_call_early_label)

	var reward_coin := TextureRect.new()
	reward_coin.texture             = load("res://assets/bug_buck_coin_small.png") as Texture2D
	reward_coin.custom_minimum_size = Vector2(20, 20)
	reward_coin.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	reward_coin.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reward_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward_coin.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_reward_bar_overlay.add_child(reward_coin)

	_send_wave_reward_label = Label.new()
	_send_wave_reward_label.text                  = ""
	_send_wave_reward_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_send_wave_reward_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_send_wave_reward_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_reward_label.add_theme_font_size_override("font_size", 17)
	_send_wave_reward_label.add_theme_color_override("font_color", COLOR_GOLD_BORDER)
	_reward_bar_overlay.add_child(_send_wave_reward_label)

	_build_early_bonus_particles()

	var send_spacer_bottom := Control.new()
	send_spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(send_spacer_bottom)

	# --- Bottom 2-button row: Play/Pause | Speed ---
	# Both buttons expand to fill equal widths.
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 4)
	bottom_row.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(bottom_row)

	# Play/pause button — shows pause bars when playing (will pause), play arrow when paused.
	_play_pause_btn = Button.new()
	_play_pause_btn.text = ""
	_apply_gold_button_style(_play_pause_btn)
	_play_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_pause_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_play_pause_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_play_pause_btn.pressed.connect(_on_play_pause_btn_pressed)
	bottom_row.add_child(_play_pause_btn)

	_play_pause_icon = _PlayPauseIcon.new()
	_play_pause_icon.play_speed_state = _play_speed_state   # 1 = playing at startup
	_play_pause_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play_pause_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_pause_btn.add_child(_play_pause_icon)

	# Speed button — cycles 1× → 2× → 3× → 1× (pause is handled by the separate button above).
	_speed_btn = Button.new()
	_speed_btn.text = ""
	_apply_gold_button_style(_speed_btn)
	_speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_speed_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_speed_btn.pressed.connect(_on_speed_btn_pressed)
	bottom_row.add_child(_speed_btn)

	_speed_icon = _PlaySpeedIcon.new()
	_speed_icon.play_speed_state = _play_speed_state
	_speed_icon.speed_text       = "1x"
	_speed_icon.font_ref         = UIFonts.primary_bold()
	_speed_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_btn.add_child(_speed_icon)


# ---------------------------------------------------------------------------
# INCOMING wave banner
# ---------------------------------------------------------------------------

func _build_incoming_overlay() -> void:
	# Reverse-trapezoid banner anchored to the bottom of the viewport.
	# Wide bottom edge overlaps the screen edge; narrow top edge is the visible face.
	# Starts below the screen and tweens upward when the countdown begins.
	_incoming_banner = Control.new()
	_incoming_banner.anchor_left   = 0.5
	_incoming_banner.anchor_right  = 0.5
	_incoming_banner.anchor_top    = 1.0
	_incoming_banner.anchor_bottom = 1.0
	_incoming_banner.offset_left   = -INCOMING_BANNER_W / 2.0
	_incoming_banner.offset_right  =  INCOMING_BANNER_W / 2.0
	# Hidden below the screen edge until a countdown starts.
	_incoming_banner.offset_top    = 0.0
	_incoming_banner.offset_bottom = INCOMING_BANNER_H
	_incoming_banner.process_mode  = Node.PROCESS_MODE_ALWAYS
	_incoming_banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_incoming_banner)

	var shape := _IncomingBannerShape.new()
	shape.taper        = INCOMING_BANNER_TAPER
	shape.border_w     = SILVER_BORDER_W
	shape.color_border = COLOR_SILVER_BORDER
	shape.color_fill   = COLOR_PAUSE_BANNER_BG
	shape.set_anchors_preset(Control.PRESET_FULL_RECT)
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_incoming_banner_shape = shape
	_incoming_banner.add_child(shape)

	# Single centred label — "INCOMING  3..." — so both words are centred as a unit.
	_countdown_seconds_label = Label.new()
	_countdown_seconds_label.text                 = ""
	_countdown_seconds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_seconds_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_seconds_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_countdown_seconds_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	var incoming_font_var := FontVariation.new()
	incoming_font_var.base_font    = UIFonts.header()
	incoming_font_var.spacing_glyph = 2   # letter spacing; LabelSettings has no such property
	var incoming_lbl_settings := LabelSettings.new()
	incoming_lbl_settings.font       = incoming_font_var
	incoming_lbl_settings.font_size  = 41   # 36 × 1.15
	incoming_lbl_settings.font_color = COLOR_TEXT
	_countdown_seconds_label.label_settings = incoming_lbl_settings
	_incoming_banner.add_child(_countdown_seconds_label)


## Animates the incoming wave banner into or out of view from the bottom edge.
## Pass true to slide it up (countdown active), false to slide it back down.
func _show_incoming_banner(visible_state: bool) -> void:
	if _incoming_banner_tween:
		_incoming_banner_tween.kill()
	_incoming_banner_tween = create_tween()
	_incoming_banner_tween.set_ease(Tween.EASE_OUT)
	_incoming_banner_tween.set_trans(Tween.TRANS_CUBIC)
	# Visible: top = -H, bottom = 0 (banner sits above screen edge).
	# Hidden: top = 0, bottom = H (banner is pushed below the screen edge).
	var target_top:    float = -INCOMING_BANNER_H if visible_state else 0.0
	var target_bottom: float = 0.0               if visible_state else INCOMING_BANNER_H
	_incoming_banner_tween.tween_property(_incoming_banner, "offset_top",    target_top,    0.22)
	_incoming_banner_tween.parallel().tween_property(_incoming_banner, "offset_bottom", target_bottom, 0.22)

	# Flash animation — pulse between base crimson and a brighter red while visible.
	if _incoming_flash_tween:
		_incoming_flash_tween.kill()
	if visible_state and is_instance_valid(_incoming_banner_shape):
		_incoming_flash_tween = create_tween()
		_incoming_flash_tween.set_loops()
		_incoming_flash_tween.set_ease(Tween.EASE_IN_OUT)
		_incoming_flash_tween.set_trans(Tween.TRANS_SINE)
		_incoming_flash_tween.tween_method(
			func(c: Color) -> void:
				_incoming_banner_shape.color_fill = c
				_incoming_banner_shape.queue_redraw(),
			COLOR_PAUSE_BANNER_BG, COLOR_INCOMING_FLASH, 0.65)
		_incoming_flash_tween.tween_method(
			func(c: Color) -> void:
				_incoming_banner_shape.color_fill = c
				_incoming_banner_shape.queue_redraw(),
			COLOR_INCOMING_FLASH, COLOR_PAUSE_BANNER_BG, 0.65)
	elif is_instance_valid(_incoming_banner_shape):
		# Reset to base color when the banner hides.
		_incoming_banner_shape.color_fill = COLOR_PAUSE_BANNER_BG
		_incoming_banner_shape.queue_redraw()


# ---------------------------------------------------------------------------
# Panel borders
# ---------------------------------------------------------------------------

## Draws the silver outline around the left panel, the arena center edges, and the right panel.
## Called last in _build_ui() so borders render on top of all panel content.
##
## Each side panel gets a single Panel + StyleBoxFlat that draws the full outline
## (all four sides) in one pass.  The two outer corners of each panel — the ones
## that sit at the physical edge of the phone display — use PANEL_CORNER_RADIUS so
## the silver line follows the device's rounded bezel.  The inner corners (facing the
## arena) are left at radius 0 so the outline meets the arena lines cleanly.
## draw_center = false keeps the panel interior transparent; only the border strip
## is visible over the existing dark panel background.
func _build_panel_borders() -> void:
	# --- Left panel outline ---
	# Rounded: top-left, bottom-left.   Sharp: top-right, bottom-right (arena edge).
	var left_border := Panel.new()
	left_border.anchor_left   = 0.0
	left_border.anchor_right  = 0.0
	left_border.anchor_top    = 0.0
	left_border.anchor_bottom = 1.0
	left_border.offset_right  = LEFT_PANEL_W
	left_border.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var left_style := StyleBoxFlat.new()
	left_style.draw_center                = false
	left_style.border_color               = COLOR_SILVER_BORDER
	left_style.set_border_width_all(int(SILVER_BORDER_W))
	left_style.corner_radius_top_left     = PANEL_CORNER_RADIUS
	left_style.corner_radius_bottom_left  = PANEL_CORNER_RADIUS
	left_style.corner_radius_top_right    = 0
	left_style.corner_radius_bottom_right = 0
	left_border.add_theme_stylebox_override("panel", left_style)
	add_child(left_border)

	# --- Right panel outline ---
	# Rounded: top-right, bottom-right.   Sharp: top-left, bottom-left (arena edge).
	var right_border := Panel.new()
	right_border.anchor_left   = 1.0
	right_border.anchor_right  = 1.0
	right_border.anchor_top    = 0.0
	right_border.anchor_bottom = 1.0
	right_border.offset_left   = -RIGHT_PANEL_W
	right_border.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var right_style := StyleBoxFlat.new()
	right_style.draw_center                = false
	right_style.border_color               = COLOR_SILVER_BORDER
	right_style.set_border_width_all(int(SILVER_BORDER_W))
	right_style.corner_radius_top_right    = PANEL_CORNER_RADIUS
	right_style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	right_style.corner_radius_top_left     = 0
	right_style.corner_radius_bottom_left  = 0
	right_border.add_theme_stylebox_override("panel", right_style)
	add_child(right_border)

	# --- Arena center edges ---
	# The StyleBoxFlats above already draw the top and bottom border strips across
	# their respective panels.  These two ColorRect lines bridge the gap across the
	# arena zone to complete the top and bottom edges of the full-screen outline.
	_add_border_line(0.0, 0.0, 1.0, 0.0,  LEFT_PANEL_W,  0.0,  -RIGHT_PANEL_W,  SILVER_BORDER_W)
	_add_border_line(0.0, 1.0, 1.0, 1.0,  LEFT_PANEL_W,  -SILVER_BORDER_W,  -RIGHT_PANEL_W,  0.0)


## Trapezoidal tab that slides down from the top border when the game is paused.
## The top edge is PAUSE_BANNER_W wide and sits flush with the existing top
## silver border; the sides angle inward by PAUSE_BANNER_TAPER px on each side
## so the bottom edge is narrower.  Starts above the viewport and tweens down.
func _build_pause_banner() -> void:
	_pause_banner = Control.new()
	# Centered horizontally — arena center equals viewport center because
	# both side panels are the same width.
	_pause_banner.anchor_left   = 0.5
	_pause_banner.anchor_right  = 0.5
	_pause_banner.anchor_top    = 0.0
	_pause_banner.anchor_bottom = 0.0
	_pause_banner.offset_left   = -PAUSE_BANNER_W / 2.0
	_pause_banner.offset_right  = PAUSE_BANNER_W / 2.0
	# Hidden above the screen until the first pause.
	_pause_banner.offset_top    = -PAUSE_BANNER_H
	_pause_banner.offset_bottom = 0.0
	_pause_banner.process_mode  = Node.PROCESS_MODE_ALWAYS
	_pause_banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_banner)

	# Trapezoidal shape — silver outline + dark fill drawn in _draw().
	var shape := _PauseBannerShape.new()
	shape.taper        = PAUSE_BANNER_TAPER
	shape.border_w     = SILVER_BORDER_W   # match the panel outline thickness exactly
	shape.color_border = COLOR_SILVER_BORDER
	shape.color_fill   = COLOR_PAUSE_BANNER_BG
	shape.set_anchors_preset(Control.PRESET_FULL_RECT)
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_banner.add_child(shape)

	var label := Label.new()
	label.text                 = "Paused"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	var pause_font_var := FontVariation.new()
	pause_font_var.base_font     = UIFonts.header()
	pause_font_var.spacing_glyph = 2   # letter spacing; LabelSettings has no such property
	var pause_lbl_settings := LabelSettings.new()
	pause_lbl_settings.font       = pause_font_var
	pause_lbl_settings.font_size  = 32   # 28 × 1.15
	pause_lbl_settings.font_color = COLOR_TEXT
	label.label_settings = pause_lbl_settings
	_pause_banner.add_child(label)


## Builds the experience bar and pins it to the very top of the arena zone.
## offset_top = 0 so the bar's own 4px silver border shares pixels with the
## arena's top silver border — they are the same colour and merge visually.
func _build_experience_bar() -> void:
	var bar := ExperienceBar.new()
	bar.anchor_left   = 0.0
	bar.anchor_right  = 1.0
	bar.anchor_top    = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left   = LEFT_PANEL_W
	bar.offset_right  = -RIGHT_PANEL_W
	bar.offset_top    = 0.0                    # was SILVER_BORDER_W — now overlaps the top outline
	bar.offset_bottom = ExperienceBar.PANEL_H  # was SILVER_BORDER_W + PANEL_H
	add_child(bar)


## Animates the pause banner into or out of view.
## Pass true to slide it down (paused), false to slide it back up (unpaused).
## When visible the banner sits immediately below the experience bar, not at
## the very top of the screen, so the XP bar remains readable while paused.
func _show_pause_banner(visible_state: bool) -> void:
	if _pause_banner_tween:
		_pause_banner_tween.kill()
	_pause_banner_tween = create_tween()
	_pause_banner_tween.set_ease(Tween.EASE_OUT)
	_pause_banner_tween.set_trans(Tween.TRANS_CUBIC)
	# Visible position: top edge = bottom edge of the experience bar.
	# The bar now starts at offset_top=0, so its bottom is simply PANEL_H.
	var exp_bar_bottom: float = ExperienceBar.PANEL_H
	var target_top:    float = exp_bar_bottom                       if visible_state else -PAUSE_BANNER_H
	var target_bottom: float = exp_bar_bottom + PAUSE_BANNER_H     if visible_state else 0.0
	_pause_banner_tween.tween_property(_pause_banner, "offset_top",    target_top,    0.22)
	_pause_banner_tween.parallel().tween_property(_pause_banner, "offset_bottom", target_bottom, 0.22)


func _add_border_line(al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, or_: float, ob: float) -> void:
	var line          := ColorRect.new()
	line.color         = COLOR_SILVER_BORDER
	line.anchor_left   = al;  line.anchor_top    = at
	line.anchor_right  = ar;  line.anchor_bottom = ab
	line.offset_left   = ol;  line.offset_top    = ot
	line.offset_right  = or_; line.offset_bottom = ob
	add_child(line)


# ---------------------------------------------------------------------------
# Settings dialog
# ---------------------------------------------------------------------------

## Builds the full-screen settings overlay.  Hidden by default; shown when the
## user taps the gear button.  The overlay fills the entire virtual viewport
## so it can give every setting generous touch targets and clear organization.
##
## Layout:
##   Header (60px):  title + Close button
##   ─────────────────────────────────────────
##   Left half (640px) │ Right half (640px)
##   AUDIO             │ DISPLAY
##   Music slider      │ Grid lines overview
##   SFX slider        │ Grid lines zoomed
##   ─────────────────────────────────────────
##   Footer (80px):  Reset Progress + Dev Mode  │  EXIT + RESTART
func _build_settings_dialog() -> void:
	_settings_dialog = Control.new()
	_settings_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_dialog.visible      = false
	_settings_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_dialog)

	const HEADER_H:     float = 60.0
	const FOOTER_H:     float = 80.0
	const COL_DIV_X:    float = 640.0
	const PADDING:      float = 32.0
	const DIVIDER_COL := Color(0.22, 0.22, 0.30, 1.0)

	# Full-screen panel — no dim, no floating box; fills the entire viewport.
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sty := StyleBoxFlat.new()
	panel_sty.bg_color = Color(0.06, 0.08, 0.14, 1.0)
	panel_sty.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", panel_sty)
	_settings_dialog.add_child(panel)

	# ── Header ──────────────────────────────────────────────────────────────
	var title_lbl := Label.new()
	title_lbl.text               = "SETTINGS"
	title_lbl.position           = Vector2(PADDING, 0.0)
	title_lbl.size               = Vector2(600.0, HEADER_H)
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", UIFonts.header())
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	title_lbl.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title_lbl)

	# Close button — right-aligned in header, same green style as PermanentUpgradeScreen.
	var close_btn := Button.new()
	close_btn.text          = "Close"
	close_btn.focus_mode    = Control.FOCUS_NONE
	close_btn.anchor_left   = 1.0;  close_btn.anchor_right  = 1.0
	close_btn.anchor_top    = 0.0;  close_btn.anchor_bottom = 0.0
	close_btn.offset_left   = -(PADDING + 130.0)
	close_btn.offset_right  = -PADDING
	close_btn.offset_top    = (HEADER_H - 44.0) * 0.5
	close_btn.offset_bottom = HEADER_H - (HEADER_H - 44.0) * 0.5
	close_btn.add_theme_font_override("font", UIFonts.primary_bold())
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  Color(0.04, 0.25, 0.00, 1.0)],
		["hover",   Color(0.07, 0.33, 0.01, 1.0)],
		["pressed", Color(0.02, 0.16, 0.00, 1.0)],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = Color(0.22, 0.60, 0.04, 1.0)
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8.0)
		close_btn.add_theme_stylebox_override(state[0], box)
	close_btn.pressed.connect(_on_settings_close_pressed)
	panel.add_child(close_btn)

	const TAB_H: float = 44.0

	# ── Structural dividers ─────────────────────────────────────────────────
	# Horizontal below header.
	var hdr_div := ColorRect.new()
	hdr_div.color        = DIVIDER_COL
	hdr_div.position     = Vector2(0.0, HEADER_H)
	hdr_div.size         = Vector2(1280.0, 1.0)
	hdr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hdr_div)

	# ── Tab bar ─────────────────────────────────────────────────────────────
	_settings_tab_btn          = _make_settings_tab_button("SETTINGS")
	_settings_tab_btn.position = Vector2(0.0, HEADER_H + 1.0)
	_settings_tab_btn.size     = Vector2(640.0, TAB_H)
	_settings_tab_btn.pressed.connect(func() -> void: _switch_settings_tab("Settings"))
	panel.add_child(_settings_tab_btn)

	var tab_v_div := ColorRect.new()
	tab_v_div.color        = DIVIDER_COL
	tab_v_div.position     = Vector2(639.5, HEADER_H + 1.0 + 6.0)
	tab_v_div.size         = Vector2(1.0, TAB_H - 12.0)
	tab_v_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tab_v_div)

	_upgrades_tab_btn          = _make_settings_tab_button("UPGRADES")
	_upgrades_tab_btn.position = Vector2(640.0, HEADER_H + 1.0)
	_upgrades_tab_btn.size     = Vector2(640.0, TAB_H)
	_upgrades_tab_btn.pressed.connect(func() -> void: _switch_settings_tab("Upgrades"))
	panel.add_child(_upgrades_tab_btn)

	var tab_div := ColorRect.new()
	tab_div.color        = DIVIDER_COL
	tab_div.position     = Vector2(0.0, HEADER_H + 1.0 + TAB_H)
	tab_div.size         = Vector2(1280.0, 1.0)
	tab_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tab_div)

	_apply_settings_tab_style(_settings_tab_btn, true)
	_apply_settings_tab_style(_upgrades_tab_btn, false)

	# ── Content area geometry ────────────────────────────────────────────────
	var main_y := HEADER_H + 1.0 + TAB_H + 1.0
	var main_h := 600.0 - main_y - FOOTER_H - 1.0

	# Horizontal above footer.
	var ftr_div := ColorRect.new()
	ftr_div.color        = DIVIDER_COL
	ftr_div.position     = Vector2(0.0, 600.0 - FOOTER_H - 1.0)
	ftr_div.size         = Vector2(1280.0, 1.0)
	ftr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(ftr_div)

	# ── SETTINGS content — two-column audio + display layout ─────────────────
	_settings_content              = Control.new()
	_settings_content.position     = Vector2(0.0, main_y)
	_settings_content.size         = Vector2(1280.0, main_h)
	_settings_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_settings_content)

	# Vertical divider between the two columns.
	var col_div := ColorRect.new()
	col_div.color        = DIVIDER_COL
	col_div.position     = Vector2(COL_DIV_X, 0.0)
	col_div.size         = Vector2(1.0, main_h)
	col_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_content.add_child(col_div)

	var left_col := VBoxContainer.new()
	left_col.position = Vector2(0.0, 0.0)
	left_col.size     = Vector2(COL_DIV_X, main_h)
	left_col.add_theme_constant_override("separation", 0)
	_settings_content.add_child(left_col)

	_add_settings_section_strip(left_col, "AUDIO")

	var left_pad := MarginContainer.new()
	left_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_pad.add_theme_constant_override("margin_left",   int(PADDING))
	left_pad.add_theme_constant_override("margin_right",  int(PADDING))
	left_pad.add_theme_constant_override("margin_top",    20)
	left_pad.add_theme_constant_override("margin_bottom", 20)
	left_col.add_child(left_pad)

	var left_inner := VBoxContainer.new()
	left_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_inner.add_theme_constant_override("separation", 16)
	left_pad.add_child(left_inner)

	_music_slider = _build_volume_row(left_inner, "MUSIC")
	_sfx_slider   = _build_volume_row(left_inner, "SFX")

	var right_col := VBoxContainer.new()
	right_col.position = Vector2(COL_DIV_X + 1.0, 0.0)
	right_col.size     = Vector2(1280.0 - COL_DIV_X - 1.0, main_h)
	right_col.add_theme_constant_override("separation", 0)
	_settings_content.add_child(right_col)

	_add_settings_section_strip(right_col, "DISPLAY")

	var right_pad := MarginContainer.new()
	right_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pad.add_theme_constant_override("margin_left",   int(PADDING))
	right_pad.add_theme_constant_override("margin_right",  int(PADDING))
	right_pad.add_theme_constant_override("margin_top",    20)
	right_pad.add_theme_constant_override("margin_bottom", 20)
	right_col.add_child(right_pad)

	var right_inner := VBoxContainer.new()
	right_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_inner.add_theme_constant_override("separation", 16)
	right_pad.add_child(right_inner)

	_grid_lines_overview_toggle = _build_toggle_row(right_inner, "Grid lines — overview")
	_grid_lines_zoomed_toggle   = _build_toggle_row(right_inner, "Grid lines — zoomed in")

	# ── UPGRADES content — campaign buff summary; rebuilt each time tab opens ──
	_upgrades_content = ScrollContainer.new()
	_upgrades_content.position               = Vector2(0.0, main_y)
	_upgrades_content.size                   = Vector2(1280.0, main_h)
	_upgrades_content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_upgrades_content.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_upgrades_content.visible                = false
	panel.add_child(_upgrades_content)

	# ── Footer ───────────────────────────────────────────────────────────────
	var footer_y   := 600.0 - FOOTER_H
	var btn_h      := 50.0
	var btn_y      := footer_y + (FOOTER_H - btn_h) * 0.5

	# Left half of footer: Reset Progress + Dev Mode (DATA actions).
	var left_btns := HBoxContainer.new()
	left_btns.position = Vector2(PADDING, btn_y)
	left_btns.size     = Vector2(COL_DIV_X - PADDING * 2.0, btn_h)
	left_btns.add_theme_constant_override("separation", 12)
	panel.add_child(left_btns)

	var reset_btn := Button.new()
	reset_btn.text                  = "Reset Progress"
	reset_btn.focus_mode            = Control.FOCUS_NONE
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.add_theme_font_override("font", UIFonts.primary_bold())
	reset_btn.add_theme_font_size_override("font_size", 20)
	reset_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.90, 1.0))
	reset_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  Color(0.30, 0.03, 0.03, 1.0)],
		["hover",   Color(0.42, 0.05, 0.05, 1.0)],
		["pressed", Color(0.20, 0.02, 0.02, 1.0)],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = Color(0.75, 0.18, 0.18, 1.0)
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8.0)
		reset_btn.add_theme_stylebox_override(state[0], box)
	reset_btn.pressed.connect(_on_reset_progress_pressed)
	left_btns.add_child(reset_btn)

	# Dev mode button — silver theme; text reflects current state.
	var dev_btn := Button.new()
	dev_btn.text                  = "Exit DEVmode" if GameState.dev_mode else "DEVmode"
	dev_btn.focus_mode            = Control.FOCUS_NONE
	dev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_btn.add_theme_font_override("font", UIFonts.primary_bold())
	dev_btn.add_theme_font_size_override("font_size", 20)
	dev_btn.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95, 1.0))
	dev_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for dev_state: Array in [
		["normal",  Color(0.30, 0.30, 0.32, 1.0)],
		["hover",   Color(0.40, 0.40, 0.42, 1.0)],
		["pressed", Color(0.22, 0.22, 0.24, 1.0)],
	]:
		var dev_box := StyleBoxFlat.new()
		dev_box.bg_color     = dev_state[1]
		dev_box.border_color = Color(0.60, 0.60, 0.62, 1.0)
		dev_box.set_border_width_all(2)
		dev_box.set_corner_radius_all(6)
		dev_box.set_content_margin_all(8.0)
		dev_btn.add_theme_stylebox_override(dev_state[0], dev_box)

	dev_btn.pressed.connect(_on_dev_mode_btn_pressed)
	left_btns.add_child(dev_btn)

	# Right half of footer: EXIT + RESTART.
	var right_btns := HBoxContainer.new()
	right_btns.position = Vector2(COL_DIV_X + 1.0 + PADDING, btn_y)
	right_btns.size     = Vector2(1280.0 - COL_DIV_X - 1.0 - PADDING * 2.0, btn_h)
	right_btns.add_theme_constant_override("separation", 12)
	panel.add_child(right_btns)

	_exit_btn = Button.new()
	_exit_btn.text                  = "EXIT"
	_exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exit_btn.custom_minimum_size   = Vector2(0, btn_h)
	_exit_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_exit_btn.add_theme_font_size_override("font_size", 26)
	_apply_gold_button_style(_exit_btn)
	_exit_btn.pressed.connect(_on_exit_pressed)
	right_btns.add_child(_exit_btn)

	_restart_btn = Button.new()
	_restart_btn.text                  = "RESTART"
	_restart_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restart_btn.custom_minimum_size   = Vector2(0, btn_h)
	_restart_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_restart_btn.add_theme_font_size_override("font_size", 26)
	_apply_gold_button_style(_restart_btn)
	_restart_btn.pressed.connect(_on_restart_pressed)
	right_btns.add_child(_restart_btn)

	# Wire signals after _load_all_settings() so the initial value emission
	# doesn't trigger save/side-effects before everything is constructed.
	_load_all_settings()
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_grid_lines_overview_toggle.toggled.connect(_on_grid_lines_overview_toggled)
	_grid_lines_zoomed_toggle.toggled.connect(_on_grid_lines_zoomed_toggled)


func _on_settings_btn_pressed() -> void:
	AudioManager.play_ui("button")
	# Save current pause state so we can restore it when the dialog closes —
	# the user might have already paused manually before opening Settings.
	_was_paused_before_settings = get_tree().paused
	get_tree().paused           = true
	# Always open on the SETTINGS tab; force a clean tab state on each open.
	_active_settings_tab        = ""
	_switch_settings_tab("Settings")
	_settings_dialog.visible    = true


func _on_settings_close_pressed() -> void:
	AudioManager.play_ui("button")
	_settings_dialog.visible = false
	get_tree().paused        = _was_paused_before_settings


# ---------------------------------------------------------------------------
# Reset Progress confirmation
# ---------------------------------------------------------------------------

func _on_reset_progress_pressed() -> void:
	AudioManager.play_ui("button")
	if _reset_confirm_overlay == null:
		_build_reset_confirm_overlay()
	_reset_confirm_overlay.visible = true


func _build_reset_confirm_overlay() -> void:
	# Sits inside _settings_dialog so it appears above the settings panel.
	_reset_confirm_overlay = Control.new()
	_reset_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reset_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_dialog.add_child(_reset_confirm_overlay)

	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_confirm_overlay.add_child(dim)

	var panel := Panel.new()
	panel.anchor_left   = 0.5;  panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5;  panel.anchor_bottom = 0.5
	panel.offset_left   = -220.0;  panel.offset_right  = 220.0
	panel.offset_top    = -100.0;  panel.offset_bottom = 100.0
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color     = Color(0.10, 0.04, 0.04, 0.97)
	panel_style.border_color = Color(0.65, 0.18, 0.18, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	_reset_confirm_overlay.add_child(panel)

	var prompt := Label.new()
	prompt.text                 = "You are about to permanently erase\nall progress. Are you sure?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	prompt.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt.offset_bottom        = -58.0
	prompt.add_theme_font_override("font", UIFonts.primary_bold())
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color(0.95, 0.90, 0.90, 1.0))
	panel.add_child(prompt)

	var btn_row := HBoxContainer.new()
	btn_row.anchor_left   = 0.0;  btn_row.anchor_right  = 1.0
	btn_row.anchor_top    = 1.0;  btn_row.anchor_bottom = 1.0
	btn_row.offset_top    = -52.0; btn_row.offset_bottom = -10.0
	btn_row.offset_left   = 16.0;  btn_row.offset_right  = -16.0
	btn_row.add_theme_constant_override("separation", 8)
	panel.add_child(btn_row)

	var no_btn := _make_reset_confirm_button("No",
			Color(0.20, 0.20, 0.24, 1.0), Color(0.45, 0.45, 0.52, 1.0))
	no_btn.pressed.connect(_on_reset_confirm_no)
	btn_row.add_child(no_btn)

	var yes_btn := _make_reset_confirm_button("Yes",
			Color(0.30, 0.03, 0.03, 1.0), Color(0.70, 0.15, 0.15, 1.0))
	yes_btn.pressed.connect(_on_reset_confirm_yes)
	btn_row.add_child(yes_btn)


func _make_reset_confirm_button(label_text: String, bg: Color, border: Color) -> Button:
	var btn := Button.new()
	btn.text                  = label_text
	btn.focus_mode            = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.90, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state_name: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color     = bg.lightened(0.08) if state_name == "hover" else \
				(bg.darkened(0.08) if state_name == "pressed" else bg)
		box.border_color = border
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.set_content_margin_all(6.0)
		btn.add_theme_stylebox_override(state_name, box)
	return btn


func _on_reset_confirm_no() -> void:
	AudioManager.play_ui("button")
	_reset_confirm_overlay.visible = false


func _on_reset_confirm_yes() -> void:
	AudioManager.play_ui("button")
	GameState.reset_all_upgrades()
	_reset_confirm_overlay.visible = false


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = GameState.format_bucks(amount)
	_refresh_trap_selector()


func _on_infestation_changed(level: float) -> void:
	var container: Control = _infestation_fill.get_parent()
	# Fill is inset 3px on each side, so usable inner width = container width − 6.
	# offset_right = left inset + proportion of inner width.
	var inner_w: float = container.size.x - 6.0
	_infestation_fill.offset_right = 3.0 + inner_w * level
	_infestation_label.text        = "%d%%" % roundi(level * 100.0)


func _on_wave_changed(wave: int) -> void:
	_wave_label.text = "%d" % wave  # "WAVE" is a static sibling label; only the number changes
	_max_countdown_seconds = 0
	_update_reward_bar_display(0.0)


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		var was_active         := _countdown_active
		_countdown_active       = true
		_last_countdown_seconds = seconds_remaining
		_countdown_seconds_label.text = "INCOMING  %d..." % seconds_remaining
		if _max_countdown_seconds == 0:
			_max_countdown_seconds = seconds_remaining
		if not was_active:
			_show_incoming_banner(true)
	else:
		_countdown_active             = false
		_last_countdown_seconds       = 0
		_countdown_seconds_label.text = ""
		_show_incoming_banner(false)


func _on_wave_spawn_progress_changed(spawned: int, total: int) -> void:
	if total <= 0:
		return
	_update_reward_bar_display(1.0 - float(spawned) / float(total))


func _process(delta: float) -> void:
	# If the game pauses while a drag is in progress due to a system event (e.g. a
	# level-up screen appears), cancel the drag so the trap is not silently committed
	# on resume.  Player-initiated pauses (_play_speed_state == 0) must NOT cancel:
	# the design allows placing traps while the player has manually paused to inspect the arena.
	if _drag_active and get_tree().paused and _play_speed_state != 0:
		_arena.cancel_hud_drag()
		_end_drag()

	# Keep the floating drag icon centred above the cursor each frame.
	# We do this in _process (rather than only in _input) so the icon stays
	# locked to position even when the cursor is stationary.
	if _drag_active and _drag_icon_ctrl != null and is_instance_valid(_drag_icon_ctrl):
		var half := DRAG_ICON_DISPLAY * 0.5
		_drag_icon_ctrl.global_position = _drag_cursor_pos + DRAG_OFFSET + DRAG_ICON_EXTRA_OFFSET - Vector2(half, half)

	if _send_wave_cooldown > 0.0:
		_send_wave_cooldown -= delta
		if _send_wave_cooldown <= 0.0:
			_send_wave_cooldown = 0.0
			_send_wave_btn.disabled = false
			_send_wave_btn.modulate = Color.WHITE


# ---------------------------------------------------------------------------
# Drag-and-drop trap placement
# ---------------------------------------------------------------------------

## Intercepts mouse/touch events when a drag is in progress, preventing them
## from reaching the arena's own input handlers.
func _input(event: InputEvent) -> void:
	# Spacebar toggles between paused and play-1× regardless of drag state.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if _play_speed_state == 0:
				_play_speed_state = _last_play_speed
			else:
				_last_play_speed  = _play_speed_state
				_play_speed_state = 0
			_apply_play_speed_state()
			get_viewport().set_input_as_handled()
			return

	if not _drag_active:
		return

	if event is InputEventMouseMotion:
		_update_drag_cursor(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0:
		_update_drag_cursor(event.position)
		get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed) \
		or (event is InputEventScreenTouch \
			and event.index == 0 \
			and not event.pressed):
		_arena.commit_hud_drag()
		_end_drag()
		get_viewport().set_input_as_handled()


## Receives gui_input events from a trap icon Control.
## Drag begins the moment the user presses and then moves — no hold delay.
func _on_icon_gui_input(event: InputEvent, trap_type: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hold_trap = trap_type
		elif _hold_trap == trap_type:
			_cancel_hold()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_hold_trap = trap_type
		elif _hold_trap == trap_type:
			_cancel_hold()
	elif _hold_trap == trap_type:
		# Any motion while the icon is pressed immediately begins drag.
		if event is InputEventMouseMotion or event is InputEventScreenDrag:
			_start_drag(trap_type)


## Initiates a drag for the given trap type.
## Builds the floating overlay icon, begins the slide-in tween, and
## notifies Arena to show a ghost preview at the current cursor position.
func _start_drag(trap_type: int) -> void:
	_cancel_hold()   # clear hold state before starting drag

	if not _can_afford(trap_type):
		return

	GameState.select_trap_type(trap_type)   # so Arena knows which ghost to draw

	# Capture the icon area's screen position for the floating icon tween origin.
	var icon_rect  := _icon_area_controls[trap_type].get_global_rect()
	var icon_center := icon_rect.get_center()

	# Full-viewport pass-through container — MOUSE_FILTER_IGNORE so it never
	# blocks the _input() interception we do ourselves above.
	_drag_overlay = Control.new()
	_drag_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_overlay)

	# Floating trap icon — starts at the original icon position, then tweens upward.
	_drag_icon_ctrl = _build_floating_trap_icon(_drag_overlay, trap_type)
	var half := DRAG_ICON_DISPLAY * 0.5
	_drag_icon_ctrl.global_position = icon_center - Vector2(half, half)

	_drag_active     = true
	_drag_type       = trap_type
	_drag_cursor_pos = icon_center

	# Tell Arena to begin the ghost preview at the icon's starting position.
	_arena.begin_hud_drag(trap_type, icon_center + DRAG_OFFSET)

	# Slide the icon from its resting position to its drag position above the cursor.
	# DRAG_ICON_EXTRA_OFFSET shifts the opaque icon further up-left from the ghost preview.
	var target_pos := icon_center + DRAG_OFFSET + DRAG_ICON_EXTRA_OFFSET - Vector2(half, half)
	_drag_tween = create_tween()
	_drag_tween.set_ease(Tween.EASE_OUT)
	_drag_tween.set_trans(Tween.TRANS_CUBIC)
	_drag_tween.tween_property(_drag_icon_ctrl, "global_position", target_pos, 0.15)


## Updates the cursor position and relays the placement-zone center to Arena.
func _update_drag_cursor(cursor_pos: Vector2) -> void:
	_drag_cursor_pos = cursor_pos
	# Placement zone is the center of the floating icon, which sits above the cursor.
	_arena.update_hud_drag(cursor_pos + DRAG_OFFSET)


## Clears press state without starting a drag.
func _cancel_hold() -> void:
	_hold_trap  = -1
	_hold_boost = -1


## Tears down the floating overlay and resets drag state.
func _end_drag() -> void:
	if _drag_tween != null and _drag_tween.is_valid():
		_drag_tween.kill()
		_drag_tween = null
	if _drag_overlay != null and is_instance_valid(_drag_overlay):
		_drag_overlay.queue_free()
	_drag_overlay   = null
	_drag_icon_ctrl = null
	_drag_active    = false
	_drag_is_boost  = false
	_drag_type      = -1


func _on_zoom_btn_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.zoom_toggle_requested.emit()


func _on_zoom_state_changed(is_zoomed: bool) -> void:
	# When already zoomed in, the action is to zoom out — show the minus sign.
	# When in overview, the action is to zoom in — show the plus sign.
	(_zoom_icon as _ZoomIcon).show_plus = not is_zoomed
	_zoom_icon.queue_redraw()


func _on_viewport_resized() -> void:
	pass


func _on_play_pause_btn_pressed() -> void:
	AudioManager.play_ui("button")
	if _play_speed_state == 0:
		_play_speed_state = _last_play_speed   # resume at the last active speed
	else:
		_last_play_speed  = _play_speed_state  # save speed before pausing
		_play_speed_state = 0
	_apply_play_speed_state()


func _on_speed_btn_pressed() -> void:
	AudioManager.play_ui("button")
	# Cycle 1× → 2× → 3× → 1×, based on last active speed (so cycling works while paused too).
	var current := _play_speed_state if _play_speed_state > 0 else _last_play_speed
	_last_play_speed = (current % 3) + 1
	if _play_speed_state > 0:
		# Apply immediately when not paused.
		_play_speed_state = _last_play_speed
		_apply_play_speed_state()
	else:
		# When paused, update the speed preview without unpausing.
		_speed_icon.play_speed_state = _last_play_speed
		_speed_icon.speed_text       = "%dx" % _last_play_speed
		_speed_icon.queue_redraw()


## Applies Engine.time_scale, tree pause, and banner visibility for the current _play_speed_state.
## Called on button press, spacebar toggle, send-wave resume, and run end.
func _apply_play_speed_state() -> void:
	match _play_speed_state:
		0:  # paused
			get_tree().paused = true
			_show_pause_banner(true)
		1:  # play 1×
			Engine.time_scale = 1.0
			get_tree().paused = false
			_show_pause_banner(false)
		2:  # play 2×
			Engine.time_scale = 2.0
			get_tree().paused = false
			_show_pause_banner(false)
		3:  # play 3×
			Engine.time_scale = 3.0
			get_tree().paused = false
			_show_pause_banner(false)
	# Play/pause icon: pass the game speed state directly.
	# _PlayPauseIcon colours triangle gold when paused (press to play) and bars gold when playing.
	_play_pause_icon.play_speed_state = _play_speed_state
	_play_pause_icon.queue_redraw()
	# Speed icon: shows current speed (or last speed when paused) with "Nx" label.
	var display_speed := _play_speed_state if _play_speed_state > 0 else _last_play_speed
	_speed_icon.play_speed_state = display_speed
	_speed_icon.speed_text       = "%dx" % display_speed
	_speed_icon.queue_redraw()


func _on_multiplier_btn_pressed() -> void:
	AudioManager.play_ui("button")
	match _wave_multiplier:
		1:   _wave_multiplier = 5
		5:   _wave_multiplier = 10
		10:  _wave_multiplier = 1
	_multiplier_label.text = "%d" % _wave_multiplier
	var wave_word := "WAVE" if _wave_multiplier == 1 else "WAVES"
	_send_wave_header_label.text = "SEND %d %s" % [_wave_multiplier, wave_word]
	_refresh_reward_label()


## Recomputes and updates the send-wave reward label immediately.
## Called when the multiplier changes so the displayed amount stays in sync
## without waiting for the next spawn tick or countdown second.
func _refresh_reward_label() -> void:
	if _current_wave_reward > 0:
		_send_wave_reward_label.text = GameState.format_bucks(_current_wave_reward * _wave_multiplier)


func _on_send_wave_pressed() -> void:
	AudioManager.play_ui("button")
	# Clicking send-wave while paused resumes play at 1× first, then sends the wave.
	if _play_speed_state == 0:
		_play_speed_state = _last_play_speed
		_apply_play_speed_state()
	if _wave_multiplier > 1:
		GameState.wave_skip_multi_requested.emit(_wave_multiplier)
	else:
		GameState.wave_skip_requested.emit()
	_send_wave_cooldown = SEND_WAVE_COOLDOWN_SEC
	_send_wave_btn.disabled = true
	_send_wave_btn.modulate = Color(0.5, 0.5, 0.5, 1.0)


func _build_early_bonus_particles() -> void:
	_early_bonus_particles = CPUParticles2D.new()
	# z_index must be > 0 so particles draw in front of the side panels (z 0).
	_early_bonus_particles.z_index               = 10
	_early_bonus_particles.emitting              = false
	_early_bonus_particles.one_shot              = true
	_early_bonus_particles.lifetime              = 0.425
	_early_bonus_particles.explosiveness         = 1.0
	_early_bonus_particles.spread                = 180.0
	_early_bonus_particles.initial_velocity_min  = 250.0
	_early_bonus_particles.initial_velocity_max  = 450.0
	_early_bonus_particles.gravity               = Vector2(0.0, 350.0)
	_early_bonus_particles.scale_amount_min      = 0.1875   # 1.5× the base 0.125
	_early_bonus_particles.scale_amount_max      = 0.3375   # 1.5× the base 0.225
	_early_bonus_particles.texture               = load("res://assets/bug_buck_coin_small.png") as Texture2D
	add_child(_early_bonus_particles)


func _on_early_bonus_awarded(coins: int) -> void:
	if coins <= 0:
		return
	const BASE_PARTICLES := 12
	var scale := 1 if _wave_multiplier == 1 else (2 if _wave_multiplier == 5 else 3)
	_early_bonus_particles.amount   = BASE_PARTICLES * scale
	_early_bonus_particles.position = _send_wave_btn.get_global_rect().get_center()
	_early_bonus_particles.restart()


func _on_early_send_reward_changed(amount: int) -> void:
	_current_wave_reward         = amount
	_send_wave_reward_label.text = GameState.format_bucks(amount * _wave_multiplier)
	# Bar fill during spawn is driven by _on_wave_spawn_progress_changed;
	# only collapse the overlay once the reward reaches zero.
	if amount <= 0:
		_update_reward_bar_display(0.0)
	else:
		_reward_bar_overlay.modulate.a = 1.0


func _on_run_ended() -> void:
	# Reset button to play-1× appearance without calling _apply_play_speed_state,
	# because the line below immediately pauses the tree for the run-over state.
	_play_speed_state = 1
	_last_play_speed  = 1
	Engine.time_scale = 1.0
	_play_pause_icon.play_speed_state = 1   # 1 = playing; _PlayPauseIcon will colour bars gold
	_play_pause_icon.queue_redraw()
	_speed_icon.play_speed_state = 1
	_speed_icon.speed_text       = "1x"
	_speed_icon.queue_redraw()
	_show_pause_banner(false)
	get_tree().paused = true
	# Open the infested dialog immediately — no interstitial overlay.
	var hub: Node = load("res://ui/HubScreen.gd").new()
	get_tree().root.add_child(hub)


func _on_restart_pressed() -> void:
	AudioManager.play_ui("button")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_dev_mode_btn_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.dev_mode = not GameState.dev_mode
	get_tree().paused  = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	AudioManager.play_ui("button")
	get_tree().quit()


# ---------------------------------------------------------------------------
# Trap selector
# ---------------------------------------------------------------------------

## Shows only the trap rows that are unlocked for this run.
## Called once after TrapSelectionScreen confirms, and on every subsequent
## unlock_traps_set emission (future: meta upgrades may change the set mid-run).
func _refresh_trap_visibility() -> void:
	for i in range(_icon_controls.size()):
		_icon_controls[i].visible = i in GameState.unlocked_trap_types


func _on_unlocked_traps_set(_types: Array[int]) -> void:
	_refresh_trap_visibility()
	_refresh_trap_selector()


func _refresh_boost_visibility() -> void:
	for i in range(_boost_icon_controls.size()):
		_boost_icon_controls[i].visible = i in GameState.unlocked_boost_types


func _on_unlocked_boosts_set(_types: Array[int]) -> void:
	_refresh_boost_visibility()
	_update_tab_styles()


func _refresh_trap_selector() -> void:
	for i in range(_icon_controls.size()):
		_icon_controls[i].modulate = Color(1, 1, 1, 1) if _can_afford(i) else COLOR_UNAFFORDABLE_MODULATE
		if i < _trap_cost_labels.size():
			var count := GameState.get_trap_placed_count(i)
			_trap_cost_labels[i].text = GameState.format_bucks(
					Trap.compute_placement_cost(i as Trap.TrapType, count))
	for i in range(_boost_icon_controls.size()):
		_boost_icon_controls[i].modulate = Color(1, 1, 1, 1) if _can_afford_boost(i) else COLOR_UNAFFORDABLE_MODULATE
		if i < _boost_cost_labels.size():
			var count := GameState.get_boost_placed_count(i)
			_boost_cost_labels[i].text = GameState.format_bucks(
					BoostUnit.compute_placement_cost(i as BoostUnit.BoostType, count))



## Builds a full-width trap row: brand-colored panel spanning the entire left-panel
## width, containing text content on the left and the 3D trap preview on the right.
## Drag-to-place input fires from anywhere on the panel, not just the icon area.
## Appends the icon area Control to _icon_area_controls for _start_drag positioning.
## Returns the outer PanelContainer so _icon_controls can store it for affordability dimming.
func _build_trap_row(parent: VBoxContainer, type: int) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color      = TRAP_BRAND[type]["normal"]
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color  = Color(0.72, 0.72, 0.72, 1.0)
	style.shadow_color  = COLOR_BTN_SHADOW
	style.shadow_size   = 2
	style.shadow_offset = Vector2(0, 2)   # no horizontal bias; shadow falls only downward

	# PanelContainer fills the full row width and intercepts all pointer events so
	# the user can drag from anywhere — not just the icon area.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size   = Vector2(0, ROW_H)
	panel.mouse_filter          = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# --- Left: text content, fills remaining width ---
	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 2)
	cvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	cvbox.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cvbox)

	var name_lbl := Label.new()
	name_lbl.text                  = TRAP_LABELS[type][0]
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text             = true
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(name_lbl)

	# cost_row fills full width so the badge can right-align against the text column edge.
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 3)
	cost_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.alignment    = BoxContainer.ALIGNMENT_BEGIN
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(cost_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin_small.png")
	coin_icon.custom_minimum_size = Vector2(16, 16)
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(coin_icon)

	var cost_lbl := Label.new()
	cost_lbl.text                = GameState.format_bucks(Trap.compute_placement_cost(type as Trap.TrapType, 0))
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 15)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	cost_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)
	_trap_cost_labels.append(cost_lbl)

	# Badge sits on the same row as the cost, pushed to the right edge.
	var badge_lbl := Label.new()
	badge_lbl.text                  = TRAP_BRAND[type]["badge"]
	badge_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_lbl.clip_text             = true
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	badge_lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	badge_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(badge_lbl)

	# --- Right: 3D trap preview with framed background ---
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size   = Vector2(48.0, 48.0)
	icon_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_ctrl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	icon_ctrl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_ctrl)

	# Framed background behind the 3D preview.
	# Floor traps (Bait Station) use a lighter purple so the dark wrought-iron grate
	# reads clearly.  All other traps use a near-transparent dark background.
	var icon_bg_style := StyleBoxFlat.new()
	if type == Trap.TrapType.BAIT_STATION:
		icon_bg_style.bg_color = Color(0.53, 0.34, 0.73, 0.90)
	else:
		icon_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	icon_bg_style.set_corner_radius_all(4)
	icon_bg_style.set_border_width_all(2)
	icon_bg_style.border_color = Color(0.72, 0.72, 0.80, 1.0)

	var icon_bg := PanelContainer.new()
	icon_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_bg.add_theme_stylebox_override("panel", icon_bg_style)
	icon_ctrl.add_child(icon_bg)

	var svp := SubViewport.new()
	svp.size                      = Vector2i(int(DRAG_ICON_SIZE), int(DRAG_ICON_SIZE))
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 2.2   # larger = more world units visible = smaller-appearing trap
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(type as Trap.TrapType)
	svp.add_child(trap_preview)
	trap_preview.call_deferred("hide_range_indicator")
	trap_preview.call_deferred("hide_decorators")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Suppress the default SubViewportContainer panel stylebox — the icon_bg above
	# draws the background; the viewport only needs to composite the 3D content.
	svc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	# Drag input connects to the full panel so the entire row is a drag target.
	panel.gui_input.connect(_on_icon_gui_input.bind(type))

	# Store icon_ctrl separately so _start_drag can tween the floating icon
	# from the trap image's actual screen position rather than the panel center.
	_icon_area_controls.append(icon_ctrl)

	return panel


## Builds a floating drag icon identical to the in-panel icon, sized DRAG_ICON_SIZE.
## Adds it as a child of parent.  Used for the overlay shown during drag.
func _build_floating_trap_icon(parent: Control, type: int) -> Control:
	# Square, no background — matches the panel icon appearance exactly.
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size = Vector2(DRAG_ICON_DISPLAY, DRAG_ICON_DISPLAY)
	icon_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon_ctrl)

	var svp := SubViewport.new()
	svp.size                      = Vector2i(int(DRAG_ICON_SIZE), int(DRAG_ICON_SIZE))
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 2.2   # larger = more world units visible = smaller-appearing trap
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(type as Trap.TrapType)
	svp.add_child(trap_preview)
	trap_preview.call_deferred("hide_range_indicator")
	trap_preview.call_deferred("hide_decorators")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Remove the default stylebox so no background or border renders behind the trap.
	svc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	return icon_ctrl


func _can_afford(type: int) -> bool:
	return GameState.bug_bucks >= Trap.compute_placement_cost(
			type as Trap.TrapType, GameState.get_trap_placed_count(type))


func _can_afford_boost(type: int) -> bool:
	return GameState.bug_bucks >= BoostUnit.compute_placement_cost(
			type as BoostUnit.BoostType, GameState.get_boost_placed_count(type))


# ---------------------------------------------------------------------------
# Tab switching
# ---------------------------------------------------------------------------

func _on_trap_tab_pressed() -> void:
	AudioManager.play_ui("button")
	_active_tab           = 0
	_trap_scroll.visible  = true
	_boost_scroll.visible = false
	_update_tab_styles()


func _on_boost_tab_pressed() -> void:
	AudioManager.play_ui("button")
	_active_tab           = 1
	_trap_scroll.visible  = false
	_boost_scroll.visible = true
	_update_tab_styles()


func _update_tab_styles() -> void:
	var has_boosts := not GameState.unlocked_boost_types.is_empty()
	_tab_btns[1].disabled = not has_boosts

	for i in range(_tab_btns.size()):
		var is_disabled := (i == 1 and not has_boosts)

		if is_disabled:
			# Greyed-out appearance while no boosts are available.
			for state_name in ["normal", "hover", "pressed", "disabled"]:
				var box := StyleBoxFlat.new()
				box.bg_color     = Color(0.08, 0.08, 0.10, 1.0)
				box.border_color = Color(0.20, 0.20, 0.22, 1.0)
				box.set_border_width_all(2)
				box.set_corner_radius_all(4)
				_tab_btns[i].add_theme_stylebox_override(state_name, box)
			_tab_btns[i].add_theme_color_override("font_color", Color(0.28, 0.28, 0.30, 1.0))
			continue

		var is_active := (i == _active_tab)
		# Silver theme: active tab is a medium steel-gray; inactive is near-black.
		var bg_normal := Color(0.42, 0.44, 0.48, 1.0) if is_active else Color(0.12, 0.12, 0.14, 1.0)
		var bg_hover  := bg_normal.lightened(0.08)
		var border_c  := Color(0.78, 0.80, 0.84, 1.0) if is_active else Color(0.30, 0.32, 0.34, 1.0)
		for state_name in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color     = bg_hover if state_name == "hover" else bg_normal
			if state_name == "pressed":
				box.bg_color = bg_normal.darkened(0.08)
			box.border_color = border_c
			box.set_border_width_all(2)
			box.set_corner_radius_all(4)
			_tab_btns[i].add_theme_stylebox_override(state_name, box)
		_tab_btns[i].add_theme_color_override("font_color",
			Color(0.96, 0.97, 0.98, 1.0) if is_active else Color(0.50, 0.52, 0.55, 1.0))


# ---------------------------------------------------------------------------
# Boost selector row
# ---------------------------------------------------------------------------

## Builds a boost row identical in structure to a trap row but uses BoostUnit
## for the icon preview and cost, and routes drag input to _start_boost_drag().
## Returns the outer PanelContainer for affordability dimming.
func _build_boost_row(parent: VBoxContainer, type: int) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color     = BOOST_BRAND[type]["normal"]
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0.72, 0.72, 0.72, 1.0)
	style.shadow_color = COLOR_BTN_SHADOW
	style.shadow_size  = 2
	style.shadow_offset = Vector2(0, 2)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size   = Vector2(0, ROW_H)
	panel.mouse_filter          = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 2)
	cvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	cvbox.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cvbox)

	var name_lbl := Label.new()
	name_lbl.text                  = BOOST_LABELS[type][0]
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text             = true
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(name_lbl)

	# cost_row fills full width so the badge can right-align against the text column edge.
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 3)
	cost_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.alignment    = BoxContainer.ALIGNMENT_BEGIN
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(cost_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin_small.png")
	coin_icon.custom_minimum_size = Vector2(16, 16)
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(coin_icon)

	var cost_lbl := Label.new()
	cost_lbl.text                = GameState.format_bucks(BoostUnit.compute_placement_cost(type as BoostUnit.BoostType, 0))
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 15)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.20))
	cost_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)
	_boost_cost_labels.append(cost_lbl)

	# Badge sits on the same row as the cost, pushed to the right edge.
	var badge_lbl := Label.new()
	badge_lbl.text                  = BOOST_BRAND[type]["badge"]
	badge_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_lbl.clip_text             = true
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	badge_lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	badge_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(badge_lbl)

	# 3D boost preview icon using a SubViewport with a BoostUnit instance.
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size   = Vector2(48.0, 48.0)
	icon_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_ctrl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	icon_ctrl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_ctrl)

	var icon_bg_style := StyleBoxFlat.new()
	icon_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	icon_bg_style.set_corner_radius_all(4)
	icon_bg_style.set_border_width_all(2)
	icon_bg_style.border_color = Color(0.72, 0.72, 0.80, 1.0)

	var icon_bg := PanelContainer.new()
	icon_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_bg.add_theme_stylebox_override("panel", icon_bg_style)
	icon_ctrl.add_child(icon_bg)

	var svp := SubViewport.new()
	svp.size                      = Vector2i(int(DRAG_ICON_SIZE), int(DRAG_ICON_SIZE))
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 2.2
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	var boost_preview := Node3D.new()
	boost_preview.set_script(BoostUnit)
	boost_preview.initialize_preview(type as BoostUnit.BoostType)
	svp.add_child(boost_preview)
	boost_preview.call_deferred("hide_range_indicator")
	boost_preview.call_deferred("hide_decorators")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	panel.gui_input.connect(_on_boost_icon_gui_input.bind(type))
	_boost_icon_area_controls.append(icon_ctrl)

	return panel


## Builds a floating boost drag icon (colored cylinder via SubViewport).
func _build_floating_boost_icon(parent: Control, type: int) -> Control:
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size = Vector2(DRAG_ICON_DISPLAY, DRAG_ICON_DISPLAY)
	icon_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon_ctrl)

	var svp := SubViewport.new()
	svp.size                      = Vector2i(int(DRAG_ICON_SIZE), int(DRAG_ICON_SIZE))
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 2.2
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	var boost_preview := Node3D.new()
	boost_preview.set_script(BoostUnit)
	boost_preview.initialize_preview(type as BoostUnit.BoostType)
	svp.add_child(boost_preview)
	boost_preview.call_deferred("hide_range_indicator")
	boost_preview.call_deferred("hide_decorators")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	return icon_ctrl


# ---------------------------------------------------------------------------
# Boost drag input
# ---------------------------------------------------------------------------

func _on_boost_icon_gui_input(event: InputEvent, boost_type: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hold_boost = boost_type
		elif _hold_boost == boost_type:
			_cancel_hold()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_hold_boost = boost_type
		elif _hold_boost == boost_type:
			_cancel_hold()
	elif _hold_boost == boost_type:
		if event is InputEventMouseMotion or event is InputEventScreenDrag:
			_start_boost_drag(boost_type)


func _start_boost_drag(boost_type: int) -> void:
	_cancel_hold()

	if not _can_afford_boost(boost_type):
		return

	var icon_rect   := _boost_icon_area_controls[boost_type].get_global_rect()
	var icon_center := icon_rect.get_center()

	_drag_overlay = Control.new()
	_drag_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_overlay)

	_drag_icon_ctrl = _build_floating_boost_icon(_drag_overlay, boost_type)
	var half := DRAG_ICON_DISPLAY * 0.5
	_drag_icon_ctrl.global_position = icon_center - Vector2(half, half)

	_drag_active     = true
	_drag_is_boost   = true
	_drag_type       = boost_type
	_drag_cursor_pos = icon_center

	_arena.begin_hud_drag_boost(boost_type as BoostUnit.BoostType, icon_center + DRAG_OFFSET)

	var target_pos := icon_center + DRAG_OFFSET + DRAG_ICON_EXTRA_OFFSET - Vector2(half, half)
	_drag_tween = create_tween()
	_drag_tween.set_ease(Tween.EASE_OUT)
	_drag_tween.set_trans(Tween.TRANS_CUBIC)
	_drag_tween.tween_property(_drag_icon_ctrl, "global_position", target_pos, 0.15)


# ---------------------------------------------------------------------------
# Button styles
# ---------------------------------------------------------------------------

## Settings (van-gear) button style: no background, no border, no padding.
## StyleBoxEmpty tells Godot to draw nothing for every interactive state, so
## only the icon texture is visible.
func _apply_gear_button_style(btn: Button) -> void:
	# Backgrounds are COLOR_BTN_* lightened by 25% (multiply each channel by 1.25).
	var states := [
		["normal",  Color(0.375, 0.375, 0.375)],
		["hover",   Color(0.475, 0.475, 0.475)],
		["pressed", Color(0.275, 0.275, 0.275)],
	]
	for state in states:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = COLOR_BTN_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE


func _apply_gold_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_GOLD_BG_NORMAL], ["hover", COLOR_GOLD_BG_HOVER], ["pressed", COLOR_GOLD_BG_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_GOLD_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_GOLD_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


func _apply_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 12.0
		box.content_margin_right  = 12.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


func _apply_send_wave_btn_style(btn: Button) -> void:
	for state in [["normal", COLOR_GREEN_NORMAL], ["hover", COLOR_GREEN_HOVER], ["pressed", COLOR_GREEN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_GREEN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


func _apply_toggle_btn_style(btn: Button) -> void:
	# Rounded-rectangle toggle button — matches the >> button's corner radius (5)
	# so the two buttons look like a cohesive pair within the send-wave panel.
	for pair: Array in [
		["normal",   COLOR_GOLD_BG_NORMAL],
		["hover",    COLOR_GOLD_BG_HOVER],
		["pressed",  COLOR_GOLD_BG_PRESSED],
		["disabled", Color(0.45, 0.35, 0.03, 1.0)],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = pair[1] as Color
		box.border_color = COLOR_GOLD_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		# Zero content margins so the anchored HBoxContainer inside the button
		# fills the full button rect without being pushed inward by StyleBox padding.
		box.set_content_margin_all(0)
		btn.add_theme_stylebox_override(pair[0] as String, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE


func _apply_ff_button_style(btn: Button) -> void:
	# Dark background with gold border — visually pairs with the gold multiplier pill
	# while remaining visually distinct (outlined vs filled). Content margins are zero
	# so the Label child placed via PRESET_FULL_RECT fills the entire button rect.
	for pair: Array in [
		["normal",   Color(0.16, 0.16, 0.16, 1.0)],
		["hover",    Color(0.24, 0.24, 0.24, 1.0)],
		["pressed",  Color(0.10, 0.10, 0.10, 1.0)],
		["disabled", Color(0.14, 0.14, 0.14, 0.6)],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = pair[1] as Color
		box.border_color = COLOR_GOLD_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.set_content_margin_all(0)
		btn.add_theme_stylebox_override(pair[0] as String, box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE


## Shows or hides the early-reward row. fill > 0.0 means a reward is available.
func _update_reward_bar_display(fill: float) -> void:
	_reward_bar_overlay.modulate.a = 1.0 if fill > 0.0 else 0.0


# ---------------------------------------------------------------------------
# Volume controls and settings helpers
# ---------------------------------------------------------------------------

## Switches the active settings tab, refreshes tab button styles, and
## shows/hides the content containers accordingly.  Rebuilds the UPGRADES
## content each time that tab is opened so values reflect the current run state.
func _switch_settings_tab(tab_name: String) -> void:
	if _active_settings_tab == tab_name:
		return
	_active_settings_tab = tab_name
	_apply_settings_tab_style(_settings_tab_btn, tab_name == "Settings")
	_apply_settings_tab_style(_upgrades_tab_btn, tab_name == "Upgrades")
	_settings_content.visible = tab_name == "Settings"
	_upgrades_content.visible = tab_name == "Upgrades"
	if tab_name == "Upgrades":
		_build_upgrades_content()


## Applies active/idle visual styling to a settings tab button.
## Active tab: gold text + gold bottom underline border.
## Idle tab: dim text + no border.
func _apply_settings_tab_style(btn: Button, active: bool) -> void:
	const ACTIVE_BG  := Color(0.04, 0.08, 0.14, 1.0)
	const IDLE_BG    := Color(0.02, 0.03, 0.08, 1.0)
	const ACTIVE_TXT := Color(1.00, 0.84, 0.00, 1.0)
	const IDLE_TXT   := Color(0.50, 0.50, 0.56, 1.0)
	btn.add_theme_color_override("font_color", ACTIVE_TXT if active else IDLE_TXT)
	for state: String in ["normal", "hover", "pressed"]:
		var bg := ACTIVE_BG if active else IDLE_BG
		if state == "hover":
			bg = bg.lightened(0.06)
		var box := StyleBoxFlat.new()
		box.bg_color = bg
		if active:
			box.border_color        = COLOR_HAZARD_YELLOW
			box.border_width_bottom = 3
			box.border_width_top    = 0
			box.border_width_left   = 0
			box.border_width_right  = 0
		else:
			box.set_border_width_all(0)
		box.content_margin_left   = 6.0
		box.content_margin_right  = 6.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state, box)


## Creates a bare Button styled for the settings tab bar.
func _make_settings_tab_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text       = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


## Populates the UPGRADES ScrollContainer with one row per campaign buff,
## showing the total magnitude picked this run (or "—" if none yet).
## Called each time the UPGRADES tab is opened so the display is always current.
func _build_upgrades_content() -> void:
	# Clear any previously built rows.
	for child in _upgrades_content.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	_upgrades_content.add_child(vbox)

	const ROW_H:     float = 64.0
	const PADDING_X: float = 28.0
	const DIVIDER_C := Color(0.22, 0.22, 0.30, 1.0)
	const COLOR_ACQUIRED := Color(1.00, 0.84, 0.00, 1.0)   # gold — buff has been picked this run
	const COLOR_NONE     := Color(0.45, 0.45, 0.50, 1.0)   # dim — not yet acquired

	var buffs: Array = LevelUpScreen.CAMPAIGN_BUFFS

	for i in buffs.size():
		var buff: Dictionary = buffs[i]
		var total: float     = GameState.run_campaign_buff_totals.get(buff["id"], 0.0)
		var acquired: bool   = total > 0.0

		var row := Control.new()
		row.custom_minimum_size   = Vector2(0.0, ROW_H)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)

		# Title — left column.
		var title_lbl := Label.new()
		title_lbl.text         = buff["title"]
		title_lbl.position     = Vector2(PADDING_X, 8.0)
		title_lbl.size         = Vector2(440.0, 24.0)
		title_lbl.clip_text    = true
		title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
		title_lbl.add_theme_font_size_override("font_size", 18)
		title_lbl.add_theme_color_override("font_color",
				COLOR_TEXT if acquired else COLOR_NONE)
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title_lbl)

		# Description — below the title.
		var desc_lbl := Label.new()
		desc_lbl.text         = buff["plain_text"]
		desc_lbl.position     = Vector2(PADDING_X, 36.0)
		desc_lbl.size         = Vector2(820.0, 20.0)
		desc_lbl.clip_text    = true
		desc_lbl.add_theme_font_override("font", UIFonts.primary_bold())
		desc_lbl.add_theme_font_size_override("font_size", 16)
		desc_lbl.add_theme_color_override("font_color",
				Color(0.72, 0.72, 0.77, 1.0) if acquired else COLOR_NONE)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(desc_lbl)

		# Current value label — right-aligned.
		var value_lbl := Label.new()
		value_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		value_lbl.add_theme_font_override("font", UIFonts.primary_bold())
		value_lbl.add_theme_font_size_override("font_size", 22)
		value_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_lbl.position             = Vector2(860.0, 0.0)
		value_lbl.size                 = Vector2(392.0, ROW_H)
		value_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		row.add_child(value_lbl)

		if acquired:
			# Format using the same logic as the level-up card display.
			var display_val: String
			if buff["id"] == "infestation_heal":
				display_val = "%.1f" % (total * 100.0)
			else:
				display_val = "%d" % roundi(total * 100.0)
			value_lbl.text = buff["impact_template"] % display_val
			value_lbl.add_theme_color_override("font_color", COLOR_ACQUIRED)
		else:
			value_lbl.text = "—"
			value_lbl.add_theme_color_override("font_color", COLOR_NONE)

		# Row divider (except after the last row).
		if i < buffs.size() - 1:
			var div := ColorRect.new()
			div.custom_minimum_size   = Vector2(0.0, 1.0)
			div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			div.color        = DIVIDER_C
			div.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(div)


## Adds a colored section-title strip spanning the full column width.
## Used in the full-screen settings layout to clearly label each column.
func _add_settings_section_strip(parent: VBoxContainer, header_text: String) -> void:
	var strip := Panel.new()
	strip.custom_minimum_size = Vector2(0.0, 44.0)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.04, 0.16, 0.12, 1.0)   # dark teal — matches the game's green palette
	sty.set_border_width_all(0)
	strip.add_theme_stylebox_override("panel", sty)
	parent.add_child(strip)

	var lbl := Label.new()
	lbl.text                 = header_text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	strip.add_child(lbl)


## Builds a label + slider row for one audio bus, sized for full-screen layout.
## Returns the HSlider so the caller can read/write its value.
func _build_volume_row(parent: VBoxContainer, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0.0, 52.0)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text                = label_text
	lbl.custom_minimum_size = Vector2(80.0, 0.0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value             = 0.0
	slider.max_value             = 1.0
	slider.step                  = 0.01
	slider.value                 = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size   = Vector2(0.0, 36.0)
	row.add_child(slider)

	return slider


## Builds a label + CheckButton row for a boolean setting, sized for full-screen layout.
## Returns the CheckButton so the caller can connect its toggled signal and read its state.
func _build_toggle_row(parent: VBoxContainer, label_text: String) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0.0, 52.0)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(lbl)

	var toggle := CheckButton.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)

	return toggle


func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	_save_all_settings()


func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	_save_all_settings()


func _on_grid_lines_overview_toggled(pressed: bool) -> void:
	_save_all_settings()
	GameState.grid_lines_changed.emit(pressed, _grid_lines_zoomed_toggle.button_pressed)


func _on_grid_lines_zoomed_toggled(pressed: bool) -> void:
	_save_all_settings()
	GameState.grid_lines_changed.emit(_grid_lines_overview_toggle.button_pressed, pressed)


func _save_all_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",   "music",               _music_slider.value)
	cfg.set_value("audio",   "sfx",                 _sfx_slider.value)
	cfg.set_value("display", "grid_lines_overview",  _grid_lines_overview_toggle.button_pressed)
	cfg.set_value("display", "grid_lines_zoomed",    _grid_lines_zoomed_toggle.button_pressed)
	cfg.save("user://settings.cfg")


## Loads all settings from disk.  Applies defaults when the file is absent (first run).
## Emits grid_lines_changed so Arena can apply the loaded values at startup.
func _load_all_settings() -> void:
	var cfg := ConfigFile.new()
	var music_vol:     float = 1.0
	var sfx_vol:       float = 1.0
	var grid_overview: bool  = false  # default: no grid lines in the zoomed-out view
	var grid_zoomed:   bool  = true   # default: grid lines visible when zoomed in
	if cfg.load("user://settings.cfg") == OK:
		music_vol     = cfg.get_value("audio",   "music",               1.0)
		sfx_vol       = cfg.get_value("audio",   "sfx",                 1.0)
		grid_overview = cfg.get_value("display", "grid_lines_overview",  false)
		grid_zoomed   = cfg.get_value("display", "grid_lines_zoomed",    true)
	_music_slider.value = music_vol
	_sfx_slider.value   = sfx_vol
	AudioManager.set_music_volume(music_vol)
	AudioManager.set_sfx_volume(sfx_vol)
	_grid_lines_overview_toggle.button_pressed = grid_overview
	_grid_lines_zoomed_toggle.button_pressed   = grid_zoomed
	GameState.grid_lines_changed.emit(grid_overview, grid_zoomed)


# ---------------------------------------------------------------------------
# Procedural icons
# ---------------------------------------------------------------------------

## Trapezoid with a silver outline and dark fill.  The top edge spans the full
## Control width; each side angles inward by 'taper' px over the Control height
## so the bottom edge is (width - 2×taper) wide.  Border width matches the
## panel outlines so the top edge is visually continuous with the arena border.
class _PauseBannerShape extends Control:
	var taper:        float = 0.0
	var border_w:     float = 0.0
	var color_border: Color = Color.WHITE
	var color_fill:   Color = Color.TRANSPARENT

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w  := size.x
		var h  := size.y
		var bw := border_w
		# Slant length — needed for perpendicular inset on the angled edges.
		var L  := sqrt(taper * taper + h * h)

		# Outer (silver) trapezoid — top edge = full width, sides angle inward.
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0,       0.0),
			Vector2(w,         0.0),
			Vector2(w - taper, h),
			Vector2(taper,     h),
		]), color_border)

		# Inner (dark fill) — each edge is offset inward perpendicular to itself by bw,
		# then adjacent offset edges are intersected to find the inner corners.
		# This gives a uniform visible border width along the angled sides;
		# a simple horizontal inset would make the border narrow at the top and wide at the bottom.
		var x_top := bw * (L + taper) / h          # inner x at the top corners
		var x_bot := taper + bw * (L - taper) / h  # inner x at the bottom corners
		draw_colored_polygon(PackedVector2Array([
			Vector2(x_top,     bw),
			Vector2(w - x_top, bw),
			Vector2(w - x_bot, h - bw),
			Vector2(x_bot,     h - bw),
		]), color_fill)


## Reverse trapezoid for the incoming-wave banner.
## Bottom edge spans the full Control width (flush with the screen edge);
## sides angle inward going upward, so the top edge is narrower by 2×taper.
## No bottom border is drawn — that edge is hidden beneath the screen boundary.
class _IncomingBannerShape extends Control:
	var taper:        float = 0.0
	var border_w:     float = 0.0
	var color_border: Color = Color.WHITE
	var color_fill:   Color = Color.TRANSPARENT

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w  := size.x
		var h  := size.y
		var bw := border_w
		# Slant length — needed for perpendicular inset on the angled edges.
		var L  := sqrt(taper * taper + h * h)

		# Outer (silver) trapezoid — bottom edge = full width, sides angle inward toward top.
		draw_colored_polygon(PackedVector2Array([
			Vector2(taper,     0.0),
			Vector2(w - taper, 0.0),
			Vector2(w,         h),
			Vector2(0.0,       h),
		]), color_border)

		# Inner (dark fill) — perpendicular inset on top and sides; no bottom border since
		# that edge is hidden beneath the screen boundary.  x_top and x_bot are derived by
		# intersecting the inward-offset left/right edges with the offset top/bottom edges.
		var x_top := taper + bw * (L - taper) / h  # inner x at the top corners
		var x_bot := bw * L / h                     # inner x at the bottom corners (y = h)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x_top,     bw),
			Vector2(w - x_top, bw),
			Vector2(w - x_bot, h),
			Vector2(x_bot,     h),
		]), color_fill)


## Combined speed icon for the bottom-right speed button.
##
## State 1 (play 1×): one dark triangle.
## State 2 (play 2×): one dark triangle + one gold triangle.
## State 3 (play 3×): one dark triangle + two gold triangles.
## The leftmost triangle is always dark; gold triangles indicate speed above 1×.
## When speed_text is set (e.g. "1x", "2x", "3x") and font_ref is provided,
## the text is drawn immediately to the right of the triangles in the same colour.
class _PlaySpeedIcon extends Control:
	const TRIANGLE_W: float = 15.6
	const TRIANGLE_H: float = 26.0
	const GAP:        float = 3.0
	const TEXT_GAP:   float = 5.0   # horizontal gap between last triangle and text
	const TEXT_SIZE:  int   = 18
	const COLOR_BASE: Color = Color(0.08, 0.05, 0.00, 1.0)
	const COLOR_FAST: Color = Color(1.00, 0.84, 0.00, 1.0)

	var play_speed_state: int  = 1
	var speed_text:       String = ""
	var font_ref:         Font   = null

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var count := play_speed_state   # 1, 2, or 3 triangles
		if count < 1:
			count = 1

		# Measure text width so the triangle+text group can be centred as a unit.
		var text_w := 0.0
		if speed_text != "" and font_ref != null:
			text_w = font_ref.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x

		var tri_block_w := count * TRIANGLE_W + (count - 1) * GAP
		var content_w   := tri_block_w + (TEXT_GAP + text_w if text_w > 0.0 else 0.0)
		var x_start     := (size.x - content_w) * 0.5
		var y_top       := (size.y - TRIANGLE_H) * 0.5
		var y_bot       := y_top + TRIANGLE_H
		var y_mid       := size.y * 0.5

		for i in count:
			# The leftmost triangle is always dark; additional triangles are gold to signal speed.
			var tri_color := COLOR_BASE if i == 0 else COLOR_FAST
			var x := x_start + i * (TRIANGLE_W + GAP)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x,              y_top),
				Vector2(x,              y_bot),
				Vector2(x + TRIANGLE_W, y_mid),
			]), tri_color)

		if text_w > 0.0 and font_ref != null:
			# Vertical offset: font baseline sits ~65% of font size below the top of the glyph.
			var text_x := x_start + tri_block_w + TEXT_GAP
			var text_y := y_mid + TEXT_SIZE * 0.35
			draw_string(font_ref, Vector2(text_x, text_y), speed_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, COLOR_BASE)


## Play/pause icon for the bottom-left control button.
## Always draws a right-pointing triangle AND two vertical pause bars side by side.
## The symbol representing the available action is gold; the other is gray.
##   Paused  (play_speed_state == 0): triangle is gold (press to play),  bars are gray.
##   Playing (play_speed_state != 0): triangle is gray (current state),  bars are gold (press to pause).
class _PlayPauseIcon extends Control:
	const TRI_W:     float = 15.6
	const TRI_H:     float = 26.0
	const BAR_W:     float = 6.0
	const BAR_H:     float = 26.0
	const BAR_GAP:   float = 4.0
	const INNER_GAP: float = 8.0   # gap between the triangle and the first pause bar
	const COLOR_GOLD: Color = Color(1.00, 0.84, 0.00, 1.0)
	const COLOR_GRAY: Color = Color(0.08, 0.05, 0.00, 1.0)   # same near-black as the speed button

	var play_speed_state: int = 1   # 0 = paused, non-zero = playing

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var is_paused  := play_speed_state == 0
		var tri_color  := COLOR_GOLD if is_paused  else COLOR_GRAY
		var bars_color := COLOR_GRAY if is_paused  else COLOR_GOLD

		# Centre the triangle + bars group as a single unit.
		var total_w := TRI_W + INNER_GAP + BAR_W + BAR_GAP + BAR_W
		var x0      := (size.x - total_w) * 0.5
		var y_mid   := size.y * 0.5
		var y_top_t := y_mid - TRI_H * 0.5
		var y_bot_t := y_mid + TRI_H * 0.5

		# Right-pointing triangle (left side of group).
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0,          y_top_t),
			Vector2(x0,          y_bot_t),
			Vector2(x0 + TRI_W,  y_mid),
		]), tri_color)

		# Two vertical pause bars (right side of group).
		var bar_x := x0 + TRI_W + INNER_GAP
		var bar_y := y_mid - BAR_H * 0.5
		draw_rect(Rect2(bar_x,                   bar_y, BAR_W, BAR_H), bars_color)
		draw_rect(Rect2(bar_x + BAR_W + BAR_GAP, bar_y, BAR_W, BAR_H), bars_color)


## Magnifying glass with a + (zoom-in) or − (zoom-out) symbol in the lens.
## Used as the icon inside the zoom toggle button.
class _ZoomIcon extends Control:
	var show_plus: bool = true  # true → zoom in available; false → zoom out available
	var icon_color: Color = Color(0.08, 0.05, 0.00)  # matches COLOR_GOLD_TEXT

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		# cx/cy offset the lens slightly from center so the handle (extending ~1.33r
		# to the lower-right) keeps the whole icon's visual mass centered in the button.
		var cx   := size.x * 0.46
		var cy   := size.y * 0.46
		var r    := minf(size.x, size.y) * 0.26
		var arm  := r * 0.50
		var line := maxf(4.0, r * 0.26)

		# Lens circle
		draw_arc(Vector2(cx, cy), r, 0.0, TAU, 32, icon_color, line)

		# Handle — diagonal line from the lower-right of the lens outward
		var h_start := Vector2(cx + r * 0.68, cy + r * 0.68)
		var h_end   := h_start + Vector2(r * 0.65, r * 0.65)
		draw_line(h_start, h_end, icon_color, line)

		# Horizontal bar (present for both + and −)
		draw_line(Vector2(cx - arm, cy), Vector2(cx + arm, cy), icon_color, line)
		if show_plus:
			draw_line(Vector2(cx, cy - arm), Vector2(cx, cy + arm), icon_color, line)



## Draws the outer progress ring on the Send Next Wave button.
## A solid green ring represents the full reward available; a gray arc sweeps clockwise
## from the top as enemies spawn, consuming the green to show how much reward is left.
## Sits on top of the TextureRect sprite, which provides the center play button graphic.
