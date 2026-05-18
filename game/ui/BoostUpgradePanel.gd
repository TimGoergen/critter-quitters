## BoostUpgradePanel.gd
## Appears when the player taps a placed Boost. Shows the Boost's current stats
## and lets the player upgrade each stat by tapping its row, or sell the Boost.
##
## Layout mirrors TrapUpgradePanel: a header row with the Boost name and sell/close
## buttons, followed by up to three stat rows. Boost types with only two upgradeable
## stats (Pheromone Dispenser, Compressor) hide the third row entirely.
##
## Perishable Boosts (Air Freshener, Quarantine Marker) show a capacity bar below
## the stat rows so the player can see how much life the Boost has left.
##
## process_mode is ALWAYS so the panel stays interactive while the game tree is
## paused (which Arena does while this panel is open).

extends CanvasLayer

signal closed
signal sell_requested   # Arena connects this to _on_sell_boost_requested(anchor)

const HUD      = preload("res://ui/HUD.gd")
const UIFonts  = preload("res://ui/UIFonts.gd")
const BoostUnit = preload("res://boosts/BoostUnit.gd")

const PADDING:    float = 10.0
const BORDER_W:   float = 2.0
const STAT_ROW_H: float = 100.0
const DESC_H:     float = 52.0

# Theme colors — derived from the boost's identity color at initialize time.
var COLOR_BG:                  Color
var COLOR_OUTLINE:             Color
var COLOR_DIVIDER:             Color
var COLOR_TEXT_DIM:            Color
var COLOR_BTN_NORMAL:          Color
var COLOR_BTN_HOVER:           Color
var COLOR_BTN_PRESSED:         Color
var COLOR_BTN_BORDER:          Color
var COLOR_BTN_MAX:             Color
var COLOR_STAT_DISPLAY:        Color
var COLOR_STAT_DISPLAY_BORDER: Color

# Neutral colors — do not vary with boost type.
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_STARS       := Color(0.85, 0.72, 0.10, 1.0)
const COLOR_BTN_MAX_BORDER  := Color(0.55, 0.55, 0.55, 1.0)
const COLOR_GOLD            := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_DELTA_AFFORDABLE   := Color(0.40, 0.90, 0.30, 1.0)
const COLOR_DELTA_UNAFFORDABLE := Color(0.85, 0.50, 0.10, 1.0)
const COLOR_NEUTRAL_NORMAL  := Color(0.24, 0.24, 0.28, 1.0)
const COLOR_NEUTRAL_HOVER   := Color(0.34, 0.34, 0.40, 1.0)
const COLOR_NEUTRAL_PRESSED := Color(0.16, 0.16, 0.20, 1.0)
const COLOR_NEUTRAL_BORDER  := Color(0.55, 0.55, 0.62, 1.0)
const COLOR_BTN_SELL         := Color(0.28, 0.10, 0.06, 1.0)
const COLOR_BTN_SELL_HOVER   := Color(0.38, 0.14, 0.08, 1.0)
const COLOR_BTN_SELL_PRESSED := Color(0.18, 0.06, 0.04, 1.0)
const COLOR_BTN_SELL_BORDER  := Color(0.75, 0.22, 0.12, 1.0)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _boost:       Node  = null
var _panel_rect:  Rect2 = Rect2()

var _border:     Panel     = null
var _bg:         ColorRect = null
var _lbl_title:  Label     = null

# Each row is a Dictionary: {row, btn, name, stars, cur, after, cost}
var _rng_row:  Dictionary = {}   # stat A: Range
var _b_row:    Dictionary = {}   # stat B: primary bonus
var _c_row:    Dictionary = {}   # stat C: secondary (hidden for 2-stat boosts)

var _btn_sell:       Button = null
var _lbl_sell_value: Label  = null

