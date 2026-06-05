## StartScreen.gd
## The game's opening screen. Displays the Critter Quitters van illustration as the
## title graphic, a scattered pile of business cards, and three buttons:
## "Start Buggin'", "Bug Out", and "Start in Dev Mode".
##
## "Start Buggin'" starts the game and skips the playtest config dialog.
## "Start in Dev Mode" starts the game and shows the playtest config dialog.
## Both launch buttons play the van exit animation before transitioning to Main.tscn.
##
## Extends CanvasLayer — same pattern as HUD.gd and DebugStartDialog.gd —
## so anchor-based layout resolves against the viewport.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")

const COLOR_BG     := Color(0.06, 0.06, 0.10, 1.0)
const COLOR_TEXT   := Color(0.90, 0.90, 0.90, 1.0)

const COLOR_GREEN_NORMAL  := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_GREEN_HOVER   := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_GREEN_PRESSED := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_GREEN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

const COLOR_RED_NORMAL  := Color(0.25, 0.04, 0.04, 1.0)
const COLOR_RED_HOVER   := Color(0.33, 0.07, 0.07, 1.0)
const COLOR_RED_PRESSED := Color(0.16, 0.02, 0.02, 1.0)
const COLOR_RED_BORDER  := Color(0.65, 0.18, 0.04, 1.0)

const COLOR_GRAY_NORMAL  := Color(0.18, 0.18, 0.20, 1.0)
const COLOR_GRAY_HOVER   := Color(0.26, 0.26, 0.28, 1.0)
const COLOR_GRAY_PRESSED := Color(0.12, 0.12, 0.14, 1.0)
const COLOR_GRAY_BORDER  := Color(0.55, 0.55, 0.58, 1.0)

const COLOR_SILVER_NORMAL  := Color(0.30, 0.30, 0.32, 1.0)
const COLOR_SILVER_HOVER   := Color(0.40, 0.40, 0.42, 1.0)
const COLOR_SILVER_PRESSED := Color(0.22, 0.22, 0.24, 1.0)
const COLOR_SILVER_BORDER  := Color(0.60, 0.60, 0.62, 1.0)

# Shared with HUD.gd — keeps the gear button appearance consistent across screens.
const COLOR_BTN_BORDER    := Color(0.68, 0.68, 0.68, 1.0)
const COLOR_HAZARD_YELLOW := Color(1.00, 0.84, 0.00, 1.0)

# "Contain" scaling: the van is as large as possible while fully visible.
# scale = min(screen_w / REF_W, screen_h / REF_H) — computed against the
# original 1536×1024 reference dimensions so the van's visual size stays
# constant even if the PNG file's pixel dimensions change.
const VAN_REF_W := 1536.0
const VAN_REF_H := 1024.0

# Tailpipe pixel coordinates in the source image (990 × 560).
# x is the horizontal centre of the exhaust pipe at the rear bumper;
# y is the pipe exit height (undercarriage, just above the rear bumper bottom).
const TAILPIPE_IMG_X := 875.0
const TAILPIPE_IMG_Y := 450.0

# Business card scales to 40% of viewport width, measured against the content
# rect (via get_used_rect) so transparent padding in the PNG doesn't throw off
# the size or position calculation.
const CARD_WIDTH_FRAC    := 0.24
# The top card (last drawn, highest z-order) is scaled up so it reads as the
# "featured" card sitting on top of the pile.
const TOP_CARD_SCALE_MULT := 1.50

# Four cards dropped in a pile. Each entry: [rotation_deg, x_offset_frac, y_offset_frac, brightness].
# Drawn bottom-to-top (index 0 is furthest back). Offsets are fractions of viewport size
# applied relative to the pile anchor point so the layout scales with the screen.
const _CARD_PILE: Array = [
	[  9.0, -0.08,  0.26, 0.20],
	[  5.0, -0.09,  0.10, 0.27],
	[ -7.0, -0.05,  0.14, 0.33],
	[ 13.0, -0.02, -0.13, 0.40],
	[-17.0,  0.00,  0.03, 0.80],
]

