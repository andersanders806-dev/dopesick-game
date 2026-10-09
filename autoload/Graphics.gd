extends Node
## Graphics quality presets and the colour grade.
##
## The rooms are built (dev-tools/build_rooms_3d.gd) with the full-fat look:
## SSIL, SSR, volumetric fog, TAA, far DOF, shadows on every lamp. That's
## the "High" preset. On an integrated GPU it runs at 12-16 FPS, so "Medium"
## and "Low" strip the expensive passes and fake the important parts
## cheaply -- depth fog stands in for volumetric fog -- and
## this node applies the choice to every WorldEnvironment and light as rooms
## load. F3 cycles the preset, F4 shows the frame rate; both are remembered
## in user://settings.cfg.
##
## Every preset renders 3D below native and upscales with AMD FSR: FSR 1
## (spatial, nearly free) with SMAA on Low and Medium, plus TAA on High;
## FSR 2 on PS5, where it does the anti-aliasing itself. FSR 2's own pass
## costs ~8 ms on a UHD 620 and smears at low frame rates, so it's kept for
## the preset meant for a desktop GPU. The render scale
## floats: it drops when frames run long and creeps back up when there's
## headroom, inside each preset's range, so the game holds a steady frame
## rate instead of stuttering -- High on a UHD 620 used to run 15 FPS.
##
## "PS5" sits above High for a strong desktop GPU, aiming at what a current
## console version would look like: everything High has, at higher
## quality -- FSR 2 from a 75-100% base instead of FSR 1 from 67-85%, the softest
## shadow filtering and a bigger shadow atlas, full-quality bounce light and
## ambient occlusion, finer volumetric fog, longer reflection traces, and
## 16x anisotropic filtering -- still under the same 60 FPS governor, so it
## drops resolution before it drops frames.
##
## The colour grade (a 3D LUT built here, plus saturation and contrast)
## applies at every preset: cool teal shadows, warm highlights, and colour
## pushed back up, so neon and sodium light actually read as colour.

enum Preset { LOW, MEDIUM, HIGH, PS5 }
const PRESET_NAMES := ["Low", "Medium", "High", "PS5"]
const SETTINGS_PATH := "user://settings.cfg"
const LUT_SIZE := 32

## Grade, applied at every preset.
const SATURATION := 1.18
const CONTRAST := 1.14
const SHADOW_TINT := Color(-0.03, 0.035, 0.07)
const HIGHLIGHT_TINT := Color(0.07, 0.025, -0.045)

## [min, max] 3D render scale per preset, and where each starts.
const SCALE_RANGE := [[0.6, 0.85], [0.67, 1.0], [0.67, 0.85], [0.75, 1.0]]
const SCALE_START := [0.77, 0.85, 0.77, 0.85]
const TARGET_FPS := 58.0
## How many lamps (omni and spot lights) may cast shadows at once, per
## preset: the ones nearest you. Each shadowed omni light redraws the scene
## six times into its cube map; on a UHD 620 the City's six shadowed street
## lamps cost 12-15 ms a frame, most of them lighting street you can't see.
const SHADOW_BUDGET := [0, 2, 3, 99]
const SHADOW_BUDGET_INTERVAL := 0.25
var _shadow_budget_t: float = 0.0

## Volume sliders in the settings menu, 0..1 per bus. They scale each bus
## from the level SFX set it up at, so the mix (voices up, ambience down,
## the walkman ducking) survives any slider position.
const VOLUME_BUSES := ["Master", "Music", "SFX", "Voice", "Walkman"]

var preset: int = Preset.MEDIUM
var show_fps: bool = false
var fullscreen: bool = false
## Through your own eyes, or the camera up over the room. Asked on New run,
## and switchable from Settings.
var first_person: bool = false
signal view_changed(first_person: bool)
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
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_apply_viewport()
	if _migrated:
		_save_settings()
		_show_toast("Graphics set to Medium to run smoothly on this GPU. F3 to change.")
		_toast_timer = 6.0

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
	_update_mouse_mode()
	_adapt_resolution(delta)
	_shadow_budget_t -= delta
	if _shadow_budget_t <= 0.0:
		_shadow_budget_t = SHADOW_BUDGET_INTERVAL
		_apply_shadow_budget()
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

