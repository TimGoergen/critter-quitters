## TrapUpgradePanel.gd
## Appears when the player taps a placed trap. Shows current stats and
## presents one upgrade button per stat (Damage, Range, Fire Rate), plus
## a SELL button at the bottom that refunds 70% of the trap's purchase price.
##
## Each stat upgrades independently up to Trap.MAX_UPGRADE_LEVEL (3) times.
## The cost for the next upgrade of each stat is shown on its button.
## A button shows "MAX" and is disabled when that stat is fully upgraded.
## A button is also disabled when the player cannot afford it.
##
## Panel dimensions are derived from the viewport at build time so the
## touch targets scale appropriately across phone screen sizes.
##
## process_mode is ALWAYS so the panel stays interactive while the game
## tree is paused (which Arena does while this panel is open).

extends CanvasLayer

signal closed
signal sell_requested   # Arena connects this to _on_sell_trap_requested(anchor)

const HUD      = preload("res://ui/HUD.gd")
const UIFonts  = preload("res://ui/UIFonts.gd")
const Trap     = preload("res://traps/Trap.gd")

const PADDING:   float = 10.0
const BORDER_W:  float = 2.0
# Upgrade buttons are intentionally smaller than the sell touch target.
const UPBTN_H:   float = 40.0

# Green palette — matches the DebugStartDialog aesthetic.
const COLOR_BG          := Color(0.04, 0.22, 0.00, 0.95)
const COLOR_OUTLINE     := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_DIVIDER     := Color(0.06, 0.22, 0.01, 1.0)
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM    := Color(0.55, 0.78, 0.50, 1.0)
const COLOR_STARS       := Color(0.85, 0.72, 0.10, 1.0)

# Upgrade button palette — green.
const COLOR_BTN_NORMAL  := Color(0.02, 0.15, 0.00, 1.0)
const COLOR_BTN_HOVER   := Color(0.07, 0.32, 0.02, 1.0)
const COLOR_BTN_PRESSED := Color(0.01, 0.10, 0.00, 1.0)
const COLOR_BTN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

# Max state — dark so it reads as "done, nothing left to upgrade."
const COLOR_BTN_MAX     := Color(0.06, 0.14, 0.06, 1.0)

# Neutral close button — gray, visually quiet.
const COLOR_NEUTRAL_NORMAL  := Color(0.24, 0.24, 0.28, 1.0)
const COLOR_NEUTRAL_HOVER   := Color(0.34, 0.34, 0.40, 1.0)
const COLOR_NEUTRAL_PRESSED := Color(0.16, 0.16, 0.20, 1.0)
const COLOR_NEUTRAL_BORDER  := Color(0.55, 0.55, 0.62, 1.0)

# Sell button — red to signal a destructive action, distinct from all green buttons.
const COLOR_BTN_SELL         := Color(0.28, 0.10, 0.06, 1.0)
const COLOR_BTN_SELL_HOVER   := Color(0.38, 0.14, 0.08, 1.0)
const COLOR_BTN_SELL_PRESSED := Color(0.18, 0.06, 0.04, 1.0)
const COLOR_BTN_SELL_BORDER  := Color(0.75, 0.22, 0.12, 1.0)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _trap:        Node       = null
var _panel_rect:  Rect2     = Rect2()