var _van:       Sprite2D
var _cards:     Array[Sprite2D] = []
var _start_btn: Button
var _quit_btn:  Button
var _dev_btn:   Button

var _settings_btn:               Button      = null
var _settings_dialog:            Control     = null
var _reset_confirm_overlay:      Control     = null
var _music_slider:               HSlider     = null
var _sfx_slider:                 HSlider     = null
var _grid_lines_overview_toggle: CheckButton = null
var _grid_lines_zoomed_toggle:   CheckButton = null


func _ready() -> void:
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if not is_instance_valid(_van):
		return
	var vp      := get_viewport().get_visible_rect().size
	var scale_f := minf(vp.x / VAN_REF_W, vp.y / VAN_REF_H)
	_van.scale    = Vector2(scale_f * 1.485, scale_f * 1.485)
	_van.position = Vector2(vp.x * 0.65, vp.y * 0.40)

	for i: int in _cards.size():
		var entry: Array  = _CARD_PILE[i]
		var card_scale    := (vp.x * CARD_WIDTH_FRAC) / _cards[i].region_rect.size.x
		var scale_mult    := TOP_CARD_SCALE_MULT if i == _cards.size() - 1 else 1.0
		_cards[i].scale    = Vector2(card_scale * scale_mult, card_scale * scale_mult)
		_cards[i].position = Vector2(
			vp.x * 0.22 + vp.x * float(entry[1]),
			vp.y * 0.32 + vp.y * float(entry[2])
		)


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# --- Background ---
	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = COLOR_BG
	add_child(bg)

	# --- Business card pile ---
	# Four cards with varying rotations and small position offsets to simulate a
	# dropped pile. region_enabled clips to get_used_rect() so transparent PNG
	# padding is excluded from scale and position math.
	var card_tex:  Texture2D = load("res://assets/BusinessCard.png")
	var used_rect            := card_tex.get_image().get_used_rect()
	var card_scale           := (vp.x * CARD_WIDTH_FRAC) / used_rect.size.x
	var pile_x               := vp.x * 0.22
	var pile_y               := vp.y * 0.32
	for i: int in _CARD_PILE.size():
		var entry: Array   = _CARD_PILE[i]
		var scale_mult     := TOP_CARD_SCALE_MULT if i == _CARD_PILE.size() - 1 else 1.0
		var c              := Sprite2D.new()
		c.texture           = card_tex
		c.region_enabled    = true
		c.region_rect       = Rect2(used_rect)
		c.centered          = true
		c.rotation_degrees  = float(entry[0])
		var b: float        = float(entry[3])
		c.modulate          = Color(b, b, b, 1.0)
		c.scale             = Vector2(card_scale * scale_mult, card_scale * scale_mult)
		c.position          = Vector2(pile_x + vp.x * float(entry[1]), pile_y + vp.y * float(entry[2]))
		_cards.append(c)
		add_child(c)

	# --- Van illustration ---
	# z_index = 1 guarantees the van renders above all z_index = 0 nodes
	# (cards, exhaust puffs) regardless of scene-tree position, including
	# while it drives left over the card pile during the exit animation.
	var van_tex: Texture2D = load("res://assets/van.png")
	_van          = Sprite2D.new()
	_van.texture  = van_tex
	_van.centered = true
	_van.z_index  = 1
	var scale_f   := minf(vp.x / VAN_REF_W, vp.y / VAN_REF_H)
	_van.scale    = Vector2(scale_f * 1.485, scale_f * 1.485)
	_van.position = Vector2(vp.x * 0.65, vp.y * 0.40)
	add_child(_van)

	# --- Buttons: three across, centred as a group ---
	# Start Buggin' and Bug Out are the primary player actions (25% wide each).
	# Start in Dev Mode is a narrower secondary button (17% wide) on the right.
	# Layout: [0.14 ── 0.39] [0.41 ── 0.66] [0.68 ── 0.85] — centred around 0.495.
	_start_btn = _make_icon_button("Start New Service Contract", "res://assets/uninfested.png", true)
	_start_btn.anchor_left   = 0.14
	_start_btn.anchor_right  = 0.39
	_start_btn.anchor_top    = 0.82
	_start_btn.anchor_bottom = 0.93
	_start_btn.z_index       = 2   # above van (z=1) and exhaust puffs (z=0)
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_quit_btn = _make_icon_button("Exit", "res://assets/infestation_level.png", false)
	_quit_btn.anchor_left   = 0.41
	_quit_btn.anchor_right  = 0.66
	_quit_btn.anchor_top    = 0.82
	_quit_btn.anchor_bottom = 0.93
	_quit_btn.z_index       = 2
	_quit_btn.pressed.connect(_on_quit_pressed)
	add_child(_quit_btn)

	_dev_btn = _make_dev_button()
	_dev_btn.anchor_left   = 0.68
	_dev_btn.anchor_right  = 0.85
	_dev_btn.anchor_top    = 0.82
	_dev_btn.anchor_bottom = 0.93
	_dev_btn.z_index       = 2
	_dev_btn.pressed.connect(_on_dev_pressed)
	add_child(_dev_btn)

	_build_settings_button()
	_build_settings_dialog()


