extends CanvasLayer
## Photo mode, F12 or from the pause menu: the world stops, the HUD goes,
## and a free camera floats off the player's -- a few metres of leash, a
## zoom, depth of field focused on whatever's in the middle of the frame,
## and a handful of looks. Space takes the picture, saved as a PNG to
## Pictures/Dope Sick (or user://photos when there's no Pictures folder).

## How far (m) the camera may float from where it started.
const LEASH := 6.0
const SPEED := 2.2
const FAST := 3.0
const LOOK := 0.0025
const FOV_RANGE := [20.0, 90.0]
const FILTERS := ["None", "Noir", "Faded film", "Cold night", "VHS"]
const FOLDER := "Dope Sick"

var cam: Camera3D
var filter: int = 0
var dof: bool = false
var last_saved: String = ""
var _game_cam: Camera3D
var _origin: Vector3
var _yaw: float
var _pitch: float
var _was_paused: bool
var _mouse_mode: Input.MouseMode
var _hidden: Array = []
var _look: ColorRect
var _help: Label
var _flash: ColorRect
var _shooting: bool = false

## Opens photo mode over the current room; false when there's nothing to
## photograph (no 3D camera -- the title, a menu-only scene).
static func open_over(tree: SceneTree) -> bool:
	if tree.root.get_node_or_null("PhotoMode") or SceneLoader.busy() or Cutscene.is_playing():
		return false
	var game_cam := tree.root.get_viewport().get_camera_3d()
	if game_cam == null or tree.current_scene == null or tree.get_first_node_in_group("player") == null:
		return false
	# Not over a screen of its own: the run's end, a menu, a minigame.
	for c in tree.root.get_children():
		if c is CanvasLayer and not ProjectSettings.has_setting("autoload/" + c.name):
			return false
	var pm = load("res://ui/PhotoMode.gd").new()
	tree.root.add_child(pm)
	pm._start(game_cam)
	return true

func _start(game_cam: Camera3D) -> void:
	name = "PhotoMode"
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game_cam = game_cam
	_was_paused = get_tree().paused
	get_tree().paused = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam = Camera3D.new()
	cam.name = "PhotoCamera"
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(cam)
	cam.global_transform = game_cam.global_transform
	cam.fov = game_cam.fov
	cam.near = game_cam.near
	cam.far = game_cam.far
	cam.cull_mask = game_cam.cull_mask
	cam.environment = game_cam.environment
	var attrs := CameraAttributesPractical.new()
	if game_cam.attributes is CameraAttributesPractical:
		attrs = game_cam.attributes.duplicate()
	cam.attributes = attrs
	cam.current = true
	_origin = cam.global_position
	var e := cam.global_basis.get_euler()
	_pitch = e.x
	_yaw = e.y
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	_hide_chrome(true)
	_build_ui()
	_apply_filter()
	SFX.play("blip", -8.0, 0.7)

func _build_ui() -> void:
	_look = ColorRect.new()
	_look.name = "Look"
	_look.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = LOOK_SHADER
	_look.material = mat
	add_child(_look)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	_help = Label.new()
	_help.name = "Help"
	_help.position = Vector2(24, 560)
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_help.add_theme_constant_override("outline_size", 5)
	add_child(_help)
	_update_help()

func _update_help() -> void:
	var lines := [
		"PHOTO MODE",
		"WASD move  ·  Q/E down/up  ·  Mouse look  ·  Shift faster",
		"Scroll zoom (%d°)  ·  F look: %s  ·  B depth of field: %s" % [roundi(cam.fov), FILTERS[filter], "on" if dof else "off"],
		"Space take photo  ·  H hide this  ·  Esc leave",
	]
	if last_saved != "":
		lines.append("Saved: " + last_saved)
	_help.text = "\n".join(lines)

