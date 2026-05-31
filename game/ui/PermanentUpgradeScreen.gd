## PermanentUpgradeScreen.gd
## Full-screen overlay for spending Service Fees on permanent upgrades.
##
## Shows two side-by-side columns: Equipment (4 upgrades) on the left,
## Business (5 upgrades) on the right. Each row displays the upgrade name,
## its current tier as filled/empty dots, a short effect label, and a
## buy button showing the SF cost. The button is disabled when the player
## cannot afford it or the upgrade is already fully purchased.
##
## Sits on CanvasLayer 20, above HubScreen (layer 15).
## PROCESS_MODE_ALWAYS so it stays interactive while the game tree is paused.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

const COLOR_PANEL      := Color(0.06, 0.06, 0.08, 0.96)
const COLOR_BORDER     := Color(0.32, 0.32, 0.38, 1.0)
const COLOR_DIVIDER    := Color(0.20, 0.20, 0.24, 1.0)
const COLOR_HEADER     := Color(1.00, 0.82, 0.10, 1.0)   # gold
const COLOR_TEXT       := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_DIM        := Color(0.50, 0.50, 0.56, 1.0)
const COLOR_DOT_ON     := Color(1.00, 0.82, 0.10, 1.0)   # filled tier — gold
const COLOR_DOT_OFF    := Color(0.30, 0.30, 0.35, 1.0)   # empty tier
const COLOR_MAX        := Color(0.85, 0.62, 0.00, 1.0)   # max label — dark gold

# Buy button.
const COLOR_BTN_BG      := Color(0.05, 0.20, 0.02, 1.0)
const COLOR_BTN_HOVER   := Color(0.08, 0.28, 0.03, 1.0)
const COLOR_BTN_PRESS   := Color(0.03, 0.12, 0.01, 1.0)
const COLOR_BTN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_BTN_DIS_BG  := Color(0.10, 0.10, 0.12, 0.55)
const COLOR_BTN_DIS_BOR := Color(0.28, 0.28, 0.32, 0.55)

# Done button — green, matching the "Start New Job" / "Start Buggin'" vocabulary.
const COLOR_DONE_BG     := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_DONE_HOVER  := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_DONE_PRESS  := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_DONE_BORDER := Color(0.22, 0.60, 0.04, 1.0)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const ROW_H:     float = 72.0   # height of each upgrade row
const COL_W:     float = 520.0  # width of each column
const COL_GAP:   float = 24.0
const PANEL_PAD: float = 18.0

# Upgrade section header height.
const SEC_H: float = 28.0

# Button dimensions within each row.
const BTN_W: float = 100.0
const BTN_H: float = 44.0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _sf_lbl:   Label  = null   # the number Label inside the SF balance HBoxContainer
var _buy_btns: Array  = []   # Array of { "id": String, "btn": Button, "cost_lbl": Label, "cost_icon": TextureRect }


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.service_fees_changed.connect(_on_fees_changed)


