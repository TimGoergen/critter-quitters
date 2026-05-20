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

## Two-column layout: left column holds the input controls; right column holds
## the enemy-type selector (visible only when Static Enemies is on).
## The panel is fixed size — it never resizes after build.
const PANEL_W: float = 820.0
const PANEL_H: float = 380.0
const PADDING: float = 24.0
const COL_GAP: float = 24.0   # gap between the left and right columns

## Column geometry — derived from the above.
const LEFT_COL_W:  float = (PANEL_W - PADDING * 2.0 - COL_GAP) / 2.0   # 374px
const RIGHT_COL_X: float = PADDING + LEFT_COL_W + COL_GAP              # 422px
const RIGHT_COL_W: float = LEFT_COL_W                                   # 374px

## Height of each control row in the left column (field rows and static toggle).
const ROW_H_CTRL: float = 52.0

## Enemy-type list layout (right column).
const ENEMY_HEADER_H:  float = 36.0   # "Enemy Type Selection" header bar height
const CELL_PAD:        float = 6.0    # horizontal text inset inside each cell
const BORDER_W:        float = 3.0    # outer box border thickness
const ROW_H:           float = 28.0   # enemy-type data row height
const ROW_STRIDE:      float = 29.0   # ROW_H + 1px row-divider
## ENEMY_SECTION_H = BORDER_W + 7 × ROW_H + 6 × 1px dividers + BORDER_W
##                 = 3 + 196 + 6 + 3 = 208px
const ENEMY_SECTION_H: float = 208.0

const COLOR_BG           := Color(0.04, 0.22, 0.00, 0.95)
const COLOR_OUTLINE      := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_TEXT         := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM     := Color(0.55, 0.78, 0.50, 1.0)
const COLOR_DIVIDER      := Color(0.06, 0.22, 0.01, 1.0)
const COLOR_BTN_NORMAL   := Color(0.02, 0.15, 0.00, 1.0)
const COLOR_BTN_HOVER    := Color(0.07, 0.32, 0.02, 1.0)
const COLOR_BTN_PRESSED  := Color(0.01, 0.10, 0.00, 1.0)
const COLOR_BTN_BORDER   := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_FIELD_BG     := Color(0.02, 0.14, 0.00, 1.0)
const COLOR_FIELD_BORDER := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_GRID         := Color(0.12, 0.42, 0.04, 1.0)   # enemy list borders and row separators
const COLOR_GRID_HEADER  := Color(0.06, 0.26, 0.01, 1.0)   # header bar background
const COLOR_ROW_A        := Color(0.03, 0.18, 0.00, 1.0)   # alternating row background A (darker)
const COLOR_ROW_B        := Color(0.06, 0.28, 0.01, 1.0)   # alternating row background B (lighter)

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
var _check_static: Button   = null   # toggle-mode button; text = "✓" when pressed
var _panel_rect:   Rect2    = Rect2()

## Right column container — holds the enemy-type header and selector list.
## Shown only when Static Enemies is toggled on.
var _right_col: Control = null

