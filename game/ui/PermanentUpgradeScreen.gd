## PermanentUpgradeScreen.gd
## Full-screen tabbed overlay for spending Service Fees on permanent upgrades.
##
## Two tabs — EQUIPMENT and BUSINESS — each showing its upgrades as a
## full-width scrollable list.  Only the active tab's items are displayed.
##
## Sits on CanvasLayer 20, above HubScreen (layer 15).
## PROCESS_MODE_ALWAYS so it stays interactive while the game tree is paused.

extends CanvasLayer

const UIFonts = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

const COLOR_PANEL      := Color(0.02, 0.10, 0.01, 1.0)
const COLOR_DIVIDER    := Color(0.20, 0.20, 0.24, 1.0)
const COLOR_HEADER     := Color(1.00, 0.82, 0.10, 1.0)   # gold
const COLOR_TEXT       := Color(0.90, 0.90, 0.90, 1.0)
const COLOR_DOT_OFF    := Color(0.30, 0.30, 0.35, 1.0)
const COLOR_MAX        := Color(0.85, 0.62, 0.00, 1.0)
const COLOR_BORDER     := Color(0.32, 0.32, 0.38, 1.0)
const COLOR_DIM        := Color(0.50, 0.50, 0.56, 1.0)

const COLOR_TAB_ACTIVE_BG  := Color(0.04, 0.18, 0.01, 1.0)
const COLOR_TAB_IDLE_BG    := Color(0.01, 0.06, 0.00, 1.0)
const COLOR_TAB_ACTIVE_TXT := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_TAB_IDLE_TXT   := Color(0.50, 0.50, 0.56, 1.0)

const COLOR_BTN_BG      := Color(0.05, 0.20, 0.02, 1.0)
const COLOR_BTN_HOVER   := Color(0.08, 0.28, 0.03, 1.0)
const COLOR_BTN_PRESS   := Color(0.03, 0.12, 0.01, 1.0)
const COLOR_BTN_BORDER  := Color(0.22, 0.60, 0.04, 1.0)
const COLOR_BTN_DIS_BG  := Color(0.10, 0.10, 0.12, 0.55)
const COLOR_BTN_DIS_BOR := Color(0.28, 0.28, 0.32, 0.55)

const COLOR_DONE_BG     := Color(0.04, 0.25, 0.00, 1.0)
const COLOR_DONE_HOVER  := Color(0.07, 0.33, 0.01, 1.0)
const COLOR_DONE_PRESS  := Color(0.02, 0.16, 0.00, 1.0)
const COLOR_DONE_BORDER := Color(0.22, 0.60, 0.04, 1.0)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

const PADDING:  float = 24.0   # horizontal inset used consistently throughout
const HEADER_H: float = 66.0   # header bar (title + SF balance + Close) — 50% larger than original 44
const TAB_H:    float = 50.0   # tab button row
const ROW_H:    float = 64.0   # height of each upgrade item in the scroll list
const BTN_W:    float = 160.0
const BTN_H:    float = 50.0


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _active_tab: String        = "Equipment"
var _sf_lbl:     Label         = null
var _tab_equip:  Button        = null
var _tab_biz:    Button        = null
var _vbox:       VBoxContainer = null
var _buy_btns:   Array         = []   # Array of { "id", "btn", "cost_lbl", "cost_icon" }


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer        = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.service_fees_changed.connect(_on_fees_changed)


