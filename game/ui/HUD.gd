## HUD.gd
## In-run overlay: left trap selector panel and right info/control panel,
## flanking the arena on both sides.  Landscape-only layout.
## Built procedurally — no scene file required.
##
## Left panel (LEFT_PANEL_W wide):  vertical stack of 4 trap selector buttons.
## Right panel (RIGHT_PANEL_W wide): wave, bug bucks, infestation bar,
##   speed/pause, zoom toggle, countdown/send-wave-early, exit/restart.

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

var _wave_label:        Label
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label
var _countdown_wave_label:   Label
var _countdown_number_label: Label
var _send_wave_btn:          Button
var _send_wave_text_label:   Label   # "Send Early" / "Send Next Wave"
var _send_wave_reward_row:   HBoxContainer
var _send_wave_reward_label: Label
var _early_bonus_particles:  CPUParticles2D
var _run_over_overlay:       Control

var _speed_btn:      Button
var _speed_mult_lbl: Label
var _speed_icon_lbl: Label
var _pause_btn:      Button
var _pause_bar_icon: Control
var _exit_btn:       Button
var _restart_btn:    Button
var _zoom_btn:       Button   # toggles overview ↔ zoomed-in

var _is_fast:        bool = false
var _is_paused:      bool = false
var _countdown_active: bool = false

var _music_slider: HSlider
var _sfx_slider:   HSlider

var _selector_buttons: Array[Button] = []