# ---------------------------------------------------------------------------
# Settings button and dialog
# ---------------------------------------------------------------------------

## Adds the gear icon button anchored to the top-right corner of the screen,
## matching the exact position it occupies in the arena HUD's right panel.
##
## HUD geometry reproduced here:
##   Right panel = 242 px wide, screen-edge margin = 24 px, top margin = 34 px.
##   Top row: zoom button (3 parts) + settings button (2 parts) with 4 px gap.
##   Content width = 242 − 48 = 194 px.  Settings share = (194 − 4) × 2/5 = 76 px.
##   → button spans [viewport_right − 100, viewport_right − 24], y [34, 94].
func _build_settings_button() -> void:
	_settings_btn = Button.new()
	_settings_btn.text          = ""
	_settings_btn.focus_mode    = Control.FOCUS_NONE
	_settings_btn.anchor_left   = 1.0
	_settings_btn.anchor_right  = 1.0
	_settings_btn.anchor_top    = 0.0
	_settings_btn.anchor_bottom = 0.0
	_settings_btn.offset_left   = -100.0
	_settings_btn.offset_right  = -24.0
	_settings_btn.offset_top    = 34.0
	_settings_btn.offset_bottom = 94.0
	_settings_btn.z_index       = 3   # above van (z=1) and buttons (z=2)
	_apply_gear_button_style(_settings_btn)
	_settings_btn.pressed.connect(_on_settings_btn_pressed)

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
	add_child(_settings_btn)


