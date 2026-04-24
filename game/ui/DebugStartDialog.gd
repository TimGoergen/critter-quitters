## DebugStartDialog.gd
## Playtest setup dialog shown once at game start, before the first wave.
## Lets the developer override the starting Bug Bucks balance and the number
## of enemies per wave without editing source files.
## Pressing Start applies the values and dismisses the dialog.

extends CanvasLayer

## Emitted when the player presses Start. Arena connects here to apply
## the values and then begin the first wave countdown.
signal confirmed(bug_bucks: int, wave_size: int)

const DEFAULT_BUG_BUCKS: int = 100
const DEFAULT_WAVE_SIZE:  int = 10

const PANEL_W: float = 300.0
const PANEL_H: float = 178.0
const PADDING: float = 14.0

const COLOR_BG      := Color(0.04, 0.28, 0.28, 0.95)
const COLOR_OUTLINE := Color(0.20, 0.55, 0.55, 1.0)
const COLOR_TEXT    := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM := Color(0.65, 0.80, 0.80, 1.0)
const COLOR_DIVIDER := Color(0.15, 0.45, 0.45, 1.0)
const COLOR_BTN_NORMAL  := Color(0.06, 0.22, 0.22, 1.0)
const COLOR_BTN_HOVER   := Color(0.10, 0.32, 0.32, 1.0)
const COLOR_BTN_PRESSED := Color(0.03, 0.15, 0.15, 1.0)
const COLOR_BTN_BORDER  := Color(0.20, 0.55, 0.55, 1.0)
const COLOR_FIELD_BG    := Color(0.02, 0.18, 0.18, 1.0)
const COLOR_FIELD_BORDER := Color(0.20, 0.55, 0.55, 1.0)

const UIFonts = preload("res://ui/UIFonts.gd")
const HUD     = preload("res://ui/HUD.gd")

var _field_bucks: LineEdit = null
var _field_waves: LineEdit = null
var _panel_rect:  Rect2    = Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	# In landscape the arena occupies only the left portion of the screen.
	# Centre the dialog within that region rather than the full viewport width.
	var arena_w := vp.x - HUD.SELECTOR_PANEL_W if vp.x >= vp.y else vp.x
	var px := (arena_w - PANEL_W) * 0.5
	var py := (vp.y - PANEL_H) * 0.5

	# Store the full panel rect (including border) for outside-click detection.
	_panel_rect = Rect2(Vector2(px - 2.0, py - 2.0), Vector2(PANEL_W + 4.0, PANEL_H + 4.0))

	# Outline border
	var border       := ColorRect.new()
	border.color      = COLOR_OUTLINE
	border.position   = Vector2(px - 2.0, py - 2.0)
	border.size       = Vector2(PANEL_W + 4.0, PANEL_H + 4.0)
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
	lbl_title.add_theme_font_size_override("font_size", 20)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl_title.add_theme_font_override("font", UIFonts.header())
	bg.add_child(lbl_title)
	y += 28.0

	# Divider
	var div       := ColorRect.new()
	div.color      = COLOR_DIVIDER
	div.position   = Vector2(PADDING, y)
	div.size       = Vector2(inner_w, 1.0)
	bg.add_child(div)
	y += 10.0

	# Bug Bucks row
	_field_bucks = _add_field_row(bg, y, "Starting Bug Bucks", str(DEFAULT_BUG_BUCKS))
	y += 36.0

	# Wave size row
	_field_waves = _add_field_row(bg, y, "Enemies per Wave", str(DEFAULT_WAVE_SIZE))
	y += 36.0

	# Divider
	var div2       := ColorRect.new()
	div2.color      = COLOR_DIVIDER
	div2.position   = Vector2(PADDING, y)
	div2.size       = Vector2(inner_w, 1.0)
	bg.add_child(div2)
	y += 10.0

	# Start button
	var btn               := Button.new()
	btn.text               = "Start"
	btn.position           = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(inner_w, 32.0)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_font_override("font", UIFonts.primary())
	btn.pressed.connect(_on_start_pressed)
	_style_button(btn)
	bg.add_child(btn)


## Builds one label + LineEdit row and returns the LineEdit.
func _add_field_row(parent: Control, y: float, label_text: String, default_value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.position            = Vector2(PADDING, y)
	row.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, 28.0)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.add_theme_font_override("font", UIFonts.primary())
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var field := LineEdit.new()
	field.text                  = default_value
	field.custom_minimum_size   = Vector2(72.0, 28.0)
	field.alignment             = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 13)
	field.add_theme_font_override("font", UIFonts.primary())
	_style_field(field)
	row.add_child(field)

	return field


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Let clicks on the trap selector through so the player can pick a trap
		# before starting without the click also dismissing the dialog.
		var vp           := get_viewport().get_visible_rect().size
		var in_selector  := vp.x >= vp.y and event.position.x >= vp.x - HUD.SELECTOR_PANEL_W
		if not _panel_rect.has_point(event.position) and not in_selector:
			get_viewport().set_input_as_handled()
			_on_start_pressed()


func _on_start_pressed() -> void:
	var bucks := int(_field_bucks.text) if _field_bucks.text.is_valid_int() else DEFAULT_BUG_BUCKS
	var waves := int(_field_waves.text) if _field_waves.text.is_valid_int() else DEFAULT_WAVE_SIZE
	bucks = maxi(bucks, 0)
	waves = maxi(waves, 1)
	confirmed.emit(bucks, waves)
	queue_free()


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
