## HUD.gd
## In-run overlay: left trap selector panel and right info/control panel,
## flanking the arena on both sides.  Landscape-only layout.
## Built procedurally — no scene file required.
##
## Left panel (LEFT_PANEL_W wide):  vertical stack of 4 trap rows.
##   Each row: static info panel (left, brand-colored) + draggable trap icon (right).
##   Press-and-hold the icon to begin drag-and-drop placement.
## Right panel (RIGHT_PANEL_W wide): wave, bug bucks, infestation bar,
##   INCOMING label, send-wave button, and a bottom row of three control buttons
##   (zoom, pause, speed).  Exit and Restart live inside the Settings dialog.

extends CanvasLayer

const Trap     = preload("res://traps/Trap.gd")
const UIFonts  = preload("res://ui/UIFonts.gd")

const COLOR_PANEL_BG    := Color(0.144, 0.144, 0.235, 0.88)
const COLOR_BAR_BG      := Color(0.28, 0.28, 0.28, 1.0)
const COLOR_BAR_FILL    := Color(0.85, 0.22, 0.22, 1.0)
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM    := Color(0.60, 0.60, 0.65, 1.0)
const COLOR_COUNTDOWN        := Color(1.00, 1.00, 1.00, 1.00)
const COLOR_COUNTDOWN_SHADOW := Color(0.00, 0.00, 0.00, 0.70)
const COLOR_INCOMING         := Color(0.90, 0.15, 0.15, 1.00)
const COLOR_INFESTED    := Color(0.85, 0.10, 0.10, 1.0)
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
	{"normal": Color(0.50, 0.34, 0.05), "hover": Color(0.62, 0.43, 0.07), "sel": Color(0.57, 0.38, 0.06), "badge": "STICKY"},
]

const TRAP_LABELS: Array = [
	["SNAP TRAP",  "$%d  *  SINCE 1952"],
	["ZAPPER",     "$%d  *  GUARANTEED"],
	["FOGGER",     "$%d  *  MOSTLY SAFE"],
	["GLUE BOARD", "$%d  *  NO ESCAPE"],
]

# Panel dimensions — read by Arena.gd to compute the usable arena area.
const LEFT_PANEL_W:   float = 220.0
const RIGHT_PANEL_W:  float = 220.0
const ARENA_MARGIN_PX: float = 4.0

const MARGIN: float = 10.0             # inner padding for both panels
const SCREEN_EDGE_MARGIN: float = 24.0 # extra inset on the screen-edge side and top/bottom to clear rounded corners
const RIGHT_BTN_H: float = 52.0        # fixed height for all right-panel buttons
const INNER_BORDER_W: float = 2.0      # black separator line at the arena-facing edge of each panel

# "INCOMING" label — large semi-transparent overlay centred over the arena.
var _countdown_wave_label:   Label
var _incoming_font:          Font   # bold Bebas Neue — stored so layout can measure it

var _send_wave_btn:          Button
var _send_wave_text_label:   Label   # "Send Early" / "Send Next Wave"
var _send_wave_reward_row:   HBoxContainer
var _send_wave_reward_label: Label
var _early_bonus_particles:  CPUParticles2D
var _run_over_overlay:       Control

var _speed_btn:      Button
var _speed_icon_lbl: Label   # ">>" icon; black at 1×, bright gold at 2×
var _pause_btn:      Button
var _pause_bar_icon: Control
var _exit_btn:       Button
var _restart_btn:    Button
var _zoom_btn:       Button  # toggles overview ↔ zoomed-in
var _zoom_icon:      Control # procedural magnifying glass inside _zoom_btn

var _wave_label:        Label
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label

var _is_fast:        bool = false
var _is_paused:      bool = false
var _countdown_active: bool = false

var _music_slider: HSlider
var _sfx_slider:   HSlider

var _settings_btn:    Button  = null
var _settings_dialog: Control = null

# One Control per trap type — the right-aligned draggable icon panels.
# Used by _refresh_trap_selector() to update affordability dimming.
var _icon_controls: Array[Control] = []

# Cached reference to Arena (our parent node) for calling the drag placement API.
var _arena: Node = null

# Press-and-hold detection for drag initiation.
var _hold_trap:      int     = -1           # trap index being held; -1 = none
var _hold_time:      float   = 0.0          # seconds held so far
var _hold_start_pos: Vector2 = Vector2.ZERO # screen position of initial press

# Drag state — active while the user is dragging a trap icon toward the arena.
var _drag_active:    bool    = false
var _drag_type:      int     = -1
var _drag_cursor_pos: Vector2 = Vector2.ZERO

