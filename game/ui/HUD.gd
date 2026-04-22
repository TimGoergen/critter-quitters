## HUD.gd
## Minimal in-run overlay: Bug Bucks counter, wave number, Infestation bar,
## between-wave countdown splash, and run-over screen.
## Built procedurally — no scene file required.

extends CanvasLayer

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

const PANEL_H: float = 44.0
const BAR_H:   float = 14.0
const MARGIN:  float = 12.0

var _wave_label:        RichTextLabel
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label
var _countdown_wave_label:   Label
var _countdown_number_label: Label
var _send_wave_btn:     Button
var _run_over_overlay:  Control

var _blink_time: float = 0.0


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
	_on_bucks_changed(GameState.bug_bucks)
	_on_infestation_changed(GameState.infestation_level)
	_on_wave_changed(GameState.current_wave)


func _build_ui() -> void:
	# --- Top panel ---
	var top_bg := ColorRect.new()
	top_bg.color         = COLOR_PANEL_BG
	top_bg.anchor_right  = 1.0
	top_bg.anchor_bottom = 0.0
	top_bg.offset_bottom = PANEL_H
	add_child(top_bg)

	# Wave display floats at the top-left outside the panel (same reason as before).
	# RichTextLabel mixes font sizes in one node and baseline-aligns runs automatically,
	# so "WAVE" (small) and the numeral (large) share a common bottom edge without
	# any manual positioning.
	var bold_wave_font := SystemFont.new()
	bold_wave_font.font_weight = 700

	_wave_label                  = RichTextLabel.new()
	_wave_label.bbcode_enabled   = true
	_wave_label.fit_content      = true
	_wave_label.scroll_active    = false
	_wave_label.autowrap_mode    = TextServer.AUTOWRAP_OFF
	_wave_label.custom_minimum_size = Vector2(260, 80)
	_wave_label.offset_left      = MARGIN
	_wave_label.offset_top       = 4.0
	_wave_label.add_theme_font_override("normal_font", bold_wave_font)
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
	var bold_font := SystemFont.new()
	bold_font.font_weight = 700
	_bucks_label.add_theme_font_override("font", bold_font)
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
	var bold_countdown_font := SystemFont.new()
	bold_countdown_font.font_weight = 700
	_countdown_wave_label.add_theme_font_override("font", bold_countdown_font)
	_countdown_wave_label.visible = false
	add_child(_countdown_wave_label)

	# Band 0.30–0.45: countdown number — italic, smaller, darker
	_countdown_number_label = Label.new()
	_countdown_number_label.anchor_right         = 1.0
	_countdown_number_label.anchor_top           = 0.30
	_countdown_number_label.anchor_bottom        = 0.45
	_countdown_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_number_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_countdown_number_label.add_theme_font_size_override("font_size", 46)
	_countdown_number_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 0.92))
	var italic_countdown_font := SystemFont.new()
	italic_countdown_font.font_italic = true
	_countdown_number_label.add_theme_font_override("font", italic_countdown_font)
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
	_send_wave_btn.visible        = false
	_apply_button_style(_send_wave_btn)
	_send_wave_btn.pressed.connect(_on_send_wave_pressed)
	add_child(_send_wave_btn)

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
	_run_over_overlay.add_child(infested_label)

	var btn := Button.new()
	btn.text                 = "Restart"
	btn.anchor_left          = 0.30
	btn.anchor_right         = 0.70
	btn.anchor_top           = 0.70
	btn.anchor_bottom        = 0.80
	btn.add_theme_font_size_override("font_size", 28)
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	_apply_button_style(btn)
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)


func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = "Bug Bucks: $%d" % amount


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
