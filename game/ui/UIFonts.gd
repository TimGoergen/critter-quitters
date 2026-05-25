## UIFonts.gd
## Central font registry. All UI scripts load fonts from here so the three
## typeface roles are defined in one place.
##
## Roles:
##   primary      — Roboto Condensed Regular  — general UI, stats, buttons
##   primary_bold — Roboto Condensed Bold     — emphasis labels (Bug Bucks)
##   header       — Bebas Neue Regular        — wave alerts, countdowns, run-over
##   flavor       — Montserrat Regular        — trap names, company branding
##   symbols      — Noto Sans Symbols 2       — Unicode symbol glyphs (★ ☆ ⚡ ◆)
##
## All five font files are present in res://assets/fonts/ and preloaded as
## constants so they are guaranteed non-null before any scene code runs.
## The symbols() fallback path (SystemFont) is kept for safety but should
## never be reached in normal builds.

const _PRIMARY      := preload("res://assets/fonts/RobotoCondensed-Regular.ttf")
const _PRIMARY_BOLD := preload("res://assets/fonts/RobotoCondensed-Bold.ttf")
const _HEADER       := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const _FLAVOR       := preload("res://assets/fonts/Montserrat-Regular.ttf")
const _SYMBOLS      := preload("res://assets/fonts/NotoSansSymbols2-Regular.ttf")


static func primary() -> Font:
	return _PRIMARY

static func primary_bold() -> Font:
	return _PRIMARY_BOLD

static func header() -> Font:
	return _HEADER

static func flavor() -> Font:
	return _FLAVOR

static func flavor_bold() -> Font:
	# Montserrat has no bold file, so synthesize via FontVariation embolden.
	var fv := FontVariation.new()
	fv.base_font = _FLAVOR
	fv.variation_embolden = 0.8
	return fv

static func flavor_bold_italic() -> Font:
	# Montserrat has no bold-italic file, so synthesize both effects via
	# FontVariation: embolden thickens strokes; variation_transform skews
	# glyphs right to mimic italic (y_axis x-component shifts top of each
	# glyph rightward in screen space where Y increases downward).
	var fv := FontVariation.new()
	fv.base_font = _FLAVOR
	fv.variation_embolden = 0.8
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.2, 1.0), Vector2.ZERO)
	return fv


## Returns the Noto Sans Symbols 2 font for Unicode glyphs (★ ☆ ⚡ etc.).
## Uses a preloaded constant so the font is available before any scene code
## runs and can never be null. Falls back to a SystemFont only when running
## outside a normal project build (e.g. a stripped export with missing assets).
static func symbols() -> Font:
	return _SYMBOLS