## EnemyType int value → toggle Button for each row in the enemy-type list.
var _enemy_type_checks: Dictionary = {}
var _check_all_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var vp       := get_viewport().get_visible_rect().size
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - PANEL_W * 0.5
	var py       := maxf(8.0, (vp.y - PANEL_H) * 0.5)

	# Fullscreen overlay — darkens the arena behind the dialog.
	var overlay           := ColorRect.new()
	overlay.anchor_right   = 1.0
	overlay.anchor_bottom  = 1.0
	overlay.color          = Color(0.0, 0.02, 0.0, 0.60)
	add_child(overlay)

	# Outline border (8px wider than the panel on each side).
	var border        := ColorRect.new()
	border.color       = COLOR_OUTLINE
	border.position    = Vector2(px - 8.0, py - 8.0)
	border.size        = Vector2(PANEL_W + 16.0, PANEL_H + 16.0)
	add_child(border)

	# Panel background.
	var bg        := ColorRect.new()
	bg.color       = COLOR_BG
	bg.position    = Vector2(px, py)
	bg.size        = Vector2(PANEL_W, PANEL_H)
	add_child(bg)

	# Panel is fixed size — _panel_rect is set once and never updated.
	_panel_rect = Rect2(Vector2(px - 8.0, py - 8.0), Vector2(PANEL_W + 16.0, PANEL_H + 16.0))

	# ── Left column ────────────────────────────────────────────────────────────
	var y := PADDING

	var lbl_title := Label.new()
	lbl_title.text     = "Playtest Setup"
	lbl_title.position = Vector2(PADDING, y)
	lbl_title.add_theme_font_size_override("font_size", 44)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	lbl_title.add_theme_font_override("font", UIFonts.header())
	bg.add_child(lbl_title)
	y += 52.0

	_add_divider(bg, y)
	y += 14.0   # 2px line + 12px breathing room

	# Capture y here so the right column top aligns with the first input row.
	var right_col_y := y

	_field_bucks = _add_field_row(bg, PADDING, y, LEFT_COL_W, ROW_H_CTRL,
			"Bug Bucks", str(DEFAULT_BUG_BUCKS), 10000, 0)
	y += ROW_H_CTRL

	_field_waves = _add_field_row(bg, PADDING, y, LEFT_COL_W, ROW_H_CTRL,
			"Wave Size", str(DEFAULT_WAVE_SIZE), 10, 1)
	y += ROW_H_CTRL

	_add_divider(bg, y)
	y += 14.0

	# Static enemies toggle row — label + checkbox.
	var static_row := HBoxContainer.new()
	static_row.position            = Vector2(PADDING, y)
	static_row.custom_minimum_size = Vector2(LEFT_COL_W, ROW_H_CTRL)
	static_row.add_theme_constant_override("separation", 4)
	bg.add_child(static_row)

	var static_lbl := Label.new()
	static_lbl.text                  = "Static Enemies"
	static_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	static_lbl.add_theme_font_size_override("font_size", 22)
	static_lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	static_lbl.add_theme_font_override("font", UIFonts.primary())
	static_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	static_row.add_child(static_lbl)

	_check_static = Button.new()
	_check_static.toggle_mode         = true
	_check_static.button_pressed      = false
	_check_static.focus_mode          = Control.FOCUS_NONE
	_check_static.custom_minimum_size = Vector2(ROW_H_CTRL, ROW_H_CTRL)
	_check_static.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check_static.add_theme_font_size_override("font_size", 28)
	_check_static.add_theme_font_override("font", UIFonts.primary())
	_style_button(_check_static)
	_check_static.toggled.connect(_on_static_toggled)
	static_row.add_child(_check_static)
	y += ROW_H_CTRL

	_add_divider(bg, y)
	y += 14.0

	# Start button — fills the remaining height of the left column.
	var start_btn := Button.new()
	start_btn.text                = "Start"
	start_btn.focus_mode          = Control.FOCUS_NONE
	start_btn.position            = Vector2(PADDING, y)
	start_btn.custom_minimum_size = Vector2(LEFT_COL_W, PANEL_H - PADDING - y)
	start_btn.add_theme_font_size_override("font_size", 30)
	start_btn.add_theme_font_override("font", UIFonts.primary_bold())
	start_btn.pressed.connect(_on_start_pressed)
	_style_start_button(start_btn)
	bg.add_child(start_btn)

	# ── Right column ───────────────────────────────────────────────────────────
	# Top edge aligns with the first input row; hidden until Static Enemies is on.
	_right_col = Control.new()
	_right_col.position            = Vector2(RIGHT_COL_X, right_col_y)
	_right_col.custom_minimum_size = Vector2(RIGHT_COL_W, ENEMY_HEADER_H + ENEMY_SECTION_H)
	_right_col.visible             = false
	bg.add_child(_right_col)

	_build_enemy_header(_right_col, RIGHT_COL_W)
	_build_enemy_section(_right_col, ENEMY_HEADER_H, RIGHT_COL_W)