## Builds the full-screen settings overlay.
##
## Uses a pure container-based layout (root VBoxContainer with PRESET_FULL_RECT
## inside the Panel) so every element sizes itself at layout time.  Absolute
## position/size on VBoxContainer children of a Panel is unreliable in Godot 4
## because the Panel's own size resolves after construction — only anchor-based
## children (like the Close button in the first version) render correctly.
##
## Layout:  header row (60 px min) | divider | content row (expand) | divider | footer row (80 px min)
## Content: left VBox (expand) | 1 px divider | right VBox (expand)
func _build_settings_dialog() -> void:
	_settings_dialog = Control.new()
	_settings_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_dialog.visible      = false
	_settings_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_dialog.z_index      = 10   # above van (1) and all buttons (2/3)
	add_child(_settings_dialog)

	const HEADER_H: float = 60.0
	const FOOTER_H: float = 80.0
	const PADDING:  float = 32.0
	const DIVIDER_COL := Color(0.22, 0.22, 0.30, 1.0)

	# Dark panel fills the entire overlay.
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sty := StyleBoxFlat.new()
	panel_sty.bg_color = Color(0.06, 0.08, 0.14, 1.0)
	panel_sty.set_border_width_all(0)
	panel.add_theme_stylebox_override("panel", panel_sty)
	_settings_dialog.add_child(panel)

	# Root VBoxContainer fills the panel — all layout flows through containers
	# so sizes resolve correctly at runtime regardless of construction order.
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)

	# ── Header ──────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, HEADER_H)
	header.add_theme_constant_override("separation", 0)
	root.add_child(header)

	var title_margin := MarginContainer.new()
	title_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_margin.add_theme_constant_override("margin_left", int(PADDING))
	header.add_child(title_margin)

	var title_lbl := Label.new()
	title_lbl.text               = "SETTINGS"
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_override("font", UIFonts.header())
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_margin.add_child(title_lbl)

	var close_margin := MarginContainer.new()
	close_margin.add_theme_constant_override("margin_right",  int(PADDING))
	close_margin.add_theme_constant_override("margin_top",    int((HEADER_H - 44.0) * 0.5))
	close_margin.add_theme_constant_override("margin_bottom", int((HEADER_H - 44.0) * 0.5))
	header.add_child(close_margin)

	var close_btn := Button.new()
	close_btn.text                = "Close"
	close_btn.focus_mode          = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(130.0, 44.0)
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
	close_margin.add_child(close_btn)

	# ── Header divider ────────────────────────────────────────────────────────
	var hdr_div := ColorRect.new()
	hdr_div.color                 = DIVIDER_COL
	hdr_div.custom_minimum_size   = Vector2(0.0, 1.0)
	hdr_div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_div.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	root.add_child(hdr_div)

	# ── Content row ──────────────────────────────────────────────────────────
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	root.add_child(content)

	# Left column: AUDIO
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 0)
	content.add_child(left_col)

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

	# Column divider
	var col_div := ColorRect.new()
	col_div.color               = DIVIDER_COL
	col_div.custom_minimum_size = Vector2(1.0, 0.0)
	col_div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_div.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	content.add_child(col_div)

	# Right column: DISPLAY
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 0)
	content.add_child(right_col)

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

	# ── Footer divider + footer ───────────────────────────────────────────────
	var ftr_div := ColorRect.new()
	ftr_div.color                 = DIVIDER_COL
	ftr_div.custom_minimum_size   = Vector2(0.0, 1.0)
	ftr_div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ftr_div.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	root.add_child(ftr_div)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0.0, FOOTER_H)
	footer.add_theme_constant_override("separation", 0)
	root.add_child(footer)

	var footer_pad := MarginContainer.new()
	footer_pad.add_theme_constant_override("margin_left",   int(PADDING))
	footer_pad.add_theme_constant_override("margin_top",    int((FOOTER_H - 50.0) * 0.5))
	footer_pad.add_theme_constant_override("margin_bottom", int((FOOTER_H - 50.0) * 0.5))
	footer.add_child(footer_pad)

	var reset_btn := Button.new()
	reset_btn.text                = "Reset Progress"
	reset_btn.focus_mode          = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(200.0, 50.0)
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
	footer_pad.add_child(reset_btn)

	# Load saved values before connecting signals so the initial assignment
	# doesn't fire value_changed/toggled and re-save prematurely.
	_load_settings()
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_grid_lines_overview_toggle.toggled.connect(_on_grid_lines_overview_toggled)
	_grid_lines_zoomed_toggle.toggled.connect(_on_grid_lines_zoomed_toggled)


func _on_settings_btn_pressed() -> void:
	AudioManager.play_ui("button")
	_settings_dialog.visible = true


func _on_settings_close_pressed() -> void:
	AudioManager.play_ui("button")
	_settings_dialog.visible = false


func _on_reset_progress_pressed() -> void:
	AudioManager.play_ui("button")
	if _reset_confirm_overlay == null:
		_build_reset_confirm_overlay()
	_reset_confirm_overlay.visible = true


