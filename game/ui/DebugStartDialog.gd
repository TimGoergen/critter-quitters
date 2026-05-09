## DebugStartDialog.gd
## Playtest setup dialog shown once at game start, before the first wave.
## Lets the developer override the starting Bug Bucks balance and the number
## of enemies per wave without editing source files.
## Pressing Start applies the values and dismisses the dialog.

extends CanvasLayer

## Emitted when the player presses Start. Arena connects here to apply
## the values and then begin the first wave countdown.
signal confirmed(bug_bucks: int, wave_size: int, static_enemies: bool)

const DEFAULT_BUG_BUCKS: int = 1000
const DEFAULT_WAVE_SIZE:  int = 10

const PANEL_W: float = 600.0
const PANEL_H: float = 432.0
const PADDING: float = 28.0

const COLOR_BG      := Color(0.04, 0.22, 0.00, 0.95)
const COLOR_OUTLINE := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_TEXT    := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.78, 0.50, 1.0)
const COLOR_DIVIDER := Color(0.06, 0.22, 0.01, 1.0)
const COLOR_BTN_NORMAL  := Color(0.02, 0.15, 0.00, 1.0)
const COLOR_BTN_HOVER   := Color(0.07, 0.32, 0.02, 1.0)
const COLOR_BTN_PRESSED := Color(0.01, 0.10, 0.00, 1.0)
const COLOR_BTN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_FIELD_BG    := Color(0.02, 0.14, 0.00, 1.0)
const COLOR_FIELD_BORDER := Color(0.22, 0.60, 0.04, 1.0)

const UIFonts = preload("res://ui/UIFonts.gd")
const HUD     = preload("res://ui/HUD.gd")

var _field_bucks:  LineEdit  = null
var _field_waves:  LineEdit  = null
var _check_static: CheckBox  = null
var _panel_rect:   Rect2     = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size
	# Centre in the arena zone (between the HUD side panels), not the full viewport.
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - PANEL_W * 0.5
	var py       := (vp.y - PANEL_H) * 0.5

	# Fullscreen darkening overlay — covers the arena behind the dialog.
	# Added first so it renders beneath the panel and border.
	var overlay       := ColorRect.new()
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.0, 0.02, 0.0, 0.60)
	add_child(overlay)

	# Store the full panel rect (including border) for outside-click detection.
	_panel_rect = Rect2(Vector2(px - 8.0, py - 8.0), Vector2(PANEL_W + 16.0, PANEL_H + 16.0))

	# Outline border
	var border       := ColorRect.new()
	border.color      = COLOR_OUTLINE
	border.position   = Vector2(px - 8.0, py - 8.0)
	border.size       = Vector2(PANEL_W + 16.0, PANEL_H + 16.0)
	add_child(border)

	# Background
	var bg       := ColorRect.new()
	bg.color      = COLOR_BG
	bg.position   = Vector2(px, py)
	bg.size       = Vector2(PANEL_W, PANEL_H)
	add_child(bg)

	var inner_w := PANEL_W - PADDING * 2.0
	var y       := PADDING

	# Title
	var lbl_title := Label.new()
	lbl_title.text     = "Playtest Setup"
	lbl_title.position = Vector2(PADDING, y)
	lbl_title.add_theme_font_size_override("font_size", 48)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl_title.add_theme_font_override("font", UIFonts.header())
	bg.add_child(lbl_title)
	y += 56.0

	# Divider
	var div       := ColorRect.new()
	div.color      = COLOR_DIVIDER
	div.position   = Vector2(PADDING, y)
	div.size       = Vector2(inner_w, 2.0)
	bg.add_child(div)
	y += 20.0

	# Bug Bucks row
	_field_bucks = _add_field_row(bg, y, "Starting Bug Bucks", str(DEFAULT_BUG_BUCKS), 10000, 0)
	y += 72.0

	# Wave size row
	_field_waves = _add_field_row(bg, y, "Enemies per Wave", str(DEFAULT_WAVE_SIZE), 10, 1)
	y += 72.0

	# Static enemies toggle — when on, each wave spawns 3 of every enemy type for visual review
	var static_row := HBoxContainer.new()
	static_row.position            = Vector2(PADDING, y)
	static_row.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, 56.0)
	static_row.add_theme_constant_override("separation", 4)
	bg.add_child(static_row)

	var static_lbl := Label.new()
	static_lbl.text                  = "Static Enemies (review mode)"
	static_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	static_lbl.add_theme_font_size_override("font_size", 26)
	static_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	static_lbl.add_theme_font_override("font", UIFonts.primary())
	static_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	static_row.add_child(static_lbl)

	_check_static = CheckBox.new()
	_check_static.button_pressed = false
	_check_static.add_theme_font_override("font", UIFonts.primary())
	_style_checkbox(_check_static)
	static_row.add_child(_check_static)
	y += 72.0

	# Divider
	var div2       := ColorRect.new()
	div2.color      = COLOR_DIVIDER
	div2.position   = Vector2(PADDING, y)
	div2.size       = Vector2(inner_w, 2.0)
	bg.add_child(div2)
	y += 20.0

	# Start button
	var btn               := Button.new()
	btn.text               = "Start"
	btn.position           = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(inner_w, 64.0)
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.pressed.connect(_on_start_pressed)
	_style_start_button(btn)
	bg.add_child(btn)