var _blink_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	_build_ui()
	GameState.bug_bucks_changed.connect(_on_bucks_changed)
	GameState.infestation_changed.connect(_on_infestation_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.wave_countdown_changed.connect(_on_wave_countdown_changed)
	GameState.early_wave_bonus_awarded.connect(_on_early_bonus_awarded)
	GameState.early_send_reward_changed.connect(_on_early_send_reward_changed)
	GameState.run_ended.connect(_on_run_ended)
	GameState.trap_type_selected.connect(_on_trap_type_selected)
	GameState.zoom_state_changed.connect(_on_zoom_state_changed)
	_on_bucks_changed(GameState.bug_bucks)
	_on_infestation_changed(GameState.infestation_level)
	_on_wave_changed(GameState.current_wave)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	_build_left_panel()
	_build_right_panel()
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
		var btn := Button.new()
		btn.text                  = ""
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		btn.clip_contents         = true

		btn.pressed.connect(GameState.select_trap_type.bind(i))
		_style_selector_button(btn, i, i == GameState.selected_trap_type, _can_afford(i))
		_build_btn_content(btn, i)
		_add_btn_badge(btn, i)
		vbox.add_child(btn)
		_selector_buttons.append(btn)


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

	# --- Wave label ---
	_wave_label = Label.new()
	_wave_label.text = "WAVE  1"
	_wave_label.add_theme_font_size_override("font_size", 52)
	_wave_label.add_theme_font_override("font", UIFonts.header())
	_wave_label.add_theme_color_override("font_color", COLOR_TEXT)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_wave_label)

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
	_bucks_label.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	_bucks_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_bucks_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bucks_row.add_child(_bucks_label)

	# --- Infestation section — single bar element ---
	# The bar background is the root container; the fill grows from the left;
	# the icon and percentage are overlaid and centered vertically inside it.
	var inf_container := Control.new()
	inf_container.custom_minimum_size   = Vector2(0, 52)  # 8px taller than the 44px icon
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
	var inf_overlay := HBoxContainer.new()
	inf_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_infestation_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_infestation_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_infestation_label.add_theme_constant_override("outline_size", 3)
	_infestation_label.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_infestation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_infestation_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_infestation_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	inf_overlay.add_child(_infestation_label)

	# --- Speed + Pause ---
	var speed_pause_row := HBoxContainer.new()
	speed_pause_row.add_theme_constant_override("separation", 4)
	speed_pause_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(speed_pause_row)

	_pause_btn = Button.new()
	_pause_btn.text = ""
	_pause_btn.add_theme_font_size_override("font_size", 26)
	_pause_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_pause_btn)
	_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_pause_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	speed_pause_row.add_child(_pause_btn)

	_pause_bar_icon = _PauseBarIcon.new()
	_pause_bar_icon.target_height = UIFonts.primary_bold().get_ascent(26)
	_pause_bar_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_bar_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_btn.add_child(_pause_bar_icon)

	_speed_btn = Button.new()
	_speed_btn.text = ""
	_speed_btn.add_theme_font_size_override("font_size", 26)
	_speed_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_speed_btn)
	_speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	_speed_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_speed_btn.pressed.connect(_on_speed_btn_pressed)
	speed_pause_row.add_child(_speed_btn)

	_speed_mult_lbl = Label.new()
	_speed_mult_lbl.text                 = "1x"
	_speed_mult_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_speed_mult_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_speed_mult_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_speed_mult_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_mult_lbl.offset_left  = 8.0
	_speed_mult_lbl.offset_right = -8.0
	_speed_mult_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_speed_mult_lbl.add_theme_font_size_override("font_size", 26)
	_speed_mult_lbl.add_theme_color_override("font_color", COLOR_GOLD_TEXT)
	_speed_btn.add_child(_speed_mult_lbl)

	_speed_icon_lbl = Label.new()
	_speed_icon_lbl.text                 = "▶▶"
	_speed_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_speed_icon_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_speed_icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_icon_lbl.offset_left  = 8.0
	_speed_icon_lbl.offset_right = -8.0
	_speed_icon_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_speed_icon_lbl.add_theme_font_size_override("font_size", 26)
	_speed_icon_lbl.add_theme_color_override("font_color", COLOR_GOLD_TEXT)
	_speed_btn.add_child(_speed_icon_lbl)

	# --- Zoom toggle ---
	_zoom_btn = Button.new()
	_zoom_btn.text = "ZOOM"
	_zoom_btn.add_theme_font_size_override("font_size", 26)
	_zoom_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_zoom_btn)
	_zoom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_btn.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_zoom_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_zoom_btn.pressed.connect(_on_zoom_btn_pressed)
	vbox.add_child(_zoom_btn)

	_build_early_bonus_particles()

	# --- Send Wave button — fills all remaining vbox space. ---
	# The countdown labels live inside this button so they always share the same
	# visual region.  btn_vbox is ALIGNMENT_CENTER so when the countdown labels
	# are hidden the action/reward rows remain vertically centered.
	_send_wave_btn = Button.new()
	_send_wave_btn.text = ""
	_send_wave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_wave_btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_send_wave_btn.custom_minimum_size   = Vector2(0, 70)
	_apply_send_wave_btn_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	vbox.add_child(_send_wave_btn)

	var btn_vbox := VBoxContainer.new()
	btn_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_vbox.offset_left   = 8.0
	btn_vbox.offset_right  = -8.0
	btn_vbox.offset_top    = 4.0
	btn_vbox.offset_bottom = -4.0
	btn_vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 4)
	btn_vbox.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	# clip_contents prevents wide reward numbers from rendering outside the button.
	btn_vbox.clip_contents = true
	_send_wave_btn.add_child(btn_vbox)

	# Countdown section — "Incoming!" + flashing seconds, always present in the
	# layout but invisible (modulate.a = 0) when no wave is due.  Using modulate
	# instead of visible keeps the labels' height reserved so the action/reward
	# rows below never shift position when the countdown appears or disappears.
	_countdown_wave_label = Label.new()
	_countdown_wave_label.text               = "INCOMING"
	_countdown_wave_label.add_theme_font_size_override("font_size", 27)
	_countdown_wave_label.add_theme_color_override("font_color", COLOR_INCOMING)
	_countdown_wave_label.add_theme_color_override("font_shadow_color", COLOR_COUNTDOWN_SHADOW)
	_countdown_wave_label.add_theme_constant_override("shadow_offset_x", 1)
	_countdown_wave_label.add_theme_constant_override("shadow_offset_y", 1)
	_countdown_wave_label.add_theme_font_override("font", UIFonts.header())
	_countdown_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_wave_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_countdown_wave_label.modulate.a          = 0.0
	btn_vbox.add_child(_countdown_wave_label)

	_countdown_number_label = Label.new()
	_countdown_number_label.add_theme_font_size_override("font_size", 18)
	_countdown_number_label.add_theme_color_override("font_color", COLOR_COUNTDOWN)
	_countdown_number_label.add_theme_color_override("font_shadow_color", COLOR_COUNTDOWN_SHADOW)
	_countdown_number_label.add_theme_constant_override("shadow_offset_x", 1)
	_countdown_number_label.add_theme_constant_override("shadow_offset_y", 1)
	_countdown_number_label.add_theme_font_override("font", UIFonts.header())
	_countdown_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_number_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_countdown_number_label.modulate.a          = 0.0
	btn_vbox.add_child(_countdown_number_label)

	# Action row — pest icon + "Send Early" / "Send Next Wave" text.
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
	_send_wave_text_label.text         = "Send Early"
	_send_wave_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_send_wave_text_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_text_label.add_theme_font_size_override("font_size", 18)
	_send_wave_text_label.add_theme_color_override("font_color", COLOR_TEXT)
	top_row.add_child(_send_wave_text_label)

	# Reward row — coin icon + gold amount earned for sending early.
	# Hidden when the reward is zero (no early bonus available).
	_send_wave_reward_row         = HBoxContainer.new()
	_send_wave_reward_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	_send_wave_reward_row.add_theme_constant_override("separation", 4)
	_send_wave_reward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_row.modulate.a   = 0.0
	btn_vbox.add_child(_send_wave_reward_row)
	var bot_row := _send_wave_reward_row

	var btn_coin_icon := TextureRect.new()
	btn_coin_icon.texture             = load("res://assets/bug_buck_coin.png") as Texture2D
	btn_coin_icon.custom_minimum_size = Vector2(22, 22)
	btn_coin_icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	btn_coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	btn_coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	bot_row.add_child(btn_coin_icon)

	_send_wave_reward_label = Label.new()
	_send_wave_reward_label.text                = "0"
	_send_wave_reward_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_send_wave_reward_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_send_wave_reward_label.add_theme_font_override("font", UIFonts.primary_bold())
	_send_wave_reward_label.add_theme_font_size_override("font_size", 20)
	_send_wave_reward_label.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	bot_row.add_child(_send_wave_reward_label)

	# --- Volume controls ---
	_music_slider = _build_volume_row(vbox, "MUS")
	_sfx_slider   = _build_volume_row(vbox, "SFX")
	_load_volume_settings()
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	# --- Exit + Restart ---
	# In the vbox like every other button row so the vbox separation constant
	# controls the gap above it consistently.
	var exit_restart_row := HBoxContainer.new()
	exit_restart_row.add_theme_constant_override("separation", 4)
	exit_restart_row.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(exit_restart_row)

	_exit_btn = Button.new()
	_exit_btn.text = "EXIT"
	_exit_btn.add_theme_font_size_override("font_size", 24)
	_exit_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_exit_btn)
	_exit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exit_btn.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_exit_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_exit_btn.pressed.connect(_on_exit_pressed)
	exit_restart_row.add_child(_exit_btn)

	_restart_btn = Button.new()
	_restart_btn.text = "RESTART"
	_restart_btn.add_theme_font_size_override("font_size", 24)
	_restart_btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_gold_button_style(_restart_btn)
	_restart_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restart_btn.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_restart_btn.custom_minimum_size   = Vector2(0, RIGHT_BTN_H)
	_restart_btn.pressed.connect(_on_restart_pressed)
	exit_restart_row.add_child(_restart_btn)


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
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_font_override("font", UIFonts.primary())
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	_apply_button_style(btn)
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)


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
	_wave_label.text = "WAVE  %d" % wave
	if not _countdown_number_label.visible:
		_send_wave_text_label.text = "Send Next Wave"
		# Reward label is driven by early_send_reward_changed — no update needed here.


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		# Between-wave countdown — button sends the wave early for a time-based bonus.
		# "INCOMING" flashes; the number label is kept in layout (for space) but never shown.
		_countdown_wave_label.modulate.a = 1.0
		_countdown_active                = true
		_send_wave_text_label.text       = "Send Early"
		_send_wave_reward_label.text     = "%d" % (seconds_remaining * GameState.early_wave_bonus_rate)
		_blink_time = 0.0
	else:
		# Wave launched — hide the countdown, switch button to "Send Next Wave".
		# Reward label is driven by early_send_reward_changed as enemies spawn.
		_countdown_wave_label.modulate.a = 0.0
		_countdown_active                = false
		_blink_time = 0.0
		_send_wave_text_label.text = "Send Next Wave"


