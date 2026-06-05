## SettingsScreen.gd
## Full-screen settings overlay.
##
## Contains housekeeping actions that apply across all runs.
## Currently: Reset Progress, which wipes all persisted data to new-install defaults.
##
## Sits on CanvasLayer 25, above PermanentUpgradeScreen (layer 20).
## PROCESS_MODE_ALWAYS so it stays interactive while the game tree is paused.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

const COLOR_PANEL   := Color(0.06, 0.06, 0.10, 1.0)
const COLOR_HEADER  := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT    := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_DIM     := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_DIVIDER := Color(0.22, 0.22, 0.26, 1.0)

const COLOR_CLOSE_BG      := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_CLOSE_HOVER   := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_CLOSE_PRESS   := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_CLOSE_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

const COLOR_RESET_BG      := Color(0.30, 0.03, 0.03, 1.0)
const COLOR_RESET_HOVER   := Color(0.42, 0.05, 0.05, 1.0)
const COLOR_RESET_PRESS   := Color(0.20, 0.02, 0.02, 1.0)
const COLOR_RESET_BORDER  := Color(0.75, 0.18, 0.18, 1.0)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const HEADER_H: float = 66.0
const PADDING:  float = 24.0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## The confirmation overlay is built once and shown/hidden on demand.
var _confirm_overlay: Control = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color        = COLOR_PANEL
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_header()

	var hdr_div := ColorRect.new()
	hdr_div.color        = COLOR_DIVIDER
	hdr_div.position     = Vector2(0.0, HEADER_H)
	hdr_div.size         = Vector2(1280.0, 1.0)
	hdr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hdr_div)

	_build_body()


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header() -> void:
	var title := Label.new()
	title.text               = "SETTINGS"
	title.position           = Vector2(PADDING, 0.0)
	title.size               = Vector2(700.0, HEADER_H)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIFonts.primary_bold())
	title.add_theme_font_size_override("font_size", 39)
	title.add_theme_color_override("font_color", COLOR_HEADER)
	title.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var close_btn := Button.new()
	close_btn.text         = "Close"
	close_btn.focus_mode   = Control.FOCUS_NONE
	close_btn.position     = Vector2(1280.0 - PADDING - 130.0, (HEADER_H - 44.0) * 0.5)
	close_btn.size         = Vector2(130.0, 44.0)
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.add_theme_font_override("font", UIFonts.primary_bold())
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  COLOR_CLOSE_BG],
		["hover",   COLOR_CLOSE_HOVER],
		["pressed", COLOR_CLOSE_PRESS],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = COLOR_CLOSE_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(6.0)
		close_btn.add_theme_stylebox_override(state[0], box)
	close_btn.pressed.connect(_on_close_pressed)
	add_child(close_btn)


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------

func _build_body() -> void:
	var body_y := HEADER_H + 1.0
	var body_h := 600.0 - body_y

	# "Reset Progress" sits in the upper quarter of the body, horizontally centred.
	const BTN_W: float = 340.0
	const BTN_H: float = 72.0
	var btn_y := body_y + body_h * 0.25 - BTN_H * 0.5

	var reset_btn := Button.new()
	reset_btn.text         = "Reset Progress"
	reset_btn.focus_mode   = Control.FOCUS_NONE
	reset_btn.position     = Vector2((1280.0 - BTN_W) * 0.5, btn_y)
	reset_btn.size         = Vector2(BTN_W, BTN_H)
	reset_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	reset_btn.add_theme_font_override("font", UIFonts.primary_bold())
	reset_btn.add_theme_font_size_override("font_size", 28)
	reset_btn.add_theme_color_override("font_color", Color(0.95, 0.90, 0.90, 1.0))
	reset_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  COLOR_RESET_BG],
		["hover",   COLOR_RESET_HOVER],
		["pressed", COLOR_RESET_PRESS],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = COLOR_RESET_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(8.0)
		reset_btn.add_theme_stylebox_override(state[0], box)
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)

	# Explanatory text directly below the button.
	var desc := Label.new()
	desc.text                 = "Wipes all Service Fees, purchased upgrades, and experience — restores the game to new-install state."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.position             = Vector2(PADDING * 2.0, btn_y + BTN_H + 16.0)
	desc.size                 = Vector2(1280.0 - PADDING * 4.0, 40.0)
	desc.add_theme_font_override("font", UIFonts.primary_bold())
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", COLOR_DIM)
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	add_child(desc)


