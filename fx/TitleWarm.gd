extends Node
## Compiles the game's own shaders behind the title screen, so the first door glass, the first wet street, the
## first sick screen or the first muzzle haze of a run is not a frame-long compile in the middle of play.
##
## Godot builds a pipeline the first time a material is drawn. This node keeps a small hidden SubViewport (set up
## like the main one: same MSAA and anti-aliasing, so the pipelines are the ones the street asks for) and puts
## each shader on a mesh in front of its camera, a couple a frame, then lets them go: every spatial shader the
## story, Dead Block, Ghetto Wars and the karts show (the door glass, the sky dome, shutter slats, the exit glow,
## the wet street, car paint and glass, the tarp, the cutaway walls, the ghetto set's haze and beams), a
## shadow-casting sun for the shadow pass, and the two screen shaders of the HUD's post effect (the sick grade is
## the full one; it used to compile on the first sick frame).
##
## It starts a moment after the title is up and takes about a second of idle menu; it is spread over frames and
## it is skipped without a window (headless has nothing to compile) and with Engine meta "no_prewarm".

const SPATIAL := [
	"res://interactables/glass.gdshader", "res://interactables/sky_dome.gdshader",
	"res://interactables/interior_map.gdshader", "res://interactables/exit_glow.gdshader",
	"res://world/shutter_slats.gdshader",
	"res://assets/shaders/wet_street.gdshader", "res://assets/shaders/car_paint.gdshader",
	"res://assets/shaders/car_glass.gdshader", "res://assets/shaders/tarp.gdshader",
	"res://assets/shaders/cutaway.gdshader", "res://assets/shaders/cutaway_double.gdshader",
	"res://assets/shaders/soft_dust.gdshader", "res://assets/shaders/rain_streak.gdshader",
	"res://assets/shaders/ghetto_marker.gdshader", "res://assets/shaders/ghetto_heat.gdshader",
	"res://assets/shaders/ghetto_beam.gdshader",
]
const CANVAS := ["res://assets/fx/postfx.gdshader", "res://assets/fx/postfx_lite.gdshader"]
## Shaders put on screen per frame, and how many frames each batch stays up (a pipeline compiles on the first).
const PER_FRAME := 2
const HOLD := 3
## Seconds after the title appears before it starts (the backdrop is fading in; nothing is competing for frames).
const DELAY := 1.2
## The guns' recorded sounds (weapons/GunSounds.gd): every gun the player can hold has its set and its foley
## (assets/sfx/guns/<set>/ and common/) read on worker threads while the shaders compile, a few files in flight
## at a time, then handed to GunSounds.warm() a gun a frame. GunSounds keeps them for the whole process, so the
## first shot, reload or tail of any gun in a run plays from memory instead of loading on the trigger frame.
const GUN_DIR := "res://weapons/"
const GUN_SFX := "res://assets/sfx/guns/"
const GunSounds := preload("res://weapons/GunSounds.gd")
const WD := preload("res://weapons/WeaponData.gd")
const SOUNDS_IN_FLIGHT := 4

static var started := false
## True once the last shader has been drawn (the title's opening card waits for it).
static var finished := false
## Seconds the whole warm-up took (the probe prints it), 0 until done.
static var took_ms := 0

var _delay := DELAY
var _vp: SubViewport
var _cam: Camera3D
var _live: Array = []
var _gun_paths: Array = []

static func skipped() -> bool:
	return Engine.has_meta("no_prewarm") or DisplayServer.get_name() == "headless"

## Whether the warm-up is still to come this process (the title then opens on its card).
static func pending() -> bool:
	return not started and not skipped()

## Called by the title screen; once per process. `delay`: seconds before the first shader (the card is already up
## when the title asks for 0.2; otherwise the menu fades in first).
static func start(host: Node, delay := DELAY) -> void:
	if started or skipped():
		return
	started = true
	var w := new()
	w.name = "TitleWarm"
	w._delay = delay
	host.get_tree().root.add_child.call_deferred(w)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _run() -> void:
	# The shader files load on worker threads while the title comes up (loading them in one frame cost 300 ms).
	for p in SPATIAL + CANVAS:
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
	_request_guns()
	await get_tree().create_timer(_delay, true, false, true).timeout
	var t0 := Time.get_ticks_msec()
	for p in SPATIAL + CANVAS:
		while ResourceLoader.exists(p) and ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
	await get_tree().process_frame
	# Built a piece a frame (the hidden viewport, its camera, the sun, the floor) and the materials as they are
	# shown, so no single frame of the title carries more than a piece of it.
	await _build()
	var paths: Array = []
	for p in SPATIAL:
		if ResourceLoader.exists(p):
			paths.append(p)
	var i := 0
	while i < paths.size():
		for k in PER_FRAME:
			if i < paths.size():
				var m := ShaderMaterial.new()
				m.shader = ResourceLoader.load_threaded_get(paths[i]) as Shader
				_show(m, i)
				i += 1
		await get_tree().process_frame
		_expire(false)
	# The sick grade and the plain one: full-screen canvas shaders over the hidden viewport.
	for p in CANVAS:
		if ResourceLoader.exists(p):
			var rect := ColorRect.new()
			rect.size = Vector2(_vp.size)
			var m := ShaderMaterial.new()
			m.shader = ResourceLoader.load_threaded_get(p) as Shader
			rect.material = m
			_vp.add_child(rect)
			_live.append([rect, HOLD])
			await get_tree().process_frame
			_expire(false)
	for k in HOLD + 1:
		await get_tree().process_frame
		_expire(false)
	_expire(true)
	await _warm_guns()
	took_ms = Time.get_ticks_msec() - t0
	finished = true
	queue_free()

