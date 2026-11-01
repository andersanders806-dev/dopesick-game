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
const PadFocus := preload("res://ui/PadFocus.gd")
const GlyphLabelScript := preload("res://ui/GlyphLabel.gd")
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
	# Tall: it scrolls (and follows the pad's focus down it) when the window is short.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, clampf((get_viewport().get_visible_rect().size.y if get_viewport() != null else 720.0) - 150.0, 300.0, 700.0))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	outer.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

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
	col.add_child(_check("Fullscreen  (F11)", Graphics.fullscreen, Graphics.set_fullscreen))
	col.add_child(_check("Show frame rate  (F4)", Graphics.show_fps, Graphics.set_show_fps))
	var laptop := _check("Laptop mode  (cooler, lower resolution)", Graphics.laptop_mode, Graphics.set_laptop_mode)
	laptop.name = "LaptopMode"
	col.add_child(laptop)
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

	col.add_child(_label("Controls", 15, Color(0.75, 0.72, 0.65)))
	var srow := HBoxContainer.new()
	var sname := _label("Mouse speed", 14, Color(0.84, 0.82, 0.78))
	sname.custom_minimum_size = Vector2(110, 0)
	srow.add_child(sname)
	var sens := HSlider.new()
	sens.name = "LookSensitivity"
	sens.min_value = 0.3
	sens.max_value = 2.5
	sens.step = 0.05
	sens.value = Graphics.look_sensitivity
	sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sval := _label("%.2fx" % sens.value, 12, Color(0.6, 0.58, 0.54))
	sval.custom_minimum_size = Vector2(44, 0)
	sens.value_changed.connect(func(v: float):
		Graphics.set_look_sensitivity(v)
		sval.text = "%.2fx" % v)
	srow.add_child(sens)
	srow.add_child(sval)
	col.add_child(srow)
	var inv := _check("Invert look up/down", Graphics.invert_look, Graphics.set_invert_look)
	inv.name = "InvertLook"
	col.add_child(inv)
	var motion := _check("Camera motion (head bob, sprint zoom)", Graphics.camera_motion, Graphics.set_camera_motion)
	motion.name = "CameraMotion"
	col.add_child(motion)
	var calm := _check("Fade the HUD while walking", Graphics.immersive_hud, Graphics.set_immersive_hud)
	calm.name = "ImmersiveHud"
	col.add_child(calm)
	_controller_section(col)
	if GameState.mode == "zombies":
		for line in ["Fire  {fire}     Aim  {aim}     Reload / buy  {reload}     Swap gun  {swap_weapon}",
				"Knife  {melee}     Sprint  {sprint}     Crouch / slide  {crouch}     Pause  {pause}"]:
			var hint := GlyphLabelScript.new()
			hint.add_theme_font_size_override("font_size", 12)
			hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.54))
			col.add_child(hint)
			hint.markup = line
	else:
		var keys := _label("Move  WASD / left stick     Interact  E / Square     Sprint  Shift / L3\nNotebook  J / touchpad     Walkman  T / Triangle     Pause  Esc / Options", 12, Color(0.6, 0.58, 0.54))
		col.add_child(keys)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 34)
	back.pressed.connect(_close)
	outer.add_child(back)
	PadFocus.dress(panel)
	back.grab_focus.call_deferred()

## Settings > Controller: the right stick, the aim assist and the rumble. Every row is a slider or a
## button the pad can reach (left / right on a slider changes it), and all of it is remembered.
func _controller_section(col: VBoxContainer) -> void:
	col.add_child(_label("Controller", 15, Color(0.75, 0.72, 0.65)))
	_slider_row(col, "PadSensH", "Look speed, horizontal", 0.3, 2.5, 0.05, Graphics.pad_sens_h, Graphics.set_pad_sens_h, "%.2fx")
	_slider_row(col, "PadSensV", "Look speed, vertical", 0.3, 2.5, 0.05, Graphics.pad_sens_v, Graphics.set_pad_sens_v, "%.2fx")
	_slider_row(col, "PadAdsMult", "Aimed down sights", 0.3, 1.5, 0.05, Graphics.pad_ads_mult, Graphics.set_pad_ads_mult, "%.2fx")
	_slider_row(col, "PadDeadzone", "Stick deadzone", 0.02, 0.3, 0.01, Graphics.pad_deadzone, Graphics.set_pad_deadzone, "%.2f")
	var arow := HBoxContainer.new()
	arow.name = "AimAssistRow"
	arow.add_theme_constant_override("separation", 6)
	var aname := _label("Aim assist", 14, Color(0.84, 0.82, 0.78))
	aname.custom_minimum_size = Vector2(150, 0)
	arow.add_child(aname)
	var group := ButtonGroup.new()
	for i in Graphics.ASSIST_NAMES.size():
		var b := Button.new()
		b.name = "Assist" + Graphics.ASSIST_NAMES[i]
		b.text = Graphics.ASSIST_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Graphics.aim_assist == i
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(Graphics.set_aim_assist.bind(i))
		arow.add_child(b)
	col.add_child(arow)
	var note := _label("Standard slows the stick over a zombie, follows one that crosses your aim and pulls the sights onto one near the crosshair. Precision does the first two, lighter. Pad only, never the mouse.", 12, Color(0.6, 0.58, 0.54))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var rumble := _check("Rumble", Graphics.rumble, Graphics.set_rumble)
	rumble.name = "Rumble"
	col.add_child(rumble)
	var triggers := _check("Adaptive triggers (DualSense)", Graphics.ds_triggers, Graphics.set_ds_triggers)
	triggers.name = "AdaptiveTriggers"
	col.add_child(triggers)
	_slider_row(col, "TriggerStrength", "Trigger strength", 0.3, 1.0, 0.05, Graphics.ds_trigger_strength, Graphics.set_ds_trigger_strength, "%.2fx")
	var bar := _check("Lightbar effects (DualSense)", Graphics.ds_lightbar, Graphics.set_ds_lightbar)
	bar.name = "LightbarEffects"
	col.add_child(bar)

func _slider_row(col: VBoxContainer, node_name: String, text: String, lo: float, hi: float, step: float, value: float, setter: Callable, fmt: String) -> HSlider:
	var row := HBoxContainer.new()
	var name_label := _label(text, 14, Color(0.84, 0.82, 0.78))
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)
	var sl := HSlider.new()
	sl.name = node_name
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := _label(fmt % value, 12, Color(0.6, 0.58, 0.54))
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(v: float):
		setter.call(v)
		val.text = fmt % v)
	row.add_child(sl)
	row.add_child(val)
	col.add_child(row)
	return sl

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