# ---------------------------------------------------------------------------
# Input blocking
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch \
			or event is InputEventMouseButton \
			or event is InputEventScreenDrag \
			or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_close_pressed() -> void:
	AudioManager.play_ui("button")
	queue_free()


func _on_reset_pressed() -> void:
	AudioManager.play_ui("button")
	if _confirm_overlay == null:
		_build_confirm_overlay()
	_confirm_overlay.visible = true


# ---------------------------------------------------------------------------
# Confirmation overlay
# ---------------------------------------------------------------------------

func _build_confirm_overlay() -> void:
	# Full-screen dim that blocks input to the settings body behind it.
	_confirm_overlay = Control.new()
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_confirm_overlay)

	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.70)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_overlay.add_child(dim)

	# Centred dialog panel — wide enough to fit the full prompt text on two lines.
	var panel := Panel.new()
	panel.anchor_left   = 0.5;  panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5;  panel.anchor_bottom = 0.5
	panel.offset_left   = -300.0;  panel.offset_right  = 300.0
	panel.offset_top    = -110.0;  panel.offset_bottom = 110.0
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color     = Color(0.10, 0.04, 0.04, 0.97)
	panel_style.border_color = Color(0.65, 0.18, 0.18, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	_confirm_overlay.add_child(panel)

	var prompt := Label.new()
	prompt.text                 = "You are about to permanently erase all progress.\nAre you sure?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	prompt.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt.offset_bottom        = -64.0   # leave room for the button row
	prompt.add_theme_font_override("font", UIFonts.primary_bold())
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_color_override("font_color", Color(0.95, 0.90, 0.90, 1.0))
	panel.add_child(prompt)

	# Button row pinned to the bottom of the panel — No on left, Yes on right.
	var btn_row := HBoxContainer.new()
	btn_row.anchor_left   = 0.0;  btn_row.anchor_right  = 1.0
	btn_row.anchor_top    = 1.0;  btn_row.anchor_bottom = 1.0
	btn_row.offset_top    = -60.0; btn_row.offset_bottom = -12.0
	btn_row.offset_left   = 20.0;  btn_row.offset_right  = -20.0
	btn_row.add_theme_constant_override("separation", 12)
	panel.add_child(btn_row)

	var no_btn := _make_confirm_button("No",
			Color(0.20, 0.20, 0.24, 1.0), Color(0.45, 0.45, 0.52, 1.0))
	no_btn.pressed.connect(_on_confirm_no)
	btn_row.add_child(no_btn)

	var yes_btn := _make_confirm_button("Yes",
			Color(0.30, 0.03, 0.03, 1.0), Color(0.70, 0.15, 0.15, 1.0))
	yes_btn.pressed.connect(_on_confirm_yes)
	btn_row.add_child(yes_btn)


func _make_confirm_button(label_text: String, bg: Color, border: Color) -> Button:
	var btn := Button.new()
	btn.text                  = label_text
	btn.focus_mode            = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.process_mode          = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.90, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state_name: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color     = bg.lightened(0.08) if state_name == "hover" else \
				(bg.darkened(0.08) if state_name == "pressed" else bg)
		box.border_color = border
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.set_content_margin_all(8.0)
		btn.add_theme_stylebox_override(state_name, box)
	return btn


func _on_confirm_no() -> void:
	AudioManager.play_ui("button")
	_confirm_overlay.visible = false


func _on_confirm_yes() -> void:
	AudioManager.play_ui("button")
	GameState.reset_all_upgrades()
	_confirm_overlay.visible = false
