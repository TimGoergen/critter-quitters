## TrapUpgradePanel.gd
## Appears when the player taps a placed trap. Shows current stats and
## lets the player upgrade each stat by tapping its row, or sell the trap.
##
## Each stat is a tappable row: stat name and star level on the left, the
## current value (large) and a preview of the post-upgrade value (slightly
## smaller, below) on the right, and the cost at the far right. Tapping the
## row purchases that upgrade if the player can afford it.
##
## Panel dimensions are derived from the viewport at build time so touch
## targets scale appropriately across phone screen sizes.
##
## process_mode is ALWAYS so the panel stays interactive while the game
## tree is paused (which Arena does while this panel is open).

extends CanvasLayer

signal closed
signal sell_requested   # Arena connects this to _on_sell_trap_requested(anchor)

const HUD     = preload("res://ui/HUD.gd")
const UIFonts = preload("res://ui/UIFonts.gd")
const Trap    = preload("res://traps/Trap.gd")

const PADDING:    float = 10.0
const BORDER_W:   float = 2.0
# Stat rows double as upgrade buttons — taller than the old separate buttons
# so they work well as touch targets in their own right.
const STAT_ROW_H: float = 100.0

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

# Cost label — gold to match the Bug Bucks coin icon.
const COLOR_GOLD := Color(1.00, 0.82, 0.10, 1.0)
# Delta label — green when the player can buy, amber when they cannot.
# Green signals opportunity; amber signals desire-but-blocked (cost risk).
const COLOR_DELTA_AFFORDABLE   := Color(0.40, 0.90, 0.30, 1.0)
const COLOR_DELTA_UNAFFORDABLE := Color(0.85, 0.50, 0.10, 1.0)

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

var _trap:        Node   = null
var _panel_rect:  Rect2  = Rect2()

var _border:     ColorRect = null
var _bg:         ColorRect = null
var _lbl_title:  Label     = null

# Each stat row is a Button containing child labels.
# Dictionary keys: btn, name, stars, cur, after, cost.
var _dmg_row:  Dictionary = {}
var _rng_row:  Dictionary = {}
var _rate_row: Dictionary = {}

var _btn_sell:       Button = null
var _lbl_sell_value: Label  = null


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wires the panel to trap and builds the UI. Call immediately after instantiation.
func initialize(trap: Node) -> void:
	_trap = trap
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
	var panel_w := maxf(360.0, vp.x * 0.50)
	# Height is content-driven: top padding + header gap + three stat rows + bottom padding.
	var panel_h := PADDING + 74.0 + (STAT_ROW_H + 8.0) * 2.0 + STAT_ROW_H + PADDING

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

	# --- Header: trap name | sell button | close button ---
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

	# Sell button — red, in the header row next to the close button.
	# Left side: trashcan icon. Right side: coin icon + refund amount.
	_btn_sell = Button.new()
	_btn_sell.text                = ""
	_btn_sell.custom_minimum_size = Vector2(160.0, 64.0)
	_apply_sell_button_style(_btn_sell)
	_btn_sell.pressed.connect(_on_btn_sell)
	header.add_child(_btn_sell)

	var sell_hbox := HBoxContainer.new()
	sell_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sell_hbox.offset_left  =  6.0
	sell_hbox.offset_right = -6.0
	sell_hbox.alignment    = BoxContainer.ALIGNMENT_CENTER
	sell_hbox.add_theme_constant_override("separation", 6)
	_btn_sell.add_child(sell_hbox)

	var icon := TrashcanIcon.new()
	icon.custom_minimum_size = Vector2(54.0, 0.0)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sell_hbox.add_child(icon)

	_lbl_sell_value = Label.new()
	_lbl_sell_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_sell_value.add_theme_font_size_override("font_size", 24)
	_lbl_sell_value.add_theme_color_override("font_color", COLOR_GOLD)
	_lbl_sell_value.add_theme_font_override("font", UIFonts.primary_bold())
	sell_hbox.add_child(_lbl_sell_value)

	_set_mouse_passthrough(sell_hbox)

	# Square close button — custom_minimum_size forces equal width and height;
	# _apply_neutral_button_style uses equal margins on all four sides so the X
	# sits at the visual centre of the square, not off-centre.
	var btn_close := Button.new()
	btn_close.text                = "X"
	btn_close.custom_minimum_size = Vector2(64.0, 64.0)
	btn_close.add_theme_font_size_override("font_size", 26)
	btn_close.add_theme_font_override("font", UIFonts.primary_bold())
	btn_close.pressed.connect(_on_close)
	_apply_neutral_button_style(btn_close)
	header.add_child(btn_close)

	y += 74.0

	# --- Stat rows: each row IS the upgrade button for that stat ---
	_dmg_row  = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_rng_row  = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_rate_row = _build_stat_button_row(y, inner_w)

	_dmg_row["btn"].pressed.connect(_on_btn_a)
	_rng_row["btn"].pressed.connect(_on_btn_b)
	_rate_row["btn"].pressed.connect(_on_btn_c)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

