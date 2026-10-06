extends CanvasLayer
## Settings: graphics preset, fullscreen, frame counter, and a volume slider
## per mix bus. Everything applies as you change it and is remembered in
## user://settings.cfg by the Graphics autoload. Opened from the title
## screen and the pause menu; Esc or "Back" closes it.

signal closed

const PRESET_NOTES := [
	"Low: fastest. No point-light shadows, simpler effects.",
	"Medium: the default. Smooth on integrated graphics.",
	"High: volumetric fog, bounce light, reflections and the film look. Wants a real GPU.",
	"PS5: High at console quality -- sharper upscaling, ultra shadows, full-res bounce light and AO. Wants a strong GPU.",
]
const BUS_LABELS := {"Master": "Master", "Music": "Music", "SFX": "Effects", "Voice": "Voices", "Walkman": "Walkman"}

var _note: Label

func open() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_label("Settings", 22, Color(0.9, 0.8, 0.55)))
	col.add_child(_label("Graphics", 15, Color(0.75, 0.72, 0.65)))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in Graphics.PRESET_NAMES.size():
		var b := Button.new()
		b.text = Graphics.PRESET_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Graphics.preset == i
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(_on_preset.bind(i))
		presets.add_child(b)
	col.add_child(presets)
	_note = _label(PRESET_NOTES[Graphics.preset], 12, Color(0.6, 0.58, 0.54))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)
	col.add_child(_check("Fullscreen", Graphics.fullscreen, Graphics.set_fullscreen))
	col.add_child(_check("Show frame rate  (F4)", Graphics.show_fps, Graphics.set_show_fps))
	col.add_child(_check("First person view", Graphics.first_person, Graphics.set_first_person))

	col.add_child(_label("Sound", 15, Color(0.75, 0.72, 0.65)))
	for bus in Graphics.VOLUME_BUSES:
		var row := HBoxContainer.new()
		var name_label := _label(BUS_LABELS[bus], 14, Color(0.84, 0.82, 0.78))
		name_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Graphics.volumes[bus]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pct := _label("", 12, Color(0.6, 0.58, 0.54))
		pct.custom_minimum_size = Vector2(44, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.text = "%d%%" % roundi(slider.value * 100)
		slider.value_changed.connect(func(v: float):
			Graphics.set_volume(bus, v)
			pct.text = "%d%%" % roundi(v * 100)
			if bus != "Music" and bus != "Walkman":
				SFX.play("blip", -6.0))
		row.add_child(slider)
		row.add_child(pct)
		col.add_child(row)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 34)
	back.pressed.connect(_close)
	col.add_child(back)
	back.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		_close()

func _on_preset(i: int) -> void:
	Graphics.set_preset(i)
	_note.text = PRESET_NOTES[i]

func _check(text: String, on: bool, setter: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(func(v: bool): setter.call(v))
	return c

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _close() -> void:
	closed.emit()
	queue_free()