var _drag_overlay:   Control = null  # full-viewport pass-through container for the floating icon
var _drag_icon_ctrl: Control = null  # the floating trap image widget
var _drag_tween:     Tween   = null

# Hold must be sustained for this long (without moving ICON_CANCEL_PX) to begin a drag.
const ICON_HOLD_SEC:  float = 0.25
const ICON_CANCEL_PX: float = 10.0
# Size of the floating drag icon in pixels.
const DRAG_ICON_SIZE: float = 90.0
# Offset applied to the cursor position to place the floating icon above the finger/cursor
# so the user can see the trap and the arena cell beneath it while dragging.
const DRAG_OFFSET: Vector2 = Vector2(0.0, -110.0)

var _blink_time: float = 0.0


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
	_build_settings_dialog()   # must be after right panel so it draws on top
	_build_run_over_overlay()


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
	margin.add_theme_constant_override("margin_left",   SCREEN_EDGE_MARGIN)
	margin.add_theme_constant_override("margin_right",  SCREEN_EDGE_MARGIN)
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
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	for i in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		vbox.add_child(row)

		_build_info_panel(row, i)
		var icon_ctrl := _build_icon_panel(row, i)
		_icon_controls.append(icon_ctrl)


# ---------------------------------------------------------------------------
# Right panel — info and controls
# ---------------------------------------------------------------------------

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

	# --- Settings button — top-right corner, opens the Settings dialog.
	# Standard button: gray background, silver border, SVG gear icon centered inside.
	var settings_row := HBoxContainer.new()
	settings_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_row.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(settings_row)

	# Left spacer pushes the button to the right edge of the panel.
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_row.add_child(left_spacer)

	_settings_btn = Button.new()
	_settings_btn.text                  = ""
	_settings_btn.custom_minimum_size   = Vector2(60.0, 60.0)
	_settings_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_settings_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_apply_gear_button_style(_settings_btn)
	_settings_btn.pressed.connect(_on_settings_btn_pressed)
	settings_row.add_child(_settings_btn)

	# TextureRect child centers the SVG gear inside the button with equal inset on all sides.
	# SVG fill is #000000 so the icon is always solid black regardless of font/emoji settings.
	var gear_rect := TextureRect.new()
	gear_rect.texture      = load("res://assets/gear_icon.svg") as Texture2D
	gear_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gear_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gear_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 8 px inset on all sides keeps the gear clear of the button border.
	gear_rect.offset_left   = 8.0
	gear_rect.offset_top    = 8.0
	gear_rect.offset_right  = -8.0
	gear_rect.offset_bottom = -8.0
	gear_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_settings_btn.add_child(gear_rect)

	# --- Wave row: "WAVE" left-aligned, number right-aligned ---
	var wave_row := HBoxContainer.new()
	wave_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_row.add_theme_constant_override("separation", 0)
	vbox.add_child(wave_row)

	var wave_text_lbl := Label.new()
	wave_text_lbl.text                  = "WAVE"
	wave_text_lbl.add_theme_font_size_override("font_size", 42)
	wave_text_lbl.add_theme_font_override("font", UIFonts.header())
	wave_text_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	wave_text_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	wave_text_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	var bucks_row := HBoxContainer.new()
	bucks_row.add_theme_constant_override("separation", 4)
	vbox.add_child(bucks_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin.png")
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.custom_minimum_size = Vector2(44, 44)
	coin_icon.size_flags_vertical = Control.SIZE_FILL
	bucks_row.add_child(coin_icon)

	_bucks_label = Label.new()
	_bucks_label.text = "0"
	_bucks_label.add_theme_font_size_override("font_size", 42)
	_bucks_label.add_theme_font_override("font", UIFonts.primary_bold())
	_bucks_label.add_theme_color_override("font_color", Color(1.00, 0.82, 0.18))
	_bucks_label.size_flags_vertical    = Control.SIZE_SHRINK_CENTER
	_bucks_label.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_bucks_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	bucks_row.add_child(_bucks_label)

	# --- Infestation section — single bar element ---
	# The bar background is the root container; the fill grows from the left;
	# the icon and percentage are overlaid and centered vertically inside it.
	var inf_container := Control.new()
	inf_container.custom_minimum_size   = Vector2(0, 62)  # 20% taller than the original 52px height
	inf_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(inf_container)

	var inf_track := ColorRect.new()
	inf_track.color = COLOR_BAR_BG
	inf_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	inf_container.add_child(inf_track)

	# Fill grows rightward; anchor_bottom=1 keeps it full height automatically.
	_infestation_fill                  = ColorRect.new()
	_infestation_fill.color            = COLOR_BAR_FILL
	_infestation_fill.anchor_bottom    = 1.0
	_infestation_fill.offset_right     = 0.0
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

	# --- Send Wave button — fixed height, centered in remaining vertical space.
	# Equal expand-fill spacers above and below float it between the infestation
	# bar and the bottom button row without stretching to fill all available space.
	var send_spacer_top := Control.new()
	send_spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(send_spacer_top)

	_send_wave_btn = Button.new()
	_send_wave_btn.text = ""
	_send_wave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_wave_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_send_wave_btn.custom_minimum_size   = Vector2(0, 104)
	_apply_send_wave_btn_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	vbox.add_child(_send_wave_btn)

	var send_spacer_bottom := Control.new()
	send_spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(send_spacer_bottom)

	var btn_vbox := VBoxContainer.new()
	btn_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_vbox.offset_left   = 8.0
	btn_vbox.offset_right  = -8.0
	btn_vbox.offset_top    = 4.0
	btn_vbox.offset_bottom = -4.0
	btn_vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 6)
	btn_vbox.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_send_wave_btn.add_child(btn_vbox)

	# Action row — house icon + text label.
	var top_row := HBoxContainer.new()
	top_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 5)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_vbox.add_child(top_row)

	var game_icon := TextureRect.new()
	game_icon.texture             = load("res://assets/uninfested.png") as Texture2D
	game_icon.custom_minimum_size = Vector2(36, 36)
	game_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	game_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	game_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	game_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(game_icon)

	_send_wave_text_label              = Label.new()
	_send_wave_text_label.text         = "Send Next Wave"
	_send_wave_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_send_wave_text_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_text_label.add_theme_font_size_override("font_size", 18)
	_send_wave_text_label.add_theme_color_override("font_color", COLOR_TEXT)
	top_row.add_child(_send_wave_text_label)

	# Reward row — coin icon + bug bucks earned for sending early.
	# Hidden when the reward is zero (no early bonus available).
	_send_wave_reward_row              = HBoxContainer.new()
	_send_wave_reward_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	_send_wave_reward_row.add_theme_constant_override("separation", 4)
	_send_wave_reward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_row.modulate.a   = 0.0
	btn_vbox.add_child(_send_wave_reward_row)

	var btn_coin_icon := TextureRect.new()
	btn_coin_icon.texture             = load("res://assets/bug_buck_coin.png") as Texture2D
	btn_coin_icon.custom_minimum_size = Vector2(22, 22)
	btn_coin_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	btn_coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	btn_coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_row.add_child(btn_coin_icon)

	_send_wave_reward_label = Label.new()
	_send_wave_reward_label.text                = "0"
	_send_wave_reward_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_send_wave_reward_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_reward_label.add_theme_font_size_override("font_size", 20)
	_send_wave_reward_label.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	_send_wave_reward_row.add_child(_send_wave_reward_label)

	_build_early_bonus_particles()

	# --- Bottom 3-button row: Zoom | Pause | Speed ---
	# Three equal-width gold buttons at a fixed height.
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 4)
	bottom_row.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(bottom_row)

	# Zoom button — magnifying glass with + (zoom in) or − (zoom out).
	_zoom_btn = Button.new()
	_zoom_btn.text = ""
	_apply_gold_button_style(_zoom_btn)
	_zoom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_zoom_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_zoom_btn.pressed.connect(_on_zoom_btn_pressed)
	bottom_row.add_child(_zoom_btn)

	# _ZoomIcon fills the button face and redraws when show_plus changes.
	_zoom_icon = _ZoomIcon.new()
	_zoom_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zoom_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_btn.add_child(_zoom_icon)

	# Pause button — procedural pause bars when playing, ▶ text when paused.
	_pause_btn = Button.new()
	_pause_btn.text = ""
	_pause_btn.add_theme_font_size_override("font_size", 26)
	_pause_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_pause_btn)
	_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_pause_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	bottom_row.add_child(_pause_btn)

	_pause_bar_icon = _PauseBarIcon.new()
	_pause_bar_icon.target_height = UIFonts.primary_bold().get_ascent(26)
	_pause_bar_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_bar_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_btn.add_child(_pause_bar_icon)

	# Speed button — always shows "▶▶"; black at 1× speed, bright gold at 2×.
	_speed_btn = Button.new()
	_speed_btn.text = ""
	_apply_gold_button_style(_speed_btn)
	_speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_speed_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_speed_btn.pressed.connect(_on_speed_btn_pressed)
	bottom_row.add_child(_speed_btn)

	_speed_icon_lbl = Label.new()
	_speed_icon_lbl.text                 = "▶▶"
	_speed_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_speed_icon_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_speed_icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_icon_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_speed_icon_lbl.add_theme_font_size_override("font_size", 26)
	_speed_icon_lbl.add_theme_color_override("font_color", Color.BLACK)  # black at 1× speed
	_speed_btn.add_child(_speed_icon_lbl)