## In first person the mouse steers the view, so it's captured -- except
## when a menu, a conversation or a minigame needs a pointer.
func _update_mouse_mode() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var want: bool = first_person and player != null and player.has_method("wants_mouse_captured") and player.wants_mouse_captured()
	var mode := Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode and not DisplayServer.get_name() == "headless":
		Input.mouse_mode = mode

## Settings from older versions, on an integrated GPU: version 1 kept High
## at 15 FPS; version 2 let you stay on High or PS5, which a UHD 620 runs at
## 16-20 FPS in the City against Medium's 30-38. Each moves you to Medium
## once -- F3 puts it back, and that choice is kept.
const SETTINGS_VERSION := 3
var _migrated: bool = false

func migrate_preset(saved: int, version: int, integrated: bool) -> int:
	if integrated and version < SETTINGS_VERSION and saved >= Preset.HIGH:
		return Preset.MEDIUM
	return saved

func set_first_person(on: bool) -> void:
	if on == first_person:
		return
	first_person = on
	_save_settings()
	view_changed.emit(on)

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
	_shadow_budget_t = 0.0
	_save_settings()
	_apply_viewport()
	Facades.set_detail(not lean())
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
	_gpu_acc += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if _frame_acc < 0.5:
		return
	var fps := _frame_count / _frame_acc
	var gpu := _gpu_acc / _frame_count
	watch_high(fps, _frame_acc)
	_frame_acc = 0.0
	_frame_count = 0
	_gpu_acc = 0.0
	var next := next_scale(render_scale, fps, gpu)
	if not is_equal_approx(next, render_scale):
		render_scale = next
		get_viewport().scaling_3d_scale = render_scale

## Vsync caps the frame rate at 60, so the rate alone can't say whether
## there's room: it read 58 and sharpened, then dipped and blurred, never
## settling. The GPU's own frame time can: over 15.5 ms (no margin under
## 60 FPS's 16.7) comes down a step, under 12 goes up, slowly. Without a
## timing (0), the old frame-rate rule.
const GPU_HIGH_MS := 15.5
const GPU_LOW_MS := 12.0
var _gpu_acc := 0.0

func next_scale(current: float, fps: float, gpu_ms: float) -> float:
	var r: Array = SCALE_RANGE_LEAN if lean() else SCALE_RANGE[preset]
	var next := current
	if gpu_ms > 0.0:
		if gpu_ms > GPU_HIGH_MS:
			next -= 0.05
		elif gpu_ms < GPU_LOW_MS:
			next += 0.02
	elif fps < TARGET_FPS - 8.0:
		next -= 0.05
	elif fps >= TARGET_FPS:
		next += 0.02
	return clampf(next, r[0], r[1])

## High on laptop graphics runs 18-41 FPS; on a 60 Hz screen anything
## that can't hold ~45 judders when you walk. Five seconds of that and it
## drops to Medium (lean, below: ~60 FPS), once a session, and says so;
## F3 puts High back and it's left alone after that.
const STEP_DOWN_FPS := 45.0
const STEP_DOWN_TIME := 5.0
var _integrated := false
var _stepped_down := false
var _slow_time := 0.0

## Fed each half-second's average; true when it just stepped down.
func watch_high(fps: float, window: float) -> bool:
	if not _integrated or _stepped_down or not is_high() or get_tree().paused or SceneLoader.busy():
		_slow_time = 0.0
		return false
	_slow_time = _slow_time + window if fps < STEP_DOWN_FPS else 0.0
	if _slow_time < STEP_DOWN_TIME:
		return false
	_stepped_down = true
	_slow_time = 0.0
	set_preset(Preset.MEDIUM)
	_show_toast("Graphics: Medium -- High was running under %d FPS. F3 to switch back." % STEP_DOWN_FPS, 5.0)
	return true

## Medium (and Low) on laptop graphics: the profile that holds 60 FPS walking the
## street at night on a UHD 620 (16.7 ms, from 24.4). No ambient occlusion
## (-3.6 ms; from the street camera it's barely there), only the near glow
## levels (neon still blooms), flat-shaded facade bricks (-1.5 ms), one
## lamp shadow instead of two, a nearer sun shadow, FXAA for SMAA
## (-1.3 ms), the lightest soft-shadow filter (-1.1 ms), and resolution
## allowed down to 60%. Measured walking: street 53-56 FPS by night, ~50
## by day, the bar 58 (was ~40 on the street).
const SCALE_RANGE_LEAN := [0.6, 1.0]
var _shadow_filter: int = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
const Facades := preload("res://world/Facades.gd")