func _process(delta: float) -> void:
	if _countdown_active:
		_blink_time += delta
		var on: bool = fmod(_blink_time, 1.0 / 2.0) < (1.0 / 4.0)
		_countdown_wave_label.modulate.a = 1.0 if on else 0.0


func _on_zoom_btn_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.zoom_toggle_requested.emit()


func _on_zoom_state_changed(is_zoomed: bool) -> void:
	_zoom_btn.text = "OVERVIEW" if is_zoomed else "ZOOM"


func _on_viewport_resized() -> void:
	pass   # panels are anchored — they resize automatically


func _on_speed_btn_pressed() -> void:
	AudioManager.play_ui("button")
	_is_fast = not _is_fast
	Engine.time_scale    = 2.0 if _is_fast else 1.0
	_speed_mult_lbl.text = "2x" if _is_fast else "1x"
	_speed_icon_lbl.text = "▶"  if _is_fast else "▶▶"


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
	for i in range(_selector_buttons.size()):
		_style_selector_button(
			_selector_buttons[i],
			i,
			i == GameState.selected_trap_type,
			_can_afford(i)
		)


func _on_trap_type_selected(_type: int) -> void:
	_refresh_trap_selector()


## Returns the path where a trap's button image should live.
## The file may not exist yet — callers check ResourceLoader.exists() first.
func _trap_image_path(type: int) -> String:
	match type:
		0: return "res://assets/traps/snap_trap.png"
		1: return "res://assets/traps/zapper.png"
		2: return "res://assets/traps/fogger.png"
		3: return "res://assets/traps/glue_board.png"
	return ""


