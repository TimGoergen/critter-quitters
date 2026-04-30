## HUD.gd
## Minimal in-run overlay: Bug Bucks counter, wave number, Infestation bar,
## between-wave countdown splash, run-over screen, and trap type selector.
## Built procedurally — no scene file required.
##
## Top panel: single row — wave + bucks (left), infestation bar (centre),
##   EXIT + RESTART (right).
## Selector: pinned to the bottom edge, orientation-aware.
##   Landscape — single-row horizontal strip, left-aligned.
##   Portrait  — 2×2 grid strip spanning full width.

extends CanvasLayer

const Trap     = preload("res://traps/Trap.gd")
const UIFonts  = preload("res://ui/UIFonts.gd")

const COLOR_PANEL_BG    := Color(0.08, 0.08, 0.13, 0.88)
const COLOR_BAR_BG      := Color(0.15, 0.10, 0.10, 1.0)
const COLOR_BAR_FILL    := Color(0.85, 0.22, 0.22, 1.0)
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM    := Color(0.60, 0.60, 0.65, 1.0)
const COLOR_COUNTDOWN   := Color(0.85, 0.85, 0.85, 0.92)
const COLOR_INFESTED    := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_OVERLAY_BG  := Color(0.04, 0.02, 0.02, 0.82)

# Generic button style — used by Send Wave Early and Restart, not the trap selector.
const COLOR_BTN_NORMAL  := Color(0.30, 0.30, 0.30, 1.0)
const COLOR_BTN_HOVER   := Color(0.38, 0.38, 0.38, 1.0)
const COLOR_BTN_PRESSED := Color(0.22, 0.22, 0.22, 1.0)
const COLOR_BTN_BORDER  := Color(0.68, 0.68, 0.68, 1.0)

# Gold palette — used for the control buttons (EXIT, RESTART, pause, speed).
const COLOR_GOLD_BG_NORMAL  := Color(0.72, 0.55, 0.04, 1.0)
const COLOR_GOLD_BG_HOVER   := Color(0.85, 0.66, 0.06, 1.0)
const COLOR_GOLD_BG_PRESSED := Color(0.55, 0.41, 0.02, 1.0)
const COLOR_GOLD_BORDER     := Color(1.00, 0.92, 0.35, 1.0)
const COLOR_GOLD_TEXT       := Color(0.08, 0.05, 0.00, 1.0)  # near-black for contrast on gold

# Trap selector — hazard / sticker palette.
const COLOR_HAZARD_YELLOW         := Color(1.00, 0.84, 0.00, 1.0)  # active-state border
const COLOR_BTN_SHADOW            := Color(0.00, 0.00, 0.00, 0.80)  # sticker drop-shadow
# Applied to the whole button node when the player can't afford it; washes colour out.
const COLOR_UNAFFORDABLE_MODULATE := Color(0.58, 0.55, 0.52, 0.80)

# Per-trap brand colours and badge text.  Indices match Trap.Type: 0=Snap, 1=Zapper, 2=Fogger, 3=Glue.
# Colours are intentionally saturated — low-budget exterminator business-card aesthetic.
const TRAP_BRAND: Array = [
	{"normal": Color(0.52, 0.20, 0.07), "hover": Color(0.64, 0.26, 0.09), "sel": Color(0.68, 0.28, 0.10), "badge": "PRO GRADE"},
	{"normal": Color(0.07, 0.25, 0.60), "hover": Color(0.10, 0.33, 0.76), "sel": Color(0.09, 0.30, 0.68), "badge": "+-1000V"},
	{"normal": Color(0.09, 0.38, 0.18), "hover": Color(0.12, 0.48, 0.24), "sel": Color(0.11, 0.44, 0.20), "badge": "SAFE*"},
	{"normal": Color(0.50, 0.34, 0.05), "hover": Color(0.62, 0.43, 0.07), "sel": Color(0.57, 0.38, 0.06), "badge": "STICKY"},
]