# ---------------------------------------------------------------------------
# INCOMING arena overlay
# ---------------------------------------------------------------------------

func _build_incoming_overlay() -> void:
	# Synthesise bold Bebas Neue — no bold file exists, so use FontVariation embolden.
	var fv := FontVariation.new()
	fv.base_font          = UIFonts.header()
	fv.variation_embolden = 1.2
	_incoming_font = fv

	# Large semi-transparent "INCOMING" text centred over the arena.
	# Purely visual — MOUSE_FILTER_IGNORE means it never blocks input.
	# Anchors mirror the panel pattern so the engine keeps the rect correct on
	# any viewport change (including zoom) without manual position/size writes.
	_countdown_wave_label = Label.new()
	_countdown_wave_label.text                 = "INCOMING"
	_countdown_wave_label.anchor_left          = 0.0
	_countdown_wave_label.anchor_right         = 1.0
	_countdown_wave_label.anchor_top           = 0.0
	_countdown_wave_label.anchor_bottom        = 1.0
	_countdown_wave_label.offset_left          = LEFT_PANEL_W
	_countdown_wave_label.offset_right         = -RIGHT_PANEL_W
	_countdown_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_wave_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_wave_label.add_theme_font_override("font", _incoming_font)
	# Baked-in alpha keeps the text translucent at the "on" phase of the blink.
	_countdown_wave_label.add_theme_color_override("font_color", Color(0.90, 0.15, 0.15, 0.48))
	# Counter-clockwise tilt: text rises from right to left.
	_countdown_wave_label.rotation_degrees = -10.0
	_countdown_wave_label.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	_countdown_wave_label.modulate.a       = 0.0   # hidden until countdown starts
	add_child(_countdown_wave_label)
	_update_incoming_overlay_layout()


