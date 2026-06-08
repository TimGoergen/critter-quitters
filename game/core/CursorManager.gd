extends CanvasLayer

## Hides the OS cursor on PC builds and replaces it with a custom
## pointing-hand cursor loaded from assets/cursor_hand.svg.
## Lives in an autoload so it persists across every scene change.

# Pixel position of the click point (index-finger tip) within the SVG.
# Update this if the finger tip moves in cursor_hand.svg.
const _HOTSPOT := Vector2(13, 1)

var _cursor_rect: TextureRect

func _ready() -> void:
	if not OS.has_feature("pc"):
		return
	layer = 200   # render above every scene's CanvasLayer
	process_mode = PROCESS_MODE_ALWAYS   # keep updating while the game is paused
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_HIDDEN)
	var tex: Texture2D = load("res://assets/cursor_hand.svg")
	_cursor_rect = TextureRect.new()
	_cursor_rect.texture        = tex
	_cursor_rect.stretch_mode   = TextureRect.STRETCH_KEEP
	_cursor_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		_cursor_rect.size = tex.get_size()
	add_child(_cursor_rect)

	# Show/hide the custom cursor as the mouse enters and leaves the window.
	# When the cursor exits, restore the OS cursor so the user isn't left with nothing.
	get_viewport().mouse_entered.connect(_on_window_mouse_entered)
	get_viewport().mouse_exited.connect(_on_window_mouse_exited)


func _on_window_mouse_entered() -> void:
	_cursor_rect.visible = true
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_HIDDEN)


func _on_window_mouse_exited() -> void:
	_cursor_rect.visible = false
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if _cursor_rect == null:
		return
	_cursor_rect.position = get_viewport().get_mouse_position() - _HOTSPOT
