extends Node
## Graphics quality presets and the colour grade.
##
## The rooms are built (dev-tools/build_rooms_3d.gd) with the full-fat look:
## SSIL, SSR, volumetric fog, TAA, far DOF, shadows on every lamp. That's
## the "High" preset. On an integrated GPU it runs at 12-16 FPS, so "Medium"
## and "Low" strip the expensive passes and fake the important parts
## cheaply -- depth fog stands in for volumetric fog, FXAA for TAA -- and
## this node applies the choice to every WorldEnvironment and light as rooms
## load. F3 cycles the preset, F4 shows the frame rate; both are remembered
## in user://settings.cfg.
##
## Every preset renders 3D below native and upscales with AMD FSR: FSR 1
## (spatial, nearly free, with FXAA) on Low and Medium, FSR 2 on High, where
## it also does the anti-aliasing in place of TAA and MSAA and keeps edges
## and texture detail sharp. FSR 2's own pass costs ~8 ms on a UHD 620, so
## it only pays off where the effects are expensive anyway. The render scale
## floats: it drops when frames run long and creeps back up when there's
## headroom, inside each preset's range, so the game holds a steady frame
## rate instead of stuttering -- High on a UHD 620 used to run 15 FPS.
##
## The colour grade (a 3D LUT built here, plus saturation and contrast)
## applies at every preset: cool teal shadows, warm highlights, and colour
## pushed back up, so neon and sodium light actually read as colour.

enum Preset { LOW, MEDIUM, HIGH }
const PRESET_NAMES := ["Low", "Medium", "High"]
const SETTINGS_PATH := "user://settings.cfg"
const LUT_SIZE := 32

## Grade, applied at every preset.
const SATURATION := 1.18
const CONTRAST := 1.14
const SHADOW_TINT := Color(-0.03, 0.035, 0.07)
const HIGHLIGHT_TINT := Color(0.07, 0.025, -0.045)

## [min, max] 3D render scale per preset, and where each starts.
const SCALE_RANGE := [[0.6, 0.85], [0.67, 1.0], [0.5, 0.77]]
const SCALE_START := [0.77, 0.85, 0.59]
const TARGET_FPS := 58.0

## Volume sliders in the settings menu, 0..1 per bus. They scale each bus
## from the level SFX set it up at, so the mix (voices up, ambience down,
## the walkman ducking) survives any slider position.
const VOLUME_BUSES := ["Master", "Music", "SFX", "Voice", "Walkman"]

var preset: int = Preset.MEDIUM
var show_fps: bool = false
var fullscreen: bool = false
var volumes := {"Master": 1.0, "Music": 1.0, "SFX": 1.0, "Voice": 1.0, "Walkman": 1.0}
var _bus_base_db := {}
var render_scale: float = 0.77
var _frame_acc: float = 0.0
var _frame_count: int = 0
var _lut: ImageTexture3D
var _overlay: CanvasLayer
var _fps_label: Label
var _toast: Label
var _toast_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lut = _build_lut()
	_load_settings()
	for bus in VOLUME_BUSES:
		var i := AudioServer.get_bus_index(bus)
		_bus_base_db[bus] = AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0
		_apply_volume(bus)
	_apply_fullscreen()
	_build_overlay()
	get_tree().node_added.connect(_on_node_added)
	_apply_viewport()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			set_preset((preset + 1) % PRESET_NAMES.size())
			_show_toast("Graphics: %s" % PRESET_NAMES[preset])
		elif event.physical_keycode == KEY_F4:
			show_fps = not show_fps
			_fps_label.visible = show_fps
			_save_settings()

func _process(delta: float) -> void:
	_adapt_resolution(delta)
	if show_fps:
		_fps_label.text = "%d FPS  (%s, %d%%)" % [Engine.get_frames_per_second(), PRESET_NAMES[preset], roundi(render_scale * 100.0)]
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)

func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_save_settings()