func _update_incoming_overlay_layout() -> void:
	if _countdown_wave_label == null or _incoming_font == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var arena_w := vp_size.x - LEFT_PANEL_W - RIGHT_PANEL_W
	var arena_h := vp_size.y

	# Measure "INCOMING" at a reference size, then scale so it spans 90% of arena width.
	var ref_size : int = 200
	var measured := _incoming_font.get_string_size(
			"INCOMING", HORIZONTAL_ALIGNMENT_LEFT, -1, ref_size).x
	var font_size := int(ref_size * (arena_w * 0.9) / measured)
	_countdown_wave_label.add_theme_font_size_override("font_size", font_size)

	# Pivot at the label's centre so the tilt rotates in place over the arena.
	_countdown_wave_label.pivot_offset = Vector2(arena_w * 0.5, arena_h * 0.5)


# ---------------------------------------------------------------------------
# Run-over overlay
# ---------------------------------------------------------------------------

func _build_run_over_overlay() -> void:
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
	infested_label.text                 = "INFESTED!"
	infested_label.anchor_right         = 1.0
	infested_label.anchor_top           = 0.30
	infested_label.anchor_bottom        = 0.55
	infested_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	infested_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	infested_label.add_theme_font_size_override("font_size", 144)
	infested_label.add_theme_color_override("font_color", COLOR_INFESTED)
	infested_label.add_theme_font_override("font", UIFonts.header())
	_run_over_overlay.add_child(infested_label)

	var btn := Button.new()
	btn.text         = ""
	btn.anchor_left  = 0.30
	btn.anchor_right = 0.70
	btn.anchor_top   = 0.70
	btn.anchor_bottom = 0.80
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_send_wave_btn_style(btn)
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)

	# Inner layout mirrors the Send Next Wave button: icon + label in an HBox.
	var btn_hbox := HBoxContainer.new()
	btn_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_hbox.alignment   = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 5)
	btn_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(btn_hbox)

	var restart_icon := TextureRect.new()
	restart_icon.texture             = load("res://assets/uninfested.png") as Texture2D
	restart_icon.custom_minimum_size = Vector2(36, 36)
	restart_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	restart_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	restart_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	restart_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	btn_hbox.add_child(restart_icon)

	var restart_label := Label.new()
	restart_label.text         = "Restart"
	restart_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	restart_label.add_theme_font_override("font", UIFonts.primary_bold())
	restart_label.add_theme_font_size_override("font_size", 24)
	restart_label.add_theme_color_override("font_color", COLOR_TEXT)
	btn_hbox.add_child(restart_label)


# ---------------------------------------------------------------------------
# Settings dialog
# ---------------------------------------------------------------------------

