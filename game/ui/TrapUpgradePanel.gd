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
const STAT_ROW_H:          float = 100.0
# Height reserved for the description label block between the header and stat rows.
const DESC_H:              float = 52.0
# Active-boost section at the panel bottom (shown only when boosts are in range).
const BOOST_SECTION_LEAD:  float = 10.0   # gap + 1px divider before the first entry
const BOOST_ENTRY_H:       float = 22.0   # height per boost entry row

# Size of the trap thumbnail in the header.
const HEADER_ICON_RENDER:  float = 90.0   # SubViewport pixel resolution
const HEADER_ICON_DISPLAY: float = 64.0   # icon displayed as a 64×64 square (matches button height)

# Theme colours — derived from the placed trap's identity colour at runtime.
# Declared as vars so _apply_trap_theme() can assign them before _build_ui() runs
# (GDScript const cannot be assigned after declaration).
var COLOR_BG:                  Color  # panel background, semi-transparent dark tint
var COLOR_OUTLINE:             Color  # panel border ring
var COLOR_DIVIDER:             Color  # horizontal divider lines
var COLOR_TEXT_DIM:            Color  # secondary text (stars label, affordability hint)
var COLOR_BTN_NORMAL:          Color  # upgrade button resting state
var COLOR_BTN_HOVER:           Color  # upgrade button hover
var COLOR_BTN_PRESSED:         Color  # upgrade button press
var COLOR_BTN_BORDER:          Color  # upgrade button outline (matches panel outline)
var COLOR_BTN_MAX:             Color  # muted maxed-stat button background
var COLOR_STAT_DISPLAY:        Color  # stat row background panel
var COLOR_STAT_DISPLAY_BORDER: Color  # stat row panel border

# Neutral colours — do not vary with trap type.
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_STARS       := Color(0.85, 0.72, 0.10, 1.0)
# Max state border — always gray so it reads as permanently exhausted, not just unaffordable.
const COLOR_BTN_MAX_BORDER := Color(0.55, 0.55, 0.55, 1.0)
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
# Sell button — red to signal a destructive action, distinct from the themed buttons.
const COLOR_BTN_SELL         := Color(0.28, 0.10, 0.06, 1.0)
const COLOR_BTN_SELL_HOVER   := Color(0.38, 0.14, 0.08, 1.0)
const COLOR_BTN_SELL_PRESSED := Color(0.18, 0.06, 0.04, 1.0)
const COLOR_BTN_SELL_BORDER  := Color(0.75, 0.22, 0.12, 1.0)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _trap:        Node   = null
var _panel_rect:  Rect2  = Rect2()

