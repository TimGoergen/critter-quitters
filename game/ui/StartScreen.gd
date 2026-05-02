## StartScreen.gd
## The game's opening screen. Shows a beat-up Critter Quitters utility van as the
## title graphic, a company slogan, and two buttons: "Start Buggin'" and "Bug Out".
##
## When the player taps "Start Buggin'", the van accelerates left off screen while
## exhaust clouds billow in its wake, then the scene transitions to Main.tscn.
##
## Extends CanvasLayer — same pattern as HUD.gd and DebugStartDialog.gd —
## so anchor-based layout resolves against the viewport.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")

const COLOR_BG     := Color(0.06, 0.06, 0.10, 1.0)
const COLOR_SLOGAN := Color(0.75, 0.75, 0.78, 1.0)
const COLOR_TEXT   := Color(0.90, 0.90, 0.90, 1.0)

const COLOR_BTN_NORMAL  := Color(0.20, 0.20, 0.22, 1.0)
const COLOR_BTN_HOVER   := Color(0.30, 0.30, 0.33, 1.0)
const COLOR_BTN_PRESSED := Color(0.14, 0.14, 0.16, 1.0)
const COLOR_BTN_BORDER  := Color(0.60, 0.60, 0.65, 1.0)

var _van:       VanNode
var _start_btn: Button
var _quit_btn:  Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# --- Background ---
	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = COLOR_BG
	add_child(bg)

	# --- Van graphic (replaces the plain text title) ---
	# Centred horizontally at 25% height. The van body extends ±100 px vertically
	# from its origin; wheels reach ~174 px below, so the bottom clears the slogan
	# at 57% with a comfortable gap.
	_van = VanNode.new()
	_van.position = Vector2(vp.x * 0.5, vp.y * 0.25)
	_van.exit_animation_finished.connect(_on_van_exited)
	add_child(_van)

	# --- Slogan ---
	var slogan := Label.new()
	slogan.text                 = "\"Bugs don't have to go home but they can't stay here\""
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	slogan.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	slogan.anchor_left          = 0.10
	slogan.anchor_right         = 0.90
	slogan.anchor_top           = 0.57
	slogan.anchor_bottom        = 0.69
	slogan.add_theme_font_override("font", UIFonts.flavor())
	slogan.add_theme_font_size_override("font_size", 26)
	slogan.add_theme_color_override("font_color", COLOR_SLOGAN)
	add_child(slogan)

	# --- Buttons: side by side, equal width, centred ---
	_start_btn = _make_button("Start Buggin'")
	_start_btn.anchor_left   = 0.25
	_start_btn.anchor_right  = 0.48
	_start_btn.anchor_top    = 0.73
	_start_btn.anchor_bottom = 0.83
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_quit_btn = _make_button("Bug Out")
	_quit_btn.anchor_left   = 0.52
	_quit_btn.anchor_right  = 0.75
	_quit_btn.anchor_top    = 0.73
	_quit_btn.anchor_bottom = 0.83
	_quit_btn.pressed.connect(_on_quit_pressed)
	add_child(_quit_btn)


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	_apply_button_style(btn)
	return btn


func _on_start_pressed() -> void:
	# Disable both buttons immediately so a double-tap cannot fire the transition twice.
	_start_btn.disabled = true
	_quit_btn.disabled  = true
	_van.play_exit_animation()


func _on_van_exited() -> void:
	# Brief pause so the exhaust cloud can begin dissipating before the scene cuts.
	var tween := create_tween()
	tween.tween_interval(0.4)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://Main.tscn"))


func _on_quit_pressed() -> void:
	get_tree().quit()


func _apply_button_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_BTN_NORMAL],
		["hover",   COLOR_BTN_HOVER],
		["pressed", COLOR_BTN_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_BTN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