var _border:     ColorRect = null
var _bg:         ColorRect = null
var _lbl_title:  Label     = null
var _lbl_damage:       Label = null
var _lbl_damage_stars: Label = null
var _lbl_range:        Label = null
var _lbl_range_stars:  Label = null
var _lbl_rate:         Label = null
var _lbl_rate_stars:   Label = null
var _btn_a:      Button    = null   # Damage upgrade
var _btn_b:      Button    = null   # Range upgrade
var _btn_c:      Button    = null   # Fire Rate upgrade
var _btn_sell:   Button    = null   # Sell trap (70% refund)


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wires the panel to trap and builds the UI. Call immediately after instantiation.
func initialize(trap: Node) -> void:
	_trap  = trap
	_trap.stats_changed.connect(_refresh)
	GameState.bug_bucks_changed.connect(_on_bug_bucks_changed)
	# Stay interactive while Arena pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size

	# Taller panel to accommodate the enlarged stat rows.
	var panel_w := maxf(360.0, vp.x * 0.50)
	var panel_h := vp.y * 0.88
	# Sell button scales with the viewport; upgrade buttons use the fixed UPBTN_H.
	var sell_h  := maxf(52.0, panel_h / 12.0)

	# Centre the panel in the arena zone (the space between the two HUD panels).
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - panel_w * 0.5
	var py       := (vp.y - panel_h) * 0.5

	# Store the full panel rect (including border) for outside-tap detection.
	_panel_rect = Rect2(
		Vector2(px - BORDER_W, py - BORDER_W),
		Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	)

	_border          = ColorRect.new()
	_border.color    = COLOR_OUTLINE
	_border.position = Vector2(px - BORDER_W, py - BORDER_W)
	_border.size     = Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	add_child(_border)

	_bg          = ColorRect.new()
	_bg.color    = COLOR_BG
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(panel_w, panel_h)
	add_child(_bg)

	var inner_w := panel_w - PADDING * 2.0
	var y       := PADDING

	# --- Header: trap name | close button ---
	var header := HBoxContainer.new()
	header.position            = Vector2(PADDING, y)
	header.custom_minimum_size = Vector2(inner_w, 64.0)
	_bg.add_child(header)

	_lbl_title = Label.new()
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 48)
	_lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_lbl_title.add_theme_font_override("font", UIFonts.header())
	header.add_child(_lbl_title)

	var btn_close := Button.new()
	btn_close.text = "X"
	btn_close.add_theme_font_size_override("font_size", 26)
	btn_close.add_theme_font_override("font", UIFonts.primary_bold())
	btn_close.pressed.connect(_on_close)
	_apply_neutral_button_style(btn_close)
	header.add_child(btn_close)

	y += 74.0

	# --- Current stats ---
	# Each row is an HBoxContainer: value label expands to fill, stars label
	# is right-aligned — this keeps the three star columns vertically aligned.
	var dmg_row := _add_stat_row(y, inner_w)
	_lbl_damage       = _make_stat_value_label()
	_lbl_damage_stars = _make_stat_stars_label()
	dmg_row.add_child(_lbl_damage)
	dmg_row.add_child(_lbl_damage_stars)
	y += 54.0

	var rng_row := _add_stat_row(y, inner_w)
	_lbl_range       = _make_stat_value_label()
	_lbl_range_stars = _make_stat_stars_label()
	rng_row.add_child(_lbl_range)
	rng_row.add_child(_lbl_range_stars)
	y += 54.0

	var rate_row := _add_stat_row(y, inner_w)
	_lbl_rate       = _make_stat_value_label()
	_lbl_rate_stars = _make_stat_stars_label()
	rate_row.add_child(_lbl_rate)
	rate_row.add_child(_lbl_rate_stars)
	y += 54.0

	# --- Horizontal divider ---
	_add_divider(y, inner_w)
	y += 14.0

	# --- Upgrade buttons (smaller height than touch-target sell button) ---
	_btn_a = _add_upgrade_button(y, inner_w); y += UPBTN_H + 6.0
	_btn_b = _add_upgrade_button(y, inner_w); y += UPBTN_H + 6.0
	_btn_c = _add_upgrade_button(y, inner_w); y += UPBTN_H + 6.0

	_btn_a.pressed.connect(_on_btn_a)
	_btn_b.pressed.connect(_on_btn_b)
	_btn_c.pressed.connect(_on_btn_c)

	# --- Divider before sell ---
	_add_divider(y, inner_w)
	y += 14.0

	# --- Sell button ---
	_btn_sell = Button.new()
	_btn_sell.position            = Vector2(PADDING, y)
	_btn_sell.custom_minimum_size = Vector2(inner_w, sell_h)
	_btn_sell.add_theme_font_size_override("font_size", 28)
	_btn_sell.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_sell_button_style(_btn_sell)
	_bg.add_child(_btn_sell)
	_btn_sell.pressed.connect(_on_btn_sell)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

