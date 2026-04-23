## HUD.gd
## Minimal in-run overlay: Bug Bucks counter, wave number, Infestation bar,
## between-wave countdown splash, run-over screen, and trap type selector.
## Built procedurally — no scene file required.
##
## The trap selector repositions itself based on screen orientation:
##   Landscape — right-side panel, buttons stacked vertically
##   Portrait  — horizontal strip above the infestation bar at the bottom

extends CanvasLayer

const Trap     = preload("res://traps/Trap.gd")
const UIFonts  = preload("res://ui/UIFonts.gd")

const COLOR_PANEL_BG    := Color(0.08, 0.08, 0.13, 0.88)
const COLOR_BAR_BG      := Color(0.15, 0.10, 0.10, 1.0)
const COLOR_BAR_FILL    := Color(0.85, 0.22, 0.22, 1.0)
const COLOR_TEXT        := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM    := Color(0.60, 0.60, 0.65, 1.0)
const COLOR_COUNTDOWN   := Color(0.85, 0.85, 0.85, 0.92)
const COLOR_INFESTED    := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_OVERLAY_BG  := Color(0.04, 0.02, 0.02, 0.82)

# Button style: base gray is the panel bg (~0.10); 20% lighter puts the fill at ~0.30.
# The border is light gray to make the button stand out against the dark overlay.
const COLOR_BTN_NORMAL  := Color(0.30, 0.30, 0.30, 1.0)
const COLOR_BTN_HOVER   := Color(0.38, 0.38, 0.38, 1.0)
const COLOR_BTN_PRESSED := Color(0.22, 0.22, 0.22, 1.0)
const COLOR_BTN_BORDER  := Color(0.68, 0.68, 0.68, 1.0)

# Selected button gets a green-tinted background and brighter border.
# Cost label is gold when affordable, red when not.
const COLOR_SEL_BG       := Color(0.14, 0.22, 0.14, 1.0)
const COLOR_SEL_BG_HOVER := Color(0.20, 0.30, 0.20, 1.0)
const COLOR_SEL_BORDER   := Color(0.45, 0.80, 0.45, 1.0)
const COLOR_COST_OK      := Color(0.80, 0.60, 0.10, 1.0)
const COLOR_COST_NO      := Color(0.70, 0.25, 0.20, 1.0)

const PANEL_H:          float = 44.0   # top stats bar height
const BAR_H:            float = 14.0   # infestation bar fill height
const MARGIN:           float = 12.0   # infestation bar padding

# Trap selector layout — read by Arena.gd to compute usable arena area.
# SELECTOR_PANEL_W is the right-panel width in landscape.
# SELECTOR_STRIP_H is the bottom strip height in portrait.
const SELECTOR_PANEL_W: float = 160.0
const SELECTOR_STRIP_H: float = 40.0

# Height of each button in the landscape vertical panel.
const SELECTOR_BTN_H:   float = 64.0

var _wave_label:        RichTextLabel
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label
var _countdown_wave_label:   Label
var _countdown_number_label: Label
var _send_wave_btn:     Button
var _run_over_overlay:  Control

var _selector_buttons: Array[Button] = []
# Root node of the current selector layout — freed and rebuilt on orientation change.
var _selector_root: Control = null
# Tracks the orientation at last build so we only rebuild when it flips.
var _selector_is_landscape: bool = true