## Confirmation overlay — sits inside _settings_dialog so it draws above the settings panel.
## Identical structure to HUD._build_reset_confirm_overlay.
func _build_reset_confirm_overlay() -> void:
	_reset_confirm_overlay = Control.new()
	_reset_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reset_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_dialog.add_child(_reset_confirm_overlay)

	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_confirm_overlay.add_child(dim)

	var confirm_panel := Panel.new()
	confirm_panel.anchor_left   = 0.5;  confirm_panel.anchor_right  = 0.5
	confirm_panel.anchor_top    = 0.5;  confirm_panel.anchor_bottom = 0.5
	confirm_panel.offset_left   = -220.0;  confirm_panel.offset_right  = 220.0
	confirm_panel.offset_top    = -100.0;  confirm_panel.offset_bottom = 100.0
	confirm_panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	var confirm_sty := StyleBoxFlat.new()
	confirm_sty.bg_color     = Color(0.10, 0.04, 0.04, 0.97)
	confirm_sty.border_color = Color(0.65, 0.18, 0.18, 1.0)
	confirm_sty.set_border_width_all(2)
	confirm_sty.set_corner_radius_all(8)
	confirm_panel.add_theme_stylebox_override("panel", confirm_sty)
	_reset_confirm_overlay.add_child(confirm_panel)

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
	confirm_panel.add_child(prompt)

	var btn_row := HBoxContainer.new()
	btn_row.anchor_left   = 0.0;  btn_row.anchor_right  = 1.0
	btn_row.anchor_top    = 1.0;  btn_row.anchor_bottom = 1.0
	btn_row.offset_top    = -52.0; btn_row.offset_bottom = -10.0
	btn_row.offset_left   = 16.0;  btn_row.offset_right  = -16.0
	btn_row.add_theme_constant_override("separation", 8)
	confirm_panel.add_child(btn_row)

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


## Same style as the gear button in HUD._apply_gear_button_style.
func _apply_gear_button_style(btn: Button) -> void:
	for state: Array in [
		["normal",  Color(0.375, 0.375, 0.375)],
		["hover",   Color(0.475, 0.475, 0.475)],
		["pressed", Color(0.275, 0.275, 0.275)],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = COLOR_BTN_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(6)
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.focus_mode = Control.FOCUS_NONE


## Adds a colored section-title strip — identical to HUD._add_settings_section_strip.
func _add_settings_section_strip(parent: VBoxContainer, header_text: String) -> void:
	var strip := Panel.new()
	strip.custom_minimum_size  = Vector2(0.0, 44.0)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.04, 0.16, 0.12, 1.0)
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


## Builds a label + slider row — identical to HUD._build_volume_row.
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


## Builds a label + CheckButton row — identical to HUD._build_toggle_row.
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
	_save_settings()


func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	_save_settings()


func _on_grid_lines_overview_toggled(_pressed: bool) -> void:
	_save_settings()


func _on_grid_lines_zoomed_toggled(_pressed: bool) -> void:
	_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",   "music",               _music_slider.value)
	cfg.set_value("audio",   "sfx",                 _sfx_slider.value)
	cfg.set_value("display", "grid_lines_overview",  _grid_lines_overview_toggle.button_pressed)
	cfg.set_value("display", "grid_lines_zoomed",    _grid_lines_zoomed_toggle.button_pressed)
	cfg.save("user://settings.cfg")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		_music_slider.value                         = cfg.get_value("audio",   "music",               1.0)
		_sfx_slider.value                           = cfg.get_value("audio",   "sfx",                 1.0)
		_grid_lines_overview_toggle.button_pressed  = cfg.get_value("display", "grid_lines_overview",  false)
		_grid_lines_zoomed_toggle.button_pressed    = cfg.get_value("display", "grid_lines_zoomed",    true)
	AudioManager.set_music_volume(_music_slider.value)
	AudioManager.set_sfx_volume(_sfx_slider.value)


# ---------------------------------------------------------------------------

