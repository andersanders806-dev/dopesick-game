extends Label
## A Label whose text can name a control as {action} ("Hold {interact}  Buy the SMG"): the key's name
## when the keyboard was last used, a drawn PlayStation button when the pad was (ui/Glyphs.gd), and it
## swaps live when the player switches device. `text` is what is shown as text (with spaces left where
## a glyph is drawn over it, so alignment, wrapping and the theme's font all stay the Label's); the
## words for the controls are in plain().

const Glyphs := preload("res://ui/Glyphs.gd")
const PadGlyph := preload("res://ui/PadGlyph.gd")

var markup := "": set = set_markup
## The glyphs drawn now (tests count them).
var glyphs: Array = []

func _ready() -> void:
	GameState.input_device_changed.connect(func(_pad: bool): _rebuild())
	resized.connect(_place)
	_rebuild()

func set_markup(m: String) -> void:
	if m == markup:
		return
	markup = m
	if is_inside_tree():
		_rebuild()
	else:
		text = m

## The markup with the controls' words in: "Hold Square  Buy the SMG".
func plain() -> String:
	return _resolve(markup, false)[0]

## [shown text, [[glyph name, char index in the shown text]]]: spaces for each glyph on the pad.
func _resolve(m: String, with_glyphs: bool) -> Array:
	var out := ""
	var marks: Array = []
	var pos := 0
	var space_w := _space_w()
	var px := _glyph_px()
	while pos < m.length():
		var a := m.find("{", pos)
		var b := m.find("}", a + 1) if a >= 0 else -1
		if a < 0 or b < 0:
			out += m.substr(pos)
			break
		out += m.substr(pos, a - pos)
		var action := m.substr(a + 1, b - a - 1)
		if with_glyphs and Glyphs.is_pad() and Glyphs.pad_glyph(action) != "":
			var g := Glyphs.pad_glyph(action)
			var n := int(ceil((PadGlyph.width_for(g, px) + 4.0) / space_w))
			marks.append([g, out.length(), n])
			out += " ".repeat(n)
		else:
			out += Glyphs.name_of(action)
		pos = b + 1
	return [out, marks]

func _rebuild() -> void:
	var r := _resolve(markup, true)
	text = r[0]
	for g in glyphs:
		if is_instance_valid(g):
			g.queue_free()
	glyphs.clear()
	for m in r[1]:
		var g := PadGlyph.make(m[0], _glyph_px())
		g.set_meta("at", m[1])
		g.set_meta("n", m[2])
		add_child(g)
		glyphs.append(g)
	_place()

func _font() -> Font:
	return get_theme_font("font")

func _fsize() -> int:
	return get_theme_font_size("font_size")

func _space_w() -> float:
	return maxf(_font().get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, _fsize()).x, 1.0)

func _glyph_px() -> float:
	return floorf(_fsize() * 1.2)

## Puts each glyph where its spaces are in the (single) line.
func _place() -> void:
	if glyphs.is_empty():
		return
	var font := _font()
	var fs := _fsize()
	var line_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var line_h := font.get_height(fs)
	# The text lives inside the label's own style box (a card's padding); the glyphs go by the same room.
	var box := get_theme_stylebox("normal")
	var ml := box.get_margin(SIDE_LEFT)
	var mr := box.get_margin(SIDE_RIGHT)
	var mt := box.get_margin(SIDE_TOP)
	var mb := box.get_margin(SIDE_BOTTOM)
	var x0 := ml
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER: x0 = ml + (size.x - ml - mr - line_w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT: x0 = size.x - mr - line_w
	var y0 := mt
	match vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER: y0 = mt + (size.y - mt - mb - line_h) * 0.5
		VERTICAL_ALIGNMENT_BOTTOM: y0 = size.y - mb - line_h
	for g in glyphs:
		if not is_instance_valid(g):
			continue
		var before := text.substr(0, int(g.get_meta("at")))
		var w := font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var span := font.get_string_size(" ".repeat(int(g.get_meta("n"))), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		g.position = Vector2(x0 + w + (span - g.size.x) * 0.5, y0 + (line_h - g.size.y) * 0.5)