## Adds a 2px horizontal divider spanning the left column at the given y.
func _add_divider(parent: Control, y: float) -> void:
	var div      := ColorRect.new()
	div.color     = COLOR_DIVIDER
	div.position  = Vector2(PADDING, y)
	div.size      = Vector2(LEFT_COL_W, 2.0)
	parent.add_child(div)


## Builds a label + [−] value [+] input row and returns the LineEdit.
## Buttons change the value by `step`; the field is clamped to >= min_val.
func _add_field_row(parent: Control, x: float, y: float, w: float, h: float,
		label_text: String, default_value: String,
		step: int = 100, min_val: int = 0) -> LineEdit:
	var row := HBoxContainer.new()
	row.position            = Vector2(x, y)
	row.custom_minimum_size = Vector2(w, h)
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.add_theme_font_override("font", UIFonts.primary())
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var minus_btn := Button.new()
	minus_btn.text                = "−"
	minus_btn.focus_mode          = Control.FOCUS_NONE
	minus_btn.custom_minimum_size = Vector2(h, h)
	minus_btn.add_theme_font_size_override("font_size", 28)
	minus_btn.add_theme_font_override("font", UIFonts.primary())
	_style_button(minus_btn)
	row.add_child(minus_btn)

	var field := LineEdit.new()
	field.text                = default_value
	field.custom_minimum_size = Vector2(96.0, h)
	field.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 22)
	field.add_theme_font_override("font", UIFonts.primary())
	_style_field(field)
	row.add_child(field)

	var plus_btn := Button.new()
	plus_btn.text                = "+"
	plus_btn.focus_mode          = Control.FOCUS_NONE
	plus_btn.custom_minimum_size = Vector2(h, h)
	plus_btn.add_theme_font_size_override("font_size", 28)
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


## Builds the "Enemy Type Selection" header bar at y=0 within parent.
## Holds a static label on the left and the check-all toggle on the right.
## No expand/collapse — the right column is shown or hidden as a unit.
func _build_enemy_header(parent: Control, w: float) -> void:
	var bg     := ColorRect.new()
	bg.color    = COLOR_GRID_HEADER
	bg.size     = Vector2(w, ENEMY_HEADER_H)
	parent.add_child(bg)

	_section_line(parent, 0.0, 0.0, w, BORDER_W)                             # top
	_section_line(parent, 0.0, ENEMY_HEADER_H - BORDER_W, w, BORDER_W)      # bottom
	_section_line(parent, 0.0, 0.0, BORDER_W, ENEMY_HEADER_H)               # left
	_section_line(parent, w - BORDER_W, 0.0, BORDER_W, ENEMY_HEADER_H)      # right

	var inner_h := ENEMY_HEADER_H - BORDER_W * 2.0
	var check_w := 36.0

	var lbl := Label.new()
	lbl.text                = "Enemy Type Selection"
	lbl.position            = Vector2(BORDER_W + CELL_PAD, BORDER_W)
	lbl.custom_minimum_size = Vector2(w - BORDER_W * 2.0 - CELL_PAD - check_w, inner_h)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.add_theme_font_override("font", UIFonts.primary())
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)

	_check_all_btn                    = Button.new()
	_check_all_btn.toggle_mode         = true
	_check_all_btn.button_pressed      = true
	_check_all_btn.text                = "✓"
	_check_all_btn.focus_mode          = Control.FOCUS_NONE
	_check_all_btn.position            = Vector2(w - BORDER_W - check_w, BORDER_W)
	_check_all_btn.custom_minimum_size = Vector2(check_w, inner_h)
	_check_all_btn.add_theme_font_size_override("font_size", 16)
	_check_all_btn.add_theme_font_override("font", UIFonts.primary())
	_style_checkbox_btn(_check_all_btn)
	_check_all_btn.toggled.connect(func(pressed: bool) -> void:
		_check_all_btn.text = "✓" if pressed else ""
		for btn: Button in _enemy_type_checks.values():
			btn.button_pressed = pressed
			btn.text = "✓" if pressed else ""
	)
	parent.add_child(_check_all_btn)


