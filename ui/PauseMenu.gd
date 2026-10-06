extends CanvasLayer
## Esc during play: the game stops (the walkman keeps playing -- it's in
## your ears, not the world) and you can resume, change settings, or save
## and go back to the title. Opened by the HUD when nothing else is using
## Esc.

const SettingsMenu := preload("res://ui/SettingsMenu.gd")
const TITLE_SCENE := "res://ui/TitleScreen.tscn"

var _was_paused: bool = false
var _panel: Control

func open() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.55))
	col.add_child(title)
	var info := Label.new()
	info.text = "Day %d  -  %s  -  $%d" % [GameState.day, GameState.clock_text(), GameState.cash]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.6, 0.58, 0.54))
	col.add_child(info)
	var resume := _button(col, "Resume", _close)
	_button(col, "Notebook  (%s)" % GameState.control_name("notebook"), _open_notebook)
	_button(col, "Settings", _open_settings)
	var quit_label := "Save and quit to title" if not (GameState.wanted or GameState.in_custody) else "Quit to title (can't save while wanted)"
	_button(col, quit_label, _quit_to_title)
	resume.grab_focus.call_deferred()

func _button(col: VBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(action)
	col.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("cancel_ui") or event.is_action_pressed("pause")) and _panel.visible:
		get_viewport().set_input_as_handled()
		_close()

func _open_notebook() -> void:
	_panel.visible = false
	var book = load("res://ui/Notebook.gd").new()
	get_tree().root.add_child(book)
	book.open()
	# The notebook unpauses to whatever it found -- paused, under us.
	book.tree_exited.connect(func(): if is_instance_valid(_panel): _panel.visible = true)

func _open_settings() -> void:
	_panel.visible = false
	var s := SettingsMenu.new()
	get_tree().root.add_child(s)
	s.open()
	s.closed.connect(func(): _panel.visible = true)

func _quit_to_title() -> void:
	# The save is whatever the last room you walked into wrote; refresh it
	# so Continue puts you right here.
	SaveGame.save()
	Walkman.stop()
	get_tree().paused = false
	queue_free()
	get_tree().change_scene_to_file(TITLE_SCENE)

func _close() -> void:
	get_tree().paused = _was_paused
	queue_free()
