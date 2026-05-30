## StartScreen.gd
## The game's opening screen. Displays the Critter Quitters van illustration as the
## title graphic, a scattered pile of business cards, and two buttons:
## "Start Buggin'" and "Bug Out".
##
## When the player taps "Start Buggin'", the van accelerates left off screen while
## exhaust puffs billow from its rear, then the scene transitions to Main.tscn.
##
## Extends CanvasLayer — same pattern as HUD.gd and DebugStartDialog.gd —
## so anchor-based layout resolves against the viewport.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")

const COLOR_BG     := Color(0.06, 0.06, 0.10, 1.0)
const COLOR_TEXT   := Color(0.90, 0.90, 0.90, 1.0)

const COLOR_GREEN_NORMAL  := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_GREEN_HOVER   := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_GREEN_PRESSED := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_GREEN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)

const COLOR_RED_NORMAL  := Color(0.25, 0.04, 0.04, 1.0)
const COLOR_RED_HOVER   := Color(0.33, 0.07, 0.07, 1.0)
const COLOR_RED_PRESSED := Color(0.16, 0.02, 0.02, 1.0)
const COLOR_RED_BORDER  := Color(0.65, 0.18, 0.04, 1.0)

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

# Business card scales to 40% of viewport width, measured against the content
# rect (via get_used_rect) so transparent padding in the PNG doesn't throw off
# the size or position calculation.
const CARD_WIDTH_FRAC    := 0.24
# The top card (last drawn, highest z-order) is scaled up so it reads as the
# "featured" card sitting on top of the pile.
const TOP_CARD_SCALE_MULT := 1.50

# Four cards dropped in a pile. Each entry: [rotation_deg, x_offset_frac, y_offset_frac, brightness].
# Drawn bottom-to-top (index 0 is furthest back). Offsets are fractions of viewport size
# applied relative to the pile anchor point so the layout scales with the screen.
const _CARD_PILE: Array = [
	[  9.0, -0.08,  0.26, 0.20],
	[  5.0, -0.09,  0.10, 0.27],
	[ -7.0, -0.05,  0.14, 0.33],
	[ 13.0, -0.02, -0.13, 0.40],
	[-17.0,  0.00,  0.03, 0.80],
]