var _border:     Panel     = null
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
	_apply_trap_theme()
	_build_ui()
	_refresh()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size
	var panel_w := maxf(360.0, vp.x * 0.50)

	# Read active boost entries now so we know how much extra height they need.
	# Boosts cannot enter or leave range while the panel is open (the game tree is
	# paused while the upgrade panel is visible), so reading once at build time is safe.
	var boosts:  Array = _trap.get_active_boost_display()
	var boost_h: float = BOOST_SECTION_LEAD + BOOST_ENTRY_H * boosts.size() if not boosts.is_empty() else 0.0

	# Height: top padding + header + description block + three stat rows + active boosts + bottom padding.
	var panel_h := PADDING + 74.0 + DESC_H + 8.0 + (STAT_ROW_H + 8.0) * 2.0 + STAT_ROW_H + boost_h + PADDING

	# Centre the panel in the arena zone (the space between the two HUD panels).
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - panel_w * 0.5
	var py       := (vp.y - panel_h) * 0.5

	# Store the full panel rect (including border) for outside-tap detection.
	_panel_rect = Rect2(
		Vector2(px - BORDER_W, py - BORDER_W),
		Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	)

	# Panel with a transparent background so only the ring is drawn.
	# A solid ColorRect here would block the 3D scene behind the semi-transparent _bg.
	var border_style         := StyleBoxFlat.new()
	border_style.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
	border_style.border_color = COLOR_OUTLINE
	border_style.set_border_width_all(int(BORDER_W))
	_border          = Panel.new()
	_border.position = Vector2(px - BORDER_W, py - BORDER_W)
	_border.size     = Vector2(panel_w + BORDER_W * 2.0, panel_h + BORDER_W * 2.0)
	_border.add_theme_stylebox_override("panel", border_style)
	add_child(_border)

	_bg            = ColorRect.new()
	_bg.color      = COLOR_BG
	_bg.position   = Vector2(px, py)
	_bg.size       = Vector2(panel_w, panel_h)
	add_child(_bg)

	var inner_w := panel_w - PADDING * 2.0
	var y       := PADDING

	# --- Header: trap name | sell button | close button ---
	var header := HBoxContainer.new()
	header.position            = Vector2(PADDING, y)
	header.custom_minimum_size = Vector2(inner_w, 64.0)
	header.add_theme_constant_override("separation", 8)
	_bg.add_child(header)

	_lbl_title = Label.new()
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 48)
	_lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_lbl_title.add_theme_font_override("font", UIFonts.header())
	header.add_child(_lbl_title)

	# Trap thumbnail — a small top-down render of the trap type placed immediately
	# right of the name so the player has an instant visual reference for which trap
	# they are upgrading without reading the label.
	header.add_child(_build_header_trap_icon())

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

	# --- Description label ---
	var lbl_desc := Label.new()
	lbl_desc.position      = Vector2(PADDING, y)
	lbl_desc.size          = Vector2(inner_w, DESC_H)
	lbl_desc.autowrap_mode = 3   # TextServer.AUTOWRAP_WORD_ARBITRARY
	lbl_desc.add_theme_font_override("font", UIFonts.primary())
	lbl_desc.add_theme_font_size_override("font_size", 18)
	lbl_desc.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	lbl_desc.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	lbl_desc.text          = _trap.get_description()
	_bg.add_child(lbl_desc)
	y += DESC_H + 8.0

	# --- Stat rows: each row IS the upgrade button for that stat ---
	_dmg_row  = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_rng_row  = _build_stat_button_row(y, inner_w); y += STAT_ROW_H + 8.0
	_rate_row = _build_stat_button_row(y, inner_w)

	_dmg_row["btn"].pressed.connect(_on_btn_a)
	_rng_row["btn"].pressed.connect(_on_btn_b)
	_rate_row["btn"].pressed.connect(_on_btn_c)

	# --- Active boosts section ---
	# Advance y past the last stat row, then draw one compact row per active boost.
	y += STAT_ROW_H
	if not boosts.is_empty():
		_build_active_boosts_section(y, inner_w, boosts)


## Derives the panel's colour palette from the placed trap's identity colour.
## All hue-tinted colours share the trap's hue; saturation and value factors
## are chosen so the panel reads as clearly tinted while text stays legible.
## Must be called after _trap is set and before _build_ui() runs.
func _apply_trap_theme() -> void:
	var base: Color = _trap.get_base_color()
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


