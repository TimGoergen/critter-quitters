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
const COLOR_COUNTDOWN   := Color(1.00, 1.00, 1.00, 0.92)
const COLOR_HINT        := Color(0.60, 0.60, 0.65, 0.80)
const COLOR_INFESTED    := Color(0.85, 0.10, 0.10, 1.0)
const COLOR_OVERLAY_BG  := Color(0.04, 0.02, 0.02, 0.82)

const PANEL_H: float = 40.0
const BAR_H:   float = 14.0
const MARGIN:  float = 12.0

var _wave_label:        Label
var _bucks_label:       Label
var _infestation_fill:  ColorRect
var _infestation_label: Label
var _countdown_label:   Label
var _hint_label:        Label
var _run_over_overlay:  Control


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

	_wave_label = _make_label("WAVE 0", Vector2(MARGIN, 0.0), PANEL_H)
	top_bg.add_child(_wave_label)

	_bucks_label                    = _make_label("BB: 0", Vector2(0.0, 0.0), PANEL_H)
	_bucks_label.anchor_left        = 1.0
	_bucks_label.anchor_right       = 1.0
	_bucks_label.offset_left        = -140.0
	_bucks_label.offset_right       = -MARGIN
	_bucks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_infestation_fill.position.y = MARGIN
	track.add_child(_infestation_fill)

	_infestation_label                    = _make_label("0%", Vector2(0.0, 0.0), BAR_H + MARGIN * 2.0)
	_infestation_label.anchor_left        = 1.0
	_infestation_label.anchor_right       = 1.0
	_infestation_label.offset_left        = -56.0
	_infestation_label.offset_right       = -MARGIN
	_infestation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_infestation_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	bar_bg.add_child(_infestation_label)

	# --- Countdown splash (upper-centre, hidden by default) ---
	# Occupies the top 15-45% of the viewport so the Q hint below never overlaps.
	_countdown_label = Label.new()
	_countdown_label.anchor_right              = 1.0
	_countdown_label.anchor_top               = 0.15
	_countdown_label.anchor_bottom            = 0.45
	_countdown_label.horizontal_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 64)
	_countdown_label.add_theme_color_override("font_color", COLOR_COUNTDOWN)
	_countdown_label.visible = false
	add_child(_countdown_label)

	# Sits in its own band directly below the countdown label.
	_hint_label = Label.new()
	_hint_label.anchor_right              = 1.0
	_hint_label.anchor_top               = 0.45
	_hint_label.anchor_bottom            = 0.55
	_hint_label.horizontal_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	_hint_label.text    = "press Q to start early"
	_hint_label.visible = false
	add_child(_hint_label)

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
	btn.anchor_left          = 0.35
	btn.anchor_right         = 0.65
	btn.anchor_top           = 0.62
	btn.anchor_bottom        = 0.75
	btn.add_theme_font_size_override("font_size", 28)
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(_on_restart_pressed)
	_run_over_overlay.add_child(btn)


func _on_bucks_changed(amount: int) -> void:
	_bucks_label.text = "BB: %d" % amount


func _on_infestation_changed(level: float) -> void:
	var track: Control = _infestation_fill.get_parent()
	_infestation_fill.size.x = track.size.x * level
	_infestation_label.text  = "%d%%" % roundi(level * 100.0)


func _on_wave_changed(wave: int) -> void:
	_wave_label.text = "WAVE %d" % wave


func _on_wave_countdown_changed(seconds_remaining: int) -> void:
	if seconds_remaining > 0:
		_countdown_label.text    = "WAVE %d\n%d" % [GameState.current_wave, seconds_remaining]
		_countdown_label.visible = true
		_hint_label.visible      = true
	else:
		_countdown_label.visible = false
		_hint_label.visible      = false


func _on_run_ended() -> void:
	_run_over_overlay.visible = true
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _make_label(text: String, pos: Vector2, container_h: float) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = Vector2(pos.x, (container_h - 16.0) * 0.5)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	return lbl
