## StartScreen.gd
## The game's opening screen. Shows the title, company slogan, and two buttons:
## "Start Buggin'" (transitions to the arena and begins a run) and "But Out"
## (quits the application).
##
## The playtest setup dialog (DebugStartDialog) is created by Arena._ready()
## and will not appear until this scene has been replaced by Main.tscn.

extends Control

const UIFonts = preload("res://ui/UIFonts.gd")

# Dark background — matches the deep navy used elsewhere in the UI.
const COLOR_BG := Color(0.06, 0.06, 0.10, 1.0)

# Title uses a warm gold to give the brand a distinctive, high-contrast look
# against the dark background.
const COLOR_TITLE  := Color(0.92, 0.85, 0.20, 1.0)
const COLOR_SLOGAN := Color(0.75, 0.75, 0.78, 1.0)
const COLOR_TEXT   := Color(0.90, 0.90, 0.90, 1.0)

# Button colours mirror the palette used in HUD.gd for visual consistency.
const COLOR_BTN_NORMAL  := Color(0.20, 0.20, 0.22, 1.0)
const COLOR_BTN_HOVER   := Color(0.30, 0.30, 0.33, 1.0)
const COLOR_BTN_PRESSED := Color(0.14, 0.14, 0.16, 1.0)
const COLOR_BTN_BORDER  := Color(0.60, 0.60, 0.65, 1.0)


func _ready() -> void:
	# Fill the entire viewport — this node is the scene root.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# --- Background ---
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = COLOR_BG
	add_child(bg)

	# CenterContainer stretches to fill the screen and places its single child
	# (the VBoxContainer) at the exact centre — both horizontally and vertically.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# VBoxContainer holds title, slogan, spacer, and button row in a vertical stack.
	# The minimum width caps it so text doesn't stretch edge-to-edge on wide screens.
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(720, 0)
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	# --- Game title ---
	var title := Label.new()
	title.text                = "Critter Quitters Pest Control"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", UIFonts.header())
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	vbox.add_child(title)

	# --- Company slogan (displayed with surrounding quotation marks per spec) ---
	var slogan := Label.new()
	slogan.text                = "\"Bugs don't have to go home but they can't stay here\""
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.autowrap_mode       = TextServer.AUTOWRAP_WORD_SMART
	slogan.add_theme_font_override("font", UIFonts.flavor())
	slogan.add_theme_font_size_override("font_size", 26)
	slogan.add_theme_color_override("font_color", COLOR_SLOGAN)
	vbox.add_child(slogan)

	# Spacer between slogan and buttons — gives the layout visual breathing room.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer)

	# --- Side-by-side buttons ---
	# Both buttons get SIZE_EXPAND_FILL so they share the available width equally.
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	var start_btn := _make_button("Start Buggin'")
	start_btn.pressed.connect(_on_start_pressed)
	hbox.add_child(start_btn)

	var quit_btn := _make_button("But Out")
	quit_btn.pressed.connect(_on_quit_pressed)
	hbox.add_child(quit_btn)


# Builds a styled button with the shared visual appearance.
func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text                    = label
	btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size     = Vector2(0, 60)
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
