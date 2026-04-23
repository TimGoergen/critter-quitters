## TrapUpgradePanel.gd
## Appears when the player taps a placed trap. Shows current stats and
## presents one upgrade button per stat (Damage, Range, Fire Rate).
##
## Each stat upgrades independently up to Trap.MAX_UPGRADE_LEVEL (3) times.
## The cost for the next upgrade of each stat is shown on its button.
## A button shows "MAX" and is disabled when that stat is fully upgraded.
## A button is also disabled when the player cannot afford it.
##
## process_mode is ALWAYS so the panel stays interactive while the game
## tree is paused (which Arena does while this panel is open).

extends CanvasLayer

signal closed

const PANEL_W:  float = 272.0
const PANEL_H:  float = 208.0
const PADDING:  float = 10.0
const BTN_H:    float = 28.0
const BORDER_W: float = 2.0
const HUD_BOT:  float = 38.0   # keep in sync with HUD.gd bottom bar height

const COLOR_BG         := Color(0.04, 0.28, 0.28, 0.90)
const COLOR_OUTLINE    := Color(0.20, 0.55, 0.55, 1.0)
const COLOR_DIVIDER    := Color(0.15, 0.45, 0.45, 1.0)
const COLOR_TEXT       := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM   := Color(0.65, 0.80, 0.80, 1.0)
const COLOR_BTN_NORMAL  := Color(0.06, 0.22, 0.22, 1.0)
const COLOR_BTN_HOVER   := Color(0.10, 0.32, 0.32, 1.0)
const COLOR_BTN_PRESSED := Color(0.03, 0.15, 0.15, 1.0)
const COLOR_BTN_BORDER  := Color(0.20, 0.55, 0.55, 1.0)
const COLOR_BTN_MAX     := Color(0.08, 0.18, 0.18, 1.0)   # dimmed when maxed


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _trap:       Node      = null

var _border:     ColorRect = null
var _bg:         ColorRect = null
var _lbl_title:  Label     = null
var _lbl_damage: Label     = null
var _lbl_range:  Label     = null
var _lbl_rate:   Label     = null
var _btn_a:      Button    = null   # Damage
var _btn_b:      Button    = null   # Range
var _btn_c:      Button    = null   # Fire Rate


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
	var vp := get_viewport().get_visible_rect().size
	var px := (vp.x - PANEL_W) * 0.5
	var py := vp.y - PANEL_H - HUD_BOT - 10.0

	# Outline border — rendered behind the background rect.
	_border          = ColorRect.new()
	_border.color    = COLOR_OUTLINE
	_border.position = Vector2(px - BORDER_W, py - BORDER_W)
	_border.size     = Vector2(PANEL_W + BORDER_W * 2.0, PANEL_H + BORDER_W * 2.0)
	add_child(_border)

	# Background panel
	_bg          = ColorRect.new()
	_bg.color    = COLOR_BG
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(PANEL_W, PANEL_H)
	add_child(_bg)

	var inner_w := PANEL_W - PADDING * 2.0
	var y       := PADDING

	# --- Header: trap name | close button ---
	var header := HBoxContainer.new()
	header.position            = Vector2(PADDING, y)
	header.custom_minimum_size = Vector2(inner_w, 22.0)
	_bg.add_child(header)

	_lbl_title = Label.new()
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.add_theme_font_size_override("font_size", 15)
	_lbl_title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(_lbl_title)

	var btn_close := Button.new()
	btn_close.text    = "X"
	btn_close.pressed.connect(_on_close)
	_apply_button_style(btn_close, false)
	header.add_child(btn_close)

	y += 28.0

	# --- Current stats ---
	_lbl_damage = _add_stat_label(y); y += 18.0
	_lbl_range  = _add_stat_label(y); y += 18.0
	_lbl_rate   = _add_stat_label(y); y += 18.0

	# --- Horizontal divider ---
	_add_divider(y)
	y += 7.0

	# --- Upgrade buttons ---
	_btn_a = _add_upgrade_button(y); y += BTN_H + 4.0
	_btn_b = _add_upgrade_button(y); y += BTN_H + 4.0
	_btn_c = _add_upgrade_button(y)

	_btn_a.pressed.connect(_on_btn_a)
	_btn_b.pressed.connect(_on_btn_b)
	_btn_c.pressed.connect(_on_btn_c)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

## Rebuilds all labels and button states from the trap's current values.
func _refresh() -> void:
	if _trap == null or not is_instance_valid(_trap):
		_on_close()
		return

	_lbl_title.text  = _trap.get_type_name()
	_lbl_damage.text = "Damage:    %.1f" % _trap.get_damage()
	_lbl_range.text  = "Range:     %.1f" % _trap.get_range_radius()

	if _trap.is_passive():
		_lbl_rate.text = "Fire Rate: passive"
	else:
		_lbl_rate.text = "Fire Rate: %.2f /s" % _trap.get_shots_per_sec()

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

func _on_btn_a() -> void:
	if _trap.is_damage_maxed():
		return
	if not GameState.spend_bug_bucks(_trap.get_damage_upgrade_cost()):
		return
	_trap.apply_damage_upgrade()


func _on_btn_b() -> void:
	if _trap.is_range_maxed():
		return
	if not GameState.spend_bug_bucks(_trap.get_range_upgrade_cost()):
		return
	_trap.apply_range_upgrade()


func _on_btn_c() -> void:
	if _trap.is_rate_maxed() or _trap.is_passive():
		return
	if not GameState.spend_bug_bucks(_trap.get_rate_upgrade_cost()):
		return
	_trap.apply_fire_rate_upgrade()


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

func _add_stat_label(y: float) -> Label:
	var lbl      := Label.new()
	lbl.position  = Vector2(PADDING, y)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_bg.add_child(lbl)
	return lbl


func _add_upgrade_button(y: float) -> Button:
	var btn               := Button.new()
	btn.position           = Vector2(PADDING, y)
	btn.custom_minimum_size = Vector2(PANEL_W - PADDING * 2.0, BTN_H)
	btn.add_theme_font_size_override("font_size", 13)
	_apply_button_style(btn, false)
	_bg.add_child(btn)
	return btn


func _add_divider(y: float) -> void:
	var line     := ColorRect.new()
	line.color    = COLOR_DIVIDER
	line.position = Vector2(PADDING, y)
	line.size     = Vector2(PANEL_W - PADDING * 2.0, 1.0)
	_bg.add_child(line)


## Applies the correct button style. maxed=true uses a dimmer palette to signal
## the stat is fully upgraded rather than just unaffordable.
func _apply_button_style(btn: Button, maxed: bool) -> void:
	var normal  := COLOR_BTN_MAX    if maxed else COLOR_BTN_NORMAL
	var hover   := COLOR_BTN_MAX    if maxed else COLOR_BTN_HOVER
	var pressed := COLOR_BTN_MAX    if maxed else COLOR_BTN_PRESSED
	for state: Array in [["normal", normal], ["hover", hover], ["pressed", pressed]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 3.0
		box.content_margin_bottom = 3.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