## Rebuilds all labels and button states from the trap's current values.
func _refresh() -> void:
	if _trap == null or not is_instance_valid(_trap):
		_on_close()
		return

	_lbl_title.text  = _trap.get_type_name()

	var trap_type: int = _trap.get_type()
	_lbl_range.text        = "Range:     %.1f" % _trap.get_range_radius()
	_lbl_range_stars.text  = _stars(_trap.get_range_level())

	if trap_type == Trap.TrapType.GLUE_BOARD:
		_lbl_damage.text       = "Adhesion:  %d%%" % int(_trap.get_adhesion_pct())
		_lbl_damage_stars.text = _stars(_trap.get_damage_level())
		_lbl_rate.text         = "Fire Rate: passive"
		_lbl_rate_stars.text   = ""
	elif trap_type == Trap.TrapType.FOGGER:
		_lbl_damage.text       = "Potency:   %.1f" % _trap.get_damage()
		_lbl_damage_stars.text = _stars(_trap.get_damage_level())
		_lbl_rate.text         = "Fire Rate: %.2f /s" % _trap.get_shots_per_sec()
		_lbl_rate_stars.text   = _stars(_trap.get_rate_level())
	else:
		_lbl_damage.text       = "Damage:    %.1f" % _trap.get_damage()
		_lbl_damage_stars.text = _stars(_trap.get_damage_level())
		_lbl_rate.text         = "Fire Rate: %.2f /s" % _trap.get_shots_per_sec()
		_lbl_rate_stars.text   = _stars(_trap.get_rate_level())

	# Upgrade button A — label depends on trap type.
	if trap_type == Trap.TrapType.GLUE_BOARD:
		_refresh_button(
			_btn_a,
			_trap.is_damage_maxed(),
			_trap.get_damage_upgrade_cost(),
			"Adhesion  %d%% → %d%%" % [int(_trap.get_adhesion_pct()), int(_trap.get_adhesion_after_upgrade_pct())]
		)
	elif trap_type == Trap.TrapType.FOGGER:
		_refresh_button(
			_btn_a,
			_trap.is_damage_maxed(),
			_trap.get_damage_upgrade_cost(),
			"Potency  %.1f → %.1f" % [_trap.get_damage(), _trap.get_damage_after_upgrade()]
		)
	else:
		_refresh_button(
			_btn_a,
			_trap.is_damage_maxed(),
			_trap.get_damage_upgrade_cost(),
			"Damage   %.1f → %.1f" % [_trap.get_damage(), _trap.get_damage_after_upgrade()]
		)
	_refresh_button(
		_btn_b,
		_trap.is_range_maxed(),
		_trap.get_range_upgrade_cost(),
		"Range    %.1f → %.1f" % [_trap.get_range_radius(), _trap.get_range_after_upgrade()]
	)

	if _trap.is_passive():
		_btn_c.visible = false
	else:
		_btn_c.visible = true
		_refresh_button(
			_btn_c,
			_trap.is_rate_maxed(),
			_trap.get_rate_upgrade_cost(),
			"Fire Rate  %.2f → %.2f /s" % [_trap.get_shots_per_sec(), _trap.get_shots_per_sec_after_upgrade()]
		)

	# Show current sell value on the SELL button.
	var sell_value := int(_trap.get_cost() * 0.70)
	_btn_sell.text = "SELL   +$%d" % sell_value


## Updates one upgrade button: sets text, cost suffix, disabled state, and dim style.
func _refresh_button(btn: Button, maxed: bool, cost: int, label: String) -> void:
	if maxed:
		btn.text     = label.split("  ")[0] + "   MAX"
		btn.disabled = true
		_apply_button_style(btn, true)
	else:
		btn.text     = "%s   $%d" % [label, cost]
		btn.disabled = GameState.bug_bucks < cost
		_apply_button_style(btn, false)


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

## Closes the panel when the player taps outside it (on either mouse or touch).
func _input(event: InputEvent) -> void:
	var pos   := Vector2.ZERO
	var fired := false
	if event is InputEventMouseButton and event.pressed:
		pos = event.position
		fired = true
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
		fired = true
	if fired and not _panel_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		_on_close()