# Per-trap button text: [name line, tagline format].  %d receives the cost.
const TRAP_LABELS: Array = [
	["SNAP TRAP",  "$%d  *  SINCE 1952"],
	["ZAPPER",     "$%d  *  GUARANTEED"],
	["FOGGER",     "$%d  *  MOSTLY SAFE"],
	["GLUE BOARD", "$%d  *  NO ESCAPE"],
]

const PANEL_H:          float = 72.0   # top stats bar height — matches SELECTOR_LANDSCAPE_STRIP_H
const BAR_H:            float = 14.0   # infestation bar fill height
const MARGIN:           float = 12.0   # general UI margin

# Trap selector layout — read by Arena.gd to compute usable arena area.
# SELECTOR_PANEL_W is the minimum width of each button in the landscape bottom strip.
# SELECTOR_LANDSCAPE_STRIP_H is the bottom strip height in landscape.
# SELECTOR_STRIP_H is the bottom strip height in portrait.
const SELECTOR_PANEL_W:          float = 160.0
const SELECTOR_LANDSCAPE_STRIP_H: float = 72.0
const SELECTOR_STRIP_H:           float = 88.0   # two button rows + margins

var _wave_label:        Label
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label
var _countdown_wave_label:   Label
var _countdown_number_label: Label
var _send_wave_btn:     Button
var _run_over_overlay:  Control

var _speed_btn:      Button
var _pause_btn:      Button
var _speed_pause_box: HBoxContainer  # wraps both buttons; repositioned on orientation change
var _is_fast:        bool = false
var _is_paused:      bool = false

var _selector_buttons: Array[Button] = []
# Root node of the current selector layout — freed and rebuilt on orientation change.
var _selector_root: Control = null
# Tracks the orientation at last build so we only rebuild when it flips.
var _selector_is_landscape: bool = true

# Index of the selector button currently under the mouse (-1 = none).
var _hovered_btn_idx: int = -1