## The guns' data, on worker threads (the sounds they name are read once it is in).
func _request_guns() -> void:
	for f in ResourceLoader.list_directory(GUN_DIR):
		var n := String(f).trim_suffix(".remap")
		if n.ends_with(".tres") and not _gun_paths.has(GUN_DIR + n):
			_gun_paths.append(GUN_DIR + n)
			ResourceLoader.load_threaded_request(GUN_DIR + n)

## Every file GunSounds.warm(d) loads for `d`: its recorded set, its foley, and the synthesised fallback of a gun
## with no set (the wonder weapon).
func _gun_files(d: WD) -> PackedStringArray:
	var out := PackedStringArray()
	if d.sound_set != "":
		var dir := GUN_SFX + d.sound_set + "/"
		for f in ResourceLoader.list_directory(dir):
			var n := String(f).trim_suffix(".import").trim_suffix(".remap")
			if n.ends_with(".wav"):
				out.append(dir + n)
	else:
		for v in ["a", "b"]:
			out.append(GUN_SFX + "fire_%s_%s.wav" % [d.handling_family(), v])
	out.append(GUN_SFX + "dry_click.wav")
	for cue in d.foley:
		for stem in d.foley[cue]:
			out.append(GUN_SFX + String(stem) + ".wav")
	return out

func _warm_guns() -> void:
	var guns: Array = []
	var files := PackedStringArray()
	for p in _gun_paths:
		while ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		var d := ResourceLoader.load_threaded_get(p) as WD
		if d == null or d.melee:
			continue
		guns.append(d)
		for f in _gun_files(d):
			if not files.has(f) and ResourceLoader.exists(f):
				files.append(f)
	# Read a few at a time and kept here until GunSounds has them (its load() then finds them in the cache).
	var hold: Array = []
	var flight: Array = []
	var i := 0
	while i < files.size() or not flight.is_empty():
		while i < files.size() and flight.size() < SOUNDS_IN_FLIGHT:
			if ResourceLoader.load_threaded_request(files[i]) == OK:
				flight.append(files[i])
			i += 1
		await get_tree().process_frame
		for f in flight.duplicate():
			if ResourceLoader.load_threaded_get_status(f) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var r := ResourceLoader.load_threaded_get(f)
				if r != null:
					hold.append(r)
				flight.erase(f)
	for d in guns:
		GunSounds.warm(d)
		await get_tree().process_frame
	hold.clear()

func _build() -> void:
	var main := get_tree().root
	_vp = SubViewport.new()
	_vp.size = Vector2i(192, 108)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = main.msaa_3d
	_vp.screen_space_aa = main.screen_space_aa
	_vp.use_taa = main.use_taa
	_vp.use_debanding = main.use_debanding
	_vp.handle_input_locally = false
	_vp.audio_listener_enable_3d = false
	add_child(_vp)
	await get_tree().process_frame
	_cam = Camera3D.new()
	_cam.current = true
	_vp.add_child(_cam)
	await get_tree().process_frame
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_vp.add_child(sun)
	await get_tree().process_frame
	# A floor for the shadows to fall on.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, -1.2, -4.0)
	_vp.add_child(floor_mesh)

func _show(mat: Material, i: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new() if i % 2 == 0 else SphereMesh.new()
	(mi.mesh as PrimitiveMesh).material = mat
	mi.position = Vector3(float(i % 5 - 2) * 1.1, 0.0, -4.0)
	_vp.add_child(mi)
	_live.append([mi, HOLD])

func _expire(all: bool) -> void:
	for e in _live.duplicate():
		e[1] -= 1
		if all or e[1] <= 0:
			if is_instance_valid(e[0]):
				e[0].queue_free()
			_live.erase(e)
