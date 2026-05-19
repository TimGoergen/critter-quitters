## DebugStartDialog.gd
## Playtest setup dialog shown once at game start, before the first wave.
## Lets the developer override the starting Bug Bucks balance and the number
## of enemies per wave without editing source files.
## Pressing Start applies the values and dismisses the dialog.

extends CanvasLayer

## Emitted when the player presses Start. Arena connects here to apply the
## values and then begin the first wave countdown.
## allowed_types is an Array of Enemy.EnemyType int values indicating which
## enemy types should appear in static mode; empty array means all types.
signal confirmed(bug_bucks: int, wave_size: int, static_enemies: bool, allowed_types: Array)

const DEFAULT_BUG_BUCKS: int = 1000
const DEFAULT_WAVE_SIZE:  int = 10

const PANEL_W: float = 600.0
const PANEL_H: float = 432.0
const PADDING: float = 28.0

## Height added to the panel when Static Enemies is toggled on.
## 1px border + 28px header + 2px separator + 7 rows × 20px + 6 row-dividers × 1px + 1px border = 178px.
## Row height is capped at 20px so the expanded panel's Start button stays within the 600px viewport.
const ENEMY_SECTION_H: float = 178.0

const COLOR_BG       := Color(0.04, 0.22, 0.00, 0.95)
const COLOR_OUTLINE  := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_TEXT     := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM := Color(0.55, 0.78, 0.50, 1.0)
const COLOR_DIVIDER  := Color(0.06, 0.22, 0.01, 1.0)
const COLOR_BTN_NORMAL  := Color(0.02, 0.15, 0.00, 1.0)
const COLOR_BTN_HOVER   := Color(0.07, 0.32, 0.02, 1.0)
const COLOR_BTN_PRESSED := Color(0.01, 0.10, 0.00, 1.0)
const COLOR_BTN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_FIELD_BG    := Color(0.02, 0.14, 0.00, 1.0)
const COLOR_FIELD_BORDER := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_GRID        := Color(0.12, 0.42, 0.04, 1.0)   # enemy list borders and row separators
const COLOR_GRID_HEADER := Color(0.06, 0.26, 0.01, 1.0)   # slightly lighter bg for header row

const UIFonts = preload("res://ui/UIFonts.gd")
const HUD     = preload("res://ui/HUD.gd")
const Enemy   = preload("res://enemies/Enemy.gd")

## The enemy types offered in the selector, in the same order as the static spawn queue.
const STATIC_ENEMY_TYPES: Array = [
	Enemy.EnemyType.ANT,
	Enemy.EnemyType.GNAT,
	Enemy.EnemyType.CRICKET,
	Enemy.EnemyType.BEETLE,
	Enemy.EnemyType.COCKROACH,
	Enemy.EnemyType.RAT,
	Enemy.EnemyType.MOSQUITO,
]

const ENEMY_TYPE_NAMES: Dictionary = {
	Enemy.EnemyType.ANT:       "Ant",
	Enemy.EnemyType.GNAT:      "Gnat",
	Enemy.EnemyType.CRICKET:   "Cricket",
	Enemy.EnemyType.BEETLE:    "Beetle",
	Enemy.EnemyType.COCKROACH: "Cockroach",
	Enemy.EnemyType.RAT:       "Rat",
	Enemy.EnemyType.MOSQUITO:  "Mosquito",
}

var _field_bucks:  LineEdit = null
var _field_waves:  LineEdit = null
var _check_static: Button   = null  # toggle_mode button; checked = "✓" centered, matching ± size
var _panel_rect:   Rect2    = Rect2()

## References held so _on_static_toggled can resize and reposition the panel.
var _bg:              ColorRect = null
var _border:          ColorRect = null
var _div_before_start: ColorRect = null
var _btn_start:        Button   = null
var _enemy_section:    Control  = null

## EnemyType int value → toggle Button for each type in STATIC_ENEMY_TYPES.
var _enemy_type_checks: Dictionary = {}
var _check_all_btn: Button = null

