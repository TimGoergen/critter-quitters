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


static func _load(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return SystemFont.new()   # fallback — renders with the OS default