## Builds the modal settings panel.  Hidden by default; shown when the user
## taps the van-gear button in the top-right corner of the right panel.
## The dialog lives at the CanvasLayer root so it floats above the side panels.
## Exit and Restart buttons are located here rather than on the right panel.
func _build_settings_dialog() -> void:
	_settings_dialog = Control.new()
	_settings_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_dialog.visible      = false
	# MOUSE_FILTER_STOP prevents taps on the dim area from reaching the arena.
	_settings_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_dialog)

	# Full-screen dimmer behind the panel.
	var dim        := ColorRect.new()
	dim.color       = Color(0.0, 0.0, 0.0, 0.60)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_dialog.add_child(dim)

	# Centered dialog panel — anchored to the viewport centre with fixed offsets.
	# Taller than before to accommodate the Exit/Restart row below the close button.
	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -190.0
	panel.offset_right  =  190.0
	panel.offset_top    = -155.0
	panel.offset_bottom =  155.0
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.22, 0.97)
	panel_style.border_color = Color(0.50, 0.50, 0.68, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	_settings_dialog.add_child(panel)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left",   24)
	inner.add_theme_constant_override("margin_right",  24)
	inner.add_theme_constant_override("margin_top",    18)
	inner.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(inner)

	var dialog_vbox := VBoxContainer.new()
	dialog_vbox.add_theme_constant_override("separation", 14)
	inner.add_child(dialog_vbox)

	var title := Label.new()
	title.text                 = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIFonts.header())
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	dialog_vbox.add_child(title)

	var sep := HSeparator.new()
	dialog_vbox.add_child(sep)

	# Volume sliders — class members so the existing save/load handlers still work.
	_music_slider = _build_volume_row(dialog_vbox, "MUSIC")
	_sfx_slider   = _build_volume_row(dialog_vbox, "SFX")
	_load_volume_settings()
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# X button — square, top-right corner of the panel, outside the vbox flow.
	var close_btn := Button.new()
	close_btn.text                = "X"
	close_btn.anchor_left         = 1.0
	close_btn.anchor_right        = 1.0
	close_btn.anchor_top          = 0.0
	close_btn.anchor_bottom       = 0.0
	close_btn.offset_left         = -48.0
	close_btn.offset_right        = -8.0
	close_btn.offset_top          =  8.0
	close_btn.offset_bottom       =  48.0
	close_btn.add_theme_font_override("font", UIFonts.primary_bold())
	close_btn.add_theme_font_size_override("font_size", 20)
	_apply_button_style(close_btn)
	close_btn.pressed.connect(_on_settings_close_pressed)
	panel.add_child(close_btn)

	var exit_sep := HSeparator.new()
	dialog_vbox.add_child(exit_sep)

	# Exit and Restart live in the settings dialog so the right panel stays clean.
	var exit_restart_row := HBoxContainer.new()
	exit_restart_row.add_theme_constant_override("separation", 4)
	dialog_vbox.add_child(exit_restart_row)

	_exit_btn = Button.new()
	_exit_btn.text = "EXIT"
	_exit_btn.add_theme_font_size_override("font_size", 24)
	_exit_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_exit_btn)
	_exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exit_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_exit_btn.pressed.connect(_on_exit_pressed)
	exit_restart_row.add_child(_exit_btn)

	_restart_btn = Button.new()
	_restart_btn.text = "RESTART"
	_restart_btn.add_theme_font_size_override("font_size", 24)
	_restart_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_restart_btn)
	_restart_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restart_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_restart_btn.pressed.connect(_on_restart_pressed)
	exit_restart_row.add_child(_restart_btn)


func _on_settings_btn_pressed() -> void:
	AudioManager.play_ui("button")
	_settings_dialog.visible = true


func _on_settings_close_pressed() -> void:
	AudioManager.play_ui("button")
	_settings_dialog.visible = false


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = "%d" % amount
	_refresh_trap_selector()


func _on_infestation_changed(level: float) -> void:
	var container: Control = _infestation_fill.get_parent()
	_infestation_fill.offset_right = container.size.x * level
	_infestation_label.text        = "%d%%" % roundi(level * 100.0)


func _on_wave_changed(wave: int) -> void:
	_wave_label.text = "%d" % wave  # "WAVE" is a static sibling label; only the number changes
	if not _countdown_active:
		_send_wave_text_label.text = "Send Next Wave"


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		# Between-wave countdown — reveal the INCOMING label and switch button text.
		# The label is shown by restoring full alpha; _process will blink it.
		_countdown_active                = true
		_countdown_wave_label.modulate.a = 1.0
		_send_wave_text_label.text       = "Send Early"
		_send_wave_reward_label.text     = "%d" % (seconds_remaining * GameState.early_wave_bonus_rate)
		_blink_time = 0.0
	else:
		# Wave launched — hide the INCOMING label and restore the button text.
		_countdown_active                = false
		_countdown_wave_label.modulate.a = 0.0
		_send_wave_text_label.text       = "Send Next Wave"
		_blink_time = 0.0


