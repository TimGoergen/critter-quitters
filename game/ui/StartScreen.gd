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

# "Contain" scaling: the van is as large as possible while fully visible.
# scale = min(screen_w / REF_W, screen_h / REF_H) — computed against the
# original 1536×1024 reference dimensions so the van's visual size stays
# constant even if the PNG file's pixel dimensions change.
const VAN_REF_W := 1536.0
const VAN_REF_H := 1024.0

# Tailpipe pixel coordinates in the source image (990 × 560).
# x is the horizontal centre of the exhaust pipe at the rear bumper;
# y is the pipe exit height (undercarriage, just above the rear bumper bottom).
const TAILPIPE_IMG_X := 875.0
const TAILPIPE_IMG_Y := 450.0

var _van:       Sprite2D
var _start_btn: Button
var _quit_btn:  Button


func _ready() -> void:
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if not is_instance_valid(_van):
		return
	var vp      := get_viewport().get_visible_rect().size
	var scale_f := minf(vp.x / VAN_REF_W, vp.y / VAN_REF_H)
	_van.scale    = Vector2(scale_f, scale_f)
	_van.position = Vector2(vp.x * 0.5, vp.y * 0.5)


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# --- Background ---
	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = COLOR_BG
	add_child(bg)

	# --- Van illustration ---
	# "Contain" scale: largest size where the full image fits on screen.
	# centered = true (Godot default) means the texture is drawn with its
	# centre at `position`, so (vp/2, vp/2) puts the sprite exactly in the
	# middle of the screen regardless of image dimensions or scale.
	var van_tex: Texture2D = load("res://assets/van.png")
	_van          = Sprite2D.new()
	_van.texture  = van_tex
	_van.centered = true
	var scale_f   := minf(vp.x / VAN_REF_W, vp.y / VAN_REF_H)
	_van.scale    = Vector2(scale_f, scale_f)
	_van.position = Vector2(vp.x * 0.5, vp.y * 0.5)
	add_child(_van)

	# --- Slogan ---
	var slogan := Label.new()
	slogan.text                 = "\"Bugs don't have to go home but they can't stay here\""
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	slogan.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	slogan.anchor_left          = 0.10
	slogan.anchor_right         = 0.90
	slogan.anchor_top           = 0.72
	slogan.anchor_bottom        = 0.80
	slogan.add_theme_font_override("font", UIFonts.flavor_bold_italic())
	slogan.add_theme_font_size_override("font_size", 26)
	slogan.add_theme_color_override("font_color", COLOR_SLOGAN)
	add_child(slogan)

	# --- Buttons: side by side, equal width, centred ---
	_start_btn = _make_button("Start Buggin'")
	_start_btn.anchor_left   = 0.25
	_start_btn.anchor_right  = 0.48
	_start_btn.anchor_top    = 0.82
	_start_btn.anchor_bottom = 0.92
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_quit_btn = _make_button("Bug Out")
	_quit_btn.anchor_left   = 0.52
	_quit_btn.anchor_right  = 0.75
	_quit_btn.anchor_top    = 0.82
	_quit_btn.anchor_bottom = 0.92
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

	# Spawn a burst every ~0.07 s across the full 1.1 s drive-off. Higher
	# frequency than before so the cloud builds up to fogger-like density.
	# Each callback reads _van.position at fire time, so the spawn point
	# tracks the current rear position naturally.
	for i: int in 15:
		if i == 0:
			_spawn_exhaust_puffs()
		else:
			get_tree().create_timer(i * 0.075).timeout.connect(_spawn_exhaust_puffs)

	var tween := create_tween()
	tween.tween_property(_van, "position:x", target_x, 1.1) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_on_van_exited)


func _spawn_exhaust_puffs() -> void:
	# Puffs are added to this CanvasLayer (siblings of the van sprite) so they
	# stay in place while the van drives left, forming a lingering cloud trail.
	#
	# TAILPIPE_IMG_X/Y are the exact pixel coordinates of the tailpipe in the
	# source image. Subtracting half the image dimensions gives the offset from
	# the Sprite2D origin (image centre), then multiplied by scale to get world px.
	var tex_size  := _van.texture.get_size()
	var exhaust_x := _van.position.x + (TAILPIPE_IMG_X - tex_size.x / 2.0) * _van.scale.x
	var exhaust_y := _van.position.y + (TAILPIPE_IMG_Y - tex_size.y / 2.0) * _van.scale.y
	# 5 puffs per burst, all spawning close to the pipe — they overlap and
	# merge into a fogger-like cloud mass rather than discrete circles.
	for i: int in 5:
		var puff        := _ExhaustPuff.new()
		var angle       := randf() * TAU
		var dist        := randf_range(0.0, 18.0)
		puff.position   = Vector2(
			exhaust_x + cos(angle) * dist,
			exhaust_y + sin(angle) * dist
		)
		puff.max_radius = randf_range(76.5, 103.5)   # base 90, ±15%
		add_child(puff)
		move_child(puff, _van.get_index())


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


# One transient exhaust cloud puff.
#
# Designed like the in-game Fogger clouds: individual puffs are nearly
# transparent (alpha * 0.18 per puff) so a single puff barely shows, but
# 5–7 overlapping puffs in the cloud core stack up to ~0.6 effective opacity
# — a dense, cohesive mass rather than visible separate circles.
#
# Animation: quick bloom (0.15 s) → hold (0.25 s) → dissolve (0.50 s).
# Puff also drifts upward 30 px over its full lifetime, mimicking real exhaust.
class _ExhaustPuff extends Node2D:
	var max_radius: float = 90.0

	var _radius: float = 8.0
	var _alpha:  float = 0.0

	const _LIFETIME := 0.90   # grow + hold + fade — must match tween durations below
	const _DRIFT_PX := 30.0   # upward travel in pixels over the full lifetime

	func _ready() -> void:
		# Drift upward slowly over the full lifetime.
		create_tween() \
			.tween_property(self, "position:y", position.y - _DRIFT_PX, _LIFETIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		var anim := create_tween()
		anim.tween_method(_grow, 0.0, 1.0, 0.15)   # quick bloom
		anim.tween_interval(0.25)                    # hold at full size
		anim.tween_method(_fade, 1.0, 0.0, 0.50)   # dissolve
		anim.tween_callback(queue_free)

	func _grow(t: float) -> void:
		_radius = lerp(8.0, max_radius, t)
		_alpha  = t
		queue_redraw()

	func _fade(t: float) -> void:
		_alpha = t
		queue_redraw()

	func _draw() -> void:
		if _alpha > 0.0:
			# Low per-puff alpha so stacked puffs merge into a solid-looking mass.
			draw_circle(Vector2.ZERO, _radius, Color(0.80, 0.80, 0.82, _alpha * 0.18))