func _build_ui() -> void:
	# Fully opaque background.
	var bg := ColorRect.new()
	bg.color        = COLOR_PANEL
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_header()

	var hdr_div := ColorRect.new()
	hdr_div.color        = COLOR_DIVIDER
	hdr_div.position     = Vector2(0.0, HEADER_H)
	hdr_div.size         = Vector2(1280.0, 1.0)
	hdr_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hdr_div)

	_build_tab_bar()

	var tab_div := ColorRect.new()
	tab_div.color        = COLOR_DIVIDER
	tab_div.position     = Vector2(0.0, HEADER_H + 1.0 + TAB_H)
	tab_div.size         = Vector2(1280.0, 1.0)
	tab_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_div)

	# Scrollable list — fills the remaining height below the tab bar.
	var scroll_top := HEADER_H + 1.0 + TAB_H + 1.0
	var scroll := ScrollContainer.new()
	scroll.position                  = Vector2(0.0, scroll_top)
	scroll.size                      = Vector2(1280.0, 600.0 - scroll_top)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	scroll.process_mode              = Node.PROCESS_MODE_ALWAYS
	add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(_vbox)

	_populate_tab(_active_tab)


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

func _build_header() -> void:
	# Title — 50% larger than original (26→39 pt).
	var title := Label.new()
	title.text               = "PERMANENT UPGRADES"
	title.position           = Vector2(PADDING, 0.0)
	title.size               = Vector2(700.0, HEADER_H)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIFonts.primary_bold())
	title.add_theme_font_size_override("font_size", 39)
	title.add_theme_color_override("font_color", COLOR_HEADER)
	title.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# SF balance: icon + number, centred in the header.
	var sf_row := HBoxContainer.new()
	sf_row.position    = Vector2(640.0 - 120.0, 4.0)
	sf_row.size        = Vector2(240.0, HEADER_H - 8.0)
	sf_row.alignment   = BoxContainer.ALIGNMENT_CENTER
	sf_row.add_theme_constant_override("separation", 6)
	sf_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sf_row)

	var sf_icon := TextureRect.new()
	sf_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	sf_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	sf_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sf_icon.custom_minimum_size = Vector2(54, 36)   # 50% larger than 36×24
	sf_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sf_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(sf_icon)

	_sf_lbl = Label.new()
	_sf_lbl.text                = "%d" % GameState.service_fees
	_sf_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sf_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	_sf_lbl.add_theme_font_size_override("font_size", 39)   # 50% larger than 26
	_sf_lbl.add_theme_color_override("font_color", COLOR_HEADER)
	_sf_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	sf_row.add_child(_sf_lbl)

	# Close button — right-aligned in the header.
	var done_btn := Button.new()
	done_btn.text         = "Close"
	done_btn.focus_mode   = Control.FOCUS_NONE
	done_btn.position     = Vector2(1280.0 - PADDING - 130.0, (HEADER_H - 44.0) * 0.5)
	done_btn.size         = Vector2(130.0, 44.0)
	done_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	done_btn.add_theme_font_override("font", UIFonts.primary_bold())
	done_btn.add_theme_font_size_override("font_size", 26)
	done_btn.add_theme_color_override("font_color", COLOR_TEXT)
	done_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state: Array in [
		["normal",  COLOR_DONE_BG],
		["hover",   COLOR_DONE_HOVER],
		["pressed", COLOR_DONE_PRESS],
	]:
		var box := StyleBoxFlat.new()
		box.bg_color     = state[1]
		box.border_color = COLOR_DONE_BORDER
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(6.0)
		done_btn.add_theme_stylebox_override(state[0], box)
	done_btn.pressed.connect(_on_done_pressed)
	add_child(done_btn)


# ---------------------------------------------------------------------------
# Tab bar
# ---------------------------------------------------------------------------

func _build_tab_bar() -> void:
	var tab_y := HEADER_H + 1.0
	var half  := 640.0   # half of 1280

	_tab_equip = _make_tab_button("EQUIPMENT")
	_tab_equip.position = Vector2(0.0, tab_y)
	_tab_equip.size     = Vector2(half, TAB_H)
	_tab_equip.pressed.connect(func() -> void: _switch_tab("Equipment"))
	add_child(_tab_equip)

	var v_div := ColorRect.new()
	v_div.color        = COLOR_DIVIDER
	v_div.position     = Vector2(half - 0.5, tab_y + 6.0)
	v_div.size         = Vector2(1.0, TAB_H - 12.0)
	v_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v_div)

	_tab_biz = _make_tab_button("BUSINESS")
	_tab_biz.position = Vector2(half, tab_y)
	_tab_biz.size     = Vector2(half, TAB_H)
	_tab_biz.pressed.connect(func() -> void: _switch_tab("Business"))
	add_child(_tab_biz)

	_refresh_tab_styles()