## Horizontal position of the panel — used when rebuilding _panel_rect on resize.
var _base_px: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size
	# Centre in the arena zone (between the HUD side panels), not the full viewport.
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - PANEL_W * 0.5
	var py       := (vp.y - PANEL_H) * 0.5
	_base_px      = px

	# Fullscreen darkening overlay — covers the arena behind the dialog.
	# Added first so it renders beneath the panel and border.
	var overlay           := ColorRect.new()
	overlay.anchor_right   = 1.0
	overlay.anchor_bottom  = 1.0
	overlay.color          = Color(0.0, 0.02, 0.0, 0.60)
	add_child(overlay)

	# Store the full panel rect (including border) for outside-click detection.
	_panel_rect = Rect2(Vector2(px - 8.0, py - 8.0), Vector2(PANEL_W + 16.0, PANEL_H + 16.0))

	# Outline border
	_border          = ColorRect.new()
	_border.color     = COLOR_OUTLINE
	_border.position  = Vector2(px - 8.0, py - 8.0)
	_border.size      = Vector2(PANEL_W + 16.0, PANEL_H + 16.0)
	add_child(_border)

	# Background
	_bg          = ColorRect.new()
	_bg.color     = COLOR_BG
	_bg.position  = Vector2(px, py)
	_bg.size      = Vector2(PANEL_W, PANEL_H)
	add_child(_bg)

	var inner_w := PANEL_W - PADDING * 2.0
	var y       := PADDING

	# Title
	var lbl_title := Label.new()
	lbl_title.text     = "Playtest Setup"
	lbl_title.position = Vector2(PADDING, y)
	lbl_title.add_theme_font_size_override("font_size", 48)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl_title.add_theme_font_override("font", UIFonts.header())
	_bg.add_child(lbl_title)
	y += 56.0

	# Divider
	var div       := ColorRect.new()
	div.color      = COLOR_DIVIDER
	div.position   = Vector2(PADDING, y)
	div.size       = Vector2(inner_w, 2.0)
	_bg.add_child(div)
	y += 20.0

	# Bug Bucks row
	_field_bucks = _add_field_row(_bg, y, "Starting Bug Bucks", str(DEFAULT_BUG_BUCKS), 10000, 0)
	y += 72.0

	# Wave size row
	_field_waves = _add_field_row(_bg, y, "Enemies per Wave", str(DEFAULT_WAVE_SIZE), 10, 1)
	y += 72.0

	# Static enemies toggle — when on, each wave spawns 3 of every enemy type for visual review
	var static_row := HBoxContainer.new()
	static_row.position            = Vector2(PADDING, y)
	static_row.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, 56.0)
	static_row.add_theme_constant_override("separation", 4)
	_bg.add_child(static_row)

	var static_lbl := Label.new()
	static_lbl.text                  = "Static Enemies (review mode)"
	static_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	static_lbl.add_theme_font_size_override("font_size", 26)
	static_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	static_lbl.add_theme_font_override("font", UIFonts.primary())
	static_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	static_row.add_child(static_lbl)

	# Toggle button instead of CheckBox so it is the same 56×56 size as the ± buttons
	# and the checkmark is naturally centered in the box.
	_check_static = Button.new()
	_check_static.toggle_mode         = true
	_check_static.button_pressed      = false
	_check_static.focus_mode          = Control.FOCUS_NONE
	_check_static.custom_minimum_size = Vector2(56.0, 56.0)
	_check_static.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check_static.add_theme_font_size_override("font_size", 30)
	_check_static.add_theme_font_override("font", UIFonts.primary())
	_style_button(_check_static)
	_check_static.toggled.connect(_on_static_toggled)
	static_row.add_child(_check_static)
	y += 72.0

	# Enemy type selector — hidden until Static Enemies is checked.
	# Positioned at the current y so it expands the panel downward when shown.
	_enemy_section = _build_enemy_section(_bg, y)

	# Divider before the Start button — stored so it can slide down when the section opens.
	_div_before_start         = ColorRect.new()
	_div_before_start.color    = COLOR_DIVIDER
	_div_before_start.position = Vector2(PADDING, y)
	_div_before_start.size     = Vector2(inner_w, 2.0)
	_bg.add_child(_div_before_start)
	y += 20.0

	# Start button — stored so it can slide down when the section opens.
	_btn_start               = Button.new()
	_btn_start.text           = "Start"
	_btn_start.focus_mode     = Control.FOCUS_NONE
	_btn_start.position       = Vector2(PADDING, y)
	_btn_start.custom_minimum_size = Vector2(inner_w, 64.0)
	_btn_start.add_theme_font_size_override("font_size", 30)
	_btn_start.add_theme_font_override("font", UIFonts.primary_bold())
	_btn_start.pressed.connect(_on_start_pressed)
	_style_start_button(_btn_start)
	_bg.add_child(_btn_start)


