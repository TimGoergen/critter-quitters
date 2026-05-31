## HubScreen.gd
## Full-screen hub overlay shown between runs.
##
## Appears after the INFESTED! flash fades. Shows the run summary (wave
## reached and Service Fees earned) alongside the player's total SF balance,
## a "Bug-Up!" button that opens the permanent upgrade screen, and a
## "Start New Job" button that begins a fresh run.
##
## Sits on CanvasLayer 15, above the HUD (layer 1) and the INFESTED overlay.
## PROCESS_MODE_ALWAYS so it stays interactive while the game tree is paused.

extends CanvasLayer

const UIFonts              = preload("res://ui/UIFonts.gd")
const PermanentUpgradeScreen = preload("res://ui/PermanentUpgradeScreen.gd")


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

const COLOR_TITLE   := Color(0.85, 0.10, 0.10, 1.0)   # red — matches INFESTED palette
const COLOR_GOLD    := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_TEXT    := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_DIM     := Color(0.55, 0.55, 0.60, 1.0)
const COLOR_PANEL   := Color(0.07, 0.07, 0.09, 0.94)
const COLOR_BORDER  := Color(0.30, 0.30, 0.35, 1.0)
const COLOR_DIVIDER := Color(0.22, 0.22, 0.26, 1.0)

# Green button palette — mirrors TrapSelectionScreen's "Start Buggin'" button.
const COLOR_BTN_GREEN        := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_BTN_GREEN_HOVER  := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_BTN_GREEN_PRESS  := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_BTN_GREEN_BORDER := Color(0.22, 0.60, 0.04, 1.0)

# Gold button palette for Bug-Up!
const COLOR_BTN_GOLD        := Color(0.22, 0.16, 0.00, 1.0)
const COLOR_BTN_GOLD_HOVER  := Color(0.30, 0.22, 0.01, 1.0)
const COLOR_BTN_GOLD_PRESS  := Color(0.14, 0.10, 0.00, 1.0)
const COLOR_BTN_GOLD_BORDER := Color(0.75, 0.55, 0.05, 1.0)

# Red button palette for Bug Out (quit the game).
const COLOR_BTN_RED        := Color(0.22, 0.03, 0.03, 1.0)
const COLOR_BTN_RED_HOVER  := Color(0.32, 0.05, 0.05, 1.0)
const COLOR_BTN_RED_PRESS  := Color(0.14, 0.01, 0.01, 1.0)
const COLOR_BTN_RED_BORDER := Color(0.80, 0.15, 0.15, 1.0)

var _sf_balance_lbl: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.service_fees_changed.connect(_on_fees_changed)