# Capacity bar — only visible for perishable boost types.
var _capacity_bar_bg:   ColorRect = null
var _capacity_bar_fill: ColorRect = null
var _lbl_capacity:      Label     = null


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Wires the panel to a BoostUnit and builds the UI. Call immediately after instantiation.
func initialize(boost: Node) -> void:
	_boost = boost
	_boost.stats_changed.connect(_refresh)
	GameState.bug_bucks_changed.connect(_on_bug_bucks_changed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_boost_theme()
	_build_ui()
	_refresh()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size
	var panel_w := maxf(360.0, vp.x * 0.50)

	# Height: header + description + 2 or 3 stat rows + optional capacity bar + bottom padding.
	var row_count    := 3 if _boost.has_stat_c() else 2
	var extra_h      := 36.0 if _is_perishable() else 0.0
	var panel_h      := PADDING + 74.0 + DESC_H + 8.0 + (STAT_ROW_H + 8.0) * (row_count - 1) + STAT_ROW_H + extra_h + PADDING

	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - panel_w * 0.5
	var py       := (vp.y - panel_h) * 0.5

	_panel_rect = Rect2(
		Vector2(px - BORDER_W, py - BORDER_W),
		Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	)

	var border_style         := StyleBoxFlat.new()
	border_style.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
	border_style.border_color = COLOR_OUTLINE
	border_style.set_border_width_all(int(BORDER_W))
	_border          = Panel.new()
	_border.position = Vector2(px - BORDER_W, py - BORDER_W)
	_border.size     = Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	_border.add_theme_stylebox_override("panel", border_style)
	add_child(_border)

	_bg          = ColorRect.new()
	_bg.color    = COLOR_BG
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(panel_w, panel_h)
	add_child(_bg)

	var inner_w := panel_w - PADDING * 2.0
	var y       := PADDING

	# Header: boost name | sell button | close button
	var header := HBoxContainer.new()
	header.position            = Vector2(PADDING, y)
	header.custom_minimum_size = Vector2(inner_w, 64.0)
	header.add_theme_constant_override("separation", 8)
	_bg.add_child(header)

	_lbl_title = Label.new()
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 42)
	_lbl_title.add_theme_color_override("font_color", COLOR_TEXT)
	_lbl_title.add_theme_font_override("font", UIFonts.header())
	header.add_child(_lbl_title)

	_btn_sell = Button.new()
	_btn_sell.text                = ""
	_btn_sell.custom_minimum_size = Vector2(136.0, 64.0)
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

	var trash := TrashcanIcon.new()
	trash.custom_minimum_size = Vector2(46.0, 0.0)
	trash.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trash.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sell_hbox.add_child(trash)

	_lbl_sell_value = Label.new()
	_lbl_sell_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_sell_value.add_theme_font_size_override("font_size", 22)
	_lbl_sell_value.add_theme_color_override("font_color", COLOR_GOLD)
	_lbl_sell_value.add_theme_font_override("font", UIFonts.primary_bold())
	sell_hbox.add_child(_lbl_sell_value)
	_set_mouse_passthrough(sell_hbox)

	var btn_close := Button.new()
	btn_close.text                = "X"
	btn_close.custom_minimum_size = Vector2(64.0, 64.0)
	btn_close.add_theme_font_size_override("font_size", 26)
	btn_close.add_theme_font_override("font", UIFonts.primary_bold())
	btn_close.pressed.connect(_on_close)
	_apply_neutral_button_style(btn_close)
	header.add_child(btn_close)

	y += 74.0

	# --- Description label ---
	var lbl_desc := Label.new()
	lbl_desc.position      = Vector2(PADDING, y)
	lbl_desc.size          = Vector2(inner_w, DESC_H)
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_ARBITRARY
	lbl_desc.add_theme_font_override("font", UIFonts.primary())
	lbl_desc.add_theme_font_size_override("font_size", 18)
	lbl_desc.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	lbl_desc.text          = _boost.get_description()
	_bg.add_child(lbl_desc)
	y += DESC_H + 8.0

	# Stat rows
	_rng_row = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_b_row   = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_c_row   = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0

	_rng_row["btn"].pressed.connect(_on_btn_range)
	_b_row["btn"].pressed.connect(_on_btn_stat_b)
	_c_row["btn"].pressed.connect(_on_btn_stat_c)

	# Hide stat C row immediately for 2-stat boosts — it never becomes visible.
	if not _boost.has_stat_c():
		_c_row["row"].visible = false

	# Capacity bar — shown only for perishable boosts.
	if _is_perishable():
		_build_capacity_bar(y, inner_w)