func _on_btn_a() -> void:
	if _trap.is_damage_maxed():
		return
	if not GameState.spend_bug_bucks(_trap.get_damage_upgrade_cost()):
		return
	_trap.apply_damage_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_b() -> void:
	if _trap.is_range_maxed():
		return
	if not GameState.spend_bug_bucks(_trap.get_range_upgrade_cost()):
		return
	_trap.apply_range_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_c() -> void:
	if _trap.is_rate_maxed() or _trap.is_passive():
		return
	if not GameState.spend_bug_bucks(_trap.get_rate_upgrade_cost()):
		return
	_trap.apply_fire_rate_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_sell() -> void:
	# Signal Arena to refund the player and remove the trap from the grid.
	# Arena handles both the Bug Bucks credit and the node cleanup.
	sell_requested.emit()
	# _on_close is not called here — Arena's handler calls queue_free() on us.


func _on_close() -> void:
	if GameState.bug_bucks_changed.is_connected(_on_bug_bucks_changed):
		GameState.bug_bucks_changed.disconnect(_on_bug_bucks_changed)
	closed.emit()
	queue_free()


func _on_bug_bucks_changed(_amount: int) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _add_stat_row(y: float, inner_w: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position            = Vector2(PADDING, y)
	row.custom_minimum_size = Vector2(inner_w, 48.0)
	_bg.add_child(row)
	return row

func _make_stat_value_label() -> Label:
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 39)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	return lbl

func _make_stat_stars_label() -> Label:
	var lbl := Label.new()
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 39)
	lbl.add_theme_color_override("font_color", COLOR_STARS)
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	return lbl


func _add_upgrade_button(y: float, inner_w: float) -> Button:
	var btn               := Button.new()
	btn.position           = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(inner_w, UPBTN_H)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	_apply_button_style(btn, false)
	_bg.add_child(btn)
	return btn


## Returns filled/empty star characters for the given upgrade level out of 3.
func _stars(level: int) -> String:
	return "★".repeat(level) + "☆".repeat(3 - level)


func _add_divider(y: float, inner_w: float) -> void:
	var line     := ColorRect.new()
	line.color    = COLOR_DIVIDER
	line.position = Vector2(PADDING, y)
	line.size     = Vector2(inner_w, 1.0)
	_bg.add_child(line)


## Upgrade button style. maxed=true shows a flat dark box that clearly differs
## from an unaffordable button — maxed can never become available, unaffordable can.
## The disabled state is also overridden so it stays green-dimmed rather than
## falling back to Godot's default gray.
func _apply_button_style(btn: Button, maxed: bool) -> void:
	if maxed:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color           = COLOR_BTN_MAX
			box.border_color       = COLOR_BTN_MAX.lightened(0.12)
			box.set_border_width_all(2)
			box.set_corner_radius_all(4)
			box.content_margin_left   = 8.0
			box.content_margin_right  = 8.0
			box.content_margin_top    = 4.0
			box.content_margin_bottom = 4.0
			btn.add_theme_stylebox_override(state, box)
		btn.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		return

	for state: Array in [
		["normal",   COLOR_BTN_NORMAL],
		["hover",    COLOR_BTN_HOVER],
		["pressed",  COLOR_BTN_PRESSED],
		["disabled", COLOR_BTN_NORMAL.darkened(0.40)],
	]:
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
	btn.add_theme_color_override("font_color",          COLOR_TEXT)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)


## Utility button style — no brand color. Used for the close button.
func _apply_neutral_button_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_NEUTRAL_NORMAL],
		["hover",   COLOR_NEUTRAL_HOVER],
		["pressed", COLOR_NEUTRAL_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_NEUTRAL_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)


## Sell button style — red-toned to signal a destructive action.
func _apply_sell_button_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_BTN_SELL],
		["hover",   COLOR_BTN_SELL_HOVER],
		["pressed", COLOR_BTN_SELL_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_SELL_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