func _process(delta: float) -> void:
	if _countdown_active:
		_blink_time += delta
		var on: bool = fmod(_blink_time, 1.0 / 2.0) < (1.0 / 4.0)
		# Blink the INCOMING label via alpha; the button content stays solid.
		_countdown_wave_label.modulate.a = 1.0 if on else 0.0

	# Press-and-hold timer: promote to drag once the hold threshold is met.
	if _hold_trap >= 0:
		_hold_time += delta
		if _hold_time >= ICON_HOLD_SEC:
			_start_drag(_hold_trap)

	# Keep the floating drag icon centred above the cursor each frame.
	# We do this in _process (rather than only in _input) so the icon stays
	# locked to position even when the cursor is stationary.
	if _drag_active and _drag_icon_ctrl != null and is_instance_valid(_drag_icon_ctrl):
		var half := DRAG_ICON_SIZE * 0.5
		_drag_icon_ctrl.global_position = _drag_cursor_pos + DRAG_OFFSET - Vector2(half, half)


# ---------------------------------------------------------------------------
# Drag-and-drop trap placement
# ---------------------------------------------------------------------------

## Intercepts mouse/touch events when a drag is in progress, preventing them
## from reaching the arena's own input handlers.
func _input(event: InputEvent) -> void:
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
## Starts the hold timer on press; cancels it if the finger moves too far.
func _on_icon_gui_input(event: InputEvent, trap_type: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hold_trap      = trap_type
			_hold_time      = 0.0
			_hold_start_pos = event.position
		elif _hold_trap == trap_type:
			_cancel_hold()
	elif event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_hold_trap      = trap_type
			_hold_time      = 0.0
			_hold_start_pos = event.position
		elif _hold_trap == trap_type:
			_cancel_hold()
	elif _hold_trap == trap_type:
		# Cancel if the press moves more than ICON_CANCEL_PX before the hold threshold.
		var pos: Vector2
		if event is InputEventMouseMotion:
			pos = event.position
		elif event is InputEventScreenDrag:
			pos = event.position
		else:
			return
		if pos.distance_to(_hold_start_pos) > ICON_CANCEL_PX:
			_cancel_hold()


## Initiates a drag for the given trap type.
## Builds the floating overlay icon, begins the slide-in tween, and
## notifies Arena to show a ghost preview at the current cursor position.
func _start_drag(trap_type: int) -> void:
	_cancel_hold()   # clear hold state before starting drag

	if not _can_afford(trap_type):
		return

	GameState.select_trap_type(trap_type)   # so Arena knows which ghost to draw

	# Capture the icon's current screen position before building the overlay.
	var icon_rect  := _icon_controls[trap_type].get_global_rect()
	var icon_center := icon_rect.get_center()

	# Full-viewport pass-through container — MOUSE_FILTER_IGNORE so it never
	# blocks the _input() interception we do ourselves above.
	_drag_overlay = Control.new()
	_drag_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_overlay)

	# Floating trap icon — starts at the original icon position, then tweens upward.
	_drag_icon_ctrl = _build_floating_trap_icon(_drag_overlay, trap_type)
	var half := DRAG_ICON_SIZE * 0.5
	_drag_icon_ctrl.global_position = icon_center - Vector2(half, half)

	_drag_active     = true
	_drag_type       = trap_type
	_drag_cursor_pos = icon_center

	# Tell Arena to begin the ghost preview at the icon's starting position.
	_arena.begin_hud_drag(trap_type, icon_center + DRAG_OFFSET)

	# Slide the icon from its resting position to its drag position above the cursor.
	var target_pos := icon_center + DRAG_OFFSET - Vector2(half, half)
	_drag_tween = create_tween()
	_drag_tween.set_ease(Tween.EASE_OUT)
	_drag_tween.set_trans(Tween.TRANS_CUBIC)
	_drag_tween.tween_property(_drag_icon_ctrl, "global_position", target_pos, 0.15)


## Updates the cursor position and relays the placement-zone center to Arena.
func _update_drag_cursor(cursor_pos: Vector2) -> void:
	_drag_cursor_pos = cursor_pos
	# Placement zone is the center of the floating icon, which sits above the cursor.
	_arena.update_hud_drag(cursor_pos + DRAG_OFFSET)


## Clears hold timer state without starting a drag.
func _cancel_hold() -> void:
	_hold_trap = -1
	_hold_time = 0.0