func _input(event: InputEvent) -> void:
	if _shooting:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * LOOK * Graphics.look_sensitivity
		_pitch = clampf(_pitch - event.relative.y * LOOK * Graphics.look_sensitivity * (-1.0 if Graphics.invert_look else 1.0), -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(3.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			take_photo()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_F12:
				close()
			KEY_SPACE, KEY_ENTER:
				take_photo()
			KEY_F:
				set_filter((filter + 1) % FILTERS.size())
			KEY_B:
				set_dof(not dof)
			KEY_H:
				_help.visible = not _help.visible
			KEY_Z:
				zoom(-5.0)
			KEY_X:
				zoom(5.0)
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if cam == null:
		return
	cam.rotation = Vector3(_pitch, _yaw, 0.0)
	var dir := Vector3.ZERO
	dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	dir.z = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	dir.y = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if dir != Vector3.ZERO:
		var speed := SPEED * (FAST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var move := cam.global_basis * Vector3(dir.x, 0.0, dir.z) + Vector3.UP * dir.y
		var to := cam.global_position + move.limit_length(1.0) * speed * delta
		cam.global_position = _origin + (to - _origin).limit_length(LEASH)
	if dof:
		_focus()

func zoom(by: float) -> void:
	cam.fov = clampf(cam.fov + by, FOV_RANGE[0], FOV_RANGE[1])
	_update_help()

func set_filter(i: int) -> void:
	filter = i
	_apply_filter()
	_update_help()

func set_dof(on: bool) -> void:
	dof = on
	var a := cam.attributes as CameraAttributesPractical
	a.dof_blur_far_enabled = on
	a.dof_blur_near_enabled = on
	a.dof_blur_amount = 0.12
	if on:
		_focus()
	_update_help()

## Focus on whatever's in the middle of the frame.
func _focus() -> void:
	var from := cam.global_position
	var to := from - cam.global_basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var d := 8.0 if hit.is_empty() else from.distance_to(hit["position"])
	var a := cam.attributes as CameraAttributesPractical
	a.dof_blur_far_distance = d + maxf(1.5, d * 0.4)
	a.dof_blur_far_transition = maxf(2.0, d * 0.6)
	a.dof_blur_near_distance = maxf(0.1, d * 0.5)
	a.dof_blur_near_transition = maxf(0.2, d * 0.3)

func _apply_filter() -> void:
	(_look.material as ShaderMaterial).set_shader_parameter("mode", filter)
	_look.visible = filter != 0

func take_photo() -> void:
	if _shooting:
		return
	_shooting = true
	var help_was := _help.visible
	_help.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	last_saved = save_image(img)
	_help.visible = help_was
	SFX.play("blip", -2.0, 1.6)
	_flash.color.a = 0.85
	create_tween().tween_property(_flash, "color:a", 0.0, 0.35)
	_update_help()
	_shooting = false

## Saves into Pictures/Dope Sick, or user://photos when that isn't there.
## Returns the path written ("" if both failed).
static func save_image(img: Image) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var file := "dopesick_%s_%03d.png" % [stamp, randi() % 1000]
	var dirs := []
	# The XDG Pictures folder -- unless it's been pointed at home itself,
	# then Pictures or Billeder under home, if there.
	var home := OS.get_environment("HOME").trim_suffix("/")
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).trim_suffix("/")
	for d in [pics, home.path_join("Pictures"), home.path_join("Billeder")]:
		if d != "" and d != home and DirAccess.dir_exists_absolute(d):
			dirs.append(d.path_join(FOLDER))
			break
	dirs.append(ProjectSettings.globalize_path("user://photos"))
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(d)
		var path: String = d.path_join(file)
		if img.save_png(path) == OK:
			return path
	return ""

func close() -> void:
	_hide_chrome(false)
	if is_instance_valid(_game_cam):
		_game_cam.current = true
	if is_instance_valid(cam):
		cam.queue_free()
	Input.mouse_mode = _mouse_mode
	get_tree().paused = _was_paused
	queue_free()

## The HUD's words and panels go; its screen effects (withdrawal, film
## look) stay, they're part of the picture.
func _hide_chrome(on: bool) -> void:
	if on:
		_hidden.clear()
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			for c in hud.get_children():
				if c is Control and c.visible and c.name not in ["PostFX", "WithdrawalTint", "FilmLook"]:
					_hidden.append(c)
		var g := get_tree().root.get_node_or_null("Graphics")
		if g and g.get("_overlay") and g._overlay.visible:
			_hidden.append(g._overlay)
		for c in _hidden:
			c.visible = false
	else:
		for c in _hidden:
			if is_instance_valid(c):
				c.visible = true
		_hidden.clear()

const LOOK_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform int mode = 0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen, uv).rgb;
	float vig = smoothstep(0.85, 0.25, distance(uv, vec2(0.5)));
	if (mode == 1) {
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		l = smoothstep(0.04, 0.9, l);
		l += (hash(uv * 900.0) - 0.5) * 0.08;
		c = vec3(l) * mix(0.55, 1.0, vig);
	} else if (mode == 2) {
		c = mix(vec3(0.08, 0.06, 0.05), vec3(1.0, 0.95, 0.85), c);
		c = mix(c, vec3(dot(c, vec3(0.33))), 0.3) * vec3(1.06, 1.0, 0.88);
		c += (hash(uv * 700.0) - 0.5) * 0.05;
		c *= mix(0.7, 1.0, vig);
	} else if (mode == 3) {
		c = c * vec3(0.78, 0.92, 1.18);
		c = mix(c, vec3(dot(c, vec3(0.33))), 0.25);
		c *= mix(0.6, 1.0, vig);
	} else if (mode == 4) {
		float off = 0.003;
		c.r = texture(screen, uv + vec2(off, 0.0)).r;
		c.b = texture(screen, uv - vec2(off, 0.0)).b;
		c *= 0.88 + 0.12 * sin(uv.y * 900.0);
		c = mix(c, vec3(dot(c, vec3(0.33))), 0.2);
		c += (hash(uv * 500.0 + TIME) - 0.5) * 0.06;
		c *= mix(0.75, 1.0, vig);
	}
	COLOR = vec4(c, 1.0);
}
"""