## Builds the enemy-type checkbox section shown when Static Enemies is enabled.
## Single-column list: a header row with the select-all toggle, then one row per enemy
## type, separated by 1px grid lines with a full outer border.
## Returns the section container; it is hidden by default.
func _build_enemy_section(parent: Control, y: float) -> Control:
	var section             := Control.new()
	section.position         = Vector2(PADDING, y)
	section.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, ENEMY_SECTION_H)
	section.visible          = false
	parent.add_child(section)

	var w := PANEL_W - PADDING * 2.0   # 544px

	# Section background fills the full area; grid lines and borders are drawn on top.
	var bg     := ColorRect.new()
	bg.color    = COLOR_BG
	bg.size     = Vector2(w, ENEMY_SECTION_H)
	section.add_child(bg)

	# Outer border: four 1px edges.
	_section_line(section, 0.0, 0.0, w, 1.0)                          # top
	_section_line(section, 0.0, ENEMY_SECTION_H - 1.0, w, 1.0)       # bottom
	_section_line(section, 0.0, 0.0, 1.0, ENEMY_SECTION_H)            # left
	_section_line(section, w - 1.0, 0.0, 1.0, ENEMY_SECTION_H)       # right

	# --- Header row (y=1, h=28): "Enemy Types" label + select-all toggle ---
	# Slightly different background to distinguish the header from data rows.
	var header_bg        := ColorRect.new()
	header_bg.color       = COLOR_GRID_HEADER
	header_bg.position    = Vector2(1.0, 1.0)
	header_bg.size        = Vector2(w - 2.0, 28.0)
	section.add_child(header_bg)

	var header_row := HBoxContainer.new()
	header_row.position            = Vector2(1.0, 1.0)
	header_row.custom_minimum_size = Vector2(w - 2.0, 28.0)
	header_row.add_theme_constant_override("separation", 4)
	section.add_child(header_row)

	var header_lbl := Label.new()
	header_lbl.text                  = "Enemy Types"
	header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_lbl.add_theme_font_size_override("font_size", 18)
	header_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	header_lbl.add_theme_font_override("font", UIFonts.primary())
	header_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(header_lbl)

	_check_all_btn                    = Button.new()
	_check_all_btn.toggle_mode         = true
	_check_all_btn.button_pressed      = true   # all types checked by default
	_check_all_btn.text                = "✓"
	_check_all_btn.focus_mode          = Control.FOCUS_NONE
	_check_all_btn.custom_minimum_size = Vector2(36.0, 28.0)
	_check_all_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check_all_btn.add_theme_font_size_override("font_size", 18)
	_check_all_btn.add_theme_font_override("font", UIFonts.primary())
	_style_checkbox_btn(_check_all_btn)
	_check_all_btn.toggled.connect(func(pressed: bool) -> void:
		_check_all_btn.text = "✓" if pressed else ""
		for btn: Button in _enemy_type_checks.values():
			btn.button_pressed = pressed
			btn.text = "✓" if pressed else ""
	)
	header_row.add_child(_check_all_btn)

	# 2px separator below header to visually distinguish it from the data rows.
	_section_line(section, 1.0, 29.0, w - 2.0, 2.0)

	# --- Enemy type rows (y=31 + i×21, h=20 each, 1px divider between rows) ---
	# Stride is 21px: 20px row content + 1px grid line drawn after each non-last row.
	for i: int in range(STATIC_ENEMY_TYPES.size()):
		var enemy_type: int = STATIC_ENEMY_TYPES[i]
		var row_top    := 31.0 + float(i) * 21.0

		var type_row := HBoxContainer.new()
		type_row.position            = Vector2(1.0, row_top)
		type_row.custom_minimum_size = Vector2(w - 2.0, 20.0)
		type_row.add_theme_constant_override("separation", 4)
		section.add_child(type_row)

		var type_lbl := Label.new()
		type_lbl.text                  = ENEMY_TYPE_NAMES[enemy_type]
		type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_lbl.add_theme_font_size_override("font_size", 16)
		type_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		type_lbl.add_theme_font_override("font", UIFonts.primary())
		type_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		type_row.add_child(type_lbl)

		var type_btn := Button.new()
		type_btn.toggle_mode         = true
		type_btn.button_pressed      = true   # all checked by default
		type_btn.text                = "✓"
		type_btn.focus_mode          = Control.FOCUS_NONE
		type_btn.custom_minimum_size = Vector2(36.0, 20.0)
		type_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		type_btn.add_theme_font_size_override("font_size", 14)
		type_btn.add_theme_font_override("font", UIFonts.primary())
		_style_checkbox_btn(type_btn)
		type_btn.toggled.connect(func(pressed: bool) -> void:
			type_btn.text = "✓" if pressed else ""
		)
		type_row.add_child(type_btn)
		_enemy_type_checks[enemy_type] = type_btn

		# 1px grid line after this row; the outer bottom border handles the last row's edge.
		if i < STATIC_ENEMY_TYPES.size() - 1:
			_section_line(section, 1.0, row_top + 20.0, w - 2.0, 1.0)

	return section


