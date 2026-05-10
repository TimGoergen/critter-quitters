## EnemyStatsPanel.gd
## Compact overlay shown while the player's camera is following an enemy.
## Displays enemy type, live HP (bar + fraction), movement speed,
## infestation damage, and kill bounty.
##
## Positioned at the top-centre of the arena zone.  The background ColorRect
## absorbs taps within the panel so they do not propagate to Arena and
## accidentally clear the follow.  Taps outside the panel reach Arena's
## _handle_tap(), which calls _set_followed_enemy(null).
##
## The game does not pause while this panel is visible — _process() updates
## the HP bar every frame to reflect live combat.

extends CanvasLayer

const Enemy   = preload("res://enemies/Enemy.gd")
const UIFonts = preload("res://ui/UIFonts.gd")
const HUD     = preload("res://ui/HUD.gd")

const COLOR_PANEL_BG := Color(0.092, 0.092, 0.150, 0.92)
const COLOR_BORDER   := Color(0.22, 0.22, 0.40, 1.0)
const COLOR_BAR_BG   := Color(0.28, 0.28, 0.28, 1.0)
const COLOR_BAR_FILL := Color(0.85, 0.22, 0.22, 1.0)
const COLOR_TEXT     := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_TEXT_DIM := Color(0.60, 0.60, 0.65, 1.0)

const PANEL_W:  float = 260.0
const PANEL_H:  float = 110.0
const PAD:      float = 10.0
const BORDER_W: float = 1.5


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _tracked_enemy: Node3D = null

var _bg:         ColorRect = null
var _name_label: Label     = null
var _hp_label:   Label     = null
var _hp_track:   ColorRect = null
var _hp_fill:    ColorRect = null
var _spd_val:    Label     = null
var _inf_val:    Label     = null
var _bounty_val: Label     = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer        = 2   # above HUD (layer 1), below upgrade panel
	_build_ui()
	visible = false


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp      := get_viewport().get_visible_rect().size
	var arena_cx := HUD.LEFT_PANEL_W + (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W) * 0.5
	var px       := arena_cx - PANEL_W * 0.5
	var py       := HUD.SCREEN_EDGE_MARGIN
	var inner_w  := PANEL_W - PAD * 2.0

	# Thin border rect behind the background
	var border        := ColorRect.new()
	border.color       = COLOR_BORDER
	border.position    = Vector2(px - BORDER_W, py - BORDER_W)
	border.size        = Vector2(PANEL_W + BORDER_W * 2.0, PANEL_H + BORDER_W * 2.0)
	add_child(border)

	# Background — MOUSE_FILTER_STOP (default) absorbs taps within the panel
	_bg          = ColorRect.new()
	_bg.color    = COLOR_PANEL_BG
	_bg.position = Vector2(px, py)
	_bg.size     = Vector2(PANEL_W, PANEL_H)
	add_child(_bg)

	var y := PAD

	# --- Row 1: enemy name (left) + HP fraction (right) ---
	_name_label          = Label.new()
	_name_label.position = Vector2(PAD, y)
	_name_label.size     = Vector2(inner_w * 0.60, 32.0)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", UIFonts.header())
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_bg.add_child(_name_label)

	_hp_label            = Label.new()
	_hp_label.position   = Vector2(PAD + inner_w * 0.60, y)
	_hp_label.size       = Vector2(inner_w * 0.40, 32.0)
	_hp_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.add_theme_font_override("font", UIFonts.primary_bold())
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_bg.add_child(_hp_label)

	y += 37.0

	# --- Row 2: HP bar ---
	_hp_track          = ColorRect.new()
	_hp_track.color    = COLOR_BAR_BG
	_hp_track.position = Vector2(PAD, y)
	_hp_track.size     = Vector2(inner_w, 10.0)
	_bg.add_child(_hp_track)

	_hp_fill          = ColorRect.new()
	_hp_fill.color    = COLOR_BAR_FILL
	_hp_fill.position = Vector2.ZERO
	_hp_fill.size     = Vector2(inner_w, 10.0)
	_hp_track.add_child(_hp_fill)

	y += 16.0

	# --- Row 3: Speed | Infestation | Bounty ---
	var col_w   := inner_w / 3.0
	var headers := ["SPD", "INFEST", "BOUNTY"]
	for i in range(3):
		var hdr        := Label.new()
		hdr.text        = headers[i]
		hdr.position    = Vector2(PAD + col_w * i, y)
		hdr.size        = Vector2(col_w, 15.0)
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_theme_font_override("font", UIFonts.primary_bold())
		hdr.add_theme_font_size_override("font_size", 11)
		hdr.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		_bg.add_child(hdr)

		var val        := Label.new()
		val.position    = Vector2(PAD + col_w * i, y + 16.0)
		val.size        = Vector2(col_w, 22.0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.add_theme_font_override("font", UIFonts.primary_bold())
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_color_override("font_color", COLOR_TEXT)
		_bg.add_child(val)

		match i:
			0: _spd_val    = val
			1: _inf_val    = val
			2: _bounty_val = val


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Shows the panel populated for enemy, or hides it when enemy is null.
func set_enemy(enemy: Node3D) -> void:
	_tracked_enemy = enemy
	visible        = is_instance_valid(enemy)
	if not visible:
		return
	_name_label.text = _type_name(enemy.get_enemy_type())
	_spd_val.text    = "%.1f" % enemy.get_base_speed()
	_inf_val.text    = "%.1f" % enemy.get_infestation_damage()
	_bounty_val.text = "%d"   % enemy.get_bounty()
	_update_hp()


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_enemy):
		visible = false
		return
	_update_hp()


func _update_hp() -> void:
	var cur:  float = _tracked_enemy.get_current_hp()
	var max_: float = _tracked_enemy.get_max_hp()
	_hp_label.text  = "%d / %d" % [ceili(cur), ceili(max_)]
	var frac        := cur / max_ if max_ > 0.0 else 0.0
	_hp_fill.size.x = _hp_track.size.x * frac


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _type_name(type: int) -> String:
	match type:
		Enemy.EnemyType.ANT:       return "ANT"
		Enemy.EnemyType.GNAT:      return "GNAT"
		Enemy.EnemyType.CRICKET:   return "CRICKET"
		Enemy.EnemyType.BEETLE:    return "BEETLE"
		Enemy.EnemyType.COCKROACH: return "COCKROACH"
		Enemy.EnemyType.RAT:       return "RAT"
	return "UNKNOWN"