var _van:       Sprite2D
var _cards:     Array[Sprite2D] = []
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
	_van.scale    = Vector2(scale_f * 1.485, scale_f * 1.485)
	_van.position = Vector2(vp.x * 0.65, vp.y * 0.40)

	for i: int in _cards.size():
		var entry: Array  = _CARD_PILE[i]
		var card_scale    := (vp.x * CARD_WIDTH_FRAC) / _cards[i].region_rect.size.x
		var scale_mult    := TOP_CARD_SCALE_MULT if i == _cards.size() - 1 else 1.0
		_cards[i].scale    = Vector2(card_scale * scale_mult, card_scale * scale_mult)
		_cards[i].position = Vector2(
			vp.x * 0.22 + vp.x * float(entry[1]),
			vp.y * 0.32 + vp.y * float(entry[2])
		)


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# --- Background ---
	var bg := ColorRect.new()
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	bg.color = COLOR_BG
	add_child(bg)

	# --- Business card pile ---
	# Four cards with varying rotations and small position offsets to simulate a
	# dropped pile. region_enabled clips to get_used_rect() so transparent PNG
	# padding is excluded from scale and position math.
	var card_tex:  Texture2D = load("res://assets/BusinessCard.png")
	var used_rect            := card_tex.get_image().get_used_rect()
	var card_scale           := (vp.x * CARD_WIDTH_FRAC) / used_rect.size.x
	var pile_x               := vp.x * 0.22
	var pile_y               := vp.y * 0.32
	for i: int in _CARD_PILE.size():
		var entry: Array   = _CARD_PILE[i]
		var scale_mult     := TOP_CARD_SCALE_MULT if i == _CARD_PILE.size() - 1 else 1.0
		var c              := Sprite2D.new()
		c.texture           = card_tex
		c.region_enabled    = true
		c.region_rect       = Rect2(used_rect)
		c.centered          = true
		c.rotation_degrees  = float(entry[0])
		var b: float        = float(entry[3])
		c.modulate          = Color(b, b, b, 1.0)
		c.scale             = Vector2(card_scale * scale_mult, card_scale * scale_mult)
		c.position          = Vector2(pile_x + vp.x * float(entry[1]), pile_y + vp.y * float(entry[2]))
		_cards.append(c)
		add_child(c)

	# --- Van illustration ---
	# z_index = 1 guarantees the van renders above all z_index = 0 nodes
	# (cards, exhaust puffs) regardless of scene-tree position, including
	# while it drives left over the card pile during the exit animation.
	var van_tex: Texture2D = load("res://assets/van.png")
	_van          = Sprite2D.new()
	_van.texture  = van_tex
	_van.centered = true
	_van.z_index  = 1
	var scale_f   := minf(vp.x / VAN_REF_W, vp.y / VAN_REF_H)
	_van.scale    = Vector2(scale_f * 1.485, scale_f * 1.485)
	_van.position = Vector2(vp.x * 0.65, vp.y * 0.40)
	add_child(_van)

	# --- Buttons: side by side, equal width, centred ---
	# Each button shows a house icon beside its label to mirror the in-game
	# Send Wave button aesthetic: green/uninfested for start, red/infested for quit.
	_start_btn = _make_icon_button("Start Buggin'", "res://assets/uninfested.png", true)
	_start_btn.anchor_left   = 0.25
	_start_btn.anchor_right  = 0.48
	_start_btn.anchor_top    = 0.80
	_start_btn.anchor_bottom = 0.90
	_start_btn.pressed.connect(_on_start_pressed)
	add_child(_start_btn)

	_quit_btn = _make_icon_button("Bug Out", "res://assets/infestation_level.png", false)
	_quit_btn.anchor_left   = 0.52
	_quit_btn.anchor_right  = 0.75
	_quit_btn.anchor_top    = 0.80
	_quit_btn.anchor_bottom = 0.90
	_quit_btn.pressed.connect(_on_quit_pressed)
	add_child(_quit_btn)


## Creates a button with an icon+label row inside, styled green (is_green=true)
## or red (is_green=false).  Mirrors the Send Wave button layout from HUD.gd.
func _make_icon_button(label_text: String, icon_path: String, is_green: bool) -> Button:
	var btn := Button.new()
	btn.text       = ""  # content provided by the child HBox, not the Button text property
	btn.focus_mode = Control.FOCUS_NONE

	if is_green:
		_apply_green_btn_style(btn)
	else:
		_apply_red_btn_style(btn)

	# Centred HBox containing the house icon and the button label.
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment   = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := TextureRect.new()
	icon.texture             = load(icon_path) as Texture2D
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text                = label_text
	lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", UIFonts.primary_bold())
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)

	return btn


func _on_start_pressed() -> void:
	_start_btn.disabled = true
	_quit_btn.visible   = false
	_strip_btn_border(_start_btn, true)
	_play_van_exit()


func _on_quit_pressed() -> void:
	_quit_btn.disabled  = true
	_start_btn.visible  = false
	_strip_btn_border(_quit_btn, false)
	get_tree().quit()