func _ready() -> void:
	# Allow the HUD layer itself to process input while the tree is paused,
	# so the run-over overlay's Restart button remains clickable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	_build_ui()
	GameState.bug_bucks_changed.connect(_on_bucks_changed)
	GameState.infestation_changed.connect(_on_infestation_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.wave_countdown_changed.connect(_on_wave_countdown_changed)
	GameState.run_ended.connect(_on_run_ended)
	GameState.trap_type_selected.connect(_on_trap_type_selected)
	_on_bucks_changed(GameState.bug_bucks)
	_on_infestation_changed(GameState.infestation_level)
	_on_wave_changed(GameState.current_wave)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	# --- Top panel ---
	# Layout: [wave + bucks (left)] [infestation bar (centre, expands)] [speed + exit + restart (right)]
	var top_bg := ColorRect.new()
	top_bg.color         = COLOR_PANEL_BG
	top_bg.anchor_right  = 1.0
	top_bg.anchor_bottom = 0.0
	top_bg.offset_bottom = PANEL_H
	add_child(top_bg)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_margin.add_theme_constant_override("margin_left",   MARGIN)
	top_margin.add_theme_constant_override("margin_right",  MARGIN)
	top_margin.add_theme_constant_override("margin_top",    6)
	top_margin.add_theme_constant_override("margin_bottom", 6)
	top_bg.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 32)
	top_margin.add_child(top_row)

	# Left group: wave label then coin + amount, all on the same row as everything else.
	_wave_label = Label.new()
	_wave_label.text = "WAVE  1"
	_wave_label.add_theme_font_size_override("font_size", 54)
	_wave_label.add_theme_font_override("font", UIFonts.header())
	_wave_label.add_theme_color_override("font_color", COLOR_TEXT)
	_wave_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_wave_label)

	# Currency: coin icon kept small so the spider/web detail blurs into a clean gold disc.
	var bucks_row := HBoxContainer.new()
	bucks_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bucks_row.add_theme_constant_override("separation", 4)
	top_row.add_child(bucks_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin.png")
	coin_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.custom_minimum_size = Vector2(48, 48)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bucks_row.add_child(coin_icon)

	_bucks_label = Label.new()
	_bucks_label.text = "0"
	_bucks_label.add_theme_font_size_override("font_size", 42)
	_bucks_label.add_theme_font_override("font", UIFonts.primary_bold())
	_bucks_label.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	_bucks_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bucks_row.add_child(_bucks_label)

	# Centre: "INFESTATION" label, expanding bar track, percentage readout.
	var center_hbox := HBoxContainer.new()
	center_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_hbox.alignment             = BoxContainer.ALIGNMENT_CENTER
	center_hbox.add_theme_constant_override("separation", 8)
	top_row.add_child(center_hbox)

	var inf_label := Label.new()
	inf_label.text = "INFESTATION"
	inf_label.add_theme_font_size_override("font_size", 54)
	inf_label.add_theme_font_override("font", UIFonts.primary_bold())
	inf_label.add_theme_color_override("font_color", COLOR_INFESTED)
	inf_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_hbox.add_child(inf_label)

	var track := ColorRect.new()
	track.color                 = COLOR_BAR_BG
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	track.custom_minimum_size   = Vector2(0, BAR_H)
	center_hbox.add_child(track)

	_infestation_fill          = ColorRect.new()
	_infestation_fill.color    = COLOR_BAR_FILL
	_infestation_fill.size.y   = BAR_H
	_infestation_fill.position = Vector2.ZERO
	track.add_child(_infestation_fill)

	_infestation_label = Label.new()
	_infestation_label.text = "0%"
	_infestation_label.add_theme_font_size_override("font_size", 33)
	_infestation_label.add_theme_font_override("font", UIFonts.primary_bold())
	_infestation_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_infestation_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_hbox.add_child(_infestation_label)

	# Right: exit and restart.
	# EXIT and RESTART both restart the run for now. Future pass: EXIT returns to the
	# between-level hub; RESTART replays the current contract from wave 1.
	var right_hbox := HBoxContainer.new()
	right_hbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_hbox.add_theme_constant_override("separation", 6)
	top_row.add_child(right_hbox)

	var exit_btn := Button.new()
	exit_btn.text = "EXIT"
	exit_btn.add_theme_font_size_override("font_size", 21)
	exit_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(exit_btn)
	exit_btn.pressed.connect(_on_exit_pressed)
	right_hbox.add_child(exit_btn)

	var restart_btn := Button.new()
	restart_btn.text = "RESTART"
	restart_btn.add_theme_font_size_override("font_size", 21)
	restart_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(restart_btn)
	restart_btn.pressed.connect(_on_restart_pressed)
	right_hbox.add_child(restart_btn)

	# --- Countdown splash (upper-centre, hidden by default) ---
	# Band 0.15–0.30: "WAVE X" — bold, larger
	_countdown_wave_label = Label.new()
	_countdown_wave_label.anchor_right         = 1.0
	_countdown_wave_label.anchor_top           = 0.15
	_countdown_wave_label.anchor_bottom        = 0.30
	_countdown_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_wave_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_wave_label.add_theme_font_size_override("font_size", 62)
	_countdown_wave_label.add_theme_color_override("font_color", COLOR_COUNTDOWN)
	_countdown_wave_label.add_theme_font_override("font", UIFonts.header())
	_countdown_wave_label.visible = false
	add_child(_countdown_wave_label)

	# Band 0.30–0.45: countdown number
	_countdown_number_label = Label.new()
	_countdown_number_label.anchor_right         = 1.0
	_countdown_number_label.anchor_top           = 0.30
	_countdown_number_label.anchor_bottom        = 0.45
	_countdown_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_number_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_number_label.add_theme_font_size_override("font_size", 46)
	_countdown_number_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 0.92))
	_countdown_number_label.add_theme_font_override("font", UIFonts.header())
	_countdown_number_label.visible = false
	add_child(_countdown_number_label)

	# "Send Wave Early" button — centred in the lower half of the screen (midpoint at y=0.75),
	# hidden during waves.
	_send_wave_btn                = Button.new()
	_send_wave_btn.text           = "Send Wave Early"
	_send_wave_btn.anchor_left    = 0.30
	_send_wave_btn.anchor_right   = 0.70
	_send_wave_btn.anchor_top     = 0.70
	_send_wave_btn.anchor_bottom  = 0.80
	_send_wave_btn.add_theme_font_size_override("font_size", 18)
	_send_wave_btn.add_theme_font_override("font", UIFonts.primary())
	_send_wave_btn.visible        = false
	_apply_button_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	add_child(_send_wave_btn)

	_build_trap_selector()

	# Speed toggle and pause: wrapped in an HBoxContainer anchored to the bottom-right.
	# The container measures its own width from the buttons' content; _position_speed_btn()
	# sets the vertical bounds to align with the selector strip.
	_speed_pause_box = HBoxContainer.new()
	_speed_pause_box.alignment = BoxContainer.ALIGNMENT_END
	_speed_pause_box.add_theme_constant_override("separation", 6)
	add_child(_speed_pause_box)

	_pause_btn = Button.new()
	_pause_btn.text = "▮▮"
	_pause_btn.add_theme_font_size_override("font_size", 21)
	_pause_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_icon_button_style(_pause_btn)
	# Lock width to the wider "▮▮" state so it doesn't reflow when toggled to "▶".
	_pause_btn.custom_minimum_size = Vector2(48, 0)
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	_speed_pause_box.add_child(_pause_btn)

	_speed_btn = Button.new()
	_speed_btn.text = "▶▶ 1x"
	_speed_btn.add_theme_font_size_override("font_size", 21)
	_speed_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_speed_btn)
	_speed_btn.pressed.connect(_on_speed_btn_pressed)
	_speed_pause_box.add_child(_speed_btn)

	_position_speed_btn()

	_build_run_over_overlay()


