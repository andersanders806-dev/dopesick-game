extends Node3D
## Title screen. The real street is the backdrop -- City3D with the player
## and HUD taken out -- under a slow camera drifting past the storefronts,
## so the first thing you see is where you'll be spending your nights.

const MenuStyle := preload("res://ui/MenuStyle.gd")
const SettingsPanel := preload("res://ui/SettingsPanel.gd")
const START_SCENE := "res://world/Apartment3D.tscn"
const BACKDROP := "res://world/City3D.tscn"

## The drift: along the street at eye height, looking up at the signs.
const PATH_FROM := Vector3(-23.0, 1.8, 3.2)
const PATH_TO := Vector3(22.0, 1.8, 3.2)
const LOOK_OFFSET := Vector3(5.0, 0.6, -6.0)
const PATH_SECONDS := 70.0

var _camera: Camera3D
var _t: float = 0.0
var _ui: Control
var _main: Control
var _sub: Control

func _ready() -> void:
	GameState.run_active = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	_build_ui()

func _build_backdrop() -> void:
	var city: Node = load(BACKDROP).instantiate()
	for n in ["Player3D", "HUD"]:
		var c := city.get_node_or_null(n)
		if c:
			city.remove_child(c)
			c.free()
	add_child(city)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.far = 300.0
	add_child(_camera)
	_camera.make_current()
	var listener := AudioListener3D.new()
	_camera.add_child(listener)
	listener.make_current()
	_place_camera()

func _process(delta: float) -> void:
	_t += delta
	_place_camera()

func _place_camera() -> void:
	# Ping-pong along the block, eased so it never visibly turns around.
	var u := 0.5 - 0.5 * cos(_t / PATH_SECONDS * TAU)
	var pos := PATH_FROM.lerp(PATH_TO, u)
	pos.y += sin(_t * 0.7) * 0.04
	_camera.global_position = pos
	var dir := 1.0 if sin(_t / PATH_SECONDS * TAU) >= 0.0 else -1.0
	var look := pos + Vector3(LOOK_OFFSET.x * dir, LOOK_OFFSET.y, LOOK_OFFSET.z)
	var want := _camera.global_transform.looking_at(look, Vector3.UP)
	_camera.global_basis = _camera.global_basis.slerp(want.basis, 0.02) if _t > 0.1 else want.basis

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	MenuStyle.fill(_ui)
	_ui.theme = MenuStyle.theme()
	layer.add_child(_ui)

	# A dark wash from the left so the menu reads over the neon.
	var wash := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.01, 0.015, 0.94))
	grad.set_color(1, Color(0.01, 0.01, 0.015, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.65, 0.5)
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	MenuStyle.fill(wash)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(wash)

	var margin := MarginContainer.new()
	MenuStyle.fill(margin)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 50)
	_ui.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	_main = v

	var title := MenuStyle.label("DOPE SICK", 76, Color(0.92, 0.88, 0.8))
	title.add_theme_color_override("font_shadow_color", Color(0.75, 0.12, 0.1, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 3)
	v.add_child(title)
	v.add_child(MenuStyle.label("One more score. One more night. Whatever it takes.", 17, MenuStyle.TEXT_DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	v.add_child(gap)

	var can_continue := GameState.run_started and GameState.health > 0.0
	if can_continue:
		v.add_child(MenuStyle.button("Continue  —  Day %d" % GameState.day, _continue))
	v.add_child(MenuStyle.button("New run", _new_run))
	v.add_child(MenuStyle.button("Settings", _open_settings))
	v.add_child(MenuStyle.button("Controls", _open_controls))
	v.add_child(MenuStyle.button("Quit", func(): get_tree().quit()))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(MenuStyle.label("Know-How banked: %d" % MetaProgress.know_how, 14, MenuStyle.BRASS))
	v.add_child(MenuStyle.label("Steal to order. Score from the pusher. Don't get picked up -- and if it comes to it, shoot your way out.",
		13, MenuStyle.TEXT_DIM))
	# Keyboard/gamepad users land on the first button.
	for c in v.get_children():
		if c is Button:
			c.call_deferred("grab_focus")
			break

func _continue() -> void:
	GameState.run_active = true
	get_tree().change_scene_to_file(START_SCENE)

func _new_run() -> void:
	GameState.start_run()
	GameState.run_active = true
	get_tree().change_scene_to_file(START_SCENE)

func _open_settings() -> void:
	var s := SettingsPanel.new()
	s.closed.connect(_close_sub)
	_show_sub(s)

func _open_controls() -> void:
	_show_sub(MenuStyle.controls_panel(_close_sub))

func _show_sub(panel: Control) -> void:
	_main.visible = false
	var center := CenterContainer.new()
	MenuStyle.fill(center)
	center.add_child(panel)
	_ui.add_child(center)
	_sub = panel

func _close_sub() -> void:
	if _sub and is_instance_valid(_sub):
		_sub.get_parent().queue_free()
	_sub = null
	_main.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _sub != null:
		get_viewport().set_input_as_handled()
		_close_sub()