## Tears down the floating overlay and resets drag state.
func _end_drag() -> void:
	if _drag_tween != null and _drag_tween.is_valid():
		_drag_tween.kill()
		_drag_tween = null
	if _drag_overlay != null and is_instance_valid(_drag_overlay):
		_drag_overlay.queue_free()
	_drag_overlay    = null
	_drag_icon_ctrl  = null
	_drag_active     = false
	_drag_type       = -1


func _on_zoom_btn_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.zoom_toggle_requested.emit()


func _on_zoom_state_changed(is_zoomed: bool) -> void:
	# When already zoomed in, the action is to zoom out — show the minus sign.
	# When in overview, the action is to zoom in — show the plus sign.
	(_zoom_icon as _ZoomIcon).show_plus = not is_zoomed
	_zoom_icon.queue_redraw()
	_update_incoming_overlay_layout()


func _on_viewport_resized() -> void:
	_update_incoming_overlay_layout()


func _on_speed_btn_pressed() -> void:
	AudioManager.play_ui("button")
	_is_fast = not _is_fast
	Engine.time_scale = 2.0 if _is_fast else 1.0
	# Icon colour signals the active speed: bright gold for 2×, black for 1×.
	_speed_icon_lbl.add_theme_color_override("font_color",
		COLOR_HAZARD_YELLOW if _is_fast else Color.BLACK)


func _on_pause_btn_pressed() -> void:
	AudioManager.play_ui("button")
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	if _is_paused:
		_pause_btn.text = "▶"
		_pause_bar_icon.hide()
	else:
		_pause_btn.text = ""
		_pause_bar_icon.show()


func _on_send_wave_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.wave_skip_requested.emit()


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
	_early_bonus_particles.scale_amount_min      = 0.125
	_early_bonus_particles.scale_amount_max      = 0.225
	_early_bonus_particles.texture               = load("res://assets/bug_buck_coin.png") as Texture2D
	add_child(_early_bonus_particles)


func _on_early_bonus_awarded(coins: int) -> void:
	_early_bonus_particles.amount   = max(1, coins / 4)
	_early_bonus_particles.position = _send_wave_btn.get_global_rect().get_center()
	_early_bonus_particles.restart()


func _on_early_send_reward_changed(amount: int) -> void:
	_send_wave_reward_row.modulate.a = 1.0 if amount > 0 else 0.0
	_send_wave_reward_label.text     = "%d" % amount


func _on_run_ended() -> void:
	Engine.time_scale = 1.0
	_is_paused        = false
	_pause_btn.text   = ""
	_pause_bar_icon.show()
	_run_over_overlay.visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	AudioManager.play_ui("button")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	AudioManager.play_ui("button")
	get_tree().quit()


# ---------------------------------------------------------------------------
# Trap selector
# ---------------------------------------------------------------------------

func _refresh_trap_selector() -> void:
	for i in range(_icon_controls.size()):
		_icon_controls[i].modulate = Color(1, 1, 1, 1) if _can_afford(i) else COLOR_UNAFFORDABLE_MODULATE


## Returns the path where a trap's button image should live.
## The file may not exist yet — callers check ResourceLoader.exists() first.
func _trap_image_path(type: int) -> String:
	match type:
		0: return "res://assets/traps/snap_trap.png"
		1: return "res://assets/traps/zapper.png"
		2: return "res://assets/traps/fogger.png"
		3: return "res://assets/traps/glue_board.png"
	return ""


## Builds the left portion of a trap row: brand-colored info panel containing
## the trap name, cost, and brand badge.  MOUSE_FILTER_STOP prevents taps from
## reaching the arena behind the panel.
func _build_info_panel(row: HBoxContainer, type: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color      = TRAP_BRAND[type]["normal"]
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color  = Color(0.72, 0.72, 0.72, 1.0)
	style.shadow_color  = COLOR_BTN_SHADOW
	style.shadow_size   = 2
	style.shadow_offset = Vector2(2, 3)

	var panel := Panel.new()
	panel.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 3.0   # 75% of the row
	panel.mouse_filter           = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", style)
	row.add_child(panel)

	# Content — left-aligned VBox centred vertically inside the panel.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	cvbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cvbox.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cvbox)

	var name_lbl := Label.new()
	name_lbl.text                 = TRAP_LABELS[type][0]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(name_lbl)

	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.alignment    = BoxContainer.ALIGNMENT_BEGIN
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(cost_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin.png")
	coin_icon.custom_minimum_size = Vector2(20, 20)
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(coin_icon)

	var cost_lbl := Label.new()
	cost_lbl.text                = str(Trap.STATS[type]["cost"])
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 20)
	cost_lbl.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	cost_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)

	# Badge — anchored to the top-right corner of the panel.
	var badge_lbl := Label.new()
	badge_lbl.text         = TRAP_BRAND[type]["badge"]
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_lbl.add_theme_font_size_override("font_size", 10)
	badge_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	badge_lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	badge_lbl.anchor_left   = 1.0
	badge_lbl.anchor_right  = 1.0
	badge_lbl.anchor_top    = 0.0
	badge_lbl.anchor_bottom = 0.0
	badge_lbl.offset_left   = -56.0
	badge_lbl.offset_right  = -4.0
	badge_lbl.offset_top    = 4.0
	badge_lbl.offset_bottom = 14.0
	panel.add_child(badge_lbl)