func _ready() -> void:
	# Allow the HUD layer itself to process input while the tree is paused,
	# so the run-over overlay's Restart button remains clickable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.bug_bucks_changed.connect(_on_bucks_changed)
	GameState.infestation_changed.connect(_on_infestation_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.wave_countdown_changed.connect(_on_wave_countdown_changed)
	GameState.run_ended.connect(_on_run_ended)
	GameState.trap_type_selected.connect(_on_trap_type_selected)
	_on_bucks_changed(GameState.bug_bucks)
	_on_infestation_changed(GameState.infestation_level)
	_on_wave_changed(GameState.current_wave)
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_ui() -> void:
	# --- Top panel ---
	var top_bg := ColorRect.new()
	top_bg.color         = COLOR_PANEL_BG
	top_bg.anchor_right  = 1.0
	top_bg.anchor_bottom = 0.0
	top_bg.offset_bottom = PANEL_H
	add_child(top_bg)

	# Wave display: RichTextLabel mixes font sizes in one node and baseline-aligns
	# runs automatically, so "WAVE" (small) and the numeral (large) share a common
	# bottom edge without any manual positioning.
	_wave_label                  = RichTextLabel.new()
	_wave_label.bbcode_enabled   = true
	_wave_label.fit_content      = true
	_wave_label.scroll_active    = false
	_wave_label.autowrap_mode    = TextServer.AUTOWRAP_OFF
	_wave_label.custom_minimum_size = Vector2(260, 80)
	_wave_label.offset_left      = MARGIN
	_wave_label.offset_top       = 4.0
	_wave_label.add_theme_font_override("normal_font", UIFonts.header())
	_wave_label.add_theme_color_override("default_color", COLOR_TEXT)
	add_child(_wave_label)

	_bucks_label                      = _make_label("Bug Bucks: $0", Vector2(0.0, 0.0), PANEL_H)
	_bucks_label.anchor_left          = 1.0
	_bucks_label.anchor_right         = 1.0
	_bucks_label.offset_left          = -290.0
	_bucks_label.offset_right         = -MARGIN
	_bucks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bucks_label.add_theme_font_size_override("font_size", 31)
	_bucks_label.add_theme_color_override("font_color", Color(0.80, 0.60, 0.10))
	_bucks_label.add_theme_font_override("font", UIFonts.primary_bold())
	top_bg.add_child(_bucks_label)

	# --- Bottom infestation bar ---
	var bar_bg := ColorRect.new()
	bar_bg.color        = COLOR_PANEL_BG
	bar_bg.anchor_top   = 1.0
	bar_bg.anchor_bottom = 1.0
	bar_bg.anchor_right  = 1.0
	bar_bg.offset_top    = -(BAR_H + MARGIN * 2.0)
	add_child(bar_bg)

	var bar_label := _make_label("INFESTATION", Vector2(MARGIN, 0.0), BAR_H + MARGIN * 2.0)
	bar_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	bar_label.add_theme_font_override("font", UIFonts.primary())
	bar_bg.add_child(bar_label)

	var track := ColorRect.new()
	track.color         = COLOR_BAR_BG
	track.anchor_right  = 1.0
	track.offset_left   = 130.0
	track.offset_right  = -MARGIN
	track.offset_top    = MARGIN
	track.offset_bottom = MARGIN + BAR_H
	bar_bg.add_child(track)

	_infestation_fill          = ColorRect.new()
	_infestation_fill.color    = COLOR_BAR_FILL
	_infestation_fill.size.y   = BAR_H
	_infestation_fill.position.y = 0
	track.add_child(_infestation_fill)

	_infestation_label                      = _make_label("0%", Vector2(0.0, 0.0), BAR_H + MARGIN * 2.0)
	_infestation_label.anchor_left          = 1.0
	_infestation_label.anchor_right         = 1.0
	_infestation_label.anchor_top           = 0.0
	_infestation_label.anchor_bottom        = 1.0
	_infestation_label.offset_left          = -56.0
	_infestation_label.offset_right         = -MARGIN
	_infestation_label.offset_top           = 0.0
	_infestation_label.offset_bottom        = 0.0
	_infestation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_infestation_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_infestation_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	bar_bg.add_child(_infestation_label)

	# --- Countdown splash (upper-centre, hidden by default) ---
	# Band 0.15–0.30: "WAVE X" — bold, larger
	_countdown_wave_label = Label.new()
	_countdown_wave_label.anchor_right         = 1.0
	_countdown_wave_label.anchor_top           = 0.15
	_countdown_wave_label.anchor_bottom        = 0.30
	_countdown_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_wave_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_wave_label.add_theme_font_size_override("font_size", 62)
	_countdown_wave_label.add_theme_color_override("font_color", COLOR_COUNTDOWN)
	_countdown_wave_label.add_theme_font_override("font", UIFonts.header())
	_countdown_wave_label.visible = false
	add_child(_countdown_wave_label)

	# Band 0.30–0.45: countdown number
	_countdown_number_label = Label.new()
	_countdown_number_label.anchor_right         = 1.0
	_countdown_number_label.anchor_top           = 0.30
	_countdown_number_label.anchor_bottom        = 0.45
	_countdown_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_number_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_number_label.add_theme_font_size_override("font_size", 46)
	_countdown_number_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 0.92))
	_countdown_number_label.add_theme_font_override("font", UIFonts.header())
	_countdown_number_label.visible = false
	add_child(_countdown_number_label)

	# "Send Wave Early" button — centred in the lower half of the screen (midpoint at y=0.75),
	# hidden during waves.
	_send_wave_btn                = Button.new()
	_send_wave_btn.text           = "Send Wave Early"
	_send_wave_btn.anchor_left    = 0.30
	_send_wave_btn.anchor_right   = 0.70
	_send_wave_btn.anchor_top     = 0.70
	_send_wave_btn.anchor_bottom  = 0.80
	_send_wave_btn.add_theme_font_size_override("font_size", 18)
	_send_wave_btn.add_theme_font_override("font", UIFonts.primary())
	_send_wave_btn.visible        = false
	_apply_button_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	add_child(_send_wave_btn)

	_build_trap_selector()
	_build_run_over_overlay()


