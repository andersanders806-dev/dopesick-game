extends RefCounted
## A focus you can see from the couch: Godot's default focus box is a hair-thin pale line, which
## vanishes on a dark menu. dress() gives every button, check box, drop-down and slider under a menu a
## bold amber frame (and a warmer fill) for the focused one, so the pad's D-pad / left stick always shows
## where it is.

const AMBER := Color(1.0, 0.8, 0.3)
const UiStyle := preload("res://ui/UiStyle.gd")

## The focus frame: a clear fill with a 3 px amber border.
static func frame() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = Color(1.0, 0.8, 0.3, 0.16)
	f.border_color = AMBER
	f.set_border_width_all(3)
	f.set_corner_radius_all(4)
	f.set_expand_margin_all(1)
	return f

## Every focusable control under `root`, now.
static func dress(root: Node) -> void:
	if root is BaseButton or root is Slider or root is OptionButton:
		var c := root as Control
		# (a title-style menu item brings its own focus: the amber bar and the underline)
		if not c.has_theme_stylebox_override("focus"):
			c.add_theme_stylebox_override("focus", frame())
		c.focus_mode = Control.FOCUS_ALL
		UiStyle.wire(c)
	for c in root.get_children():
		dress(c)

## Whether `c` has a visible focus frame (the tests).
static func dressed(c: Control) -> bool:
	return c.has_theme_stylebox_override("focus")