func lean() -> bool:
	return _integrated and preset <= Preset.MEDIUM

## High or above: the presets with the full-fat room effects.
func is_high() -> bool:
	return preset >= Preset.HIGH

func _apply_viewport() -> void:
	var vp := get_viewport()
	var high := is_high()
	var ps5 := preset == Preset.PS5
	# FSR 2 is temporal: it anti-aliases and reconstructs detail itself, but
	# only well from a decent base resolution at a decent frame rate. On a
	# UHD 620, High's FSR 2 from ~59% at 20-25 FPS left edges crawling;
	# FSR 1 from 77% with TAA and SMAA measured faster (38 ms vs 40 in the
	# Dive Bar) and smoother. So FSR 2 is the PS5 preset's, for desktop GPUs.
	# SMAA everywhere else: crisper than FXAA for about half a millisecond.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if ps5 else Viewport.SCALING_3D_MODE_FSR
	vp.fsr_sharpness = 0.25 if ps5 else 0.35
	vp.use_taa = high and not ps5
	vp.msaa_3d = Viewport.MSAA_DISABLED
	# The project's soft-shadow filter (medium) everywhere but lean.
	_shadow_filter = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if lean() else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	RenderingServer.positional_soft_shadow_filter_set_quality(_shadow_filter)
	RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_filter)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if ps5 else (Viewport.SCREEN_SPACE_AA_FXAA if lean() else Viewport.SCREEN_SPACE_AA_SMAA)
	for n in get_tree().get_nodes_in_group("film_look"):
		n.visible = high
	render_scale = SCALE_START[preset]
	vp.scaling_3d_scale = render_scale
	# Cheaper versions of the expensive passes; at a sub-native render scale
	# the difference doesn't show.
	if ps5:
		# Full resolution and quality for the screen-space passes.
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH, false, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, false, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
	else:
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.environment_glow_set_use_bicubic_upscale(ps5)
	vp.positional_shadow_atlas_size = 8192 if ps5 else 4096
	# How many pixels of error a mesh LOD may show before a finer one is
	# drawn. The street fronts and Poly Haven props model every brick and
	# bolt; from the camera ~11 m back a 4 px error doesn't show, and below
	# High it buys back most of what the real buildings cost.
	vp.mesh_lod_threshold = 1.0 if high else 4.0
	if "anisotropic_filtering_level" in vp:
		vp.set("anisotropic_filtering_level", Viewport.ANISOTROPY_16X if ps5 else Viewport.ANISOTROPY_4X)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_ULTRA if ps5 else (RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else (RenderingServer.SHADOW_QUALITY_SOFT_LOW if preset == Preset.MEDIUM else RenderingServer.SHADOW_QUALITY_HARD))
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
			"vol": env.volumetric_fog_enabled, "fog": env.fog_enabled, "fog_density": env.fog_density, "glow": env.glow_enabled,
			"fog_color": env.fog_light_color, "glow_levels": [env.get_glow_level(3), env.get_glow_level(4), env.get_glow_level(5), env.get_glow_level(6)],
		})
	# Per node, not per Environment: a room loaded twice shares its cached
	# Environment but gets a fresh WorldEnvironment.
	if not we.has_meta("built_camera_attributes"):
		we.set_meta("built_camera_attributes", we.camera_attributes)
	var built: Dictionary = env.get_meta("built")
	var high := is_high()
	env.ssil_enabled = high and built["ssil"]
	env.ssr_enabled = high and built["ssr"]
	env.ssr_max_steps = 64 if preset == Preset.PS5 else 32
	env.volumetric_fog_enabled = high and built["vol"]
	env.ssao_enabled = preset != Preset.LOW and built["ssao"] and not lean()
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
	# Wide glow levels are the expensive ones. On a UHD 620 the glow pass
	# itself is a fixed ~3.5 ms whatever the levels, so Low drops it.
	for i in 4:
		env.set_glow_level(3 + i, built["glow_levels"][i] if preset != Preset.LOW and not lean() else false)
	env.glow_enabled = built.get("glow", env.glow_enabled) and preset != Preset.LOW
	we.camera_attributes = we.get_meta("built_camera_attributes") if high else null
	# The grade, at every preset.
	env.adjustment_enabled = true
	env.adjustment_saturation = SATURATION
	env.adjustment_contrast = CONTRAST
	env.adjustment_color_correction = _lut