func _build_run_over_overlay() -> void:
	# Full-screen container. Stays responsive while the tree is paused.
	_run_over_overlay = Control.new()
	_run_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_over_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_run_over_overlay.visible      = false
	add_child(_run_over_overlay)

	var bg := ColorRect.new()
	bg.color = COLOR_OVERLAY_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_over_overlay.add_child(bg)

	var infested_label := Label.new()
	infested_label.text                  = "INFESTED!"
	infested_label.anchor_right          = 1.0
	infested_label.anchor_top            = 0.30
	infested_label.anchor_bottom         = 0.55
	infested_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	infested_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	infested_label.add_theme_font_size_override("font_size", 96)
	infested_label.add_theme_color_override("font_color", COLOR_INFESTED)
	infested_label.add_theme_font_override("font", UIFonts.header())
	_run_over_overlay.add_child(infested_label)

	var btn := Button.new()
	btn.text                 = "Restart"
	btn.anchor_left          = 0.30
	btn.anchor_right         = 0.70
	btn.anchor_top           = 0.70
	btn.anchor_bottom        = 0.80
	btn.add_theme_font_size_override("font_size", 28)
	btn.add_theme_font_override("font", UIFonts.primary())
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	_apply_button_style(btn)
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)


func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = "Bug Bucks: $%d" % amount
	_refresh_trap_selector()


func _on_infestation_changed(level: float) -> void:
	var track: Control = _infestation_fill.get_parent()
	_infestation_fill.size.x = track.size.x * level
	_infestation_label.text  = "%d%%" % roundi(level * 100.0)


func _on_wave_changed(wave: int) -> void:
	_wave_label.text = "[font_size=38]WAVE [/font_size][font_size=64]%d[/font_size]" % wave


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		_countdown_wave_label.text    = "Incoming!"
		_countdown_number_label.text  = "%d..." % seconds_remaining
		_countdown_wave_label.visible   = true
		_countdown_number_label.visible = true
		_send_wave_btn.visible          = true
	else:
		_countdown_wave_label.visible   = false
		_countdown_number_label.visible = false
		_send_wave_btn.visible          = false
		_blink_time = 0.0
		_countdown_number_label.modulate.a = 1.0


var _blink_time: float = 0.0

func _process(delta: float) -> void:
	if not _countdown_number_label.visible:
		return
	_blink_time += delta
	# 2 full on-off cycles per second: period = 1/2 s, on for the first half of each cycle.
	var on: bool = fmod(_blink_time, 1.0 / 2.0) < (1.0 / 4.0)
	_countdown_number_label.modulate.a = 1.0 if on else 0.0