## Creates a button with an icon+label row inside, styled green (is_green=true)
## or red (is_green=false).  Mirrors the Send Wave button layout from HUD.gd.
func _make_icon_button(label_text: String, icon_path: String, is_green: bool) -> Button:
	var btn := Button.new()
	btn.text       = ""  # content provided by the child HBox, not the Button text property
	btn.focus_mode = Control.FOCUS_NONE

	if is_green:
		_apply_green_btn_style(btn)
	else:
		_apply_red_btn_style(btn)

	# Centred HBox containing the house icon and the button label.
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment   = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := TextureRect.new()
	icon.texture             = load(icon_path) as Texture2D
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text                = label_text
	lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	return btn


func _on_start_pressed() -> void:
	GameState.dev_mode  = false
	_start_btn.disabled = true
	_quit_btn.visible   = false
	_dev_btn.visible    = false
	_strip_btn_border(_start_btn, true)
	_play_van_exit()


func _on_dev_pressed() -> void:
	GameState.dev_mode = true
	_dev_btn.disabled  = true
	_start_btn.visible = false
	_quit_btn.visible  = false
	_strip_btn_border(_dev_btn, false, true)
	_play_van_exit()


func _on_quit_pressed() -> void:
	_quit_btn.disabled  = true
	_start_btn.visible  = false
	_dev_btn.visible    = false
	_strip_btn_border(_quit_btn, false)
	get_tree().quit()


func _play_van_exit() -> void:
	# Drop the settings button below z=0 so exhaust puffs (added to the
	# CanvasLayer at z=0 after this point) render on top of it.
	_settings_btn.z_index = 0

	var van_scaled_w := _van.texture.get_size().x * _van.scale.x
	# Drive the van fully off the left edge of the screen.
	var target_x := -(van_scaled_w / 2.0)

	# Schedule bursts at even *position* intervals by inverting the cubic ease-in
	# curve (pos = t^3 → t = pos^(1/3)). Without this correction, even time
	# intervals produce clumps at the start where the van is slow and gaps at
	# the end where it accelerates.
	const DRIVE_DURATION := 1.1
	const BURST_COUNT    := 13
	for i: int in BURST_COUNT:
		if i == 0:
			_spawn_exhaust_puffs()
		else:
			var pos_frac := float(i) / float(BURST_COUNT - 1)
			var delay    := pow(pos_frac, 1.0 / 3.0) * DRIVE_DURATION
			get_tree().create_timer(delay).timeout.connect(_spawn_exhaust_puffs)

	var tween := create_tween()
	tween.tween_property(_van, "position:x", target_x, DRIVE_DURATION) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_on_van_exited)


func _spawn_exhaust_puffs() -> void:
	# Puffs are added to this CanvasLayer (siblings of the van sprite) so they
	# stay in place while the van drives left, forming a lingering cloud trail.
	#
	# TAILPIPE_IMG_X/Y are the exact pixel coordinates of the tailpipe in the
	# source image. Subtracting half the image dimensions gives the offset from
	# the Sprite2D origin (image centre), then multiplied by scale to get world px.
	var tex_size  := _van.texture.get_size()
	var exhaust_x := _van.position.x + (TAILPIPE_IMG_X - tex_size.x / 2.0) * _van.scale.x
	var exhaust_y := _van.position.y + (TAILPIPE_IMG_Y - tex_size.y / 2.0) * _van.scale.y
	# 8 puffs per burst, all spawning close to the pipe — they overlap and
	# merge into a fogger-like cloud mass rather than discrete circles.
	for i: int in 8:
		var puff        := _ExhaustPuff.new()
		var angle       := randf() * TAU
		var dist        := randf_range(0.0, 18.0)
		puff.position   = Vector2(
			exhaust_x + cos(angle) * dist,
			exhaust_y + sin(angle) * dist
		)
		puff.max_radius = randf_range(76.5, 103.5)   # base 90, ±15%
		add_child(puff)