func _play_van_exit() -> void:
	var van_scaled_w := _van.texture.get_size().x * _van.scale.x
	# Drive the van fully off the left edge of the screen.
	var target_x := -(van_scaled_w / 2.0)

	# Schedule bursts at even *position* intervals by inverting the cubic ease-in
	# curve (pos = t^3 → t = pos^(1/3)). Without this correction, even time
	# intervals produce clumps at the start where the van is slow and gaps at
	# the end where it accelerates.
	const DRIVE_DURATION := 1.1
	const BURST_COUNT    := 13
	for i: int in BURST_COUNT:
		if i == 0:
			_spawn_exhaust_puffs()
		else:
			var pos_frac := float(i) / float(BURST_COUNT - 1)
			var delay    := pow(pos_frac, 1.0 / 3.0) * DRIVE_DURATION
			get_tree().create_timer(delay).timeout.connect(_spawn_exhaust_puffs)

	var tween := create_tween()
	tween.tween_property(_van, "position:x", target_x, DRIVE_DURATION) \
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
	# 8 puffs per burst, all spawning close to the pipe — they overlap and
	# merge into a fogger-like cloud mass rather than discrete circles.
	for i: int in 8:
		var puff        := _ExhaustPuff.new()
		var angle       := randf() * TAU
		var dist        := randf_range(0.0, 18.0)
		puff.position   = Vector2(
			exhaust_x + cos(angle) * dist,
			exhaust_y + sin(angle) * dist
		)
		puff.max_radius = randf_range(76.5, 103.5)   # base 90, ±15%
		add_child(puff)


func _on_van_exited() -> void:
	# The van is now off-screen. Spawn fill puffs spread across the full viewport
	# width at the exhaust trail's height. Each puff grows until it covers the
	# entire screen from its position, creating a cloud-wipe scene transition.
	var vp        := get_viewport().get_visible_rect().size
	var exhaust_y := _van.position.y + (TAILPIPE_IMG_Y - _van.texture.get_size().y / 2.0) * _van.scale.y

	const FILL_COUNT    := 7
	const FILL_DURATION := 0.85

	for i: int in FILL_COUNT:
		var fx := (float(i) + 0.5) / float(FILL_COUNT) * vp.x
		var fy := exhaust_y + randf_range(-30.0, 30.0)
		# Each puff must reach the farthest corner of the viewport from its spawn
		# position — that guarantees no gaps regardless of where it is placed.
		var farthest := maxf(
			Vector2(fx, fy).distance_to(Vector2(0.0,   0.0)),
			maxf(
				Vector2(fx, fy).distance_to(Vector2(vp.x, 0.0)),
				maxf(
					Vector2(fx, fy).distance_to(Vector2(0.0,   vp.y)),
					Vector2(fx, fy).distance_to(Vector2(vp.x, vp.y))
				)
			)
		)
		var puff            := _FillPuff.new()
		puff.position       = Vector2(fx, fy)
		puff.target_radius  = farthest * 1.15  # 15 % overshoot so corners are fully covered
		puff.duration       = FILL_DURATION + randf_range(0.0, 0.12)
		add_child(puff)

	# Change scene after the fill animation has had time to complete.
	get_tree().create_timer(FILL_DURATION + 0.25).timeout.connect(
		func(): get_tree().change_scene_to_file("res://Main.tscn")
	)