func _build_run_over_overlay() -> void:
	# Full-screen container. Stays responsive while the tree is paused.
	_run_over_overlay = Control.new()
	_run_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_over_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_run_over_overlay.visible      = false
	add_child(_run_over_overlay)

	var bg := ColorRect.new()
	bg.color = COLOR_OVERLAY_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_over_overlay.add_child(bg)

	var infested_label := Label.new()
	infested_label.text                  = "INFESTED!"
	infested_label.anchor_right          = 1.0
	infested_label.anchor_top            = 0.30
	infested_label.anchor_bottom         = 0.55
	infested_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	infested_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	infested_label.add_theme_font_size_override("font_size", 96)
	infested_label.add_theme_color_override("font_color", COLOR_INFESTED)
	infested_label.add_theme_font_override("font", UIFonts.header())
	_run_over_overlay.add_child(infested_label)

	var btn := Button.new()
	btn.text                 = "Restart"
	btn.anchor_left          = 0.30
	btn.anchor_right         = 0.70
	btn.anchor_top           = 0.70
	btn.anchor_bottom        = 0.80
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_font_override("font", UIFonts.primary())
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	_apply_button_style(btn)
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)


func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = "%d" % amount
	_refresh_trap_selector()


func _on_infestation_changed(level: float) -> void:
	var track: Control = _infestation_fill.get_parent()
	_infestation_fill.size.x = track.size.x * level
	_infestation_label.text  = "%d%%" % roundi(level * 100.0)


func _on_wave_changed(wave: int) -> void:
	_wave_label.text = "WAVE  %d" % wave


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		_countdown_wave_label.text    = "Incoming!"
		_countdown_number_label.text  = "%d..." % seconds_remaining
		_countdown_wave_label.visible   = true
		_countdown_number_label.visible = true
		_send_wave_btn.visible          = true
	else:
		_countdown_wave_label.visible   = false
		_countdown_number_label.visible = false
		_send_wave_btn.visible          = false
		_blink_time = 0.0
		_countdown_number_label.modulate.a = 1.0


var _blink_time: float = 0.0