func _on_van_exited() -> void:
	# The van is now off-screen. Spawn fill puffs spread across the full viewport
	# width at the exhaust trail's height. Each puff grows until it covers the
	# entire screen from its position, creating a cloud-wipe scene transition.
	var vp        := get_viewport().get_visible_rect().size
	var exhaust_y := _van.position.y + (TAILPIPE_IMG_Y - _van.texture.get_size().y / 2.0) * _van.scale.y

	const FILL_COUNT    := 7
	const FILL_DURATION := 0.85

	for i: int in FILL_COUNT:
		var fx := (float(i) + 0.5) / float(FILL_COUNT) * vp.x
		var fy := exhaust_y + randf_range(-30.0, 30.0)
		# Each puff must reach the farthest corner of the viewport from its spawn
		# position — that guarantees no gaps regardless of where it is placed.
		var farthest := maxf(
			Vector2(fx, fy).distance_to(Vector2(0.0,   0.0)),
			maxf(
				Vector2(fx, fy).distance_to(Vector2(vp.x, 0.0)),
				maxf(
					Vector2(fx, fy).distance_to(Vector2(0.0,   vp.y)),
					Vector2(fx, fy).distance_to(Vector2(vp.x, vp.y))
				)
			)
		)
		var puff            := _FillPuff.new()
		puff.position       = Vector2(fx, fy)
		puff.target_radius  = farthest * 1.15  # 15 % overshoot so corners are fully covered
		puff.duration       = FILL_DURATION + randf_range(0.0, 0.12)
		add_child(puff)

	# Change scene after the fill animation has had time to complete.
	get_tree().create_timer(FILL_DURATION + 0.25).timeout.connect(
		func(): get_tree().change_scene_to_file("res://Main.tscn")
	)


func _apply_green_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_GREEN_NORMAL],
		["hover",   COLOR_GREEN_HOVER],
		["pressed", COLOR_GREEN_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_GREEN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _apply_red_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_RED_NORMAL],
		["hover",   COLOR_RED_HOVER],
		["pressed", COLOR_RED_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_RED_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _apply_gray_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_GRAY_NORMAL],
		["hover",   COLOR_GRAY_HOVER],
		["pressed", COLOR_GRAY_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_GRAY_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _apply_silver_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_SILVER_NORMAL],
		["hover",   COLOR_SILVER_HOVER],
		["pressed", COLOR_SILVER_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_SILVER_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


## Creates the silver "DEVmode" button.
func _make_dev_button() -> Button:
	var btn := Button.new()
	btn.text       = "DEVmode"
	btn.focus_mode = Control.FOCUS_NONE
	_apply_silver_btn_style(btn)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	return btn


## Replaces all state styleboxes on btn with a border-free version of its base color.
## Applied to the clicked button so it retains its background while the outline disappears.
func _strip_btn_border(btn: Button, is_green: bool, is_gray: bool = false) -> void:
	var bg: Color
	if is_gray:
		bg = COLOR_SILVER_NORMAL
	elif is_green:
		bg = COLOR_GREEN_NORMAL
	else:
		bg = COLOR_RED_NORMAL
	var box := StyleBoxFlat.new()
	box.bg_color              = bg
	box.set_border_width_all(0)
	box.set_corner_radius_all(6)
	box.content_margin_left   = 16.0
	box.content_margin_right  = 16.0
	box.content_margin_top    = 8.0
	box.content_margin_bottom = 8.0
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, box)