func _build_ui() -> void:
	# Full-screen dim.
	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.82)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Centred panel.
	const PW: float = 560.0
	const PH: float = 340.0
	var panel_x := (1280.0 - PW) * 0.5
	var panel_y := (600.0  - PH) * 0.5

	var panel := _make_panel(panel_x, panel_y, PW, PH)
	add_child(panel)

	var inner_w := PW - 32.0   # 16 px padding each side
	var y       := 20.0

	# "INFESTED!" title.
	var title := Label.new()
	title.text                 = "INFESTED!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position             = Vector2(16.0, y)
	title.size                 = Vector2(inner_w, 60.0)
	title.add_theme_font_override("font", UIFonts.header())
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	y += 64.0

	# Wave reached.
	var wave_lbl := Label.new()
	wave_lbl.text                 = "Wave %d reached" % GameState.current_wave
	wave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_lbl.position             = Vector2(16.0, y)
	wave_lbl.size                 = Vector2(inner_w, 28.0)
	wave_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	wave_lbl.add_theme_font_size_override("font_size", 22)
	wave_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	wave_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(wave_lbl)
	y += 32.0

	# Fees earned this run.
	var earned_lbl := Label.new()
	var earned: int = GameState.service_fees_last_run
	earned_lbl.text                 = "Service Fees earned: +%d" % earned
	earned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	earned_lbl.position             = Vector2(16.0, y)
	earned_lbl.size                 = Vector2(inner_w, 26.0)
	earned_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	earned_lbl.add_theme_font_size_override("font_size", 18)
	earned_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	earned_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(earned_lbl)
	y += 36.0

	# Divider.
	var divider := ColorRect.new()
	divider.color        = COLOR_DIVIDER
	divider.position     = Vector2(16.0, y)
	divider.size         = Vector2(inner_w, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)
	y += 16.0

	# SF balance — "Service Fees" descriptor above, icon + number below.
	var sf_desc_lbl := Label.new()
	sf_desc_lbl.text                 = "Service Fees"
	sf_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sf_desc_lbl.position             = Vector2(16.0, y)
	sf_desc_lbl.size                 = Vector2(inner_w, 20.0)
	sf_desc_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	sf_desc_lbl.add_theme_font_size_override("font_size", 13)
	sf_desc_lbl.add_theme_color_override("font_color", COLOR_DIM)
	sf_desc_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sf_desc_lbl)
	y += 20.0

	# Icon + number row — centred in the panel.
	var sf_row := HBoxContainer.new()
	sf_row.position    = Vector2(16.0, y)
	sf_row.size        = Vector2(inner_w, 32.0)
	sf_row.alignment   = BoxContainer.ALIGNMENT_CENTER
	sf_row.add_theme_constant_override("separation", 6)
	sf_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sf_row)

	var sf_icon := TextureRect.new()
	sf_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	sf_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	sf_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Height matches the label; width derives from the 80:52 bill aspect ratio.
	sf_icon.custom_minimum_size = Vector2(49, 32)
	sf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sf_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(sf_icon)

	_sf_balance_lbl = Label.new()
	_sf_balance_lbl.text                 = "%d" % GameState.service_fees
	_sf_balance_lbl.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	_sf_balance_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_sf_balance_lbl.add_theme_font_size_override("font_size", 28)
	_sf_balance_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	_sf_balance_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(_sf_balance_lbl)
	y += 32.0

	# Button row: Bug-Up! | Start New Job | Bug Out
	const BTN_H: float = 56.0
	const BTN_GAP: float = 10.0
	const BTN_W: float = (PW - 32.0 - BTN_GAP * 2.0) / 3.0

	var bugup_btn := _make_button("Bug-Up!", COLOR_BTN_GOLD, COLOR_BTN_GOLD_HOVER,
			COLOR_BTN_GOLD_PRESS, COLOR_BTN_GOLD_BORDER)
	bugup_btn.position = Vector2(16.0, y)
	bugup_btn.size     = Vector2(BTN_W, BTN_H)
	bugup_btn.pressed.connect(_on_bugup_pressed)
	panel.add_child(bugup_btn)

	var start_btn := _make_button("Start New Job", COLOR_BTN_GREEN, COLOR_BTN_GREEN_HOVER,
			COLOR_BTN_GREEN_PRESS, COLOR_BTN_GREEN_BORDER)
	start_btn.position = Vector2(16.0 + BTN_W + BTN_GAP, y)
	start_btn.size     = Vector2(BTN_W, BTN_H)
	start_btn.pressed.connect(_on_start_pressed)
	panel.add_child(start_btn)

	var bugout_btn := _make_button("Bug Out", COLOR_BTN_RED, COLOR_BTN_RED_HOVER,
			COLOR_BTN_RED_PRESS, COLOR_BTN_RED_BORDER)
	bugout_btn.position = Vector2(16.0 + (BTN_W + BTN_GAP) * 2.0, y)
	bugout_btn.size     = Vector2(BTN_W, BTN_H)
	bugout_btn.pressed.connect(_on_bugout_pressed)
	panel.add_child(bugout_btn)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_panel(px: float, py: float, pw: float, ph: float) -> Control:
	var ctrl := Control.new()
	ctrl.position     = Vector2(px, py)
	ctrl.size         = Vector2(pw, ph)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color        = COLOR_PANEL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(bg)

	# Border drawn via a StyleBoxFlat on a Panel node.
	var border := Panel.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color.TRANSPARENT
	sty.border_color = COLOR_BORDER
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(8)
	border.add_theme_stylebox_override("panel", sty)
	ctrl.add_child(border)

	return ctrl


func _make_button(label: String,
		bg: Color, hover: Color, pressed: Color, border: Color) -> Button:
	var btn := Button.new()
	btn.text       = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	for state: Array in [
		["normal",  bg],
		["hover",   hover],
		["pressed", pressed],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = border
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 12.0
		box.content_margin_right  = 12.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	return btn


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

func _on_fees_changed(new_amount: int) -> void:
	if _sf_balance_lbl != null:
		_sf_balance_lbl.text = "%d" % new_amount


func _on_bugup_pressed() -> void:
	AudioManager.play_ui("button")
	var screen := PermanentUpgradeScreen.new()
	get_tree().root.add_child(screen)


func _on_start_pressed() -> void:
	AudioManager.play_ui("button")
	GameState.service_fees_changed.disconnect(_on_fees_changed)
	get_tree().paused = false
	# queue_free() removes the HubScreen before the reload — without this the
	# dialog survives because it lives on root, not inside the Arena scene.
	queue_free()
	get_tree().reload_current_scene()


func _on_bugout_pressed() -> void:
	AudioManager.play_ui("button")
	get_tree().quit()
