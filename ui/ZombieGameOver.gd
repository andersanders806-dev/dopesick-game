extends CanvasLayer
## Dead Block's end: round reached, kills, headshots, time and the best.
## Built in code, on the tree root (it outlives a scene change); the
## tree is paused behind it. "Again" starts another run in the same view,
## "Title" leaves the mode.

const BLOOD := Color(0.72, 0.08, 0.08)
const PAPER := Color(0.93, 0.9, 0.82)
const PadFocus := preload("res://ui/PadFocus.gd")
const GlyphLabelScript := preload("res://ui/GlyphLabel.gd")

var again_button: Button
var title_button: Button
var stats_label: Label

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110

func show_summary(s: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/Bungee-Regular.ttf")
	font.spacing_glyph = 6
	var cause := String(s.get("cause", ""))
	var title := _label(cause.to_upper() if cause != "" else "YOU WERE OVERRUN", 52 if cause == "" else 40, BLOOD)
	title.add_theme_font_override("font", font)
	col.add_child(title)
	var best_line := "Best: round %d" % int(s["best_round"])
	if s.get("new_best", false):
		best_line = "A new best."
	stats_label = _label("Round %d\n%d kills, %d headshots\nSurvived %s\n%s" % [
		int(s["round"]), int(s["kills"]), int(s["headshots"]), format_time(float(s["time"])), best_line], 24, PAPER)
	col.add_child(stats_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	again_button = _button("Again", func():
		_close()
		ZombieMode.restart())
	col.add_child(again_button)
	title_button = _button("Title", func():
		_close()
		ZombieMode.leave()
		get_tree().change_scene_to_file(ZombieMode.TITLE_SCENE))
	col.add_child(title_button)
	var hint := GlyphLabelScript.new()
	hint.name = "PadHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	col.add_child(hint)
	hint.markup = "{accept} Choose"
	PadFocus.dress(col)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	again_button.grab_focus.call_deferred()

static func format_time(seconds: float) -> String:
	var t := int(seconds)
	return "%d:%02d" % [t / 60, t % 60]

func _close() -> void:
	get_tree().paused = false
	queue_free()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	return b