## Derives the panel color palette from the boost's identity color.
func _apply_boost_theme() -> void:
	var base: Color = _boost.get_base_color()
	var h    := base.h
	var s    := base.s
	var v    := base.v

	COLOR_BG                  = Color.from_hsv(h, s * 0.75, v * 0.15, 0.80)
	COLOR_OUTLINE             = Color.from_hsv(h, s * 0.85, v * 0.62, 1.0)
	COLOR_DIVIDER             = Color.from_hsv(h, s * 0.75, v * 0.22, 1.0)
	COLOR_TEXT_DIM            = Color.from_hsv(h, s * 0.35, v * 0.78, 1.0)
	COLOR_BTN_NORMAL          = Color.from_hsv(h, s * 0.90, v * 0.16, 1.0)
	COLOR_BTN_HOVER           = Color.from_hsv(h, s * 0.90, v * 0.34, 1.0)
	COLOR_BTN_PRESSED         = Color.from_hsv(h, s * 0.85, v * 0.10, 1.0)
	COLOR_BTN_BORDER          = Color.from_hsv(h, s * 0.85, v * 0.62, 1.0)
	COLOR_BTN_MAX             = Color.from_hsv(h, s * 0.20, v * 0.14, 1.0)
	COLOR_STAT_DISPLAY        = Color.from_hsv(h, s * 0.40, v * 0.12, 0.50)
	COLOR_STAT_DISPLAY_BORDER = Color.from_hsv(h, s * 0.70, v * 0.42, 1.0)


## Builds the remaining-capacity bar shown below the stat rows for perishable boosts.
func _build_capacity_bar(y: float, inner_w: float) -> void:
	var bar_h   := 16.0
	var lbl_h   := 18.0
	var total_y := y

	_lbl_capacity = Label.new()
	_lbl_capacity.position = Vector2(PADDING, total_y)
	_lbl_capacity.size     = Vector2(inner_w, lbl_h)
	_lbl_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_capacity.add_theme_font_size_override("font_size", 16)
	_lbl_capacity.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_lbl_capacity.add_theme_font_override("font", UIFonts.primary_bold())
	_bg.add_child(_lbl_capacity)

	total_y += lbl_h + 2.0

	# Background track.
	_capacity_bar_bg       = ColorRect.new()
	_capacity_bar_bg.color = Color(0.12, 0.12, 0.14, 0.90)
	_capacity_bar_bg.position = Vector2(PADDING, total_y)
	_capacity_bar_bg.size     = Vector2(inner_w, bar_h)
	_bg.add_child(_capacity_bar_bg)

	# Colored fill — width updated each _refresh().
	_capacity_bar_fill       = ColorRect.new()
	_capacity_bar_fill.color = COLOR_OUTLINE
	_capacity_bar_fill.position = Vector2(PADDING, total_y)
	_capacity_bar_fill.size     = Vector2(inner_w, bar_h)
	_bg.add_child(_capacity_bar_fill)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

## Rebuilds all row labels and button states from the boost's current values.
func _refresh() -> void:
	if _boost == null or not is_instance_valid(_boost):
		_on_close()
		return

	_lbl_title.text = _boost.get_type_name()

	# Range row.
	_refresh_stat_row(
		_rng_row, "Range", _boost.get_range_level(),
		"%.1f" % _boost.get_range_radius(),
		"+%.1f" % (_boost.get_range_after_upgrade() - _boost.get_range_radius()),
		_boost.is_range_maxed(), _boost.get_range_upgrade_cost()
	)

	# Stat B row.
	var b_cur:   float = _boost.get_stat_b_value()
	var b_after: float = _boost.get_stat_b_after_upgrade()
	_refresh_stat_row(
		_b_row, _boost.get_stat_b_name(), _boost.get_stat_b_level(),
		_boost.format_stat_b(b_cur),
		"+%s" % _boost.format_stat_b(b_after - b_cur),
		_boost.is_stat_b_maxed(), _boost.get_stat_b_upgrade_cost()
	)

	# Stat C row — only relevant for 3-stat boosts; row is hidden for others.
	if _boost.has_stat_c():
		var c_cur:   float = _boost.get_stat_c_value()
		var c_after: float = _boost.get_stat_c_after_upgrade()
		_refresh_stat_row(
			_c_row, _boost.get_stat_c_name(), _boost.get_stat_c_level(),
			_boost.format_stat_c(c_cur),
			"+%s" % _boost.format_stat_c(c_after - c_cur),
			_boost.is_stat_c_maxed(), _boost.get_stat_c_upgrade_cost()
		)

	# Sell value.
	if _lbl_sell_value != null:
		_lbl_sell_value.text = "🪙%d" % _boost.get_sell_value()

	# Capacity bar.
	if _is_perishable() and _capacity_bar_fill != null:
		var frac: float = _boost.get_capacity_fraction()
		_capacity_bar_fill.size.x = _capacity_bar_bg.size.x * frac
		_lbl_capacity.text        = "Capacity: %d%%" % int(frac * 100.0)


