extends CanvasLayer
## Esc during play. Freezes the tree (craving included -- GameState is
## paused along with everything else) and offers settings, controls, and
## the way out.

const MenuStyle := preload("res://ui/MenuStyle.gd")
const SettingsPanel := preload("res://ui/SettingsPanel.gd")
const MAIN_MENU := "res://ui/MainMenu.tscn"

var _root: Control
var _main: Control
var _sub: Control

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	MenuStyle.fill(_root)
	_root.theme = MenuStyle.theme()
	_root.visible = false
	add_child(_root)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	MenuStyle.fill(shade)
	_root.add_child(shade)

	var center := CenterContainer.new()
	MenuStyle.fill(center)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(MenuStyle.label("PAUSED", 32, MenuStyle.BRASS, HORIZONTAL_ALIGNMENT_CENTER))
	var stats := MenuStyle.label("", 14, MenuStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	stats.name = "Stats"
	v.add_child(stats)
	v.add_child(MenuStyle.button("Resume", close))
	v.add_child(MenuStyle.button("Settings", _open_settings))
	v.add_child(MenuStyle.button("Controls", _open_controls))
	v.add_child(MenuStyle.button("Quit to main menu", _quit_to_menu))
	v.add_child(MenuStyle.button("Quit game", func(): get_tree().quit()))
	center.add_child(panel)
	_main = panel

func is_open() -> bool:
	return _root.visible

func open() -> void:
	# Nothing to pause into while a run-end or drug menu is up, or when dead.
	if not get_tree().get_nodes_in_group("modal_ui").is_empty():
		return
	var stats := _main.find_child("Stats", true, false) as Label
	stats.text = "Day %d   ·   $%d   ·   %d kills" % [GameState.day, GameState.cash, GameState.kills]
	_root.visible = true
	_main.visible = true
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	_close_sub()
	_root.visible = false
	get_tree().paused = false

func _close_sub() -> void:
	if _sub and is_instance_valid(_sub):
		_sub.get_parent().queue_free()
	_sub = null
	_main.visible = true

func _show_sub(panel: Control) -> void:
	_main.visible = false
	var center := CenterContainer.new()
	MenuStyle.fill(center)
	center.add_child(panel)
	_root.add_child(center)
	_sub = panel

func _open_settings() -> void:
	var s := SettingsPanel.new()
	s.closed.connect(_close_sub)
	_show_sub(s)

func _open_controls() -> void:
	_show_sub(MenuStyle.controls_panel(_close_sub))

func _quit_to_menu() -> void:
	get_tree().paused = false
	GameState.run_active = false
	get_tree().change_scene_to_file(MAIN_MENU)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if not is_open():
		open()
	elif _sub == null:
		close()
	else:
		_close_sub()