# One transient exhaust cloud puff.
#
# Designed like the in-game Fogger clouds: individual puffs are nearly
# transparent (alpha * 0.18 per puff) so a single puff barely shows, but
# 5–7 overlapping puffs in the cloud core stack up to ~0.6 effective opacity
# — a dense, cohesive mass rather than visible separate circles.
#
# Animation: quick bloom (0.15 s) → hold (0.25 s) → dissolve (0.50 s).
# Puff also drifts upward 30 px over its full lifetime, mimicking real exhaust.
class _ExhaustPuff extends Node2D:
	var max_radius: float = 90.0

	var _radius: float = 8.0
	var _alpha:  float = 0.0

	# Per-lobe layout: each entry is [offset_frac_x, offset_frac_y, radius_frac].
	# Fractions of max_radius, generated once at ready so the shape is stable
	# as the puff animates. A central blob plus irregular satellite bumps gives
	# the classic fluffy cloud silhouette instead of a smooth circle.
	var _lobes: Array = []

	const _LIFETIME   := 0.99   # grow + hold + fade — must match tween durations below
	const _DRIFT_UP   := 35.0   # upward travel in pixels
	const _DRIFT_LEFT := 18.0   # leftward drift — trails behind the departing van

	func _ready() -> void:
		# Central dominant blob.
		_lobes.append([0.0, 0.0, 0.72])
		# Six satellite lobes at irregular angles and distances.
		for i: int in 6:
			var angle := TAU * float(i) / 6.0 + randf_range(-0.45, 0.45)
			var dist  := randf_range(0.26, 0.50)
			var r     := randf_range(0.36, 0.56)
			_lobes.append([cos(angle) * dist, sin(angle) * dist, r])

		# Drift upward and slightly left.
		var dest := Vector2(position.x - _DRIFT_LEFT, position.y - _DRIFT_UP)
		create_tween() \
			.tween_property(self, "position", dest, _LIFETIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		var anim := create_tween()
		anim.tween_method(_grow, 0.0, 1.0, 0.165)   # quick bloom
		anim.tween_interval(0.275)                   # hold at full size
		anim.tween_method(_fade, 1.0, 0.0, 0.55)   # dissolve
		anim.tween_callback(queue_free)

	func _grow(t: float) -> void:
		_radius = lerp(8.0, max_radius, t)
		_alpha  = t
		queue_redraw()

	func _fade(t: float) -> void:
		_alpha  = t
		# Continue expanding during dissolve — puffs drift outward as they vanish.
		# t runs 1.0 → 0.0, so radius runs max_radius → max_radius * 1.8.
		_radius = lerp(max_radius * 1.8, max_radius, t)
		queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.0:
			return
		# Each lobe is a semi-transparent circle offset from the puff centre.
		# Low per-lobe alpha (0.07) lets the ~7 lobes across 8 overlapping puffs
		# stack to ~0.55 effective opacity in the cloud core without looking painted.
		for lobe: Array in _lobes:
			var offset := Vector2(float(lobe[0]) * _radius, float(lobe[1]) * _radius)
			var r: float = float(lobe[2]) * _radius
			draw_circle(offset, r, Color(0.82, 0.82, 0.85, _alpha * 0.07))


# One exhaust puff that expands to fill its section of the screen without fading.
# Spawned after the van exits to create a cloud-wipe scene transition.
# Visual structure mirrors _ExhaustPuff (same lobe layout and colour) for continuity,
# but uses a higher per-lobe alpha so multiple overlapping puffs reach full opacity.
class _FillPuff extends Node2D:
	var target_radius: float = 600.0
	var duration:      float = 0.85

	var _radius: float = 12.0
	var _alpha:  float = 0.0
	var _lobes:  Array = []

	func _ready() -> void:
		_lobes.append([0.0, 0.0, 0.72])
		for i: int in 6:
			var angle := TAU * float(i) / 6.0 + randf_range(-0.45, 0.45)
			var dist  := randf_range(0.26, 0.50)
			var r     := randf_range(0.36, 0.56)
			_lobes.append([cos(angle) * dist, sin(angle) * dist, r])

		var anim := create_tween()
		anim.tween_method(_expand, 0.0, 1.0, duration)

	func _expand(t: float) -> void:
		# Ease-in growth: starts slow, accelerates like gas expanding under pressure.
		_radius = lerp(12.0, target_radius, t * t)
		# Reach full opacity in the first third of the animation, then stay opaque.
		_alpha  = minf(t * 3.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.0:
			return
		# Higher per-lobe alpha than _ExhaustPuff (0.16 vs 0.07): these puffs need
		# to fully obscure the screen rather than layer into a wispy cloud effect.
		for lobe: Array in _lobes:
			var offset := Vector2(float(lobe[0]) * _radius, float(lobe[1]) * _radius)
			var r: float = float(lobe[2]) * _radius
			draw_circle(offset, r, Color(0.82, 0.82, 0.85, _alpha * 0.16))
