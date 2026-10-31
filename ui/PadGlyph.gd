extends Control
## One PlayStation button, drawn: the face buttons as a dark disc with their symbol in the DualSense's
## colour (blue cross, red circle, pink square, green triangle), the shoulder and trigger buttons as a
## rounded plate with their name, the sticks as a disc with L3 / R3, Options and the D-pad as their
## shapes. Drawn, not typed, because the symbols are not in the game's fonts. `button` is the name
## ("Cross", "Square", "R2", "DpadDown" ...); `size_px` the height.

const FACE := {
	"Cross": Color(0.45, 0.62, 1.0), "Circle": Color(1.0, 0.36, 0.36),
	"Square": Color(0.98, 0.55, 0.85), "Triangle": Color(0.35, 0.88, 0.62),
}
const DISC := Color(0.08, 0.08, 0.1, 0.92)
const RIM := Color(0.85, 0.85, 0.9, 0.9)
const PLATE_TEXT := {"L1": "L1", "R1": "R1", "L2": "L2", "R2": "R2", "L3": "L3", "R3": "R3",
	"Options": "OPT", "Touchpad": "PAD", "LStick": "L", "RStick": "R"}

var button := "Cross": set = set_button
var size_px := 26.0: set = set_size_px

static func make(name_: String, px := 26.0) -> Control:
	var g: Control = (load("res://ui/PadGlyph.gd") as GDScript).new()
	g.button = name_
	g.size_px = px
	return g

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()

func set_button(v: String) -> void:
	button = v
	_fit()
	queue_redraw()

func set_size_px(v: float) -> void:
	size_px = v
	_fit()
	queue_redraw()

## Width a button takes at this height.
static func width_for(name_: String, px: float) -> float:
	return px * (1.7 if name_ in ["L2", "R2", "L1", "R1", "Options", "Touchpad"] else 1.0)

func _fit() -> void:
	custom_minimum_size = Vector2(width_for(button, size_px), size_px)
	size = custom_minimum_size

func _draw() -> void:
	var h := size_px
	var w := width_for(button, h)
	var c := Vector2(w, h) * 0.5
	var r := h * 0.5 - 1.0
	if FACE.has(button):
		draw_circle(c, r, DISC)
		draw_arc(c, r, 0.0, TAU, 28, FACE[button], 1.5, true)
		_symbol(c, h * 0.2, FACE[button])
	elif button.begins_with("Dpad"):
		_dpad(c, h)
	elif button in ["LStick", "RStick", "L3", "R3"]:
		draw_circle(c, r, DISC)
		draw_arc(c, r, 0.0, TAU, 28, RIM, 1.5, true)
		_text(c, button.substr(0, 1) + ("3" if button.ends_with("3") else ""), h * 0.5)
	else:
		var plate := StyleBoxFlat.new()
		plate.bg_color = DISC
		plate.border_color = RIM
		plate.set_border_width_all(1)
		plate.set_corner_radius_all(int(h * 0.3))
		draw_style_box(plate, Rect2(Vector2(0, 1), Vector2(w, h - 2)))
		_text(c, PLATE_TEXT.get(button, button), h * 0.42)

func _symbol(c: Vector2, s: float, col: Color) -> void:
	var wd := 2.0
	match button:
		"Cross":
			draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, wd, true)
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, wd, true)
		"Circle":
			draw_arc(c, s * 1.15, 0.0, TAU, 24, col, wd, true)
		"Square":
			draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), col, false, wd)
		"Triangle":
			var pts := PackedVector2Array([c + Vector2(0, -s * 1.15), c + Vector2(s * 1.1, s * 0.85), c + Vector2(-s * 1.1, s * 0.85), c + Vector2(0, -s * 1.15)])
			draw_polyline(pts, col, wd, true)

func _dpad(c: Vector2, h: float) -> void:
	var a := h * 0.16
	var arm := h * 0.46
	draw_rect(Rect2(c - Vector2(arm, a), Vector2(arm * 2.0, a * 2.0)), RIM)
	draw_rect(Rect2(c - Vector2(a, arm), Vector2(a * 2.0, arm * 2.0)), RIM)
	var dir := Vector2.DOWN
	match button:
		"DpadUp": dir = Vector2.UP
		"DpadLeft": dir = Vector2.LEFT
		"DpadRight": dir = Vector2.RIGHT
	draw_circle(c + dir * arm * 0.68, a * 0.9, Color(1, 1, 1))

func _text(c: Vector2, t: String, px: float) -> void:
	var font := ThemeDB.fallback_font
	var s := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px))
	draw_string(font, Vector2(c.x - s.x * 0.5, c.y + px * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), Color(1, 1, 1))