func _make_tab_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text         = label_text
	btn.focus_mode   = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


func _refresh_tab_styles() -> void:
	_apply_tab_style(_tab_equip, _active_tab == "Equipment")
	_apply_tab_style(_tab_biz,   _active_tab == "Business")


func _apply_tab_style(btn: Button, active: bool) -> void:
	btn.add_theme_color_override("font_color",
		COLOR_TAB_ACTIVE_TXT if active else COLOR_TAB_IDLE_TXT)
	for state: String in ["normal", "hover", "pressed"]:
		var bg := COLOR_TAB_ACTIVE_BG if active else COLOR_TAB_IDLE_BG
		if state == "hover":
			bg = bg.lightened(0.06)
		var box := StyleBoxFlat.new()
		box.bg_color = bg
		if active:
			# Gold underline marks the active tab.
			box.border_color        = COLOR_HEADER
			box.border_width_bottom = 3
			box.border_width_top    = 0
			box.border_width_left   = 0
			box.border_width_right  = 0
		else:
			box.set_border_width_all(0)
		box.content_margin_left   = 6.0
		box.content_margin_right  = 6.0
		box.content_margin_top    = 4.0
		box.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override(state, box)


# ---------------------------------------------------------------------------
# Tab content
# ---------------------------------------------------------------------------

func _switch_tab(tab_name: String) -> void:
	if _active_tab == tab_name:
		return
	_active_tab = tab_name
	_refresh_tab_styles()
	_buy_btns.clear()
	for child in _vbox.get_children():
		child.queue_free()
	_populate_tab(_active_tab)


func _populate_tab(tab_name: String) -> void:
	var defs: Array = []
	for def: Dictionary in GameState.PERMANENT_UPGRADE_DEFS:
		if def["category"] == tab_name:
			defs.append(def)

	for i in defs.size():
		_build_upgrade_row(defs[i])
		# 1 px divider between rows (not after the last one).
		if i < defs.size() - 1:
			var div := ColorRect.new()
			div.custom_minimum_size   = Vector2(0.0, 1.0)
			div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			div.color        = COLOR_DIVIDER
			div.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_vbox.add_child(div)

	_refresh_all_buttons()


# ---------------------------------------------------------------------------
# Upgrade row
# ---------------------------------------------------------------------------

## Returns the effect label string for a given upgrade at its current tier:
##   tier 0       → first tier label (what you'll get)
##   tier 1–9     → "previous → next" so the player sees what changes
##   tier == max  → "MAX"
func _effect_text(def: Dictionary, tier: int) -> String:
	var max_tiers: int = def["tier_costs"].size()
	if tier >= max_tiers:
		return "MAX"
	if tier == 0:
		return def["tier_effects"][0]
	return def["tier_effects"][tier - 1] + " → " + def["tier_effects"][tier]