## Rebuilds all row labels and button states from the trap's current values.
func _refresh() -> void:
	if _trap == null or not is_instance_valid(_trap):
		_on_close()
		return

	_lbl_title.text = _trap.get_type_name()

	var trap_type: int = _trap.get_type()

	# Damage row — label and value format depend on trap type.
	# after_text is always a delta ("+X") so the player sees the gain, not a second absolute value.
	if trap_type == Trap.TrapType.GLUE_BOARD:
		_refresh_stat_row(
			_dmg_row, "Adhesion", _trap.get_damage_level(),
			"%d%%" % int(_trap.get_adhesion_pct()),
			"+%d%%" % int(_trap.get_adhesion_after_upgrade_pct() - _trap.get_adhesion_pct()),
			_trap.is_damage_maxed(), _trap.get_damage_upgrade_cost()
		)
	elif trap_type == Trap.TrapType.FOGGER:
		_refresh_stat_row(
			_dmg_row, "Potency", _trap.get_damage_level(),
			"%.1f" % _trap.get_damage(),
			"+%.1f" % (_trap.get_damage_after_upgrade() - _trap.get_damage()),
			_trap.is_damage_maxed(), _trap.get_damage_upgrade_cost()
		)
	else:
		_refresh_stat_row(
			_dmg_row, "Damage", _trap.get_damage_level(),
			"%.1f" % _trap.get_damage(),
			"+%.1f" % (_trap.get_damage_after_upgrade() - _trap.get_damage()),
			_trap.is_damage_maxed(), _trap.get_damage_upgrade_cost()
		)

	# Range row — same label for all trap types.
	_refresh_stat_row(
		_rng_row, "Range", _trap.get_range_level(),
		"%.1f" % _trap.get_range_radius(),
		"+%.1f" % (_trap.get_range_after_upgrade() - _trap.get_range_radius()),
		_trap.is_range_maxed(), _trap.get_range_upgrade_cost()
	)

	# Fire Rate row — hidden for passive traps (Glue Board).
	if _trap.is_passive():
		_rate_row["btn"].visible = false
	else:
		_rate_row["btn"].visible = true
		_refresh_stat_row(
			_rate_row, "Fire Rate", _trap.get_rate_level(),
			"%.2f /s" % _trap.get_shots_per_sec(),
			"+%.2f /s" % (_trap.get_shots_per_sec_after_upgrade() - _trap.get_shots_per_sec()),
			_trap.is_rate_maxed(), _trap.get_rate_upgrade_cost()
		)

	# Sell button: keep the refund amount current as upgrades are purchased.
	if _lbl_sell_value != null:
		_lbl_sell_value.text = "🪙%d" % _trap.get_sell_value()

## Updates one stat row's labels and interactive state.
func _refresh_stat_row(
	row: Dictionary,
	name_text: String, level: int,
	cur_text: String, after_text: String,
	maxed: bool, cost: int
) -> void:
	row["name"].text  = name_text
	row["stars"].text = _stars(level)
	row["cur"].text   = cur_text

	if maxed:
		row["after"].text   = ""
		row["cost"].text    = "MAX"
		row["btn"].disabled = true
		_apply_button_style(row["btn"], true)
	else:
		row["after"].text = after_text  # already formatted as "+X.X" by _refresh
		# Color the delta green when affordable (you can gain this now) or amber when not
		# (you can see what you'd gain but can't yet pay — the cost risk is visible).
		var can_afford := GameState.bug_bucks >= cost
		var delta_color := COLOR_DELTA_AFFORDABLE if can_afford else COLOR_DELTA_UNAFFORDABLE
		row["after"].add_theme_color_override("font_color", delta_color)
		row["cost"].text    = "🪙%d" % cost
		row["btn"].disabled = not can_afford
		_apply_button_style(row["btn"], false)


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
	_spawn_coin_burst()
	# Signal Arena to refund the player and remove the trap from the grid.
	# Arena handles both the Bug Bucks credit and the node cleanup.
	sell_requested.emit()
	# _on_close is not called here — Arena's handler calls queue_free() on us.