func _apply_light(light: Light3D) -> void:
	if not is_instance_valid(light):
		return
	if light is DirectionalLight3D:
		_apply_sun(light)
		return
	if not light.has_meta("built_shadow"):
		light.set_meta("built_shadow", light.shadow_enabled)
	# Low: no point-light shadows at all. The budget picks which of the
	# rest are on; until it runs, nothing new is.
	light.shadow_enabled = light.get_meta("built_shadow") and preset == Preset.PS5

## The sun (the City's "Moon" by day): four cascades out to 100 m cost
## 5.8 ms on a UHD 620 for a camera that sees ~30 m. Lean: two out to 35 m
## on a 2048 map (-2.7 ms).
func _apply_sun(sun: DirectionalLight3D) -> void:
	if not sun.has_meta("built_mode"):
		sun.set_meta("built_mode", sun.directional_shadow_mode)
		sun.set_meta("built_distance", sun.directional_shadow_max_distance)
	var lean_sun := lean()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if lean_sun else sun.get_meta("built_mode")
	sun.directional_shadow_max_distance = 35.0 if lean_sun else sun.get_meta("built_distance")
	RenderingServer.directional_shadow_atlas_set_size(2048 if lean_sun else 4096, true)

## The SHADOW_BUDGET lamps nearest the player get their shadows; the rest
## light without them.
func _apply_shadow_budget() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# The City's sky light is the moon by night and the sun by day. The
	# moon's shadow is faint and its pass costs ~3.5 ms on the street, so
	# below High it goes after dark.
	var sky := scene.get_node_or_null("Moon") as DirectionalLight3D
	if sky:
		if not sky.has_meta("built_shadow"):
			sky.set_meta("built_shadow", sky.shadow_enabled)
		var want: bool = sky.get_meta("built_shadow") and (is_high() or GameState.daylight() > 0.3)
		if sky.shadow_enabled != want:
			sky.shadow_enabled = want
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var lamps: Array = scene.find_children("*", "Light3D", true, false).filter(func(l): return not (l is DirectionalLight3D) and l.get_meta("built_shadow", false))
	if lamps.is_empty():
		return
	var budget: int = mini(1, SHADOW_BUDGET[preset]) if lean() else SHADOW_BUDGET[preset]
	if player and lamps.size() > budget:
		var at := player.global_position
		lamps.sort_custom(func(a, b): return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	# A lamp that's switched off doesn't use up a slot.
	var slots := budget
	for lamp in lamps:
		var on: bool = slots > 0 and lamp.is_visible_in_tree()
		if on:
			slots -= 1
		if lamp.shadow_enabled != on:
			lamp.shadow_enabled = on

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
	# Centred under the day's headline, wrapped: phone messages are a
	# sentence or two.
	_toast = Label.new()
	_toast.position = Vector2(290, 140)
	_toast.size = Vector2(700, 0)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_overlay.add_child(_toast)

func _show_toast(text: String, time := 2.0) -> void:
	_toast.text = text
	_toast_timer = time

func _load_settings() -> void:
	# First launch starts on Medium everywhere: adaptive resolution keeps it
	# smooth even on integrated graphics.
	var integrated := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	_integrated = integrated
	preset = Preset.MEDIUM
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		# Settings from before adaptive resolution (version 1) kept High on
		# integrated graphics at 15 FPS; start those over on Medium once.
		var saved := clampi(int(cfg.get_value("graphics", "preset", Preset.MEDIUM)), 0, PRESET_NAMES.size() - 1)
		var version := int(cfg.get_value("graphics", "version", 1))
		preset = migrate_preset(saved, version, integrated)
		if preset != saved:
			_migrated = true
		show_fps = bool(cfg.get_value("graphics", "show_fps", false))
		fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
		first_person = bool(cfg.get_value("controls", "first_person", false))
		for bus in VOLUME_BUSES:
			volumes[bus] = float(cfg.get_value("audio", bus, 1.0))

func _save_settings() -> void:
	if Engine.get_meta("sandbox", false):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "version", SETTINGS_VERSION)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("controls", "first_person", first_person)
	cfg.save(SETTINGS_PATH)
