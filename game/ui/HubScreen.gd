## HubScreen.gd
## Full-screen hub overlay shown between runs.
##
## Appears after the INFESTED! flash fades. Shows the wave reached, a "Service
## Fees" header, and the player's total SF balance (with "+n" appended when fees
## were earned this run). Buttons: Bug-Up! (permanent upgrades), Start New Job,
## and Quit.
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
const COLOR_SILVER  := Color(0.75, 0.75, 0.80, 1.0)   # delta earned — subordinate to gold balance
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
var _sf_earned_lbl:  Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.service_fees_changed.connect(_on_fees_changed)


func _build_ui() -> void:
	# Background illustration — fills the entire screen.
	# Save the artwork as res://assets/infested_bg.png to activate this.
	var bg_tex := load("res://assets/infested_bg.PNG") as Texture2D
	if bg_tex != null:
		var bg_img := TextureRect.new()
		bg_img.texture      = bg_tex
		bg_img.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		bg_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_img.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		bg_img.process_mode  = Node.PROCESS_MODE_ALWAYS
		add_child(bg_img)

	# Semi-transparent dark overlay — keeps text legible against the busy illustration.
	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.60)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Full-screen content container — no border, fills the viewport.
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)

	const PW: float  = 1280.0
	const PAD: float = 24.0
	var inner_w := PW - PAD * 2.0      # 1232 px usable width
	var y       := 24.0

	# "INFESTED!" title — font doubled from 54 to 108.
	var title := Label.new()
	title.text                 = "INFESTED!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position             = Vector2(PAD, y)
	title.size                 = Vector2(inner_w, 168.0)   # 140 × 1.20
	title.add_theme_font_override("font", UIFonts.header())
	title.add_theme_font_size_override("font_size", 192)   # 160 × 1.20
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	y += 178.0

	# Wave reached — font doubled from 22 to 44.
	var wave_lbl := Label.new()
	wave_lbl.text                 = "Wave %d reached" % GameState.current_wave
	wave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_lbl.position             = Vector2(PAD, y)
	wave_lbl.size                 = Vector2(inner_w, 50.0)
	wave_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	wave_lbl.add_theme_font_size_override("font_size", 44)
	wave_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	wave_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	wave_lbl.add_theme_constant_override("shadow_offset_x", 2)
	wave_lbl.add_theme_constant_override("shadow_offset_y", 2)
	wave_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	panel.add_child(wave_lbl)
	y += 58.0

	# Currency row: [icon]  [balance]  [+earned]
	# Icon and balance are one visual unit (gold). The delta sits to the right
	# at 65% the balance size in silver — clearly subordinate context, not the headline.
	# The delta label is hidden entirely when nothing was earned this run.
	var sf_row := HBoxContainer.new()
	sf_row.position    = Vector2(PAD, y)
	sf_row.size        = Vector2(inner_w, 148.0)
	sf_row.alignment   = BoxContainer.ALIGNMENT_CENTER
	sf_row.add_theme_constant_override("separation", 24)
	sf_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sf_row)

	var sf_icon := TextureRect.new()
	sf_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	sf_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	sf_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sf_icon.custom_minimum_size = Vector2(176, 115)   # sized to match 112pt cap-height; 10% smaller than original 196×128
	sf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sf_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(sf_icon)

	_sf_balance_lbl = Label.new()
	_sf_balance_lbl.text                = "%d" % GameState.service_fees
	_sf_balance_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sf_balance_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_sf_balance_lbl.add_theme_font_size_override("font_size", 112)
	_sf_balance_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	_sf_balance_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_sf_balance_lbl.add_theme_constant_override("shadow_offset_x", 3)
	_sf_balance_lbl.add_theme_constant_override("shadow_offset_y", 3)
	_sf_balance_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(_sf_balance_lbl)

	var earned: int = GameState.service_fees_last_run
	_sf_earned_lbl = Label.new()
	_sf_earned_lbl.text                = "+%d" % earned
	_sf_earned_lbl.visible             = earned > 0   # takes no row space when hidden
	_sf_earned_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sf_earned_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_sf_earned_lbl.add_theme_font_size_override("font_size", 72)   # 65% of 112pt balance
	_sf_earned_lbl.add_theme_color_override("font_color", COLOR_SILVER)
	_sf_earned_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.70))
	_sf_earned_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_sf_earned_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_sf_earned_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(_sf_earned_lbl)
	y += 175.0

	# Button row: Bug-Up! | Start New Job | Quit
	# Buttons sized to fill the panel width; font doubled from 22 to 44.
	const BTN_H: float   = 80.0
	const BTN_GAP: float = 14.0
	const BTN_W: float   = (PW - PAD * 2.0 - BTN_GAP * 2.0) / 3.0

	var bugup_btn := _make_button("Company Upgrades", COLOR_BTN_GOLD, COLOR_BTN_GOLD_HOVER,
			COLOR_BTN_GOLD_PRESS, COLOR_BTN_GOLD_BORDER)
	bugup_btn.position = Vector2(PAD, y)
	bugup_btn.size     = Vector2(BTN_W, BTN_H)
	bugup_btn.pressed.connect(_on_bugup_pressed)
	panel.add_child(bugup_btn)

	var start_btn := _make_button("Start New Job", COLOR_BTN_GREEN, COLOR_BTN_GREEN_HOVER,
			COLOR_BTN_GREEN_PRESS, COLOR_BTN_GREEN_BORDER)
	start_btn.position = Vector2(PAD + BTN_W + BTN_GAP, y)
	start_btn.size     = Vector2(BTN_W, BTN_H)
	start_btn.pressed.connect(_on_start_pressed)
	panel.add_child(start_btn)

	# "Quit" is the plain-language equivalent of the old "Bug Out" label.
	var quit_btn := _make_button("Quit", COLOR_BTN_RED, COLOR_BTN_RED_HOVER,
			COLOR_BTN_RED_PRESS, COLOR_BTN_RED_BORDER)
	quit_btn.position = Vector2(PAD + (BTN_W + BTN_GAP) * 2.0, y)
	quit_btn.size     = Vector2(BTN_W, BTN_H)
	quit_btn.pressed.connect(_on_bugout_pressed)
	panel.add_child(quit_btn)


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
	btn.add_theme_font_size_override("font_size", 44)
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
	if _sf_earned_lbl != null:
		var earned: int        = GameState.service_fees_last_run
		_sf_earned_lbl.text    = "+%d" % earned
		_sf_earned_lbl.visible = earned > 0


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