func _build_ui() -> void:
	# Full-screen dim.
	var dim := ColorRect.new()
	dim.color        = Color(0.0, 0.0, 0.0, 0.75)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Split upgrades into Equipment and Business columns.
	var equip_defs: Array = []
	var biz_defs:   Array = []
	for def: Dictionary in GameState.PERMANENT_UPGRADE_DEFS:
		if def["category"] == "Equipment":
			equip_defs.append(def)
		else:
			biz_defs.append(def)

	# Panel dimensions — sized to fit the taller column (Business: 5 items).
	var max_rows: int = maxi(equip_defs.size(), biz_defs.size())
	var content_h: float = SEC_H + float(max_rows) * ROW_H + float(max_rows - 1) * 6.0
	var panel_w: float   = COL_W * 2.0 + COL_GAP + PANEL_PAD * 2.0
	var header_h: float  = 52.0   # SF balance row
	var footer_h: float  = 56.0   # Done button row
	var panel_h: float   = PANEL_PAD + header_h + 12.0 + content_h + 12.0 + footer_h + PANEL_PAD

	var panel_x := (1280.0 - panel_w) * 0.5
	var panel_y := (600.0  - panel_h) * 0.5

	var panel := _make_panel(panel_x, panel_y, panel_w, panel_h)
	add_child(panel)

	var y := PANEL_PAD

	# --- Header: title left, SF balance right ---
	var title_lbl := Label.new()
	title_lbl.text      = "PERMANENT UPGRADES"
	title_lbl.position  = Vector2(PANEL_PAD, y + 4.0)
	title_lbl.size      = Vector2(panel_w - PANEL_PAD * 2.0 - 180.0, header_h)
	title_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", COLOR_HEADER)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title_lbl)

	# SF balance header — icon on the left, number on the right, right-aligned as a pair.
	var sf_hdr_row := HBoxContainer.new()
	sf_hdr_row.position    = Vector2(panel_w - PANEL_PAD - 180.0, y + 4.0)
	sf_hdr_row.size        = Vector2(180.0, header_h)
	sf_hdr_row.alignment   = BoxContainer.ALIGNMENT_END
	sf_hdr_row.add_theme_constant_override("separation", 5)
	sf_hdr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sf_hdr_row)

	var sf_hdr_icon := TextureRect.new()
	sf_hdr_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	sf_hdr_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	sf_hdr_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Height matches the font size; width from the 80:52 bill aspect ratio.
	sf_hdr_icon.custom_minimum_size = Vector2(40, 26)
	sf_hdr_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sf_hdr_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_hdr_row.add_child(sf_hdr_icon)

	_sf_lbl = Label.new()
	_sf_lbl.text                 = "%d" % GameState.service_fees
	_sf_lbl.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	_sf_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_sf_lbl.add_theme_font_size_override("font_size", 26)
	_sf_lbl.add_theme_color_override("font_color", COLOR_HEADER)
	_sf_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	sf_hdr_row.add_child(_sf_lbl)
	y += header_h + 12.0

	# Divider below header.
	var hdr_div := ColorRect.new()
	hdr_div.color        = COLOR_DIVIDER
	hdr_div.position     = Vector2(PANEL_PAD, y - 6.0)
	hdr_div.size         = Vector2(panel_w - PANEL_PAD * 2.0, 1.0)
	hdr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hdr_div)

	# --- Two columns ---
	var left_x  := PANEL_PAD
	var right_x := PANEL_PAD + COL_W + COL_GAP

	_build_column(panel, equip_defs,  left_x,  y, "EQUIPMENT")
	_build_column(panel, biz_defs,    right_x, y, "BUSINESS")

	# Vertical divider between columns.
	var col_div := ColorRect.new()
	col_div.color        = COLOR_DIVIDER
	col_div.position     = Vector2(PANEL_PAD + COL_W + COL_GAP * 0.5 - 0.5, y)
	col_div.size         = Vector2(1.0, content_h)
	col_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col_div)

	y += content_h + 12.0

	# --- Footer divider + Done button ---
	var ftr_div := ColorRect.new()
	ftr_div.color        = COLOR_DIVIDER
	ftr_div.position     = Vector2(PANEL_PAD, y)
	ftr_div.size         = Vector2(panel_w - PANEL_PAD * 2.0, 1.0)
	ftr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(ftr_div)
	y += 10.0

	var done_btn := Button.new()
	done_btn.text        = "Done"
	done_btn.focus_mode  = Control.FOCUS_NONE
	done_btn.position    = Vector2(panel_w - PANEL_PAD - 140.0, y)
	done_btn.size        = Vector2(140.0, 48.0)
	done_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	done_btn.add_theme_font_override("font", UIFonts.primary_bold())
	done_btn.add_theme_font_size_override("font_size", 22)
	done_btn.add_theme_color_override("font_color", COLOR_TEXT)
	done_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  COLOR_DONE_BG],
		["hover",   COLOR_DONE_HOVER],
		["pressed", COLOR_DONE_PRESS],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color              = state[1]
		box.border_color          = COLOR_DONE_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.content_margin_left   = 12.0
		box.content_margin_right  = 12.0
		box.content_margin_top    = 8.0
		box.content_margin_bottom = 8.0
		done_btn.add_theme_stylebox_override(state[0], box)
	done_btn.pressed.connect(_on_done_pressed)
	panel.add_child(done_btn)

	_refresh_all_buttons()