func _process(delta: float) -> void:
	# Countdown blink: 2 on/off cycles per second while the label is visible.
	if _countdown_number_label.visible:
		_blink_time += delta
		var on: bool = fmod(_blink_time, 1.0 / 2.0) < (1.0 / 4.0)
		_countdown_number_label.modulate.a = 1.0 if on else 0.0



## Repositions the speed/pause container to align with the selector strip.
##
## The container is anchored to the bottom-right corner and given a generous fixed width;
## ALIGNMENT_END keeps the buttons right-justified within it regardless of their content
## widths, so no manual pixel measurement is needed.  Godot resolves each button's width
## from its own minimum size (font + margins), not from any offset we supply.
##
## Landscape: vertically flush with the selector strip's inner bounds.
## Portrait:  floats above the strip, one row tall.
##
## Called after the selector is built and on every orientation change.
func _position_speed_btn() -> void:
	var box := _speed_pause_box
	box.anchor_left   = 1.0
	box.anchor_right  = 1.0
	box.anchor_top    = 1.0
	box.anchor_bottom = 1.0
	# 400px is well beyond the combined button widths; ALIGNMENT_END right-justifies the
	# buttons so the speed toggle is always flush with the right screen edge.
	box.offset_right  = 0
	box.offset_left   = -400

	if _selector_is_landscape:
		# inner margins match the MarginContainer values in _build_selector_landscape.
		box.offset_bottom = -6.0
		box.offset_top    = -(SELECTOR_LANDSCAPE_STRIP_H - 6.0)
	else:
		# Portrait selector fills the full width, so float buttons just above it.
		# Height matches one portrait selector row.
		var row_h := (SELECTOR_STRIP_H - 5.0 - 5.0 - 6.0) / 2.0
		box.offset_bottom = -(SELECTOR_STRIP_H + MARGIN)
		box.offset_top    = box.offset_bottom - row_h


func _on_speed_btn_pressed() -> void:
	_is_fast = not _is_fast
	Engine.time_scale  = 2.0 if _is_fast else 1.0
	_speed_btn.text    = "▶▶ 2x" if _is_fast else "▶▶ 1x"


func _on_pause_btn_pressed() -> void:
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	_pause_btn.text   = "▶" if _is_paused else "▮▮"


func _on_send_wave_pressed() -> void:
	GameState.wave_skip_requested.emit()


func _on_run_ended() -> void:
	Engine.time_scale = 1.0
	# Clear any player-initiated pause so the run-over overlay owns the paused state cleanly.
	_is_paused      = false
	_pause_btn.text = "▮▮"
	_run_over_overlay.visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	# Future: navigate to the between-level hub instead of restarting.
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Trap selector
# ---------------------------------------------------------------------------

func _is_landscape() -> bool:
	var vp := get_viewport().get_visible_rect().size
	return vp.x >= vp.y


## Rebuilds the selector panel when the screen flips between landscape and portrait.
func _on_viewport_resized() -> void:
	var landscape := _is_landscape()
	if landscape == _selector_is_landscape:
		return
	# Orientation changed — free the old layout and build the new one.
	_hovered_btn_idx = -1
	_selector_buttons.clear()
	if _selector_root != null and is_instance_valid(_selector_root):
		_selector_root.queue_free()
	_selector_root = null
	_build_trap_selector()
	_position_speed_btn()


func _build_trap_selector() -> void:
	_selector_is_landscape = _is_landscape()
	if _selector_is_landscape:
		_build_selector_landscape()
	else:
		_build_selector_portrait()


