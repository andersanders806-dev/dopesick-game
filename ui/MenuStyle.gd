extends RefCounted
## The look shared by the main menu, pause menu and settings: near-black
## panels with the HUD's tarnished-brass trim, and buttons that light up
## amber under the cursor. Built as a Theme in code so every menu stays in
## step without a .tres to keep in sync.

const BRASS := Color(0.8, 0.68, 0.33)
const BRASS_DIM := Color(0.55, 0.45, 0.2, 0.8)
const TEXT := Color(0.86, 0.83, 0.78)
const TEXT_DIM := Color(0.55, 0.53, 0.5)
const BLOOD := Color(0.78, 0.16, 0.14)
const PANEL_BG := Color(0.035, 0.035, 0.045, 0.9)

const CONTROLS := [
	["Move", "W A S D"],
	["Look", "Mouse"],
	["Fire", "Left mouse"],
	["Aim down sights", "Right mouse"],
	["Reload", "R"],
	["Fire mode (auto / semi)", "B"],
	["Sprint", "Shift"],
	["Crouch", "C / Ctrl"],
	["Jump", "Space"],
	["Interact / talk / steal", "E"],
	["Flashlight", "F"],
	["Pause", "Esc / P"],
]

static func _box(bg: Color, border: Color, border_w := 1, radius := 4, margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin * 1.6
	s.content_margin_right = margin * 1.6
	s.content_margin_top = margin * 0.8
	s.content_margin_bottom = margin * 0.8
	return s

static func theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(Color(0.06, 0.06, 0.07, 0.85), Color(0.3, 0.26, 0.15, 0.6)))
	t.set_stylebox("hover", "Button", _box(Color(0.16, 0.12, 0.05, 0.95), BRASS))
	t.set_stylebox("pressed", "Button", _box(Color(0.3, 0.2, 0.06, 1.0), BRASS))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BRASS, 1))
	t.set_stylebox("disabled", "Button", _box(Color(0.04, 0.04, 0.05, 0.6), Color(0.2, 0.2, 0.2, 0.4)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", BRASS)
	t.set_color("font_pressed_color", "Button", Color(1, 0.9, 0.6))
	t.set_color("font_focus_color", "Button", BRASS)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.4))
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", BRASS)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, BRASS_DIM, 1, 6, 14.0))
	var grabber := _box(BRASS, BRASS, 0, 3, 0.0)
	t.set_stylebox("slider", "HSlider", _box(Color(0.15, 0.15, 0.16), Color(0.3, 0.26, 0.15), 1, 3, 2.0))
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	return t

static func label(text: String, size := 16, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, on_press: Callable, min_w := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		SFX.play("blip", -8.0, 1.1)
		on_press.call())
	b.mouse_entered.connect(func(): SFX.play("blip", -20.0, 1.8))
	return b

static func fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

## Key bindings, two columns, with a Back button.
static func controls_panel(on_back: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(label("CONTROLS", 24, BRASS))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	for row in CONTROLS:
		grid.add_child(label(row[0], 15, TEXT_DIM))
		grid.add_child(label(row[1], 15, TEXT))
	v.add_child(grid)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(button("Back", on_back, 160))
	return panel