func _spawn_coin_burst() -> void:
	# Particles must outlive this panel, so they get their own CanvasLayer
	# parented to root. PROCESS_MODE_ALWAYS because the tree is paused while
	# the upgrade panel is open.
	var btn_center := _btn_sell.get_global_rect().get_center()

	var host := CanvasLayer.new()
	host.layer        = 10
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(host)

	var particles := CPUParticles2D.new()
	particles.process_mode         = Node.PROCESS_MODE_ALWAYS
	particles.position             = btn_center
	particles.amount               = 28
	particles.lifetime             = 0.9
	particles.one_shot             = true
	particles.explosiveness        = 1.0   # all particles emit simultaneously
	particles.emitting             = true
	particles.direction            = Vector2(0.0, -1.0)
	particles.spread               = 180.0
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 260.0
	particles.gravity              = Vector2(0.0, 380.0)
	particles.scale_amount_min     = 5.0
	particles.scale_amount_max     = 10.0
	particles.color                = Color(1.00, 0.82, 0.10, 1.0)  # gold
	host.add_child(particles)

	# process_always=true (default) keeps the timer ticking while tree is paused.
	var timer := get_tree().create_timer(particles.lifetime + 0.2)
	timer.timeout.connect(host.queue_free)


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

## Builds one combined stat-display / upgrade-button row.
## Left column: stat name (bold) with star rating below.
## Right column: current value (large) with after-upgrade preview below (smaller).
## Far right: cost label (or "MAX").
## Returns a dict of label refs so _refresh_stat_row() can update in place.
func _build_stat_button_row(y: float, inner_w: float) -> Dictionary:
	var btn := Button.new()
	btn.text                = ""  # All visual content is provided by child labels.
	btn.position            = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(inner_w, STAT_ROW_H)
	_apply_button_style(btn, false)
	_bg.add_child(btn)

	# HBoxContainer fills the button face with horizontal padding.
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left  =  8.0
	hbox.offset_right = -8.0
	hbox.add_theme_constant_override("separation", 12)
	btn.add_child(hbox)

	# Left column: stat name on top, star rating below.
	var vbox_left := VBoxContainer.new()
	vbox_left.custom_minimum_size = Vector2(140.0, 0.0)
	vbox_left.alignment           = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox_left)

	var lbl_name := Label.new()
	lbl_name.add_theme_font_size_override("font_size", 28)
	lbl_name.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_name.add_theme_font_override("font", UIFonts.primary_bold())
	vbox_left.add_child(lbl_name)

	var lbl_stars := Label.new()
	lbl_stars.add_theme_font_size_override("font_size", 44)
	lbl_stars.add_theme_color_override("font_color", COLOR_STARS)
	lbl_stars.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08, 1.0))
	lbl_stars.add_theme_constant_override("outline_size", 4)
	lbl_stars.add_theme_font_override("font", UIFonts.primary_bold())
	vbox_left.add_child(lbl_stars)

	# Flexible spacer separates the name/stars from the value section.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Right section: current value and delta side by side on one horizontal line.
	# Using HBoxContainer so the player reads: "current  +gain" in a single glance.
	var hbox_vals := HBoxContainer.new()
	hbox_vals.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_vals.add_theme_constant_override("separation", 8)
	hbox.add_child(hbox_vals)

	var lbl_cur := Label.new()
	lbl_cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_cur.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_cur.add_theme_font_size_override("font_size", 36)
	lbl_cur.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_cur.add_theme_font_override("font", UIFonts.primary_bold())
	hbox_vals.add_child(lbl_cur)

	# "+X.X" delta — colored by _refresh_stat_row to signal affordability.
	var lbl_after := Label.new()
	lbl_after.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_after.add_theme_font_size_override("font_size", 26)
	lbl_after.add_theme_color_override("font_color", COLOR_DELTA_AFFORDABLE)
	lbl_after.add_theme_font_override("font", UIFonts.primary_bold())
	hbox_vals.add_child(lbl_after)

	# Cost label: coin icon + amount in gold, vertically centered in the row.
	var lbl_cost := Label.new()
	lbl_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_cost.add_theme_font_size_override("font_size", 26)
	lbl_cost.add_theme_color_override("font_color", COLOR_GOLD)
	lbl_cost.add_theme_font_override("font", UIFonts.primary_bold())
	hbox.add_child(lbl_cost)

	# Child controls must not consume input — clicks anywhere in the row must
	# reach the Button itself, not be swallowed by the labels or containers.
	_set_mouse_passthrough(hbox)

	return {
		"btn":   btn,
		"name":  lbl_name,
		"stars": lbl_stars,
		"cur":   lbl_cur,
		"after": lbl_after,
		"cost":  lbl_cost,
	}