## Updates one stat row's labels and button state.
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
		row["after"].visible              = false
		row["cost"].text                  = "MAX"
		row["cost"].horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		row["btn"].disabled               = true
		_apply_button_style(row["btn"], true)
	else:
		row["after"].visible              = true
		row["after"].text                 = after_text
		row["cost"].horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		var can_afford := GameState.bug_bucks >= cost
		row["after"].add_theme_color_override(
			"font_color",
			COLOR_DELTA_AFFORDABLE if can_afford else COLOR_DELTA_UNAFFORDABLE
		)
		row["cost"].text    = "🪙%d" % cost
		row["btn"].disabled = not can_afford
		_apply_button_style(row["btn"], false)


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var pos   := Vector2.ZERO
	var fired := false
	if event is InputEventMouseButton and event.pressed:
		pos = event.position; fired = true
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position; fired = true
	if fired and not _panel_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		_on_close()


func _on_btn_range() -> void:
	if _boost.is_range_maxed():
		return
	if not GameState.spend_bug_bucks(_boost.get_range_upgrade_cost()):
		return
	_boost.apply_range_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_stat_b() -> void:
	if _boost.is_stat_b_maxed():
		return
	if not GameState.spend_bug_bucks(_boost.get_stat_b_upgrade_cost()):
		return
	_boost.apply_stat_b_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_stat_c() -> void:
	if not _boost.has_stat_c() or _boost.is_stat_c_maxed():
		return
	if not GameState.spend_bug_bucks(_boost.get_stat_c_upgrade_cost()):
		return
	_boost.apply_stat_c_upgrade()
	AudioManager.play_ui("upgrade")


func _on_btn_sell() -> void:
	_spawn_coin_burst()
	sell_requested.emit()


func _spawn_coin_burst() -> void:
	var camera    := get_viewport().get_camera_3d()
	var burst_pos := camera.unproject_position(_boost.global_position)

	var host := CanvasLayer.new()
	host.layer        = 10
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(host)

	var particles := CPUParticles2D.new()
	particles.process_mode         = Node.PROCESS_MODE_ALWAYS
	particles.position             = burst_pos
	particles.amount               = 28
	particles.lifetime             = 0.9
	particles.one_shot             = true
	particles.explosiveness        = 1.0
	particles.emitting             = true
	particles.direction            = Vector2(0.0, -1.0)
	particles.spread               = 180.0
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 260.0
	particles.gravity              = Vector2(0.0, 380.0)
	particles.scale_amount_min     = 5.0
	particles.scale_amount_max     = 10.0
	particles.color                = COLOR_GOLD
	host.add_child(particles)

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