## Adds a colored rectangle to parent, used for grid lines and outer borders.
func _section_line(parent: Control, x: float, y: float, w: float, h: float) -> void:
	var line     := ColorRect.new()
	line.color    = COLOR_GRID
	line.position = Vector2(x, y)
	line.size     = Vector2(w, h)
	parent.add_child(line)


## Shows or hides the enemy-type selector section when the static toggle changes.
## Resizes the panel background and border, slides the divider and Start button,
## and recentres the entire panel vertically so it stays within the viewport.
func _on_static_toggled(pressed: bool) -> void:
	_check_static.text     = "✓" if pressed else ""
	_enemy_section.visible = pressed

	var extra_h    := ENEMY_SECTION_H if pressed else 0.0
	var new_panel_h := PANEL_H + extra_h

	# Resize background and border to fit the expanded content.
	_bg.size.y     = new_panel_h
	_border.size.y = new_panel_h + 16.0

	# Slide the divider and Start button down (or back up) by the section height.
	# 320.0 is the y offset of the divider in the collapsed panel (see _build_ui layout).
	_div_before_start.position.y = 320.0 + extra_h
	_btn_start.position.y        = 340.0 + extra_h

	# Recentre the panel; clamp so the border (8px above bg) never goes off-screen.
	var vp     := get_viewport().get_visible_rect().size
	var new_py := maxf(8.0, (vp.y - new_panel_h) * 0.5)
	_bg.position.y     = new_py
	_border.position.y = new_py - 8.0

	# Rebuild the click-detection rect for the new size and position.
	_panel_rect = Rect2(
		Vector2(_base_px - 8.0, new_py - 8.0),
		Vector2(PANEL_W + 16.0, new_panel_h + 16.0)
	)


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
	minus_btn.text               = "−"
	minus_btn.focus_mode         = Control.FOCUS_NONE
	minus_btn.custom_minimum_size = Vector2(56.0, 56.0)
	minus_btn.add_theme_font_size_override("font_size", 30)
	minus_btn.add_theme_font_override("font", UIFonts.primary())
	_style_button(minus_btn)
	row.add_child(minus_btn)

	var field := LineEdit.new()
	field.text                = default_value
	field.custom_minimum_size = Vector2(128.0, 56.0)
	field.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 26)
	field.add_theme_font_override("font", UIFonts.primary())
	_style_field(field)
	row.add_child(field)

	var plus_btn := Button.new()
	plus_btn.text               = "+"
	plus_btn.focus_mode         = Control.FOCUS_NONE
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

	# Collect the checked enemy types — only relevant when static mode is on.
	# An empty array passed to Arena means "use all types".
	var allowed: Array = []
	if _check_static.button_pressed:
		for enemy_type: int in _enemy_type_checks:
			if _enemy_type_checks[enemy_type].button_pressed:
				allowed.append(enemy_type)

	confirmed.emit(bucks, waves, _check_static.button_pressed, allowed)
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
		box.set_corner_radius_all(0)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _style_button(btn: Button) -> void:
	for state: Array in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(0)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


## Variant of _style_button for compact row checkboxes.
## Sets vertical content margins to zero so the button's natural height equals
## the glyph height alone, allowing it to fit inside the tight enemy-list rows.
## (_style_button's 4px top+bottom margins push the button to ~26px, which
## overrides custom_minimum_size and overflows 20px rows.)
func _style_checkbox_btn(btn: Button) -> void:
	for state: Array in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(0)
		box.content_margin_left   = 4.0
		box.content_margin_right  = 4.0
		box.content_margin_top    = 0.0
		box.content_margin_bottom = 0.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