## Builds a single upgrade row and appends it to _vbox.
##
## Layout (ROW_H = 64 px):
##   Row 1 (y=8):  [★ tier | name (large) | effect text]     ← title is dominant
##   Row 2 (y=37): [description (smaller, dimmer)]
##   Right column: buy button, vertically centred
func _build_upgrade_row(def: Dictionary) -> void:
	var upgrade_id: String = def["id"]
	var tier: int          = GameState.get_upgrade_tier(upgrade_id)
	var max_tiers: int     = def["tier_costs"].size()

	# Full-width row container; height is fixed, width expands to fill VBoxContainer.
	var row := Control.new()
	row.custom_minimum_size   = Vector2(0.0, ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(row)

	# Vertical positions within the row — two content rows centred in ROW_H.
	var row1_y: float = 8.0    # top label row, inset slightly from the top edge
	var row2_y: float = 37.0   # description row below

	# ── Star-level panel — spans the full row height ─────────────────────────
	# Gold border when fully maxed; dark gray otherwise.
	# The star glyph fills the upper portion; the tier number is centred below.
	var star_color: Color   = COLOR_HEADER if tier > 0 else COLOR_DOT_OFF
	var star_panel          := Panel.new()
	star_panel.position     = Vector2(PADDING, 0.0)
	star_panel.size         = Vector2(88.0, ROW_H)
	star_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_sty            := StyleBoxFlat.new()
	star_sty.bg_color     = Color(0.04, 0.04, 0.06, 0.60)
	star_sty.border_color = COLOR_HEADER if tier >= max_tiers else COLOR_BORDER
	star_sty.set_border_width_all(1)
	star_sty.set_corner_radius_all(3)
	star_panel.add_theme_stylebox_override("panel", star_sty)
	row.add_child(star_panel)

	# HBoxContainer fills the panel: star glyph on the left, tier number on the right.
	var star_vbox := HBoxContainer.new()
	star_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	star_vbox.add_theme_constant_override("separation", 0)
	star_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_panel.add_child(star_vbox)

	# Star glyph — takes an equal share of the panel width; centred vertically.
	var star_sym := Label.new()
	star_sym.text                      = "★"
	star_sym.size_flags_horizontal     = Control.SIZE_EXPAND_FILL
	star_sym.size_flags_stretch_ratio  = 1.0
	star_sym.size_flags_vertical       = Control.SIZE_SHRINK_CENTER
	star_sym.horizontal_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	star_sym.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	star_sym.add_theme_font_override("font", UIFonts.primary_bold())
	star_sym.add_theme_font_size_override("font_size", 46)   # ~85% of 64px row height
	star_sym.add_theme_color_override("font_color", star_color)
	star_sym.mouse_filter              = Control.MOUSE_FILTER_IGNORE
	star_vbox.add_child(star_sym)

	# Tier number — takes an equal share of the panel width; centred vertically.
	var tier_num := Label.new()
	tier_num.text                      = "%d" % tier
	tier_num.size_flags_horizontal     = Control.SIZE_EXPAND_FILL
	tier_num.size_flags_stretch_ratio  = 1.0
	tier_num.size_flags_vertical       = Control.SIZE_SHRINK_CENTER
	tier_num.horizontal_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	tier_num.vertical_alignment        = VERTICAL_ALIGNMENT_CENTER
	tier_num.add_theme_font_override("font", UIFonts.primary_bold())
	tier_num.add_theme_font_size_override("font_size", 32)
	tier_num.add_theme_color_override("font_color", star_color)
	tier_num.mouse_filter              = Control.MOUSE_FILTER_IGNORE
	star_vbox.add_child(tier_num)

	# ── Row 1: name (large title) + effect text ───────────────────────────────
	var name_lbl := Label.new()
	name_lbl.text         = def["name"]
	name_lbl.position     = Vector2(PADDING + 96.0, row1_y)
	name_lbl.size         = Vector2(300.0, 26.0)
	name_lbl.clip_text    = true
	name_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	name_lbl.add_theme_font_size_override("font_size", 18)   # title — larger
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var effect_lbl := Label.new()
	effect_lbl.text = _effect_text(def, tier)
	effect_lbl.add_theme_color_override("font_color",
		COLOR_MAX if tier >= max_tiers else COLOR_HEADER)
	effect_lbl.position     = Vector2(PADDING + 96.0 + 300.0 + 16.0, row1_y)
	effect_lbl.size         = Vector2(660.0, 26.0)
	effect_lbl.clip_text    = true
	effect_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	effect_lbl.add_theme_font_size_override("font_size", 23)
	effect_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(effect_lbl)

	# ── Row 2: description (smaller, so it reads as subordinate to the title) ──
	var desc_lbl := Label.new()
	desc_lbl.text         = def["desc"]
	desc_lbl.position     = Vector2(PADDING + 96.0, row2_y)
	desc_lbl.size         = Vector2(1000.0, 24.0)
	desc_lbl.clip_text    = true
	desc_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	desc_lbl.add_theme_font_size_override("font_size", 21)   # description — clearly smaller than name
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.77, 1.0))
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	# ── Buy button — right-aligned, vertically centred ────────────────────────
	var btn := Button.new()
	btn.focus_mode   = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.position     = Vector2(1280.0 - PADDING - BTN_W, (ROW_H - BTN_H) * 0.5)
	btn.size         = Vector2(BTN_W, BTN_H)
	btn.add_theme_font_override("font", UIFonts.primary_bold())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_buy_pressed.bind(upgrade_id))
	row.add_child(btn)

	var cost_row := HBoxContainer.new()
	cost_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cost_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	cost_row.add_theme_constant_override("separation", 4)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cost_row)

	var cost_icon := TextureRect.new()
	cost_icon.texture             = load("res://assets/service_fee_icon.svg") as Texture2D
	cost_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	cost_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cost_icon.custom_minimum_size = Vector2(64, 43)   # 3:2 aspect ratio at 43px (85% of BTN_H 50)
	cost_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_icon)

	var cost_lbl := Label.new()
	cost_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.add_theme_font_override("font", UIFonts.primary_bold())
	cost_lbl.add_theme_font_size_override("font_size", 36)
	cost_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)

	_buy_btns.append({ "id": upgrade_id, "btn": btn, "cost_lbl": cost_lbl, "cost_icon": cost_icon })