## Builds one column of upgrade rows below a section header label.
func _build_column(parent: Control, defs: Array,
		col_x: float, col_y: float, header: String) -> void:
	# Section header.
	var hdr := Label.new()
	hdr.text          = header
	hdr.position      = Vector2(col_x, col_y)
	hdr.size          = Vector2(COL_W, SEC_H)
	hdr.add_theme_font_override("font", UIFonts.primary_bold())
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COLOR_DIM)
	hdr.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hdr)

	var row_y := col_y + SEC_H
	for def: Dictionary in defs:
		_build_upgrade_row(parent, def, col_x, row_y)
		row_y += ROW_H + 6.0


## Builds one upgrade row: name + dots | effect label | cost | buy button.
func _build_upgrade_row(parent: Control, def: Dictionary,
		rx: float, ry: float) -> void:
	var row := Control.new()
	row.position     = Vector2(rx, ry)
	row.size         = Vector2(COL_W, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var upgrade_id: String = def["id"]
	var tier: int          = GameState.get_upgrade_tier(upgrade_id)
	var max_tiers: int     = def["tier_costs"].size()

	# Name label.
	var name_lbl := Label.new()
	name_lbl.text         = def["name"]
	name_lbl.position     = Vector2(0.0, 2.0)
	name_lbl.size         = Vector2(COL_W - BTN_W - 10.0, 24.0)
	name_lbl.clip_text    = true
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	# Tier dots — one filled circle per purchased tier, one empty per remaining.
	var dots_lbl := Label.new()
	var dots_text := ""
	for i in max_tiers:
		dots_text += ("●" if i < tier else "○") + (" " if i < max_tiers - 1 else "")
	dots_lbl.text         = dots_text
	dots_lbl.position     = Vector2(0.0, 26.0)
	dots_lbl.size         = Vector2(60.0, 20.0)
	dots_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	dots_lbl.add_theme_font_size_override("font_size", 14)
	dots_lbl.add_theme_color_override("font_color", COLOR_DOT_ON if tier > 0 else COLOR_DOT_OFF)
	dots_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dots_lbl)

	# Effect label — shows the tier being unlocked, or "MAX" when complete.
	var effect_lbl := Label.new()
	if tier >= max_tiers:
		effect_lbl.text = "MAX"
		effect_lbl.add_theme_color_override("font_color", COLOR_MAX)
	else:
		effect_lbl.text = def["tier_effects"][tier]
		effect_lbl.add_theme_color_override("font_color", COLOR_HEADER)
	effect_lbl.position     = Vector2(62.0, 26.0)
	effect_lbl.size         = Vector2(COL_W - BTN_W - 72.0, 20.0)
	effect_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	effect_lbl.add_theme_font_size_override("font_size", 13)
	effect_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(effect_lbl)

	# Description.
	var desc_lbl := Label.new()
	desc_lbl.text         = def["desc"]
	desc_lbl.position     = Vector2(0.0, 48.0)
	desc_lbl.size         = Vector2(COL_W - BTN_W - 10.0, 22.0)
	desc_lbl.clip_text    = true
	desc_lbl.add_theme_font_override("font", UIFonts.primary())
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", COLOR_DIM)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	# Buy button — right-aligned in the row.
	var btn := Button.new()
	btn.focus_mode   = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.position     = Vector2(COL_W - BTN_W, (ROW_H - BTN_H) * 0.5)
	btn.size         = Vector2(BTN_W, BTN_H)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_buy_pressed.bind(upgrade_id))
	row.add_child(btn)

	# Cost content inside the button — icon + number, centred.
	# The HBoxContainer fills the button face; the icon is hidden when "MAX" is shown.
	var cost_row := HBoxContainer.new()
	cost_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cost_row.alignment   = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 3)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cost_row)

	var cost_icon := TextureRect.new()
	cost_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	cost_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	cost_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cost_icon.custom_minimum_size = Vector2(23, 15)
	cost_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_icon)

	var cost_lbl := Label.new()
	cost_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 15)
	cost_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)

	_buy_btns.append({ "id": upgrade_id, "btn": btn, "cost_lbl": cost_lbl, "cost_icon": cost_icon })