## Recursively marks every Control child as mouse-transparent so clicks
## anywhere inside a stat row reach the Button rather than its children.
func _set_mouse_passthrough(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_passthrough(child)


## Returns filled/empty star characters for the given upgrade level out of 3.
func _stars(level: int) -> String:
	return "★".repeat(level) + "☆".repeat(3 - level)


func _add_divider(y: float, inner_w: float) -> void:
	var line     := ColorRect.new()
	line.color    = COLOR_DIVIDER
	line.position = Vector2(PADDING, y)
	line.size     = Vector2(inner_w, 1.0)
	_bg.add_child(line)


## Upgrade button / stat row style. maxed=true shows a flat dark box that clearly
## differs from an unaffordable button — maxed can never become available, unaffordable can.
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
## All four content margins are equal so the label sits at the visual centre
## of the button regardless of its width or height.
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
		box.set_content_margin_all(8.0)
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


# ---------------------------------------------------------------------------
# Trashcan icon — drawn procedurally to represent an old-fashioned round
# steel can: tapered body (narrower at base) with vertical panel lines,
# flat lid, and a small knob handle on top. All black with bright gray edges.
# ---------------------------------------------------------------------------
class TrashcanIcon extends Control:
	func _draw() -> void:
		var s  := minf(size.x, size.y) * 1.02  # 50% larger than the original 0.68
		var cx := size.x * 0.5
		var cy := size.y * 0.5

		var body_w   := s * 0.56   # width at the top of the body
		var base_w   := body_w * 0.72  # narrower at the bottom
		var body_h   := s * 0.62
		var lid_w    := body_w * 1.22
		var lid_h    := s * 0.10
		var handle_w := lid_w * 0.28
		var handle_h := s * 0.09
		var total_h  := handle_h + lid_h + body_h
		var top_y    := cy - total_h * 0.5

		var black := Color(0.0, 0.0, 0.0, 1.0)
		var edge  := Color(0.62, 0.62, 0.62, 1.0)

		var body_top := top_y + handle_h + lid_h
		var body_bot := body_top + body_h

		# Handle — small knob centered on top of the lid.
		var handle_rect := Rect2(cx - handle_w * 0.5, top_y, handle_w, handle_h)
		draw_rect(handle_rect, black)
		draw_rect(handle_rect, edge, false, 2.0, true)

		# Lid — flat rect, slightly wider than the body.
		var lid_rect := Rect2(cx - lid_w * 0.5, top_y + handle_h, lid_w, lid_h)
		draw_rect(lid_rect, black)
		draw_rect(lid_rect, edge, false, 2.0, true)

		# Body — tapered trapezoid: full width at top, narrower at base.
		var body_poly := PackedVector2Array([
			Vector2(cx - body_w * 0.5, body_top),
			Vector2(cx + body_w * 0.5, body_top),
			Vector2(cx + base_w * 0.5, body_bot),
			Vector2(cx - base_w * 0.5, body_bot),
		])
		draw_polygon(body_poly, PackedColorArray([black, black, black, black]))
		var outline_pts := PackedVector2Array([
			body_poly[0], body_poly[1], body_poly[2], body_poly[3], body_poly[0],
		])
		draw_polyline(outline_pts, edge, 2.0, true)

		# Vertical panel lines — stay within the safe inner width (base_w) so they
		# don't clip outside the tapered shape at the bottom.
		for i in 2:
			var lx := cx - base_w * 0.5 + base_w * ((i + 1.0) / 3.0)
			draw_line(Vector2(lx, body_top + 1.0), Vector2(lx, body_bot - 1.0), edge, 2.0, true)
