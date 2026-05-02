## UIFonts.gd
## Central font registry. All UI scripts load fonts from here so the three
## typeface roles are defined in one place.
##
## Roles:
##   primary      — Roboto Condensed Regular  — general UI, stats, buttons
##   primary_bold — Roboto Condensed Bold     — emphasis labels (Bug Bucks)
##   header       — Bebas Neue Regular        — wave alerts, countdowns, run-over
##   flavor       — Montserrat Regular        — trap names, company branding
##
## Font files must be placed in res://assets/fonts/. If a file is missing,
## the function returns a plain SystemFont so the UI still renders.

const _PRIMARY_PATH      := "res://assets/fonts/RobotoCondensed-Regular.ttf"
const _PRIMARY_BOLD_PATH := "res://assets/fonts/RobotoCondensed-Bold.ttf"
const _HEADER_PATH       := "res://assets/fonts/BebasNeue-Regular.ttf"
const _FLAVOR_PATH       := "res://assets/fonts/Montserrat-Regular.ttf"


static func primary() -> Font:
	return _load(_PRIMARY_PATH)

static func primary_bold() -> Font:
	return _load(_PRIMARY_BOLD_PATH)

static func header() -> Font:
	return _load(_HEADER_PATH)

static func flavor() -> Font:
	return _load(_FLAVOR_PATH)

static func flavor_bold_italic() -> Font:
	# Montserrat has no bold-italic file, so synthesize both effects via
	# FontVariation: embolden thickens strokes; variation_transform skews
	# glyphs right to mimic italic (y_axis x-component shifts top of each
	# glyph rightward in screen space where Y increases downward).
	var fv := FontVariation.new()
	fv.base_font = _load(_FLAVOR_PATH)
	fv.variation_embolden = 0.8
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.2, 1.0), Vector2.ZERO)
	return fv


static func _load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return SystemFont.new()   # fallback — renders with the OS default
