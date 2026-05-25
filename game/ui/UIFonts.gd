## UIFonts.gd
## Central font registry. All UI scripts load fonts from here so the five
## typeface roles are defined in one place.
##
## Roles:
##   primary      — Roboto Condensed Regular  — general UI, stats, buttons
##   primary_bold — Roboto Condensed Bold     — emphasis labels (Bug Bucks)
##   header       — Bebas Neue Regular        — wave alerts, countdowns, run-over
##   flavor       — Montserrat Regular        — trap names, company branding
##   symbols      — Noto Sans Symbols 2       — Unicode symbol glyphs (◆ ⚡ etc.)
##
## Note: ★ / ☆ star indicators are drawn as vector polygons by StarBar.gd and
## Trap._make_star_mesh() rather than rendered as text. symbols() is only needed
## for non-star glyphs (the ◆ boost indicator on placed traps, etc.).
##
## Font files live in res://assets/fonts/. Missing files degrade gracefully.

const _PRIMARY_PATH      := "res://assets/fonts/RobotoCondensed-Regular.ttf"
const _PRIMARY_BOLD_PATH := "res://assets/fonts/RobotoCondensed-Bold.ttf"
const _HEADER_PATH       := "res://assets/fonts/BebasNeue-Regular.ttf"
const _FLAVOR_PATH       := "res://assets/fonts/Montserrat-Regular.ttf"
const _SYMBOLS_PATH      := "res://assets/fonts/NotoSansSymbols2-Regular.ttf"


static func primary() -> Font:
	return _load(_PRIMARY_PATH)

static func primary_bold() -> Font:
	return _load(_PRIMARY_BOLD_PATH)

static func header() -> Font:
	return _load(_HEADER_PATH)

static func flavor() -> Font:
	return _load(_FLAVOR_PATH)

static func flavor_bold() -> Font:
	# Montserrat has no bold file, so synthesize via FontVariation embolden.
	var fv := FontVariation.new()
	fv.base_font = _load(_FLAVOR_PATH)
	fv.variation_embolden = 0.8
	return fv

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


## Returns the Noto Sans Symbols 2 font for non-star Unicode glyphs (◆ ⚡ etc.).
## Falls back to a SystemFont on machines where the .ttf file is absent.
static func symbols() -> Font:
	if ResourceLoader.exists(_SYMBOLS_PATH):
		return load(_SYMBOLS_PATH)
	# Dev-machine fallback: monochrome OS font so modulate works during testing.
	var sf := SystemFont.new()
	sf.font_names = ["Segoe UI Symbol", "Noto Sans Symbols 2", "Symbola"]
	sf.allow_system_fallback = true
	return sf


static func _load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return SystemFont.new()   # fallback — renders with the OS default
