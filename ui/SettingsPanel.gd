extends PanelContainer
## Options, shared by the main menu and the pause menu. Every change applies
## immediately and is saved when you leave the panel.

signal closed

const MenuStyle := preload("res://ui/MenuStyle.gd")

func _ready() -> void:
	custom_minimum_size = Vector2(540, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(MenuStyle.label("SETTINGS", 24, MenuStyle.BRASS))

	v.add_child(_slider("Mouse sensitivity", 0.2, 3.0, 0.05, Settings.mouse_sensitivity,
		func(x): Settings.mouse_sensitivity = x, func(x): return "%.2f" % x))
	v.add_child(_slider("Field of view", 60.0, 110.0, 1.0, Settings.fov,
		func(x): Settings.fov = x, func(x): return "%d°" % int(x)))
	v.add_child(_slider("Master volume", 0.0, 1.0, 0.01, Settings.master_volume,
		func(x):
			Settings.master_volume = x
			Settings.apply(), func(x): return "%d%%" % int(round(x * 100.0))))
	v.add_child(_check("Invert mouse Y", Settings.invert_y, func(on): Settings.invert_y = on))
	v.add_child(_check("Head bob", Settings.head_bob, func(on): Settings.head_bob = on))
	v.add_child(_check("Fullscreen", Settings.fullscreen, func(on):
		Settings.fullscreen = on
		Settings.apply()))
	v.add_child(_check("Show FPS", Settings.show_fps, func(on):
		Settings.show_fps = on
		Settings.apply()))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	v.add_child(MenuStyle.button("Back", _close, 160))

func _close() -> void:
	Settings.save_settings()
	closed.emit()

func _slider(title: String, lo: float, hi: float, step: float, value: float, on_change: Callable, fmt: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := MenuStyle.label(title, 16, MenuStyle.TEXT_DIM)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(200, 20)
	row.add_child(s)
	var readout := MenuStyle.label(fmt.call(value), 16, MenuStyle.TEXT)
	readout.custom_minimum_size = Vector2(60, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)
	s.value_changed.connect(func(x):
		on_change.call(x)
		readout.text = fmt.call(x))
	return row

func _check(title: String, value: bool, on_change: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = title
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(func(on): on_change.call(on))
	return c

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		_close()