## Builds the right portion of a trap row: the draggable trap icon.
## The user presses and holds here to initiate drag-and-drop placement.
## Returns the Control so _icon_controls can store it for affordability updates.
func _build_icon_panel(row: HBoxContainer, type: int) -> Control:
	var icon_ctrl := Control.new()
	icon_ctrl.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	icon_ctrl.size_flags_vertical      = Control.SIZE_EXPAND_FILL
	icon_ctrl.size_flags_stretch_ratio = 1.0   # 25% of the row
	# STOP so this Control receives gui_input events for hold detection.
	icon_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(icon_ctrl)

	# No background — the trap image renders over the panel background behind it.
	# SubViewport — own_world_3d isolates it; transparent_bg shows the row bg.
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

	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(type as Trap.TrapType)
	svp.add_child(trap_preview)
	trap_preview.call_deferred("hide_range_indicator")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	icon_ctrl.gui_input.connect(_on_icon_gui_input.bind(type))

	return icon_ctrl


## Builds a floating drag icon identical to the in-panel icon, sized DRAG_ICON_SIZE.
## Adds it as a child of parent.  Used for the overlay shown during drag.
func _build_floating_trap_icon(parent: Control, type: int) -> Control:
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size = Vector2(DRAG_ICON_SIZE, DRAG_ICON_SIZE)
	icon_ctrl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon_ctrl)

	var style := StyleBoxFlat.new()
	style.bg_color      = TRAP_BRAND[type]["normal"]
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color  = Color(0.72, 0.72, 0.72, 1.0)
	style.shadow_color  = COLOR_BTN_SHADOW
	style.shadow_size   = 4
	style.shadow_offset = Vector2(3, 4)

	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.add_theme_stylebox_override("panel", style)
	icon_ctrl.add_child(bg_panel)

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

	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(type as Trap.TrapType)
	svp.add_child(trap_preview)
	trap_preview.call_deferred("hide_range_indicator")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	return icon_ctrl


func _can_afford(type: int) -> bool:
	return GameState.bug_bucks >= Trap.STATS[type]["cost"]


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
	btn.add_theme_color_override("font_color", COLOR_GOLD_TEXT)


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
	btn.add_theme_color_override("font_color", COLOR_TEXT)


# ---------------------------------------------------------------------------
# Volume controls
# ---------------------------------------------------------------------------

## Builds a compact label + slider row for one audio bus.
## Returns the HSlider so the caller can read/write its value.
func _build_volume_row(parent: VBoxContainer, label_text: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_END
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.custom_minimum_size = Vector2(32, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value             = 0.0
	slider.max_value             = 1.0
	slider.step                  = 0.01
	slider.value                 = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size   = Vector2(0, 24)
	row.add_child(slider)

	return slider


func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_music_volume(value)
	_save_volume_settings()


func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	_save_volume_settings()


func _save_volume_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", _music_slider.value)
	cfg.set_value("audio", "sfx",   _sfx_slider.value)
	cfg.save("user://settings.cfg")


func _load_volume_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	var music_vol: float = cfg.get_value("audio", "music", 1.0)
	var sfx_vol:   float = cfg.get_value("audio", "sfx",   1.0)
	_music_slider.value = music_vol
	_sfx_slider.value   = sfx_vol
	AudioManager.set_music_volume(music_vol)
	AudioManager.set_sfx_volume(sfx_vol)


# ---------------------------------------------------------------------------
# Procedural icons
# ---------------------------------------------------------------------------

## Two vertical bars drawn at the correct cap height for the pause button.
class _PauseBarIcon extends Control:
	var target_height: float = 0.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var bar_w := size.x * 0.13
		var gap   := size.x * 0.091
		var bar_h := target_height if target_height > 0.0 else size.y * 0.52
		var x0    := (size.x - bar_w * 2.0 - gap) * 0.5
		var y0    := (size.y - bar_h) * 0.5
		var color := Color(0.08, 0.05, 0.00)
		draw_rect(Rect2(x0,               y0, bar_w, bar_h), color)
		draw_rect(Rect2(x0 + bar_w + gap, y0, bar_w, bar_h), color)


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