## Builds one label + [−] LineEdit [+] row and returns the LineEdit.
## The ± buttons each change the value by `step`; the field is clamped to >= min_val.
func _add_field_row(parent: Control, y: float, label_text: String, default_value: String,
		step: int = 100, min_val: int = 0) -> LineEdit:
	var row := HBoxContainer.new()
	row.position            = Vector2(PADDING, y)
	row.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, 56.0)
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.add_theme_font_override("font", UIFonts.primary())
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var minus_btn := Button.new()
	minus_btn.text              = "−"
	minus_btn.custom_minimum_size = Vector2(56.0, 56.0)
	minus_btn.add_theme_font_size_override("font_size", 30)
	minus_btn.add_theme_font_override("font", UIFonts.primary())
	_style_button(minus_btn)
	row.add_child(minus_btn)

	var field := LineEdit.new()
	field.text                  = default_value
	field.custom_minimum_size   = Vector2(128.0, 56.0)
	field.alignment             = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 26)
	field.add_theme_font_override("font", UIFonts.primary())
	_style_field(field)
	row.add_child(field)

	var plus_btn := Button.new()
	plus_btn.text               = "+"
	plus_btn.custom_minimum_size = Vector2(56.0, 56.0)
	plus_btn.add_theme_font_size_override("font_size", 30)
	plus_btn.add_theme_font_override("font", UIFonts.primary())
	_style_button(plus_btn)
	row.add_child(plus_btn)

	minus_btn.pressed.connect(func() -> void:
		var val: int = int(field.text) if field.text.is_valid_int() else min_val
		field.text = str(maxi(min_val, val - step))
	)
	plus_btn.pressed.connect(func() -> void:
		var val: int = int(field.text) if field.text.is_valid_int() else min_val
		field.text = str(val + step)
	)

	return field


## Returns true when screen_pos falls inside the dialog panel.
## Arena calls this to suppress the grid reticle while the dialog is open.
func covers_point(screen_pos: Vector2) -> bool:
	return _panel_rect.has_point(screen_pos)


func _input(event: InputEvent) -> void:
	var pos   := Vector2.ZERO
	var fired := false
	if event is InputEventMouseButton and event.pressed:
		pos = event.position
		fired = true
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
		fired = true
	if fired:
		# Let taps on the left HUD panel through so the player can change trap
		# type before starting without the tap also dismissing the dialog.
		var in_left_panel := pos.x < HUD.LEFT_PANEL_W
		if not _panel_rect.has_point(pos) and not in_left_panel:
			get_viewport().set_input_as_handled()
			_on_start_pressed()


func _on_start_pressed() -> void:
	var bucks := int(_field_bucks.text) if _field_bucks.text.is_valid_int() else DEFAULT_BUG_BUCKS
	var waves := int(_field_waves.text) if _field_waves.text.is_valid_int() else DEFAULT_WAVE_SIZE
	bucks = maxi(bucks, 0)
	waves = maxi(waves, 1)
	confirmed.emit(bucks, waves, _check_static.button_pressed)
	queue_free()


func _style_start_button(btn: Button) -> void:
	# Darker background than the panel (COLOR_BG = 0.04, 0.22, 0.00) and a 4px
	# border — doubled from the standard 2px — to give the Start button more weight.
	var colors: Array = [
		["normal",  Color(0.02, 0.15, 0.00, 1.0)],
		["hover",   COLOR_BTN_HOVER],
		["pressed", COLOR_BTN_PRESSED],
	]
	for state: Array in colors:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(4)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _style_button(btn: Button) -> void:
	for state: Array in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _style_checkbox(cb: CheckBox) -> void:
	# Normal/pressed: dim green border always visible so the control has a clear boundary.
	for state: String in ["normal", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
		box.border_color = Color(0.10, 0.35, 0.02, 1.0)
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		cb.add_theme_stylebox_override(state, box)
	# Hover: full-brightness outline signals interactivity.
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
	hover_box.border_color = COLOR_OUTLINE
	hover_box.set_border_width_all(2)
	hover_box.set_corner_radius_all(4)
	cb.add_theme_stylebox_override("hover", hover_box)


func _style_field(field: LineEdit) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color     = COLOR_FIELD_BG
	box.border_color = COLOR_FIELD_BORDER
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.content_margin_left   = 6.0
	box.content_margin_right  = 6.0
	box.content_margin_top    = 4.0
	box.content_margin_bottom = 4.0
	field.add_theme_stylebox_override("normal", box)
	field.add_theme_stylebox_override("focus",  box)
	field.add_theme_color_override("font_color", COLOR_TEXT)
	field.add_theme_color_override("caret_color", COLOR_TEXT)