## Landscape: buttons in a horizontal strip pinned to the bottom-left of the screen.
## Buttons are left-aligned and sized to SELECTOR_PANEL_W each — the strip does not
## span the full screen width, leaving the right portion clear.
func _build_selector_landscape() -> void:
	var bg := ColorRect.new()
	bg.color         = COLOR_PANEL_BG
	bg.anchor_left   = 0.0
	bg.anchor_right  = 1.0
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top    = -SELECTOR_LANDSCAPE_STRIP_H
	bg.offset_bottom = 0
	add_child(bg)
	_selector_root = bg

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bg.add_child(margin)

	# Left-aligned row — buttons occupy only their minimum width, not the full strip.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size   = Vector2(SELECTOR_PANEL_W, 0.0)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.clip_contents         = false
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_font_override("font", UIFonts.primary_bold())
		btn.text = _selector_label(i)
		btn.pressed.connect(GameState.select_trap_type.bind(i))
		btn.mouse_entered.connect(_on_btn_hover_start.bind(i))
		btn.mouse_exited.connect(_on_btn_hover_end.bind(i))
		_style_selector_button(btn, i, i == GameState.selected_trap_type, _can_afford(i))
		row.add_child(btn)
		_selector_buttons.append(btn)
		_add_btn_badge(btn, i)


## Portrait: 2×2 grid of buttons pinned to the bottom edge of the screen.
## Each trap occupies one cell; the two columns fill the screen width evenly.
func _build_selector_portrait() -> void:
	var bg := ColorRect.new()
	bg.color         = COLOR_PANEL_BG
	bg.anchor_left   = 0.0
	bg.anchor_right  = 1.0
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top    = -SELECTOR_STRIP_H
	bg.offset_bottom = 0
	add_child(bg)
	_selector_root = bg

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	margin.add_theme_constant_override("margin_top",    5)
	margin.add_theme_constant_override("margin_bottom", 5)
	bg.add_child(margin)

	# 2 columns → 4 buttons become a 2×2 grid; each cell expands to fill its half.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	margin.add_child(grid)

	for i in range(4):
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		btn.clip_contents         = false
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_font_override("font", UIFonts.primary_bold())
		btn.text = _selector_label(i)
		btn.pressed.connect(GameState.select_trap_type.bind(i))
		btn.mouse_entered.connect(_on_btn_hover_start.bind(i))
		btn.mouse_exited.connect(_on_btn_hover_end.bind(i))
		_style_selector_button(btn, i, i == GameState.selected_trap_type, _can_afford(i))
		grid.add_child(btn)
		_selector_buttons.append(btn)
		_add_btn_badge(btn, i)


func _refresh_trap_selector() -> void:
	for i in range(_selector_buttons.size()):
		_style_selector_button(
			_selector_buttons[i],
			i,
			i == GameState.selected_trap_type,
			_can_afford(i)
		)


func _on_trap_type_selected(_type: int) -> void:
	_refresh_trap_selector()


# Returns two-line display text: trap name on the first line, cost + tagline on the second.
func _selector_label(type: int) -> String:
	var cost: int   = Trap.STATS[type]["cost"]
	var lines: Array = TRAP_LABELS[type]
	return lines[0] + "\n" + (lines[1] % cost)


# Returns true if the player can currently afford the given trap type.
func _can_afford(type: int) -> bool:
	return GameState.bug_bucks >= Trap.STATS[type]["cost"]