## Builds the internal layout of a trap selector button:
##   top area  — live SubViewport rendering the trap from directly above
##   name row  — trap name centred below the image
##   cost row  — bug bucks coin icon + numeric cost in gold, centred
## All child nodes carry MOUSE_FILTER_IGNORE so clicks reach the Button.
func _build_btn_content(btn: Button, type: int) -> void:
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left",   6)
	inner.add_theme_constant_override("margin_right",  6)
	inner.add_theme_constant_override("margin_top",    6)
	inner.add_theme_constant_override("margin_bottom", 6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 4)
	cvbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cvbox.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	inner.add_child(cvbox)

	# Image area — brand-coloured background with a live 3D sub-viewport on top.
	# The sub-viewport renders the actual trap visual from an orthographic
	# top-down camera, so the icon exactly matches what appears in the arena.
	# All trap materials are SHADING_MODE_UNSHADED, so no lighting is needed.
	var img_area := Control.new()
	img_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img_area.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	img_area.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(img_area)

	# SubViewport — own_world_3d isolates it from the main scene so only the
	# trap is rendered; transparent_bg lets the button's own background show through.
	var svp := SubViewport.new()
	svp.size                      = Vector2i(180, 180)
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Orthographic camera looking straight down. size=2.2 gives ~15% margin
	# around the 1.9-cell trap footprint on all sides.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 2.2
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	# Trap in preview mode — spawns the full visual without combat state.
	# Range indicator is deferred-hidden so it does not clutter the icon.
	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(type as Trap.TrapType)
	svp.add_child(trap_preview)
	trap_preview.call_deferred("hide_range_indicator")

	# SubViewportContainer stretches the sub-viewport to fill the available area.
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_child(svp)
	img_area.add_child(svc)

	# Trap name
	var name_lbl := Label.new()
	name_lbl.text                  = TRAP_LABELS[type][0]
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(name_lbl)

	# Cost row — coin icon + numeric amount in gold
	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cvbox.add_child(cost_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture             = load("res://assets/bug_buck_coin.png")
	coin_icon.custom_minimum_size = Vector2(24, 24)
	coin_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(coin_icon)

	var cost_lbl := Label.new()
	cost_lbl.text                = str(Trap.STATS[type]["cost"])
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 22)
	cost_lbl.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)


func _selector_label(type: int) -> String:
	return TRAP_LABELS[type][0]


func _selector_cost_line(type: int) -> String:
	var cost: int = Trap.STATS[type]["cost"]
	return TRAP_LABELS[type][1] % cost


func _can_afford(type: int) -> bool:
	return GameState.bug_bucks >= Trap.STATS[type]["cost"]


func _style_selector_button(btn: Button, type: int, selected: bool, affordable: bool) -> void:
	var brand: Dictionary = TRAP_BRAND[type]
	var border_color := COLOR_HAZARD_YELLOW       if selected else Color(0.72, 0.72, 0.72, 1.0)
	var border_width := 4                         if selected else 2
	var shadow_size  := 3                         if selected else 2
	var shadow_off   := Vector2(3, 4)             if selected else Vector2(2, 3)

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

	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.modulate = Color(1.0, 1.0, 1.0, 1.0) if affordable else COLOR_UNAFFORDABLE_MODULATE


func _add_btn_badge(btn: Button, type: int) -> void:
	var lbl := Label.new()
	lbl.text         = TRAP_BRAND[type]["badge"]
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_color_override("font_color", COLOR_HAZARD_YELLOW)
	lbl.anchor_left   = 1.0
	lbl.anchor_right  = 1.0
	lbl.anchor_top    = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left   = -58.0
	lbl.offset_right  = -4.0
	lbl.offset_top    = 4.0
	lbl.offset_bottom = 16.0
	btn.add_child(lbl)


func _add_btn_cost_label(btn: Button, type: int, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text                  = _selector_cost_line(type)
	lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left           = 0.0
	lbl.anchor_right          = 1.0
	lbl.anchor_top            = 1.0
	lbl.anchor_bottom         = 1.0
	lbl.offset_top            = -(font_size + 8)
	lbl.offset_bottom         = -5.0
	btn.add_child(lbl)


# ---------------------------------------------------------------------------
# Button styles
# ---------------------------------------------------------------------------

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
# Pause icon
# ---------------------------------------------------------------------------

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