func _build_stat_button_row(y: float, inner_w: float) -> Dictionary:
	var left_col := 140.0
	var split_x  := inner_w * 0.60

	var row_ctrl := Control.new()
	row_ctrl.position     = Vector2(PADDING, y)
	row_ctrl.size         = Vector2(inner_w, STAT_ROW_H)
	row_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(row_ctrl)

	var panel_bg := Panel.new()
	panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color     = COLOR_STAT_DISPLAY
	bg_style.border_color = COLOR_STAT_DISPLAY_BORDER
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(4)
	panel_bg.add_theme_stylebox_override("panel", bg_style)
	row_ctrl.add_child(panel_bg)

	var vbox_left := VBoxContainer.new()
	vbox_left.position     = Vector2(8.0, 0.0)
	vbox_left.size         = Vector2(left_col, STAT_ROW_H)
	vbox_left.alignment    = BoxContainer.ALIGNMENT_CENTER
	vbox_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_left.add_theme_constant_override("separation", 0)
	row_ctrl.add_child(vbox_left)

	var lbl_name := Label.new()
	lbl_name.add_theme_font_size_override("font_size", 26)
	lbl_name.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_name.add_theme_font_override("font", UIFonts.primary_bold())
	lbl_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_left.add_child(lbl_name)

	var lbl_stars := Label.new()
	lbl_stars.add_theme_font_size_override("font_size", 44)
	lbl_stars.add_theme_color_override("font_color", COLOR_STARS)
	lbl_stars.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08, 1.0))
	lbl_stars.add_theme_constant_override("outline_size", 4)
	lbl_stars.add_theme_font_override("font", UIFonts.primary_bold())
	lbl_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_left.add_child(lbl_stars)

	var lbl_cur := Label.new()
	lbl_cur.position             = Vector2(0.0, 0.0)
	lbl_cur.size                 = Vector2(split_x, STAT_ROW_H)
	lbl_cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_cur.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_cur.add_theme_font_size_override("font_size", 34)
	lbl_cur.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_cur.add_theme_font_override("font", UIFonts.primary_bold())
	lbl_cur.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	row_ctrl.add_child(lbl_cur)

	var btn_h   := STAT_ROW_H * 0.60
	var v_inset := (STAT_ROW_H - btn_h) * 0.5
	var btn_x   := split_x + v_inset
	var btn_w   := inner_w - btn_x - v_inset
	var btn := Button.new()
	btn.text       = ""
	btn.position   = Vector2(btn_x, v_inset)
	btn.size       = Vector2(btn_w, btn_h)
	btn.focus_mode = Control.FOCUS_NONE
	_apply_button_style(btn, false)
	row_ctrl.add_child(btn)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn_hbox.offset_left  =  8.0
	btn_hbox.offset_right = -8.0
	btn_hbox.alignment    = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(btn_hbox)

	var lbl_after := Label.new()
	lbl_after.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_after.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	lbl_after.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl_after.add_theme_font_size_override("font_size", 22)
	lbl_after.add_theme_color_override("font_color", COLOR_DELTA_AFFORDABLE)
	lbl_after.add_theme_font_override("font", UIFonts.primary_bold())
	btn_hbox.add_child(lbl_after)

	var lbl_cost := Label.new()
	lbl_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_cost.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_cost.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl_cost.add_theme_font_size_override("font_size", 22)
	lbl_cost.add_theme_color_override("font_color", COLOR_GOLD)
	lbl_cost.add_theme_font_override("font", UIFonts.primary_bold())
	btn_hbox.add_child(lbl_cost)

	_set_mouse_passthrough(btn_hbox)

	return {
		"row":   row_ctrl,
		"btn":   btn,
		"name":  lbl_name,
		"stars": lbl_stars,
		"cur":   lbl_cur,
		"after": lbl_after,
		"cost":  lbl_cost,
	}


## Returns true for perishable boost types that have a remaining-capacity bar.
func _is_perishable() -> bool:
	return _boost.get_type() in [
		BoostUnit.BoostType.AIR_FRESHENER,
		BoostUnit.BoostType.QUARANTINE_MARKER,
	]


func _set_mouse_passthrough(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_passthrough(child)


func _stars(level: int) -> String:
	return "★".repeat(level) + "☆".repeat(3 - level)


func _apply_button_style(btn: Button, maxed: bool) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if maxed:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color           = COLOR_BTN_MAX
			box.border_color       = COLOR_BTN_MAX_BORDER
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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


# ---------------------------------------------------------------------------
# Trashcan icon — identical to TrapUpgradePanel.TrashcanIcon.
# ---------------------------------------------------------------------------
class TrashcanIcon extends Control:
	func _draw() -> void:
		var s  := minf(size.x, size.y) * 1.02
		var cx := size.x * 0.5
		var cy := size.y * 0.5

		var body_w   := s * 0.56
		var base_w   := body_w * 0.72
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

		var handle_rect := Rect2(cx - handle_w * 0.5, top_y, handle_w, handle_h)
		draw_rect(handle_rect, black)
		draw_rect(handle_rect, edge, false, 2.0, true)

		var lid_rect := Rect2(cx - lid_w * 0.5, top_y + handle_h, lid_w, lid_h)
		draw_rect(lid_rect, black)
		draw_rect(lid_rect, edge, false, 2.0, true)

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

		for i in 2:
			var lx := cx - base_w * 0.5 + base_w * ((i + 1.0) / 3.0)
			draw_line(Vector2(lx, body_top + 1.0), Vector2(lx, body_bot - 1.0), edge, 2.0, true)
