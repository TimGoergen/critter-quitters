## StartScreen.gd
## The game's opening screen. Displays the Critter Quitters van illustration as the
## title graphic, a company slogan, and two buttons: "Start Buggin'" and "Bug Out".
##
## When the player taps "Start Buggin'", the van accelerates left off screen while
## exhaust puffs billow from its rear, then the scene transitions to Main.tscn.
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

# The van sprite is sized to this fraction of the viewport width.
const VAN_WIDTH_FRACTION := 0.62

var _van:       Sprite2D
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

	# --- Van illustration ---
	# The image is centred horizontally at 27% down. It is scaled so its width
	# equals VAN_WIDTH_FRACTION of the viewport; height scales proportionally.
	# The van faces left, so the animation drives it further left off screen.
	var van_tex: Texture2D = load("res://assets/van.png")
	_van = Sprite2D.new()
	_van.texture  = van_tex
	var scale_f   := (vp.x * VAN_WIDTH_FRACTION) / van_tex.get_size().x
	_van.scale    = Vector2(scale_f, scale_f)
	_van.position = Vector2(vp.x * 0.5, vp.y * 0.27)
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
	_play_van_exit()


func _play_van_exit() -> void:
	var van_scaled_w := _van.texture.get_size().x * _van.scale.x
	# Drive the van fully off the left edge of the screen.
	var target_x := -(van_scaled_w / 2.0)

	# Stagger exhaust puffs across the first two-thirds of the drive-off.
	_spawn_exhaust_puffs()
	get_tree().create_timer(0.35).timeout.connect(_spawn_exhaust_puffs)
	get_tree().create_timer(0.65).timeout.connect(_spawn_exhaust_puffs)

	var tween := create_tween()
	tween.tween_property(_van, "position:x", target_x, 1.1) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_on_van_exited)


func _spawn_exhaust_puffs() -> void:
	# The van's rear is at the right edge of the sprite (Sprite2D origin is centre).
	# Puffs are added directly to this CanvasLayer (as siblings of the van sprite)
	# so they stay in place while the van drives left.
	var van_half_w    := _van.texture.get_size().x * _van.scale.x / 2.0
	var van_half_h    := _van.texture.get_size().y * _van.scale.y / 2.0
	# Exhaust pipe sits at roughly the lower-right quarter of the van image.
	var exhaust_x     := _van.position.x + van_half_w * 0.80
	var exhaust_y     := _van.position.y + van_half_h * 0.40
	for i: int in 2:
		var puff         := _ExhaustPuff.new()
		puff.position    =  Vector2(
			exhaust_x + randf_range(-20.0, 20.0),
			exhaust_y + randf_range(-15.0, 20.0)
		)
		puff.max_radius  = randf_range(48.0, 75.0)
		puff.start_delay = i * 0.10
		add_child(puff)


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


# One transient exhaust cloud puff. Expands from a small point, fades, then frees itself.
class _ExhaustPuff extends Node2D:
	var start_delay: float = 0.0
	var max_radius:  float = 65.0

	var _radius: float = 0.0
	var _alpha:  float = 0.0

	func _ready() -> void:
		var tween := create_tween()
		if start_delay > 0.0:
			tween.tween_interval(start_delay)
		tween.tween_method(_update, 0.0, 1.0, 0.6)
		tween.tween_callback(queue_free)

	func _update(t: float) -> void:
		_radius = lerp(10.0, max_radius, t)
		_alpha  = sin(t * PI)  # smooth bell: rises quickly then fades out
		queue_redraw()

	func _draw() -> void:
		if _alpha > 0.0:
			draw_circle(Vector2.ZERO, _radius, Color(0.65, 0.65, 0.65, _alpha * 0.65))