func _on_send_wave_pressed() -> void:
	GameState.wave_skip_requested.emit()


func _on_run_ended() -> void:
	_run_over_overlay.visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Trap selector
# ---------------------------------------------------------------------------

func _is_landscape() -> bool:
	var vp := get_viewport().get_visible_rect().size
	return vp.x >= vp.y


## Rebuilds the selector panel when the screen flips between landscape and portrait.
func _on_viewport_resized() -> void:
	var landscape := _is_landscape()
	if landscape == _selector_is_landscape:
		return
	# Orientation changed — free the old layout and build the new one.
	_selector_buttons.clear()
	if _selector_root != null and is_instance_valid(_selector_root):
		_selector_root.queue_free()
	_selector_root = null
	_build_trap_selector()
	# _build_trap_selector already calls _update_bucks_right_margin and _update_arena_ui_centering.


func _build_trap_selector() -> void:
	_selector_is_landscape = _is_landscape()
	if _selector_is_landscape:
		_build_selector_landscape()
	else:
		_build_selector_portrait()
	_update_bucks_right_margin()
	_update_arena_ui_centering()


# In landscape the Bug Bucks label must stop before the selector panel begins,
# so the text does not crowd against or flow under the panel's left edge.
func _update_bucks_right_margin() -> void:
	_bucks_label.offset_right = -(SELECTOR_PANEL_W + MARGIN) if _is_landscape() else -MARGIN


# Shifts the countdown labels and "Send Wave Early" button so they are centred
# over the arena rather than the full screen. In landscape the arena occupies
# only the left (screen_w - SELECTOR_PANEL_W) pixels, so all centred elements
# must treat that narrower region as their horizontal extent.
func _update_arena_ui_centering() -> void:
	var scr_w := get_viewport().get_visible_rect().size.x
	# arena_right_frac: what fraction of screen width the arena occupies (0–1).
	var arena_right_frac := (scr_w - SELECTOR_PANEL_W) / scr_w if _is_landscape() else 1.0

	# Countdown labels: set anchor_right so the label spans only the arena's width.
	# horizontal_alignment = CENTER still centres the text within that span.
	_countdown_wave_label.anchor_right   = arena_right_frac
	_countdown_number_label.anchor_right = arena_right_frac

	# "Send Wave Early" button: keep it at 30–70% of the arena width, not screen width.
	_send_wave_btn.anchor_left  = arena_right_frac * 0.30
	_send_wave_btn.anchor_right = arena_right_frac * 0.70


## Landscape: buttons in a vertical panel pinned to the right edge of the screen.
## A 10% gap is added at the top and bottom of the available space (between the
## stats bar and the infestation bar), so the panel is ~20% shorter than the
## available height and sits clearly separate from the Bug Bucks display.
func _build_selector_landscape() -> void:
	var bar_h_total := BAR_H + MARGIN * 2.0
	var scr_h       := get_viewport().get_visible_rect().size.y
	var available   := scr_h - PANEL_H - bar_h_total
	# 10% gap each side → panel is 80% of available height, vertically centred.
	var gap_v       := roundf(available * 0.10)

	var bg := ColorRect.new()
	bg.color         = COLOR_PANEL_BG
	bg.anchor_left   = 1.0
	bg.anchor_right  = 1.0
	bg.anchor_top    = 0.0
	bg.anchor_bottom = 1.0
	bg.offset_left   = -SELECTOR_PANEL_W
	bg.offset_right  = 0.0
	bg.offset_top    = PANEL_H + gap_v
	bg.offset_bottom = -bar_h_total - gap_v
	add_child(bg)
	_selector_root = bg

	# Thin left border to separate the panel from the arena.
	var border := ColorRect.new()
	border.color         = Color(0.25, 0.25, 0.35, 1.0)
	border.anchor_top    = 0.0
	border.anchor_bottom = 1.0
	border.offset_right  = 2.0
	bg.add_child(border)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	bg.add_child(margin)

	# VBoxContainer centred so the button group sits in the middle of the panel.
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0.0, SELECTOR_BTN_H)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_font_override("font", UIFonts.primary())
		btn.text = _selector_label(i)
		btn.pressed.connect(GameState.select_trap_type.bind(i))
		_style_selector_button(btn, i == GameState.selected_trap_type, _can_afford(i))
		col.add_child(btn)
		_selector_buttons.append(btn)


