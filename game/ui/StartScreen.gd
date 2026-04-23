## StartScreen.gd
## The game's opening screen. Shows the title, company slogan, and two buttons:
## "Start Buggin'" (transitions to the arena and begins a run) and "But Out"
## (quits the application).
##
## Extends CanvasLayer — the same pattern used by HUD.gd and DebugStartDialog.gd —
## so that anchor-based layout resolves correctly against the viewport.
##
## The playtest setup dialog (DebugStartDialog) is created by Arena._ready()
## and will not appear until this scene has been replaced by Main.tscn.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")

const COLOR_BG := Color(0.06, 0.06, 0.10, 1.0)

# Warm gold for the title — high contrast against the dark background.
const COLOR_TITLE  := Color(0.92, 0.85, 0.20, 1.0)
const COLOR_SLOGAN := Color(0.75, 0.75, 0.78, 1.0)
const COLOR_TEXT   := Color(0.90, 0.90, 0.90, 1.0)

# Button colours mirror HUD.gd for visual consistency.
const COLOR_BTN_NORMAL  := Color(0.20, 0.20, 0.22, 1.0)
const COLOR_BTN_HOVER   := Color(0.30, 0.30, 0.33, 1.0)
const COLOR_BTN_PRESSED := Color(0.14, 0.14, 0.16, 1.0)
const COLOR_BTN_BORDER  := Color(0.60, 0.60, 0.65, 1.0)


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# --- Background: fills the entire viewport ---
	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = COLOR_BG
	add_child(bg)

	# --- Title: occupies the upper-centre of the screen (28–50% height) ---
	var title := Label.new()
	title.text                 = "Critter Quitters Pest Control"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left          = 0.05
	title.anchor_right         = 0.95
	title.anchor_top           = 0.28
	title.anchor_bottom        = 0.50
	title.add_theme_font_override("font", UIFonts.header())
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	add_child(title)

	# --- Slogan: below the title (52–65% height), horizontally inset ---
	# Quotation marks are part of the display text per spec.
	var slogan := Label.new()
	slogan.text                 = "\"Bugs don't have to go home but they can't stay here\""
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	slogan.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	slogan.anchor_left          = 0.10
	slogan.anchor_right         = 0.90
	slogan.anchor_top           = 0.52
	slogan.anchor_bottom        = 0.65
	slogan.add_theme_font_override("font", UIFonts.flavor())
	slogan.add_theme_font_size_override("font_size", 26)
	slogan.add_theme_color_override("font_color", COLOR_SLOGAN)
	add_child(slogan)

	# --- Buttons: side by side, equal width, centred horizontally (68–78% height) ---
	# A 4% gap between the buttons (48 to 52) mirrors the inner margins.
	var start_btn := _make_button("Start Buggin'")
	start_btn.anchor_left   = 0.25
	start_btn.anchor_right  = 0.48
	start_btn.anchor_top    = 0.68
	start_btn.anchor_bottom = 0.78
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	var quit_btn := _make_button("But Out")
	quit_btn.anchor_left   = 0.52
	quit_btn.anchor_right  = 0.75
	quit_btn.anchor_top    = 0.68
	quit_btn.anchor_bottom = 0.78
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)


# Builds a styled button. The caller sets the anchor position.
func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	_apply_button_style(btn)
	return btn


func _on_start_pressed() -> void:
	# Replace this scene with Main.tscn, which instantiates the Arena.
	# Arena._ready() will then show the DebugStartDialog before the first wave.
	get_tree().change_scene_to_file("res://Main.tscn")


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