## Builds a small top-down SubViewport render of the trap for the header row.
## Keeps decorators (coloured background plate, shadow) so the trap's identity
## colour is immediately visible; hides only the range indicator circle.
func _build_header_trap_icon() -> Control:
	var icon_ctrl := Control.new()
	icon_ctrl.custom_minimum_size = Vector2(HEADER_ICON_DISPLAY, HEADER_ICON_DISPLAY)
	# SIZE_FILL (default) lets the HBox stretch the icon to the full row height (64 px),
	# matching the sell and close buttons.  SIZE_SHRINK_CENTER would cap it at min-height.
	icon_ctrl.mouse_filter        = Control.MOUSE_FILTER_IGNORE

	var svp := SubViewport.new()
	svp.size                      = Vector2i(int(HEADER_ICON_RENDER), int(HEADER_ICON_RENDER))
	svp.own_world_3d              = true
	svp.transparent_bg            = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Background plate is 1.85 world units wide; cam.size = 1.9 makes it fill ~97%
	# of the viewport so the coloured icon looks as tall as the adjacent buttons.
	# (The HUD selector icons use 3.1 but those hide decorators and show only the
	# small trap model, so the looser framing is appropriate there.)
	cam.size       = 1.9
	cam.position   = Vector3(0.0, 5.0, 0.0)
	cam.rotation   = Vector3(-PI * 0.5, 0.0, 0.0)
	svp.add_child(cam)

	var trap_preview := Node3D.new()
	trap_preview.set_script(Trap)
	trap_preview.initialize_preview(_trap.get_type())
	svp.add_child(trap_preview)
	# Range indicator is spawned and shown in _ready() for preview instances;
	# hide it deferred so the circle does not appear in the thumbnail.
	trap_preview.call_deferred("hide_range_indicator")

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch      = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# StyleBoxEmpty prevents SubViewportContainer from drawing its default background.
	svc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	svc.add_child(svp)
	icon_ctrl.add_child(svc)

	return icon_ctrl


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
			"%.1f" % _trap.get_effective_damage(),
			"+%.1f" % (_trap.get_effective_damage_after_upgrade() - _trap.get_effective_damage()),
			_trap.is_damage_maxed(), _trap.get_damage_upgrade_cost()
		)
	else:
		_refresh_stat_row(
			_dmg_row, "Damage", _trap.get_damage_level(),
			"%.1f" % _trap.get_effective_damage(),
			"+%.1f" % (_trap.get_effective_damage_after_upgrade() - _trap.get_effective_damage()),
			_trap.is_damage_maxed(), _trap.get_damage_upgrade_cost()
		)

	# Range row — same label for all trap types.
	_refresh_stat_row(
		_rng_row, "Range", _trap.get_range_level(),
		"%.1f" % _trap.get_range_radius(),
		"+%.1f" % (_trap.get_range_after_upgrade() - _trap.get_range_radius()),
		_trap.is_range_maxed(), _trap.get_range_upgrade_cost()
	)

	# Third stat row: Duration for Glue Board, Fire Rate for active traps.
	if trap_type == Trap.TrapType.GLUE_BOARD:
		_rate_row["row"].visible = true
		_refresh_stat_row(
			_rate_row, "Duration", _trap.get_duration_level(),
			"%.1fs" % _trap.get_duration(),
			"+%.1fs" % (_trap.get_duration_after_upgrade() - _trap.get_duration()),
			_trap.is_duration_maxed(), _trap.get_duration_upgrade_cost()
		)
	elif _trap.is_passive():
		_rate_row["row"].visible = false
	else:
		_rate_row["row"].visible = true
		_refresh_stat_row(
			_rate_row, "Fire Rate", _trap.get_rate_level(),
			"%.2f /s" % _trap.get_effective_shots_per_sec(),
			"+%.2f /s" % (_trap.get_effective_shots_per_sec_after_upgrade() - _trap.get_effective_shots_per_sec()),
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
		# Hide the delta label so "MAX" fills the full button width and can center itself.
		row["after"].visible              = false
		row["cost"].text                  = "MAX"
		row["cost"].horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		row["btn"].disabled = true
		_apply_button_style(row["btn"], true)
	else:
		row["after"].visible              = true
		row["after"].text                 = after_text  # already formatted as "+X.X" by _refresh
		row["cost"].horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
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
	if _trap.get_type() == Trap.TrapType.GLUE_BOARD:
		if _trap.is_duration_maxed():
			return
		if not GameState.spend_bug_bucks(_trap.get_duration_upgrade_cost()):
			return
		_trap.apply_duration_upgrade()
		AudioManager.play_ui("upgrade")
	else:
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
	var camera    := get_viewport().get_camera_3d()
	var burst_pos := camera.unproject_position(_trap.global_position)

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

## Draws a thin divider followed by one compact row per active boost entry.
## Each row shows the boost name on the left and the stat effect on the right.
func _build_active_boosts_section(y: float, inner_w: float, boosts: Array) -> void:
	# Thin divider — uses the same color as the section dividers above the stat rows.
	var divider        := ColorRect.new()
	divider.color       = COLOR_DIVIDER
	divider.position    = Vector2(PADDING, y + 8.0)
	divider.size        = Vector2(inner_w, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(divider)

	var entry_y := y + BOOST_SECTION_LEAD
	for entry: Dictionary in boosts:
		var row_ctrl              := Control.new()
		row_ctrl.position          = Vector2(PADDING, entry_y)
		row_ctrl.size              = Vector2(inner_w, BOOST_ENTRY_H)
		row_ctrl.mouse_filter      = Control.MOUSE_FILTER_IGNORE
		_bg.add_child(row_ctrl)

		var lbl_name := Label.new()
		lbl_name.position             = Vector2(0.0, 0.0)
		lbl_name.size                 = Vector2(inner_w * 0.65, BOOST_ENTRY_H)
		lbl_name.text                 = "  • " + entry["name"]   # bullet character
		lbl_name.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl_name.add_theme_font_override("font", UIFonts.primary())
		lbl_name.add_theme_font_size_override("font_size", 16)
		lbl_name.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		lbl_name.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		row_ctrl.add_child(lbl_name)

		var lbl_detail := Label.new()
		lbl_detail.position              = Vector2(inner_w * 0.65, 0.0)
		lbl_detail.size                  = Vector2(inner_w * 0.35, BOOST_ENTRY_H)
		lbl_detail.text                  = entry["detail"]
		lbl_detail.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		lbl_detail.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		lbl_detail.add_theme_font_override("font", UIFonts.primary_bold())
		lbl_detail.add_theme_font_size_override("font_size", 16)
		lbl_detail.add_theme_color_override("font_color", COLOR_DELTA_AFFORDABLE)
		lbl_detail.mouse_filter          = Control.MOUSE_FILTER_IGNORE
		row_ctrl.add_child(lbl_detail)

		entry_y += BOOST_ENTRY_H


## Builds one stat row: a full-width background panel with an inset upgrade button
## overlaid on the right portion.
##
## Layout (absolute coordinates within row_ctrl):
##   panel_bg  — full width, decorative background only (no child content)
##   vbox_left — name + stars, anchored to left edge
##   lbl_cur   — current value, spans x=0..60% of row, text right-aligned to the split
##   btn       — upgrade button, inset inside the right 40%, smaller than the panel
##
## "row" key controls visibility (e.g. Fire Rate on passive traps).
## "btn" key is the clickable upgrade button.
func _build_stat_button_row(y: float, inner_w: float) -> Dictionary:
	# Width reserved for the name+stars column.
	var left_col  := 140.0
	# Horizontal split: value label ends here, button begins here.
	var split_x   := inner_w * 0.60

	# Root plain Control — holds all row elements as absolutely-positioned children.
	# MOUSE_FILTER_IGNORE on the root so it does not eat events from the Button child.
	var row_ctrl := Control.new()
	row_ctrl.position     = Vector2(PADDING, y)
	row_ctrl.size         = Vector2(inner_w, STAT_ROW_H)
	row_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(row_ctrl)

	# Full-width background panel — purely decorative, no children, no interaction.
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

	# Name + stars — left-aligned, vertically centred.
	var vbox_left := VBoxContainer.new()
	vbox_left.position     = Vector2(8.0, 0.0)
	vbox_left.size         = Vector2(left_col, STAT_ROW_H)
	vbox_left.alignment    = BoxContainer.ALIGNMENT_CENTER
	vbox_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_left.add_theme_constant_override("separation", 0)
	row_ctrl.add_child(vbox_left)

	var lbl_name := Label.new()
	lbl_name.add_theme_font_size_override("font_size", 28)
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

	# Current value — spans x=0 to x=split_x so right-alignment lands at the split point.
	var lbl_cur := Label.new()
	lbl_cur.position             = Vector2(0.0, 0.0)
	lbl_cur.size                 = Vector2(split_x, STAT_ROW_H)
	lbl_cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_cur.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl_cur.add_theme_font_size_override("font_size", 36)
	lbl_cur.add_theme_color_override("font_color", COLOR_TEXT)
	lbl_cur.add_theme_font_override("font", UIFonts.primary_bold())
	lbl_cur.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	row_ctrl.add_child(lbl_cur)

	# Upgrade button — inset inside the right 40% of the panel.
	# Height is 60% of the row (≈40% shorter). Top/bottom margin is derived from
	# that height so all three exposed sides (top, bottom, right) show equal panel background.
	var btn_h   := STAT_ROW_H * 0.60
	var v_inset := (STAT_ROW_H - btn_h) * 0.5   # = 20px; applied to top, bottom, and right
	var btn_x   := split_x + v_inset
	var btn_w   := inner_w - btn_x - v_inset
	var btn := Button.new()
	btn.text       = ""
	btn.position   = Vector2(btn_x, v_inset)
	btn.size       = Vector2(btn_w, btn_h)
	# FOCUS_NONE prevents the button from showing a focus ring after being tapped,
	# which would otherwise appear as a white outline even on disabled buttons.
	btn.focus_mode = Control.FOCUS_NONE
	_apply_button_style(btn, false)
	row_ctrl.add_child(btn)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn_hbox.offset_left  =  8.0
	btn_hbox.offset_right = -8.0
	btn_hbox.alignment    = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(btn_hbox)

	# "+X" gain — left-aligned, expands to push cost to the far right.
	var lbl_after := Label.new()
	lbl_after.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_after.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	lbl_after.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl_after.add_theme_font_size_override("font_size", 24)
	lbl_after.add_theme_color_override("font_color", COLOR_DELTA_AFFORDABLE)
	lbl_after.add_theme_font_override("font", UIFonts.primary_bold())
	btn_hbox.add_child(lbl_after)

	# Cost (coin + amount) — right-aligned, expands to fill its side.
	var lbl_cost := Label.new()
	lbl_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_cost.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_cost.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl_cost.add_theme_font_size_override("font_size", 24)
	lbl_cost.add_theme_color_override("font_color", COLOR_GOLD)
	lbl_cost.add_theme_font_override("font", UIFonts.primary_bold())
	btn_hbox.add_child(lbl_cost)

	# Labels must not absorb input — clicks anywhere on the button face reach the Button.
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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.focus_mode = Control.FOCUS_NONE


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