# Applies the hazard-sticker visual style to a trap selector button.
# Selected state: thick caution-yellow border + raised drop-shadow (sticker sitting proud).
# Pressed state: shadow collapses to simulate the sticker being pushed flat.
# Unaffordable state: entire button node is modulated grey (sun-bleached look).
func _style_selector_button(btn: Button, type: int, selected: bool, affordable: bool) -> void:
	var brand: Dictionary = TRAP_BRAND[type]
	var border_color := COLOR_HAZARD_YELLOW       if selected else Color(0.72, 0.72, 0.72, 1.0)
	var border_width := 4                         if selected else 2
	var shadow_size  := 3                         if selected else 2
	var shadow_off   := Vector2(3, 4)             if selected else Vector2(2, 3)

	# Normal — raised shadow gives the "sticker sitting off the surface" look.
	var box_n := StyleBoxFlat.new()
	box_n.bg_color              = brand["sel"]   if selected else brand["normal"]
	box_n.border_color          = border_color
	box_n.set_border_width_all(border_width)
	box_n.set_corner_radius_all(6)
	box_n.shadow_color          = COLOR_BTN_SHADOW
	box_n.shadow_size           = shadow_size
	box_n.shadow_offset         = shadow_off
	box_n.content_margin_left   = 10.0
	box_n.content_margin_right  = 10.0
	box_n.content_margin_top    = 5.0
	box_n.content_margin_bottom = 5.0
	btn.add_theme_stylebox_override("normal", box_n)

	# Hover — brighter background, same border and shadow.
	var box_h := StyleBoxFlat.new()
	box_h.bg_color              = brand["hover"]
	box_h.border_color          = border_color
	box_h.set_border_width_all(border_width)
	box_h.set_corner_radius_all(6)
	box_h.shadow_color          = COLOR_BTN_SHADOW
	box_h.shadow_size           = shadow_size
	box_h.shadow_offset         = shadow_off
	box_h.content_margin_left   = 10.0
	box_h.content_margin_right  = 10.0
	box_h.content_margin_top    = 5.0
	box_h.content_margin_bottom = 5.0
	btn.add_theme_stylebox_override("hover", box_h)

	# Pressed — shadow collapses; top margin grows slightly to simulate pressing in.
	var box_p := StyleBoxFlat.new()
	box_p.bg_color              = brand["sel"].darkened(0.15)
	box_p.border_color          = border_color
	box_p.set_border_width_all(border_width)
	box_p.set_corner_radius_all(6)
	box_p.shadow_color          = COLOR_BTN_SHADOW
	box_p.shadow_size           = 0
	box_p.shadow_offset         = Vector2(0, 1)
	box_p.content_margin_left   = 10.0
	box_p.content_margin_right  = 10.0
	box_p.content_margin_top    = 6.0
	box_p.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("pressed", box_p)

	# White text reads clearly on every dark saturated background.
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	# Desaturate the whole button (background, text, badge) when the player can't afford it.
	btn.modulate = Color(1.0, 1.0, 1.0, 1.0) if affordable else COLOR_UNAFFORDABLE_MODULATE


# Adds a small hazard-yellow fake-credential badge to the top-right corner of a button.
# The label is a child of the button so it moves with it, but ignores mouse input.
func _add_btn_badge(btn: Button, type: int) -> void:
	var lbl := Label.new()
	lbl.text         = TRAP_BRAND[type]["badge"]
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	# Anchor to the button's top-right corner.
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left   = -58.0
	lbl.offset_right  = -4.0
	lbl.offset_top    = 4.0
	lbl.offset_bottom = 16.0
	btn.add_child(lbl)


func _on_btn_hover_start(idx: int) -> void:
	if _hovered_btn_idx == idx:
		return  # already at hover scale — ignore re-entry caused by the scale animation shifting bounds
	_hovered_btn_idx = idx
	var btn := _selector_buttons[idx]
	btn.pivot_offset = btn.size * 0.5
	var t := create_tween()
	t.tween_property(btn, "scale", Vector2(1.042, 1.042), 0.09).set_ease(Tween.EASE_OUT)


func _on_btn_hover_end(idx: int) -> void:
	if _hovered_btn_idx == idx:
		_hovered_btn_idx = -1
	var btn := _selector_buttons[idx]
	btn.pivot_offset = btn.size * 0.5
	var t := create_tween()
	t.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08).set_ease(Tween.EASE_IN)


func _apply_gold_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_GOLD_BG_NORMAL], ["hover", COLOR_GOLD_BG_HOVER], ["pressed", COLOR_GOLD_BG_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_GOLD_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 12.0
		box.content_margin_right  = 12.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_GOLD_TEXT)


# Compact variant for icon-only buttons: 4px content margins instead of 12px.
func _apply_gold_icon_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_GOLD_BG_NORMAL], ["hover", COLOR_GOLD_BG_HOVER], ["pressed", COLOR_GOLD_BG_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_GOLD_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 4.0
		box.content_margin_right  = 4.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_GOLD_TEXT)


# Compact variant for icon-only buttons: 4px content margins instead of 12px.
func _apply_icon_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 4.0
		box.content_margin_right  = 4.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)


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
	btn.add_theme_color_override("font_color", COLOR_TEXT)