func _apply_volume(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v: float = volumes.get(bus, 1.0)
	AudioServer.set_bus_mute(i, v <= 0.01)
	AudioServer.set_bus_volume_db(i, _bus_base_db.get(bus, 0.0) + linear_to_db(maxf(v, 0.01)))

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	_save_settings()

func set_show_fps(on: bool) -> void:
	show_fps = on
	if _fps_label:
		_fps_label.visible = on
	_save_settings()

func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func set_preset(p: int) -> void:
	preset = p
	_save_settings()
	_apply_viewport()
	var scene := get_tree().current_scene
	if scene:
		for we in scene.find_children("*", "WorldEnvironment", true, false):
			_apply_env(we)
		for light in scene.find_children("*", "Light3D", true, false):
			_apply_light(light)

func _on_node_added(node: Node) -> void:
	# Deferred so a room's own _ready (City3D duplicates its Environment)
	# has run first.
	if node is WorldEnvironment:
		_apply_env.call_deferred(node)
	elif node is Light3D:
		_apply_light.call_deferred(node)

## Half-second averages: a slow frame rate lowers the render scale a step,
## a comfortable one raises it again, slower, so it doesn't pump.
func _adapt_resolution(delta: float) -> void:
	_frame_acc += delta
	_frame_count += 1
	if _frame_acc < 0.5:
		return
	var fps := _frame_count / _frame_acc
	_frame_acc = 0.0
	_frame_count = 0
	var r: Array = SCALE_RANGE[preset]
	var next := render_scale
	if fps < TARGET_FPS - 8.0:
		next -= 0.05
	elif fps >= TARGET_FPS:
		next += 0.02
	next = clampf(next, r[0], r[1])
	if not is_equal_approx(next, render_scale):
		render_scale = next
		get_viewport().scaling_3d_scale = render_scale

func _apply_viewport() -> void:
	var vp := get_viewport()
	var high := preset == Preset.HIGH
	# FSR 2 is temporal: it anti-aliases and reconstructs detail itself.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if high else Viewport.SCALING_3D_MODE_FSR
	vp.fsr_sharpness = 0.25 if high else 0.35
	vp.use_taa = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if high else Viewport.SCREEN_SPACE_AA_FXAA
	for n in get_tree().get_nodes_in_group("film_look"):
		n.visible = high
	render_scale = SCALE_START[preset]
	vp.scaling_3d_scale = render_scale
	# Cheaper versions of the expensive passes; at a sub-native render scale
	# the difference doesn't show.
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else (RenderingServer.SHADOW_QUALITY_SOFT_LOW if preset == Preset.MEDIUM else RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)

func _apply_env(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var env := we.environment
	# Remember what the room was built with, so High can put it back.
	if not env.has_meta("built"):
		env.set_meta("built", {
			"ssil": env.ssil_enabled, "ssr": env.ssr_enabled, "ssao": env.ssao_enabled,
			"vol": env.volumetric_fog_enabled, "fog": env.fog_enabled, "fog_density": env.fog_density,
			"fog_color": env.fog_light_color, "glow_levels": [env.get_glow_level(3), env.get_glow_level(4), env.get_glow_level(5), env.get_glow_level(6)],
		})
	# Per node, not per Environment: a room loaded twice shares its cached
	# Environment but gets a fresh WorldEnvironment.
	if not we.has_meta("built_camera_attributes"):
		we.set_meta("built_camera_attributes", we.camera_attributes)
	var built: Dictionary = env.get_meta("built")
	var high := preset == Preset.HIGH
	env.ssil_enabled = high and built["ssil"]
	env.ssr_enabled = high and built["ssr"]
	env.ssr_max_steps = 32
	env.volumetric_fog_enabled = high and built["vol"]
	env.ssao_enabled = preset != Preset.LOW and built["ssao"]
	# Without volumetric fog the rooms lose their haze entirely; plain depth
	# fog in the same murky colour brings most of it back for next to nothing.
	if high:
		env.fog_enabled = built["fog"]
		env.fog_density = built["fog_density"]
		env.fog_light_color = built["fog_color"]
	else:
		env.fog_enabled = true
		env.fog_density = maxf(built["fog_density"] if built["fog"] else 0.0, 0.012)
		if not built["fog"]:
			env.fog_light_color = Color(0.07, 0.07, 0.09)
		env.fog_sky_affect = 0.0
	# Wide glow levels are the expensive ones.
	for i in 4:
		env.set_glow_level(3 + i, built["glow_levels"][i] if preset != Preset.LOW else false)
	we.camera_attributes = we.get_meta("built_camera_attributes") if high else null
	# The grade, at every preset.
	env.adjustment_enabled = true
	env.adjustment_saturation = SATURATION
	env.adjustment_contrast = CONTRAST
	env.adjustment_color_correction = _lut

func _apply_light(light: Light3D) -> void:
	if not is_instance_valid(light) or light is DirectionalLight3D:
		return
	if not light.has_meta("built_shadow"):
		light.set_meta("built_shadow", light.shadow_enabled)
	# Low: no point-light shadows at all. Medium keeps them.
	light.shadow_enabled = light.get_meta("built_shadow") and preset != Preset.LOW

## A 32^3 colour lookup: saturation lifted, shadows pushed toward teal,
## highlights toward amber, a gentle S-curve for bite.
func _build_lut() -> ImageTexture3D:
	var images: Array[Image] = []
	for b in LUT_SIZE:
		var img := Image.create(LUT_SIZE, LUT_SIZE, false, Image.FORMAT_RGB8)
		for g in LUT_SIZE:
			for r in LUT_SIZE:
				var c := Color(r / float(LUT_SIZE - 1), g / float(LUT_SIZE - 1), b / float(LUT_SIZE - 1))
				img.set_pixel(r, g, _grade(c))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, images)
	return tex

func _grade(c: Color) -> Color:
	var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var shadow := pow(1.0 - lum, 2.0)
	var highlight := pow(lum, 2.0)
	var out := Color(
		c.r + SHADOW_TINT.r * shadow + HIGHLIGHT_TINT.r * highlight,
		c.g + SHADOW_TINT.g * shadow + HIGHLIGHT_TINT.g * highlight,
		c.b + SHADOW_TINT.b * shadow + HIGHLIGHT_TINT.b * highlight)
	# Gentle S-curve.
	for i in 3:
		var v := clampf(out[i], 0.0, 1.0)
		out[i] = lerpf(v, v * v * (3.0 - 2.0 * v), 0.35)
	return out

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_fps_label = Label.new()
	_fps_label.position = Vector2(1130, 690)
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.visible = show_fps
	_overlay.add_child(_fps_label)
	_toast = Label.new()
	_toast.position = Vector2(560, 90)
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_overlay.add_child(_toast)

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_timer = 2.0

func _load_settings() -> void:
	# First launch starts on Medium everywhere: adaptive resolution keeps it
	# smooth even on integrated graphics.
	var integrated := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	preset = Preset.MEDIUM
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		# Settings from before adaptive resolution (version 1) kept High on
		# integrated graphics at 15 FPS; start those over on Medium once.
		var saved := int(cfg.get_value("graphics", "preset", Preset.MEDIUM))
		if int(cfg.get_value("graphics", "version", 1)) >= 2 or not integrated:
			preset = saved
		show_fps = bool(cfg.get_value("graphics", "show_fps", false))
		fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
		for bus in VOLUME_BUSES:
			volumes[bus] = float(cfg.get_value("audio", bus, 1.0))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "version", 2)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.save(SETTINGS_PATH)