# ---------------------------------------------------------------------------
# Button state management
# ---------------------------------------------------------------------------

func _refresh_all_buttons() -> void:
	for entry: Dictionary in _buy_btns:
		var upgrade_id: String     = entry["id"]
		var btn: Button            = entry["btn"]
		var cost_lbl: Label        = entry["cost_lbl"]
		var cost_icon: TextureRect = entry["cost_icon"]
		var def: Dictionary        = _def_for(upgrade_id)
		var tier: int              = GameState.get_upgrade_tier(upgrade_id)
		var maxed: bool            = tier >= def["tier_costs"].size()
		var can_buy: bool          = GameState.can_purchase_upgrade(upgrade_id)

		btn.disabled = maxed or not can_buy

		if maxed:
			cost_icon.visible = false
			cost_lbl.text     = "MAX"
			cost_lbl.add_theme_color_override("font_color", COLOR_MAX)
			_apply_btn_style(btn, false, true)
		elif can_buy:
			cost_icon.visible = true
			cost_lbl.text     = "%d" % def["tier_costs"][tier]
			cost_lbl.add_theme_color_override("font_color", COLOR_HEADER)
			_apply_btn_style(btn, true, false)
		else:
			cost_icon.visible = true
			cost_lbl.text     = "%d" % def["tier_costs"][tier]
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

	var bg_n := COLOR_BTN_BG    if affordable else COLOR_BTN_DIS_BG
	var bg_h := COLOR_BTN_HOVER if affordable else COLOR_BTN_DIS_BG
	var bg_p := COLOR_BTN_PRESS if affordable else COLOR_BTN_DIS_BG
	var bor  := COLOR_BTN_BORDER if affordable else COLOR_BTN_DIS_BOR
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
# Input blocking
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Swallow pointer events so the arena behind the screen never receives them.
	# The ScrollContainer's _gui_input handles drag-to-scroll before this fires,
	# so vertical scrolling still works correctly.
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
		# Repopulate the active tab in place so the scroll position is preserved
		# and only the affected column needs to rebuild.
		_buy_btns.clear()
		for child in _vbox.get_children():
			child.queue_free()
		_populate_tab(_active_tab)


func _on_done_pressed() -> void:
	AudioManager.play_ui("button")
	if GameState.service_fees_changed.is_connected(_on_fees_changed):
		GameState.service_fees_changed.disconnect(_on_fees_changed)
	queue_free()