func _apply_green_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_GREEN_NORMAL],
		["hover",   COLOR_GREEN_HOVER],
		["pressed", COLOR_GREEN_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_GREEN_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


func _apply_red_btn_style(btn: Button) -> void:
	for state: Array in [
		["normal",  COLOR_RED_NORMAL],
		["hover",   COLOR_RED_HOVER],
		["pressed", COLOR_RED_PRESSED],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_RED_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 16.0
		box.content_margin_right  = 16.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override(state[0], box)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", COLOR_TEXT)


## Replaces all state styleboxes on btn with a border-free version of its base color.
## Applied to the clicked button so it retains its background while the outline disappears.
func _strip_btn_border(btn: Button, is_green: bool) -> void:
	var bg := COLOR_GREEN_NORMAL if is_green else COLOR_RED_NORMAL
	var box := StyleBoxFlat.new()
	box.bg_color              = bg
	box.set_border_width_all(0)
	box.set_corner_radius_all(6)
	box.content_margin_left   = 16.0
	box.content_margin_right  = 16.0
	box.content_margin_top    = 8.0
	box.content_margin_bottom = 8.0
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, box)


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

	# Per-lobe layout: each entry is [offset_frac_x, offset_frac_y, radius_frac].
	# Fractions of max_radius, generated once at ready so the shape is stable
	# as the puff animates. A central blob plus irregular satellite bumps gives
	# the classic fluffy cloud silhouette instead of a smooth circle.
	var _lobes: Array = []

	const _LIFETIME   := 0.99   # grow + hold + fade — must match tween durations below
	const _DRIFT_UP   := 35.0   # upward travel in pixels
	const _DRIFT_LEFT := 18.0   # leftward drift — trails behind the departing van

	func _ready() -> void:
		# Central dominant blob.
		_lobes.append([0.0, 0.0, 0.72])
		# Six satellite lobes at irregular angles and distances.
		for i: int in 6:
			var angle := TAU * float(i) / 6.0 + randf_range(-0.45, 0.45)
			var dist  := randf_range(0.26, 0.50)
			var r     := randf_range(0.36, 0.56)
			_lobes.append([cos(angle) * dist, sin(angle) * dist, r])

		# Drift upward and slightly left.
		var dest := Vector2(position.x - _DRIFT_LEFT, position.y - _DRIFT_UP)
		create_tween() \
			.tween_property(self, "position", dest, _LIFETIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		var anim := create_tween()
		anim.tween_method(_grow, 0.0, 1.0, 0.165)   # quick bloom
		anim.tween_interval(0.275)                   # hold at full size
		anim.tween_method(_fade, 1.0, 0.0, 0.55)   # dissolve
		anim.tween_callback(queue_free)

	func _grow(t: float) -> void:
		_radius = lerp(8.0, max_radius, t)
		_alpha  = t
		queue_redraw()

	func _fade(t: float) -> void:
		_alpha  = t
		# Continue expanding during dissolve — puffs drift outward as they vanish.
		# t runs 1.0 → 0.0, so radius runs max_radius → max_radius * 1.8.
		_radius = lerp(max_radius * 1.8, max_radius, t)
		queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.0:
			return
		# Each lobe is a semi-transparent circle offset from the puff centre.
		# Low per-lobe alpha (0.07) lets the ~7 lobes across 8 overlapping puffs
		# stack to ~0.55 effective opacity in the cloud core without looking painted.
		for lobe: Array in _lobes:
			var offset := Vector2(float(lobe[0]) * _radius, float(lobe[1]) * _radius)
			var r: float = float(lobe[2]) * _radius
			draw_circle(offset, r, Color(0.82, 0.82, 0.85, _alpha * 0.07))


# One exhaust puff that expands to fill its section of the screen without fading.
# Spawned after the van exits to create a cloud-wipe scene transition.
# Visual structure mirrors _ExhaustPuff (same lobe layout and colour) for continuity,
# but uses a higher per-lobe alpha so multiple overlapping puffs reach full opacity.
class _FillPuff extends Node2D:
	var target_radius: float = 600.0
	var duration:      float = 0.85

	var _radius: float = 12.0
	var _alpha:  float = 0.0
	var _lobes:  Array = []

	func _ready() -> void:
		_lobes.append([0.0, 0.0, 0.72])
		for i: int in 6:
			var angle := TAU * float(i) / 6.0 + randf_range(-0.45, 0.45)
			var dist  := randf_range(0.26, 0.50)
			var r     := randf_range(0.36, 0.56)
			_lobes.append([cos(angle) * dist, sin(angle) * dist, r])

		var anim := create_tween()
		anim.tween_method(_expand, 0.0, 1.0, duration)

	func _expand(t: float) -> void:
		# Ease-in growth: starts slow, accelerates like gas expanding under pressure.
		_radius = lerp(12.0, target_radius, t * t)
		# Reach full opacity in the first third of the animation, then stay opaque.
		_alpha  = minf(t * 3.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if _alpha <= 0.0:
			return
		# Higher per-lobe alpha than _ExhaustPuff (0.16 vs 0.07): these puffs need
		# to fully obscure the screen rather than layer into a wispy cloud effect.
		for lobe: Array in _lobes:
			var offset := Vector2(float(lobe[0]) * _radius, float(lobe[1]) * _radius)
			var r: float = float(lobe[2]) * _radius
			draw_circle(offset, r, Color(0.82, 0.82, 0.85, _alpha * 0.16))
