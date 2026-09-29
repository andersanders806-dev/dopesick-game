extends CanvasLayer
## A small "what do you do?" panel: a speaker, a line of text, and a few
## buttons. For conversations that need a decision rather than just a line
## -- giving the man by the alley a couple of dollars, what to pawn. Built in
## code like ui/DrugMenu.gd, and parented to the tree root for the same
## reason (a scene change mustn't take it down mid-choice).

signal chosen(index: int)
signal cancelled

var _hud: CanvasLayer

## `options` are button labels; `disabled` holds the indices to grey out
## (shown, so you can see what you'd need, but not pickable).
func open(speaker: String, text: String, options: Array, disabled: Array = [], portrait: Texture2D = null) -> void:
	layer = 90
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.82)
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
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	if portrait:
		var pic := TextureRect.new()
		pic.texture = portrait
		pic.custom_minimum_size = Vector2(110, 110)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	if speaker != "":
		col.add_child(_label(speaker, 17, Color(0.9, 0.8, 0.55)))
	Voice.say(speaker, text)
	var body := _label(text, 14, Color(0.84, 0.82, 0.78))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	var first: Button = null
	# Long lists (the tape shoebox) scroll instead of running off screen.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if options.size() > 8:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 380)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(list)
		col.add_child(scroll)
	else:
		col.add_child(list)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.custom_minimum_size = Vector2(0, 32)
		b.disabled = disabled.has(i)
		b.pressed.connect(_on_pick.bind(i))
		list.add_child(b)
		if first == null and not b.disabled:
			first = b
	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(0, 32)
	leave.pressed.connect(_on_cancel)
	col.add_child(leave)
	(first if first else leave).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		_on_cancel()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _close() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

func _on_pick(index: int) -> void:
	Voice.stop()
	chosen.emit(index)
	_close()

func _on_cancel() -> void:
	cancelled.emit()
	_close()