## Builds the enemy-type checkbox list starting at y within parent.
## One alternating-background row per type, separated by 1px grid lines,
## surrounded by a BORDER_W-thick outer box.
func _build_enemy_section(parent: Control, y: float, w: float) -> void:
	var section             := Control.new()
	section.position         = Vector2(0.0, y)
	section.custom_minimum_size = Vector2(w, ENEMY_SECTION_H)
	parent.add_child(section)

	var bg     := ColorRect.new()
	bg.color    = COLOR_BG
	bg.size     = Vector2(w, ENEMY_SECTION_H)
	section.add_child(bg)

	_section_line(section, 0.0, 0.0, w, BORDER_W)                             # top
	_section_line(section, 0.0, ENEMY_SECTION_H - BORDER_W, w, BORDER_W)     # bottom
	_section_line(section, 0.0, 0.0, BORDER_W, ENEMY_SECTION_H)              # left
	_section_line(section, w - BORDER_W, 0.0, BORDER_W, ENEMY_SECTION_H)     # right

	for i: int in range(STATIC_ENEMY_TYPES.size()):
		var enemy_type: int = STATIC_ENEMY_TYPES[i]
		var row_top    := BORDER_W + float(i) * ROW_STRIDE

		var row_bg := ColorRect.new()
		row_bg.color    = COLOR_ROW_A if i % 2 == 0 else COLOR_ROW_B
		row_bg.position = Vector2(BORDER_W, row_top)
		row_bg.size     = Vector2(w - BORDER_W * 2.0, ROW_H)
		section.add_child(row_bg)

		var type_row := HBoxContainer.new()
		type_row.position            = Vector2(BORDER_W + CELL_PAD, row_top)
		type_row.custom_minimum_size = Vector2(w - BORDER_W * 2.0 - CELL_PAD * 2.0, ROW_H)
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
		type_btn.button_pressed      = true
		type_btn.text                = "✓"
		type_btn.focus_mode          = Control.FOCUS_NONE
		type_btn.custom_minimum_size = Vector2(36.0, ROW_H)
		type_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		type_btn.add_theme_font_size_override("font_size", 14)
		type_btn.add_theme_font_override("font", UIFonts.primary())
		_style_checkbox_btn(type_btn)
		type_btn.toggled.connect(func(pressed: bool) -> void:
			type_btn.text = "✓" if pressed else ""
		)
		type_row.add_child(type_btn)
		_enemy_type_checks[enemy_type] = type_btn

		# 1px separator after every row except the last; the outer bottom border closes the last row.
		if i < STATIC_ENEMY_TYPES.size() - 1:
			_section_line(section, BORDER_W, row_top + ROW_H, w - BORDER_W * 2.0, 1.0)


## Adds a colored rectangle to parent, used for borders and grid lines.
func _section_line(parent: Control, x: float, y: float, w: float, h: float) -> void:
	var line     := ColorRect.new()
	line.color    = COLOR_GRID
	line.position = Vector2(x, y)
	line.size     = Vector2(w, h)
	parent.add_child(line)


## Shows or hides the right column when Static Enemies is toggled.
## No panel resize needed — the panel is fixed size.
func _on_static_toggled(pressed: bool) -> void:
	_check_static.text = "✓" if pressed else ""
	_right_col.visible = pressed


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
	# Doubled border width (4px vs 2px) gives the Start button more visual weight.
	var colors: Array = [
		["normal",  Color(0.02, 0.15, 0.00, 1.0)],
		["hover",   COLOR_BTN_HOVER],
		["pressed", COLOR_BTN_PRESSED],
	]
	for state: Array in colors:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_BTN_BORDER
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
		box.bg_color              = state[1]
		box.border_color          = COLOR_BTN_BORDER
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
## Zero vertical margins let the button fit inside tight ROW_H rows without
## overflowing — _style_button's 4px top+bottom push height past custom_minimum_size.
func _style_checkbox_btn(btn: Button) -> void:
	for state: Array in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_BTN_BORDER
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