## Portrait: buttons in a horizontal strip above the infestation bar at the bottom.
func _build_selector_portrait() -> void:
	var bar_h_total := BAR_H + MARGIN * 2.0

	var bg := ColorRect.new()
	bg.color         = COLOR_PANEL_BG
	bg.anchor_left   = 0.0
	bg.anchor_right  = 1.0
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top    = -(bar_h_total + SELECTOR_STRIP_H)
	bg.offset_bottom = -bar_h_total
	add_child(bg)
	_selector_root = bg

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   6)
	margin.add_theme_constant_override("margin_right",  6)
	margin.add_theme_constant_override("margin_top",    5)
	margin.add_theme_constant_override("margin_bottom", 5)
	bg.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	for i in range(4):
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_font_override("font", UIFonts.primary())
		btn.text = _selector_label(i)
		btn.pressed.connect(GameState.select_trap_type.bind(i))
		_style_selector_button(btn, i == GameState.selected_trap_type, _can_afford(i))
		row.add_child(btn)
		_selector_buttons.append(btn)


func _refresh_trap_selector() -> void:
	for i in range(_selector_buttons.size()):
		_style_selector_button(
			_selector_buttons[i],
			i == GameState.selected_trap_type,
			_can_afford(i)
		)


func _on_trap_type_selected(_type: int) -> void:
	_refresh_trap_selector()


# Returns the display text for one trap selector button.
func _selector_label(type: int) -> String:
	var cost: int = Trap.STATS[type]["cost"]
	match type:
		0: return "Snap Trap  $%d" % cost
		1: return "Zapper  $%d"    % cost
		2: return "Fogger  $%d"    % cost
		3: return "Glue Board  $%d" % cost
	return "???"


# Returns true if the player can currently afford the given trap type.
func _can_afford(type: int) -> bool:
	return GameState.bug_bucks >= Trap.STATS[type]["cost"]


# Applies the correct visual style to a selector button based on its
# selected state and whether the player can afford it.
func _style_selector_button(btn: Button, selected: bool, affordable: bool) -> void:
	var bg_normal := COLOR_SEL_BG     if selected else COLOR_BTN_NORMAL
	var bg_hover  := COLOR_SEL_BG_HOVER if selected else COLOR_BTN_HOVER
	var bg_press  := COLOR_BTN_PRESSED
	var border    := COLOR_SEL_BORDER if selected else COLOR_BTN_BORDER
	var bwidth    := 2                if selected else 1

	for pair: Array in [["normal", bg_normal], ["hover", bg_hover], ["pressed", bg_press]]:
		var box := StyleBoxFlat.new()
		box.bg_color     = pair[1]
		box.border_color = border
		box.set_border_width_all(bwidth)
		box.set_corner_radius_all(4)
		box.content_margin_left   = 8.0
		box.content_margin_right  = 8.0
		box.content_margin_top    = 3.0
		box.content_margin_bottom = 3.0
		btn.add_theme_stylebox_override(pair[0], box)

	btn.add_theme_color_override("font_color", COLOR_COST_OK if affordable else COLOR_COST_NO)


func _apply_button_style(btn: Button) -> void:
	for state in [["normal", COLOR_BTN_NORMAL], ["hover", COLOR_BTN_HOVER], ["pressed", COLOR_BTN_PRESSED]]:
		var box := StyleBoxFlat.new()
		box.bg_color           = state[1]
		box.border_color       = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(5)
		box.content_margin_left   = 12.0
		box.content_margin_right  = 12.0
		box.content_margin_top    = 6.0
		box.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _make_label(text: String, pos: Vector2, container_h: float) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = Vector2(pos.x, (container_h - 16.0) * 0.5)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	return lbl