## Rebuilds all buy button states and cost labels from current GameState.
func _refresh_all_buttons() -> void:
	for entry: Dictionary in _buy_btns:
		var upgrade_id: String   = entry["id"]
		var btn: Button          = entry["btn"]
		var cost_lbl: Label      = entry["cost_lbl"]
		var cost_icon: TextureRect = entry["cost_icon"]
		var tier: int            = GameState.get_upgrade_tier(upgrade_id)
		var maxed: bool          = tier >= 2
		var can_buy: bool        = GameState.can_purchase_upgrade(upgrade_id)

		btn.disabled = maxed or not can_buy

		if maxed:
			cost_icon.visible = false   # hide the bill icon when showing "MAX"
			cost_lbl.text = "MAX"
			cost_lbl.add_theme_color_override("font_color", COLOR_MAX)
			_apply_btn_style(btn, false, true)
		elif can_buy:
			cost_icon.visible = true
			var def := _def_for(upgrade_id)
			cost_lbl.text = "%d" % def["tier_costs"][tier]
			cost_lbl.add_theme_color_override("font_color", COLOR_HEADER)
			_apply_btn_style(btn, true, false)
		else:
			cost_icon.visible = true
			var def := _def_for(upgrade_id)
			cost_lbl.text = "%d" % def["tier_costs"][tier]
			cost_lbl.add_theme_color_override("font_color", COLOR_DIM)
			_apply_btn_style(btn, false, false)


func _def_for(upgrade_id: String) -> Dictionary:
	for def: Dictionary in GameState.PERMANENT_UPGRADE_DEFS:
		if def["id"] == upgrade_id:
			return def
	return {}


func _apply_btn_style(btn: Button, affordable: bool, maxed: bool) -> void:
	if maxed:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color     = COLOR_BTN_DIS_BG
			box.border_color = COLOR_BTN_DIS_BOR
			box.set_border_width_all(1)
			box.set_corner_radius_all(6)
			box.set_content_margin_all(6.0)
			btn.add_theme_stylebox_override(state, box)
		return

	var bg_n  := COLOR_BTN_BG      if affordable else COLOR_BTN_DIS_BG
	var bg_h  := COLOR_BTN_HOVER   if affordable else COLOR_BTN_DIS_BG
	var bg_p  := COLOR_BTN_PRESS   if affordable else COLOR_BTN_DIS_BG
	var bor   := COLOR_BTN_BORDER  if affordable else COLOR_BTN_DIS_BOR
	for state: Array in [
		["normal",   bg_n],
		["hover",    bg_h],
		["pressed",  bg_p],
		["disabled", COLOR_BTN_DIS_BG],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = bor
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(6.0)
		btn.add_theme_stylebox_override(state[0], box)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_panel(px: float, py: float, pw: float, ph: float) -> Control:
	var ctrl := Control.new()
	ctrl.position     = Vector2(px, py)
	ctrl.size         = Vector2(pw, ph)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color        = COLOR_PANEL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.add_child(bg)

	var border := Panel.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color.TRANSPARENT
	sty.border_color = COLOR_BORDER
	sty.set_border_width_all(2)
	sty.set_corner_radius_all(8)
	border.add_theme_stylebox_override("panel", sty)
	ctrl.add_child(border)

	return ctrl


# ---------------------------------------------------------------------------
# Input blocking
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch \
			or event is InputEventMouseButton \
			or event is InputEventScreenDrag \
			or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_fees_changed(_new_amount: int) -> void:
	if _sf_lbl != null:
		_sf_lbl.text = "%d" % GameState.service_fees
	_refresh_all_buttons()


func _on_buy_pressed(upgrade_id: String) -> void:
	if GameState.purchase_upgrade(upgrade_id):
		AudioManager.play_ui("upgrade")
		# Rebuild the screen so tier dots and effect labels update immediately.
		# Simpler than patching individual nodes in place.
		for child in get_children():
			child.queue_free()
		_buy_btns.clear()
		_sf_lbl = null
		_build_ui()


func _on_done_pressed() -> void:
	AudioManager.play_ui("button")
	if GameState.service_fees_changed.is_connected(_on_fees_changed):
		GameState.service_fees_changed.disconnect(_on_fees_changed)
	queue_free()
