extends CanvasLayer
## Three laps at the Southside Speedway, the kart track behind the block
## (world/KartCenter3D.gd sells the ride). Opens over the room like the pool
## and darts games and keeps the day waiting while it runs, but the race is
## a whole 3D world of its own, built here in code inside a SubViewport so
## none of it touches the room behind it.
##
## The track: a closed Catmull-Rom spline through CIRCUIT, sampled every
## metre into points, tangents, lateral normals and curvature. Everything
## reads those samples -- the asphalt ribbon, red-and-white kerbs wherever
## the track bends hard, tyre walls on both sides, the racing AI, lap
## counting, and the minimap.
##
## The karts are arcade, not a physics engine: speed along the nose, a
## lateral slip that grip bleeds off, and a yaw rate from the wheel.
## Collisions are against the track itself -- your distance from the centre
## line -- so they're cheap, exact, and never snag on a mesh seam. The tyre
## wall bounces you back and costs you speed; the gravel strip in front of
## it slows you.
##
## Drifting is the Mario Kart mini-turbo: hold Shift or Space while steering
## at speed and the kart hops, swings its tail out, and starts throwing
## sparks. Hold the drift ~1 s for blue sparks, ~2 s for orange; let go and
## it fires a blue or orange turbo. The camera widens while it burns.
##
## The other drivers are the Dive Bar regulars. They "chase the rabbit": a
## point a speed-dependent distance ahead on the centre line, plus a lane
## offset they shift to get round slower karts. They brake for what's
## coming from the track's curvature, drift through the long bends like
## you can, and get a mild rubber band so a race stays a race.
##
## $5 a ride, paid at the desk. The day's first race pays prize money to the
## podium; after that you're racing for the time on the board.

signal finished(place: int)

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

const LAPS := 3
const TRACK_W := 9.0
## Gravel between the asphalt edge and the tyre wall.
const RUNOFF := 2.2
const SAMPLE_STEP := 1.0
const KART_R := 0.85

const MAX_SPEED := 21.0  # m/s, ~75 km/h -- a rental kart with the governor off
const ACCEL := 15.0
const BRAKE := 26.0
const REVERSE_MAX := 5.0
const ROLL_DRAG := 2.5
const STEER_RATE := 2.6  # rad/s at full lock
const GRIP := 9.0
const DRIFT_GRIP := 2.0
const GRAVEL_MAX := 0.5  # of MAX_SPEED
const WALL_KEEP := 0.55  # speed kept off a wall hit
const BOOST_SPEED := 1.35
const DRIFT_MIN_SPEED := 9.0
## Tightest and widest drift arcs, metres.
const DRIFT_RADIUS := Vector2(7.0, 30.0)
const BLUE_TIME := 1.0
const ORANGE_TIME := 2.0
const BLUE_BOOST := 0.8
const ORANGE_BOOST := 1.4
## Corner speed the AI aims for: v = sqrt(AI_LAT_ACCEL / curvature).
const AI_LAT_ACCEL := 15.0

const PRIZES := [15, 8, 5]
const PRIZE_DAILY_KEY := "kart_prize"

## The circuit, in metres, run clockwise from the start line. A long main
## straight past the grandstand into a hairpin, a fast sweeper, an S, a
## tight double-apex and back onto the straight.
## Checked for no bend under a 9 m radius (the tyre walls sit 7 m out) and
## 30 m+ between separate parts of the track.
const CIRCUIT := [
	Vector2(0, 0), Vector2(0, -40), Vector2(3, -60), Vector2(16, -72), Vector2(32, -70),
	Vector2(40, -56), Vector2(40, -40), Vector2(48, -28), Vector2(64, -24), Vector2(80, -30),
	Vector2(96, -26), Vector2(104, -8), Vector2(98, 12), Vector2(82, 20), Vector2(70, 32),
	Vector2(72, 50), Vector2(64, 68), Vector2(46, 76), Vector2(28, 72), Vector2(18, 58),
	Vector2(6, 54), Vector2(0, 40),
]

## Who's racing tonight: the bar's regulars, each with their own kart.
const FIELD := [
	{"name": "Big Eddie", "skill": 0.78, "color": Color(0.85, 0.12, 0.1), "num": 7},
	{"name": "Tired Woman", "skill": 0.66, "color": Color(0.15, 0.45, 0.9), "num": 22},
	{"name": "Old Sailor", "skill": 0.72, "color": Color(0.95, 0.75, 0.1), "num": 9},
	{"name": "Quiet Kid", "skill": 0.88, "color": Color(0.1, 0.75, 0.35), "num": 41},
	{"name": "Nervous Dave", "skill": 0.6, "color": Color(0.7, 0.2, 0.85), "num": 13},
]
const PLAYER_COLOR := Color(0.95, 0.45, 0.08)

const ORDINALS := ["1st", "2nd", "3rd", "4th", "5th", "6th"]

# --- Track samples ----------------------------------------------------------
var _pts: PackedVector3Array = []
var _tan: PackedVector3Array = []
## Unit vector to the right of the direction of travel.
var _nrm: PackedVector3Array = []
## Signed curvature (1/m); positive bends right.
var _curv: PackedFloat32Array = []
var _length: float = 0.0

# --- Scene ------------------------------------------------------------------
var _vp: SubViewport
var _world: Node3D
var _camera: Camera3D
var _hud: Control
var _minimap: Control
var _speedo: Control
var _env: Environment
var _start_lights: Array[MeshInstance3D] = []
var _gantry_lamps: Array[MeshInstance3D] = []
var _skid_mm: MultiMeshInstance3D
var _skid_next: int = 0
const SKID_MAX := 1600

# --- Karts ------------------------------------------------------------------
## One dictionary per kart; index 0 is you.
var _karts: Array[Dictionary] = []

# --- Race state ---------------------------------------------------------------
enum Phase { INTRO, COUNTDOWN, RACE, DONE }
var _phase: int = Phase.INTRO
var _t: float = 0.0
var _race_time: float = 0.0
var _countdown_shown: int = -1
var _finish_order: Array[int] = []
var _paused_confirm: bool = false
var _player_role: String = "player"
var _prize_paid: int = 0
var _results_shown: bool = false
var _banner_text: String = ""
var _banner_t: float = 0.0
var _banner_color: Color = Color.WHITE
var _cam_shake: float = 0.0
var _cam_pos: Vector3
var _cam_ready: bool = false
var _fov_boost: float = 0.0
var _hidden_scene: Node3D
var _room_hud: CanvasLayer
## Tests and the playthrough bot: your kart drives itself.
var autopilot: bool = false
var _deal: Dictionary = {}
## How the deal went, for the results board.
var _deal_line: String = ""
## Seconds you spent pointed the wrong way: throwing a race by reversing
## round the track doesn't look real.
var _wrong_way_total: float = 0.0
## A throw "looks real" if you're this close to the kart ahead of you.
const THROW_GAP := 8.0
const THROW_WRONG_WAY := 3.0

# --- Sound --------------------------------------------------------------------
var _engine: AudioStreamPlayer
var _engine_pb: AudioStreamGeneratorPlayback
var _pack: AudioStreamPlayer
var _pack_pb: AudioStreamGeneratorPlayback
var _phase_a: float = 0.0
var _phase_b: float = 0.0
var _phase_c: float = 0.0
var _pack_phase: float = 0.0
var _noise_lp: float = 0.0
var _beep_hi: AudioStreamWAV
var _beep_lo: AudioStreamWAV
var _bump_sfx: AudioStreamWAV
var _boost_sfx: AudioStreamWAV
var _hop_sfx: AudioStreamWAV
var _squeal: AudioStreamPlayer
var _cheer_sfx: AudioStreamWAV
var _sfx_players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS

## `player_role`: whose body sits in your kart (CharacterCast). `deal` is
## the hustle riding on this race (world/KartCenter3D.gd), if any:
## {"kind": "throw", "by", "pay"} -- finish 4th or worse and make it look
## real -- or {"kind": "bet", "stake", "pays"} -- podium and collect.
func start(player_role := "player", deal: Dictionary = {}) -> void:
	_player_role = player_role
	_deal = deal
	_room_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _room_hud:
		_room_hud.visible = false
	# Nothing renders the room behind a full-screen race.
	_hidden_scene = get_tree().current_scene as Node3D
	if _hidden_scene:
		_hidden_scene.visible = false
	# The day, the craving and closing time wait, like they do for pool.
	GameState.set_process(false)
	_build_track_samples()
	_build_viewport()
	_build_world()
	_build_karts()
	_build_hud()
	_build_sound()
	_reset_race()

func _exit_tree() -> void:
	GameState.set_process(true)
	if is_instance_valid(_hidden_scene):
		_hidden_scene.visible = true
	if is_instance_valid(_room_hud):
		_room_hud.visible = true

# =============================================================================
# Track geometry
# =============================================================================

func _build_track_samples() -> void:
	var ctrl: Array[Vector3] = []
	for p in CIRCUIT:
		ctrl.append(Vector3(p.x, 0.0, p.y))
	var n := ctrl.size()
	# Densely sample the closed Catmull-Rom spline, then resample at an even
	# metre so distance along the track is just an index.
	var dense: Array[Vector3] = []
	for i in n:
		var p0 := ctrl[(i - 1 + n) % n]
		var p1 := ctrl[i]
		var p2 := ctrl[(i + 1) % n]
		var p3 := ctrl[(i + 2) % n]
		for s in 40:
			var t := s / 40.0
			dense.append(_catmull(p0, p1, p2, p3, t))
	var total := 0.0
	var seg_len: Array[float] = []
	for i in dense.size():
		var d := dense[i].distance_to(dense[(i + 1) % dense.size()])
		seg_len.append(d)
		total += d
	var count := int(total / SAMPLE_STEP)
	_length = count * SAMPLE_STEP
	var stretch := total / _length
	var seg := 0
	var acc := 0.0
	for k in count:
		var want := k * SAMPLE_STEP * stretch
		while acc + seg_len[seg] < want:
			acc += seg_len[seg]
			seg += 1
		var f := (want - acc) / maxf(seg_len[seg], 0.0001)
		_pts.append(dense[seg].lerp(dense[(seg + 1) % dense.size()], f))
	for k in count:
		var a := _pts[(k - 2 + count) % count]
		var b := _pts[(k + 2) % count]
		var tan := (b - a).normalized()
		_tan.append(tan)
		_nrm.append(Vector3(-tan.z, 0.0, tan.x))
	for k in count:
		var t0 := _tan[(k - 3 + count) % count]
		var t1 := _tan[(k + 3) % count]
		# Turning right means the tangent swings toward the right normal.
		var ang := atan2(t0.cross(t1).y, t0.dot(t1))
		_curv.append(-ang / (6.0 * SAMPLE_STEP))

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _idx(i: int) -> int:
	var n := _pts.size()
	return ((i % n) + n) % n

## Nearest sample to `p`, searching around `hint` (karts don't teleport).
func _nearest(p: Vector3, hint: int, window := 24) -> int:
	var best := hint
	var best_d := INF
	for o in range(-window, window + 1):
		var k := _idx(hint + o)
		var d := Vector2(_pts[k].x - p.x, _pts[k].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = k
	return best

func _nearest_global(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in _pts.size():
		var d := _pts[k].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	return best

## Signed distance right of the centre line at sample `k`.
func _lateral(p: Vector3, k: int) -> float:
	return (p - _pts[k]).dot(_nrm[k])

# =============================================================================
# The 3D world
# =============================================================================

func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.positional_shadow_atlas_size = 2048
	_vp.audio_listener_enable_3d = true
	_vp.handle_input_locally = false
	container.add_child(_vp)
	_world = Node3D.new()
	_world.name = "Speedway"
	_vp.add_child(_world)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 900.0
	_world.add_child(_camera)
	_camera.make_current()

func _build_world() -> void:
	_environment()
	_ground()
	_road()
	_kerbs_and_lines()
	_tyre_walls()
	_start_gantry()
	_grandstand()
	_floodlights()
	_banners()
	_pit_building()
	_skyline()
	_cones_and_dressing()
	_skid_layer()

func _environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.02, 0.03, 0.08)
	sm.sky_horizon_color = Color(0.22, 0.14, 0.2)
	sm.ground_horizon_color = Color(0.12, 0.08, 0.1)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.85
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.1
	_env.glow_enabled = true
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.08
	_env.glow_hdr_threshold = 1.1
	# No SSAO: it costs more than it shows from a chase cam at speed, and
	# the race needs its frame rate on modest GPUs.
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.2, 0.16, 0.22)
	_env.fog_density = 0.0045
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.12
	_env.adjustment_saturation = 1.15
	we.environment = _env
	_world.add_child(we)
	# Graphics grades every WorldEnvironment as it enters the tree, and on
	# Low/Medium thickens the fog to stand in for the rooms' volumetric
	# haze; out here that buries the far side of the track, so thin it back
	# once Graphics is done.
	_thin_fog.call_deferred()
	# The city glow and a low moon do the fill; the floodlights do the work.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-38, 30, 0)
	moon.shadow_enabled = Graphics.is_high()
	if Graphics.preset == Graphics.Preset.PS5:
		# The passes the race leaves off for frame rate elsewhere.
		_env.ssao_enabled = true
		_env.ssao_radius = 1.2
		_env.ssr_enabled = true
		_env.ssr_max_steps = 48
		moon.directional_shadow_max_distance = 90.0
	moon.directional_shadow_max_distance = 45.0
	_world.add_child(moon)

func _thin_fog() -> void:
	_env.fog_enabled = true
	_env.fog_density = 0.0045
	_env.fog_light_color = Color(0.2, 0.16, 0.22)

func _pbr(set_name: String, uv: Vector3, tint := Color.WHITE, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/pbr/%s_" % set_name
	m.albedo_texture = load(base + "diff.jpg")
	m.albedo_color = tint
	if ResourceLoader.exists(base + "nor.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "nor.jpg")
	if ResourceLoader.exists(base + "rough.jpg"):
		m.roughness_texture = load(base + "rough.jpg")
	m.roughness = rough
	m.uv1_scale = uv
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _mat(c: Color, rough := 0.7, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	mi.rotation.y = rot_y
	return mi

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	return mi

func _label(parent: Node3D, text: String, pos: Vector3, size: int, col: Color, rot_y := 0.0, px := 0.02) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.shaded = false
	parent.add_child(l)
	l.position = pos
	l.rotation.y = rot_y
	return l

## A flat ribbon following the centre line between lateral offsets a and b,
## y above the ground. `v_scale` metres of track per texture repeat.
func _ribbon(a: float, b: float, y: float, m: Material, v_scale := 9.0, from := 0, to := -1) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _pts.size()
	var last := n if to < 0 else to
	for k in range(from, last):
		var k1 := _idx(k + 1)
		var v0 := float(k) * SAMPLE_STEP / v_scale
		var v1 := float(k + 1) * SAMPLE_STEP / v_scale
		var p0a := _pts[_idx(k)] + _nrm[_idx(k)] * a + Vector3.UP * y
		var p0b := _pts[_idx(k)] + _nrm[_idx(k)] * b + Vector3.UP * y
		var p1a := _pts[k1] + _nrm[k1] * a + Vector3.UP * y
		var p1b := _pts[k1] + _nrm[k1] * b + Vector3.UP * y
		var ua := a / v_scale
		var ub := b / v_scale
		st.set_normal(Vector3.UP)
		for v in [[p0a, Vector2(ua, v0)], [p1a, Vector2(ua, v1)], [p0b, Vector2(ub, v0)], [p0b, Vector2(ub, v0)], [p1a, Vector2(ua, v1)], [p1b, Vector2(ub, v1)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	_world.add_child(mi)
	return mi

func _ground() -> void:
	# An old industrial lot: cracked concrete out to the fence.
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(420, 420)
	g.mesh = pm
	g.material_override = _pbr("concrete_floor", Vector3(70, 70, 1), Color(0.55, 0.55, 0.58))
	_world.add_child(g)
	g.position = Vector3(50, -0.02, 0)

func _road() -> void:
	var asphalt := _pbr("asphalt", Vector3(1, 1, 1), Color(0.62, 0.62, 0.66), 0.9)
	_ribbon(-TRACK_W / 2, TRACK_W / 2, 0.0, asphalt, 7.0)
	# Gravel run-off on both sides.
	var gravel := _pbr("sidewalk", Vector3(1, 1, 1), Color(0.5, 0.44, 0.36), 1.0)
	_ribbon(-TRACK_W / 2 - RUNOFF, -TRACK_W / 2, 0.005, gravel, 3.0)
	_ribbon(TRACK_W / 2, TRACK_W / 2 + RUNOFF, 0.005, gravel, 3.0)

func _kerbs_and_lines() -> void:
	var white := _mat(Color(0.92, 0.92, 0.9), 0.6)
	# Painted edge lines, a hand's width in from the edge.
	_ribbon(-TRACK_W / 2 + 0.15, -TRACK_W / 2 + 0.35, 0.012, white)
	_ribbon(TRACK_W / 2 - 0.35, TRACK_W / 2 - 0.15, 0.012, white)
	# Kerbs: alternating red and white metre blocks on both sides of every
	# bend tighter than ~40 m radius -- one mesh, coloured per vertex, so
	# hundreds of blocks cost a single draw.
	var n := _pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var near := false
		for o in range(-6, 7):
			if absf(_curv[_idx(k + o)]) > 0.025:
				near = true
				break
		if not near:
			continue
		var col := Color(0.85, 0.08, 0.06) if k % 2 == 0 else Color(0.92, 0.92, 0.9)
		var k1 := _idx(k + 1)
		for side in [-1.0, 1.0]:
			var a: float = side * (TRACK_W / 2)
			var b: float = side * (TRACK_W / 2 + 0.9)
			var y := Vector3.UP * 0.03
			var q := [_pts[k] + _nrm[k] * a + y, _pts[k1] + _nrm[k1] * a + y, _pts[k] + _nrm[k] * b + y, _pts[k1] + _nrm[k1] * b + y]
			st.set_color(col)
			st.set_normal(Vector3.UP)
			for v in [q[0], q[1], q[2], q[2], q[1], q[3]]:
				st.add_vertex(v)
	var kerb_m := StandardMaterial3D.new()
	kerb_m.vertex_color_use_as_albedo = true
	kerb_m.roughness = 0.55
	kerb_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var kerbs := MeshInstance3D.new()
	kerbs.mesh = st.commit()
	kerbs.material_override = kerb_m
	kerbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(kerbs)
	# The start/finish line: a checker strip across the track.
	var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 2:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.05, 0.05, 0.05))
	var tex := ImageTexture.create_from_image(img)
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = tex
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cm.roughness = 0.6
	var line := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(TRACK_W, 1.1)
	line.mesh = pm
	line.material_override = cm
	_world.add_child(line)
	line.position = _pts[0] + Vector3.UP * 0.015
	line.rotation.y = atan2(_tan[0].x, _tan[0].z)
	# Grid boxes behind the line, two by two.
	for g in 6:
		var k := _idx(-6 - g * 5)
		var side := -1.0 if g % 2 == 0 else 1.0
		var p := _pts[k] + _nrm[k] * side * 2.0
		var yaw := atan2(_tan[k].x, _tan[k].z)
		var frame := Node3D.new()
		_world.add_child(frame)
		frame.position = p + Vector3.UP * 0.013
		frame.rotation.y = yaw
		for bar in [[Vector3(1.8, 0.01, 0.12), Vector3(0, 0, 1.0)], [Vector3(0.12, 0.01, 1.2), Vector3(-0.9, 0, 0.5)], [Vector3(0.12, 0.01, 1.2), Vector3(0.9, 0, 0.5)]]:
			_box(frame, bar[0], bar[1], white)
		_label(frame, str(g + 1), Vector3(0, 0.01, 1.5), 96, Color(0.9, 0.9, 0.85), 0.0, 0.006).rotation_degrees.x = -90

## Tyre stacks along the outside of the run-off, both sides: one MultiMesh
## of tyres (three to a stack), mostly black with a band of red and white
## every few stacks so the wall reads at speed.
func _tyre_walls() -> void:
	var tyre := TorusMesh.new()
	tyre.inner_radius = 0.2
	tyre.outer_radius = 0.38
	tyre.rings = 10
	tyre.ring_segments = 6
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.85
	tyre.material = tm
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var n := _pts.size()
	var spacing := 0.78
	for side in [-1.0, 1.0]:
		var stack := 0
		var dist := 0.0
		while dist < _length:
			var k := int(dist / SAMPLE_STEP) % n
			var off: float = side * (TRACK_W / 2 + RUNOFF + 0.4)
			var p := _pts[k] + _nrm[k] * off
			var band := (stack / 3) % 4 == 0
			for h in 3:
				var c := Color(0.07, 0.07, 0.075)
				if band:
					c = Color(0.85, 0.1, 0.08) if h % 2 == 0 else Color(0.92, 0.92, 0.9)
				xforms.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * (0.12 + h * 0.21)))
				colors.append(c)
			stack += 1
			# Even spacing along the wall itself, which is shorter than
			# the centre line on the inside of a bend and longer outside.
			dist += spacing / clampf(1.0 - _curv[k] * off, 0.3, 3.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tyre
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Thousands of tyres re-drawn into every shadow cascade cost more than
	# the shadows they'd throw at night.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(mmi)

func _start_gantry() -> void:
	var k := 0
	var p := _pts[k]
	var yaw := atan2(_tan[k].x, _tan[k].z)
	var g := Node3D.new()
	_world.add_child(g)
	g.position = p + _tan[k] * -1.5
	g.rotation.y = yaw
	var steel := _mat(Color(0.25, 0.26, 0.28), 0.4, 0.0, 0.7)
	var span := TRACK_W + RUNOFF * 2 + 1.0
	for side in [-1.0, 1.0]:
		_box(g, Vector3(0.45, 6.0, 0.45), Vector3(side * span / 2, 3.0, 0), steel)
	_box(g, Vector3(span + 0.5, 1.4, 0.5), Vector3(0, 6.2, 0), _mat(Color(0.08, 0.08, 0.1), 0.6))
	var title := _label(g, "SOUTHSIDE SPEEDWAY", Vector3(0, 6.25, -0.27), 110, Color(1.0, 0.55, 0.1), PI)
	title.pixel_size = 0.012
	var back := _label(g, "SOUTHSIDE SPEEDWAY", Vector3(0, 6.25, 0.27), 110, Color(1.0, 0.55, 0.1))
	back.pixel_size = 0.012
	# Five start lights facing the grid, back down the straight. The
	# gantry's local +z is the direction of travel, +x is to the left.
	for i in 5:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.48
		lamp.mesh = sm
		lamp.material_override = _mat(Color(0.15, 0.02, 0.02), 0.3)
		g.add_child(lamp)
		lamp.position = Vector3((i - 2) * 0.7, 5.15, -0.3)
		_box(g, Vector3(0.6, 0.6, 0.15), Vector3((i - 2) * 0.7, 5.15, -0.18), _mat(Color(0.03, 0.03, 0.03), 0.8))
		_start_lights.append(lamp)
	# Chequered flags on the uprights.
	for side in [-1.0, 1.0]:
		var flag := _box(g, Vector3(0.05, 0.8, 1.1), Vector3(side * (span / 2 + 0.3), 5.4, 0.4), _checker_mat(), 0.0)
		flag.rotation.z = side * 0.05

func _checker_mat() -> StandardMaterial3D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m

## Bleachers along the outside of the main straight, with a crowd: one
## MultiMesh of capsule people in jackets of every colour.
func _grandstand() -> void:
	var k := 0
	var side := -1.0  # the straight's outside is to its left
	# The stand's local +x points left, away from the track.
	var base := _pts[k] + _nrm[k] * side * (TRACK_W / 2 + RUNOFF + 4.5)
	var yaw := atan2(_tan[k].x, _tan[k].z)
	var stand := Node3D.new()
	_world.add_child(stand)
	stand.position = base
	stand.rotation.y = yaw
	var conc := _pbr("concrete_floor", Vector3(4, 1, 1), Color(0.6, 0.6, 0.62))
	var rows := 6
	var length := 46.0
	for r in rows:
		_box(stand, Vector3(1.3, 0.45, length), Vector3(r * 1.1, 0.25 + r * 0.45, 0), conc)
	# Roof on posts.
	var steel := _mat(Color(0.3, 0.3, 0.33), 0.5, 0.0, 0.6)
	for z in range(-22, 23, 11):
		_box(stand, Vector3(0.2, 6.0, 0.2), Vector3(rows * 1.1, 3.0, z), steel)
		_box(stand, Vector3(0.2, 4.2, 0.2), Vector3(-0.6, 2.1, z), steel)
	var roof := _box(stand, Vector3(rows * 1.1 + 1.6, 0.15, length + 1.0), Vector3(rows * 0.55 - 0.1, 5.2, 0), _mat(Color(0.75, 0.15, 0.1), 0.6))
	roof.rotation.z = -0.12
	# Under-roof strip lights.
	for z in range(-20, 21, 10):
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.65)
		lamp.light_energy = 1.4
		lamp.omni_range = 9.0
		stand.add_child(lamp)
		lamp.position = Vector3(3.0, 4.6, z)
	# The crowd.
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.1
	cap.radial_segments = 8
	cap.rings = 2
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.9
	cap.material = cm
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	head.radial_segments = 8
	head.rings = 4
	var hm := StandardMaterial3D.new()
	hm.vertex_color_use_as_albedo = true
	head.material = hm
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.use_colors = true
	bodies.mesh = cap
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.use_colors = true
	heads.mesh = head
	var spots: Array[Vector3] = []
	for r in rows:
		var z := -length / 2 + 0.6
		while z < length / 2 - 0.6:
			if rng.randf() < 0.62:
				spots.append(Vector3(r * 1.1 + rng.randf_range(-0.15, 0.15), 0.5 + r * 0.45 + 0.55, z))
			z += rng.randf_range(0.55, 0.9)
	bodies.instance_count = spots.size()
	heads.instance_count = spots.size()
	var jackets := [Color(0.7, 0.1, 0.1), Color(0.1, 0.2, 0.5), Color(0.15, 0.15, 0.15), Color(0.8, 0.7, 0.2), Color(0.2, 0.45, 0.25), Color(0.85, 0.85, 0.8), Color(0.45, 0.25, 0.15), Color(0.9, 0.4, 0.1)]
	var skins := [Color(0.95, 0.8, 0.68), Color(0.75, 0.55, 0.4), Color(0.45, 0.3, 0.2), Color(0.88, 0.72, 0.58)]
	for i in spots.size():
		var bt := Transform3D(Basis.IDENTITY, spots[i])
		bodies.set_instance_transform(i, bt)
		bodies.set_instance_color(i, jackets[rng.randi() % jackets.size()])
		heads.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i] + Vector3.UP * 0.68))
		heads.set_instance_color(i, skins[rng.randi() % skins.size()])
	for mm in [bodies, heads]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.add_child(mmi)
	_label(stand, "GRANDSTAND  -  NO GLASS  NO FIGHTING  NO REFUNDS", Vector3(-0.72, 3.6, 0), 64, Color(1, 1, 0.9), -PI / 2.0, 0.012)

## Floodlight masts round the outside, each a pole, a bank of lamps that
## actually glow, and a real spotlight down onto the asphalt.
func _floodlights() -> void:
	var steel := _mat(Color(0.35, 0.36, 0.38), 0.5, 0.0, 0.7)
	var lamp_m := _mat(Color(1.0, 0.95, 0.85), 0.2, 9.0)
	var every := 38.0
	var dist := 10.0
	var i := 0
	while dist < _length - 10.0:
		var k := int(dist) % _pts.size()
		# Masts go on the outside of the bend, where there's room.
		var side := 1.0 if _curv[k] < 0.0 else -1.0
		if i % 3 == 2:
			side = -side
		var base := _pts[k] + _nrm[k] * side * (TRACK_W / 2 + RUNOFF + 2.4)
		var mast := Node3D.new()
		_world.add_child(mast)
		mast.position = base
		mast.look_at_from_position(base, _pts[k] + Vector3.UP * 0.0001, Vector3.UP)
		mast.rotation.x = 0.0
		mast.rotation.z = 0.0
		_cyl(mast, 0.16, 11.0, Vector3(0, 5.5, 0), steel, 8)
		_box(mast, Vector3(2.4, 0.9, 0.3), Vector3(0, 11.2, -0.2), _mat(Color(0.12, 0.12, 0.13), 0.5))
		for lx in 3:
			for ly in 2:
				_box(mast, Vector3(0.6, 0.3, 0.05), Vector3((lx - 1) * 0.75, 11.0 + ly * 0.4, -0.37), lamp_m)
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.94, 0.82)
		spot.light_energy = 13.0
		spot.spot_range = 44.0
		spot.spot_angle = 58.0
		spot.spot_attenuation = 0.7
		spot.shadow_enabled = false
		_world.add_child(spot)
		spot.position = base + Vector3.UP * 10.8
		spot.look_at(_pts[k] + _nrm[k] * -side * 1.5, Vector3.UP)
		dist += every
		i += 1

## Sponsor boards on the tyre walls, from businesses on the block.
func _banners() -> void:
	var boards := [
		["TAPE DECK  -  USED TAPES $2", Color(1.0, 0.3, 0.8)],
		["GOLD & PAWN  -  WE BUY GOLD", Color(1.0, 0.75, 0.15)],
		["ST. JUDE'S  -  ALL ARE WELCOME", Color(0.85, 0.9, 1.0)],
		["LIQUOR  -  COLD BEER", Color(1.0, 0.2, 0.15)],
		["24/7  -  WE NEVER CLOSE", Color(0.95, 0.85, 0.3)],
		["DIVE BAR  -  POOL  DARTS  KARAOKE (BROKEN)", Color(1.0, 0.25, 0.55)],
		["SOUTHSIDE SPEEDWAY", Color(1.0, 0.55, 0.1)],
		["ELECTRONICS  -  NO RETURNS", Color(0.3, 0.9, 1.0)],
	]
	var n := _pts.size()
	var count := 14
	for b in count:
		var k := int(float(b) / count * n + 18) % n
		if absf(_curv[k]) > 0.03:
			k = _idx(k + 12)
		var side := -1.0 if b % 2 == 0 else 1.0
		var p := _pts[k] + _nrm[k] * side * (TRACK_W / 2 + RUNOFF + 1.05)
		var yaw := atan2(_tan[k].x, _tan[k].z)
		var holder := Node3D.new()
		_world.add_child(holder)
		holder.position = p
		# Face the track: local +z toward it, the board's length along it.
		holder.rotation.y = yaw + (-PI / 2.0 if side < 0.0 else PI / 2.0)
		var info: Array = boards[b % boards.size()]
		_box(holder, Vector3(7.0, 1.1, 0.12), Vector3(0, 1.15, 0), _mat(Color(0.06, 0.06, 0.07), 0.5))
		_box(holder, Vector3(7.2, 0.06, 0.14), Vector3(0, 1.72, 0), _mat(info[1], 0.4, 2.5))
		var l := _label(holder, info[0], Vector3(0, 1.15, 0.08), 64, info[1], 0.0, 0.0095)
		l.shaded = false

func _pit_building() -> void:
	# The office and garages inside the main straight.
	var k := _idx(-28)
	var p := _pts[k] + _nrm[k] * (TRACK_W / 2 + RUNOFF + 7.5)
	var yaw := atan2(_tan[k].x, _tan[k].z)
	var b := Node3D.new()
	_world.add_child(b)
	b.position = p
	b.rotation.y = yaw
	var brick := _pbr("brick", Vector3(6, 2, 1), Color(0.75, 0.7, 0.68))
	# Local +x points back at the track; the building runs away from it.
	_box(b, Vector3(9.0, 4.2, 26.0), Vector3(-4.5, 2.1, 0), brick)
	_box(b, Vector3(9.6, 0.3, 26.6), Vector3(-4.5, 4.35, 0), _mat(Color(0.15, 0.15, 0.16), 0.6))
	for gz in [-8.0, 0.0, 8.0]:
		_box(b, Vector3(0.08, 3.0, 5.5), Vector3(0.02, 1.5, gz), _mat(Color(0.55, 0.57, 0.6), 0.4, 0.0, 0.6))
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.85, 0.6)
		glow.light_energy = 1.2
		glow.omni_range = 7.0
		b.add_child(glow)
		glow.position = Vector3(1.5, 3.3, gz)
	var sign := _label(b, "PIT LANE  -  KARTS", Vector3(0.1, 3.75, 0), 120, Color(0.3, 0.95, 1.0), PI / 2.0, 0.012)
	sign.shaded = false
	_box(b, Vector3(0.1, 0.06, 14.0), Vector3(0.08, 3.35, 0), _mat(Color(0.3, 0.95, 1.0), 0.3, 4.0))
	# A kart up on a stand by the garage, wheels off.
	var parked := _kart_mesh(Color(0.2, 0.2, 0.22), 0, false)
	b.add_child(parked)
	parked.position = Vector3(2.0, 0.6, 12.0)
	parked.rotation.y = 0.6
	_box(b, Vector3(1.0, 0.6, 1.2), Vector3(2.0, 0.3, 12.0), _mat(Color(0.6, 0.1, 0.1), 0.6))

## A ring of dark towers past the fence with lit windows -- the city the
## track's squeezed into.
func _skyline() -> void:
	var img := Image.create(32, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for x in 32:
		for y in 64:
			var wx := x % 4 < 2
			var wy := y % 4 < 2
			var lit := rng.randf() < 0.28
			var c := Color(0.02, 0.02, 0.03)
			if wx and wy:
				c = Color(1.0, 0.82, 0.5) * rng.randf_range(0.6, 1.0) if lit else Color(0.05, 0.06, 0.08)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 1.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var centre := Vector3(50, 0, 0)
	for i in 34:
		var a := TAU * i / 34.0 + rng.randf_range(-0.05, 0.05)
		var r := rng.randf_range(150, 190)
		var h := rng.randf_range(20, 70)
		var w := rng.randf_range(14, 26)
		var tower := _box(_world, Vector3(w, h, w), centre + Vector3(cos(a) * r, h / 2, sin(a) * r), m, -a)
		var tm := tower.material_override.duplicate() as StandardMaterial3D
		tm.uv1_scale = Vector3(w / 12.0, h / 24.0, 1)
		tower.material_override = tm
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 5 == 0:
			# Aircraft-warning light on the roof.
			var red := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.6
			sm.height = 1.2
			red.mesh = sm
			red.material_override = _mat(Color(1, 0.1, 0.05), 0.3, 8.0)
			tower.add_child(red)
			red.position = Vector3(0, h / 2 + 0.6, 0)
	# A chain-link fence round the lot.
	var fence := _mat(Color(0.5, 0.52, 0.55, 0.55), 0.5, 0.0, 0.6)
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var post := _mat(Color(0.4, 0.4, 0.42), 0.5, 0.0, 0.6)
	var lo := Vector2(-40, -110)
	var hi := Vector2(140, 110)
	for edge in [[Vector3(lo.x, 0, lo.y), Vector3(hi.x, 0, lo.y)], [Vector3(hi.x, 0, lo.y), Vector3(hi.x, 0, hi.y)], [Vector3(hi.x, 0, hi.y), Vector3(lo.x, 0, hi.y)], [Vector3(lo.x, 0, hi.y), Vector3(lo.x, 0, lo.y)]]:
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		var mid := (a + b) / 2.0
		var len := a.distance_to(b)
		var f := _box(_world, Vector3(len, 2.6, 0.04), mid + Vector3.UP * 1.3, fence, -atan2(b.z - a.z, b.x - a.x))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var steps := int(len / 6.0)
		for s in steps + 1:
			_cyl(_world, 0.05, 2.8, a.lerp(b, float(s) / steps) + Vector3.UP * 1.4, post, 6)

func _cones_and_dressing() -> void:
	var cone_m := _mat(Color(1.0, 0.4, 0.05), 0.5)
	var stripe := _mat(Color(0.95, 0.95, 0.95), 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Cones at the apex of the tightest bends, just off the kerb.
	var n := _pts.size()
	var k := 0
	while k < n:
		if absf(_curv[k]) > 0.06:
			var inside := -signf(_curv[k])
			var p := _pts[k] + _nrm[k] * inside * (TRACK_W / 2 + 1.3)
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.2
			cm.height = 0.6
			cone.mesh = cm
			cone.material_override = cone_m
			_world.add_child(cone)
			cone.position = p + Vector3.UP * 0.3
			_cyl(cone, 0.13, 0.08, Vector3(0, 0.02, 0), stripe, 10)
			k += 9
		k += 1
	# Hay bales and oil drums out in the lot.
	var drum := _mat(Color(0.15, 0.3, 0.6), 0.45, 0.0, 0.5)
	var hay := _mat(Color(0.75, 0.62, 0.3), 1.0)
	for i in 18:
		var kk := rng.randi() % n
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := _pts[kk] + _nrm[kk] * side * (TRACK_W / 2 + RUNOFF + rng.randf_range(3.0, 7.0))
		if _distance_to_track(p) < TRACK_W / 2 + RUNOFF + 2.0:
			continue
		if i % 2 == 0:
			_cyl(_world, 0.3, 0.9, p + Vector3.UP * 0.45, drum, 12)
		else:
			_box(_world, Vector3(1.2, 0.5, 0.6), p + Vector3.UP * 0.25, hay, rng.randf() * TAU)

func _distance_to_track(p: Vector3) -> float:
	var k := _nearest_global(p)
	return absf(_lateral(p, k))

## Rubber laid down by drifts and hard braking: a ring buffer of dark quads.
func _skid_layer() -> void:
	var q := PlaneMesh.new()
	q.size = Vector2(0.22, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = SKID_MAX
	mm.visible_instance_count = 0
	_skid_mm = MultiMeshInstance3D.new()
	_skid_mm.multimesh = mm
	_skid_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_skid_mm)

func _lay_skid(pos: Vector3, yaw: float) -> void:
	var mm := _skid_mm.multimesh
	mm.set_instance_transform(_skid_next, Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.018, pos.z)))
	_skid_next = (_skid_next + 1) % SKID_MAX
	mm.visible_instance_count = maxi(mm.visible_instance_count, _skid_next if mm.visible_instance_count < SKID_MAX else SKID_MAX)

# =============================================================================
# Karts
# =============================================================================

## A rental kart: tube chassis, side pods and nose in the driver's colour,
## a seat, a lawnmower engine with an exhaust on the right, fat slicks.
## The wheel nodes are returned in meta so they can spin and steer.
func _kart_mesh(color: Color, number: int, with_wheels := true) -> Node3D:
	var k := Node3D.new()
	var body := _mat(color, 0.35, 0.0, 0.2)
	body.clearcoat_enabled = true
	body.clearcoat = 0.6
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.6)
	var chrome := _mat(Color(0.75, 0.76, 0.78), 0.2, 0.0, 0.9)
	var tube := _mat(Color(0.18, 0.18, 0.2), 0.4, 0.0, 0.7)
	# Floor tray and frame rails.
	_box(k, Vector3(0.95, 0.05, 1.55), Vector3(0, 0.12, 0), dark)
	for x in [-0.42, 0.42]:
		_box(k, Vector3(0.05, 0.05, 1.7), Vector3(x, 0.14, 0), tube)
	# Nose cone and front fairing.
	var nose := _box(k, Vector3(0.95, 0.22, 0.45), Vector3(0, 0.22, -0.85), body)
	nose.rotation.x = -0.25
	_box(k, Vector3(1.25, 0.08, 0.12), Vector3(0, 0.15, -1.08), body)
	# Side pods.
	for x in [-0.62, 0.62]:
		_box(k, Vector3(0.22, 0.2, 0.75), Vector3(x, 0.2, 0.08), body)
	# Steering column and wheel.
	var col := _cyl(k, 0.02, 0.5, Vector3(0, 0.38, -0.42), tube, 6)
	col.rotation.x = 1.0
	var wheel := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.13
	tor.outer_radius = 0.16
	tor.rings = 16
	tor.ring_segments = 6
	wheel.mesh = tor
	wheel.material_override = dark
	k.add_child(wheel)
	wheel.position = Vector3(0, 0.56, -0.28)
	wheel.rotation.x = 1.15
	k.set_meta("steering_wheel", wheel)
	# Seat.
	_box(k, Vector3(0.48, 0.1, 0.48), Vector3(0, 0.2, 0.25), _mat(Color(0.05, 0.05, 0.05), 0.5))
	var back := _box(k, Vector3(0.48, 0.55, 0.08), Vector3(0, 0.45, 0.52), _mat(Color(0.05, 0.05, 0.05), 0.5))
	back.rotation.x = -0.35
	# Engine, exhaust, rear bumper.
	_box(k, Vector3(0.32, 0.32, 0.32), Vector3(0.42, 0.32, 0.6), _mat(Color(0.5, 0.5, 0.52), 0.4, 0.0, 0.6))
	_box(k, Vector3(0.26, 0.12, 0.2), Vector3(0.42, 0.52, 0.6), _mat(Color(0.75, 0.1, 0.1), 0.5))
	var pipe := _cyl(k, 0.04, 0.4, Vector3(0.55, 0.3, 0.85), chrome, 8)
	pipe.rotation.x = PI / 2.0
	k.set_meta("exhaust", Vector3(0.55, 0.3, 1.05))
	_box(k, Vector3(1.3, 0.08, 0.08), Vector3(0, 0.18, 0.98), tube)
	# Number board on the nose.
	if number > 0:
		var plate := _box(k, Vector3(0.36, 0.26, 0.02), Vector3(0, 0.36, -0.98), _mat(Color(0.95, 0.95, 0.92), 0.5))
		plate.rotation.x = -0.6
		var num := _label(plate, str(number), Vector3(0, 0, -0.012), 72, Color(0.05, 0.05, 0.05), PI, 0.0035)
		num.outline_size = 0
		num.shaded = true
	if with_wheels:
		var wheels: Array[Node3D] = []
		var tyre_m := _mat(Color(0.05, 0.05, 0.05), 0.85)
		var rim_m := _mat(color.lerp(Color(0.8, 0.8, 0.8), 0.5), 0.3, 0.0, 0.8)
		for spec in [[-0.6, -0.72, 0.13, 0.17], [0.6, -0.72, 0.13, 0.17], [-0.62, 0.68, 0.14, 0.24], [0.62, 0.68, 0.14, 0.24]]:
			var pivot := Node3D.new()
			k.add_child(pivot)
			pivot.position = Vector3(spec[0], spec[2], spec[1])
			var spin := Node3D.new()
			pivot.add_child(spin)
			var t := _cyl(spin, spec[2], spec[3], Vector3.ZERO, tyre_m, 18)
			t.rotation.z = PI / 2.0
			var rim := _cyl(spin, spec[2] * 0.6, spec[3] + 0.01, Vector3.ZERO, rim_m, 10)
			rim.rotation.z = PI / 2.0
			wheels.append(pivot)
		k.set_meta("wheels", wheels)
	return k

## Puts `role`'s character in the seat, sitting, with a helmet on.
func _seat_driver(kart: Node3D, role: String, helmet_color: Color) -> void:
	var path := CharacterCast.model_for(role)
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = load(path).instantiate()
	kart.add_child(model)
	model.scale = Vector3.ONE * 1.5
	# Facing the nose (-z); the sitting clip's hips land about here.
	model.rotation.y = PI
	model.position = Vector3(0, -0.18, 0.28)
	CharacterCast.dress(model, role)
	var anim := CharacterAnimator.new(model)
	anim.play("sit")
	kart.set_meta("animator", anim)
	var skeleton: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n
	if skeleton == null:
		return
	var head_bone := -1
	for b in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(b).to_lower()
		if bn.ends_with("head") or bn == "head":
			head_bone = b
			break
	if head_bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_idx = head_bone
	skeleton.add_child(attach)
	var helmet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	helmet.mesh = sm
	var hm := _mat(helmet_color, 0.15, 0.0, 0.3)
	hm.clearcoat_enabled = true
	hm.clearcoat = 1.0
	helmet.material_override = hm
	attach.add_child(helmet)
	# Bone space is in the model's import units; undo the 1.5x and import
	# scale so the helmet is head-sized whatever the skeleton's scale.
	var s := skeleton.global_transform.basis.get_scale().x
	helmet.scale = Vector3.ONE / maxf(s, 0.0001)
	helmet.position = Vector3(0, 0.1, 0.0) / maxf(s, 0.0001)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.22, 0.08, 0.05)
	visor.mesh = vm
	var visor_m := _mat(Color(0.05, 0.05, 0.08), 0.05, 0.0, 0.6)
	visor.material_override = visor_m
	helmet.add_child(visor)
	visor.position = Vector3(0, 0.0, 0.13)

func _build_karts() -> void:
	var drivers: Array[Dictionary] = [{"name": "You", "role": _player_role, "skill": 0.0, "color": PLAYER_COLOR, "num": 1, "ai": false}]
	var others := FIELD.duplicate()
	others.shuffle()
	for d in others:
		drivers.append({"name": d["name"], "role": d["name"], "skill": d["skill"], "color": d["color"], "num": d["num"], "ai": true})
	for i in drivers.size():
		var d: Dictionary = drivers[i]
		var node := _kart_mesh(d["color"], d["num"])
		_world.add_child(node)
		_seat_driver(node, d["role"], (d["color"] as Color).lightened(0.25) if d["ai"] else Color(0.95, 0.95, 0.95))
		var kart := {
			"name": d["name"], "ai": d["ai"], "skill": d["skill"], "color": d["color"],
			"node": node, "pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3.ZERO, "steer": 0.0,
			"k": 0, "lap": 0, "progress": 0.0, "half": false, "finished": false, "time": 0.0,
			"lap_start": 0.0, "best_lap": INF, "last_lap": 0.0, "drift": 0, "drift_t": 0.0,
			"boost": 0.0, "boost_kind": 0, "hop": 0.0, "lane": 0.0, "wheel_spin": 0.0,
			"bump_cd": 0.0, "throttle": 0.0, "brake": false, "wrong_way": 0.0,
			"sparks": _make_sparks(node), "flame": _make_flame(node), "dust": _make_dust(node),
		}
		_karts.append(kart)

## A soft round puff, white at the centre and gone at the edge, so smoke
## and flame read as puffs rather than quads.
var _puff_tex: GradientTexture2D

func _puff() -> GradientTexture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_puff_tex = GradientTexture2D.new()
		_puff_tex.gradient = g
		_puff_tex.fill = GradientTexture2D.FILL_RADIAL
		_puff_tex.fill_from = Vector2(0.5, 0.5)
		_puff_tex.fill_to = Vector2(1.0, 0.5)
		_puff_tex.width = 64
		_puff_tex.height = 64
	return _puff_tex

func _make_sparks(node: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.6, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.4, 0.7, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 1.0)
	m.emission_energy_multiplier = 6.0
	q.material = m
	p.draw_pass_1 = q
	node.add_child(p)
	p.position = Vector3(0, 0.08, 0.75)
	return p

func _make_flame(node: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 32
	p.lifetime = 0.22
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.1, 1)
	pm.spread = 8.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	m.albedo_texture = _puff()
	q.material = m
	p.draw_pass_1 = q
	node.add_child(p)
	p.position = node.get_meta("exhaust", Vector3(0.55, 0.3, 1.05))
	return p

func _make_dust(node: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.9
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 1)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 1))
	curve.curve = c
	pm.scale_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.5, 0.45, 0.5))
	ramp.set_color(1, Color(0.55, 0.5, 0.45, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff()
	q.material = m
	p.draw_pass_1 = q
	node.add_child(p)
	p.position = Vector3(0, 0.1, 0.8)
	return p

# =============================================================================
# The race
# =============================================================================

func _reset_race() -> void:
	_phase = Phase.INTRO
	_t = 0.0
	_race_time = 0.0
	_countdown_shown = -1
	_finish_order.clear()
	_results_shown = false
	_prize_paid = 0
	_deal_line = ""
	_wrong_way_total = 0.0
	_cam_ready = false
	_skid_mm.multimesh.visible_instance_count = 0
	_skid_next = 0
	# Grid: you start from the back row, the regulars spread out ahead --
	# the fast ones further back, so there's someone to pass and someone
	# coming for you.
	var order: Array[int] = [1, 2, 3, 4, 5]
	order.sort_custom(func(a, b): return _karts[a]["skill"] < _karts[b]["skill"])
	var slots: Array[int] = []
	for i in order:
		slots.append(i)
	slots.append(0)
	for slot in slots.size():
		var kart: Dictionary = _karts[slots[slot]]
		var k := _idx(-6 - slot * 5)
		var side := -1.0 if slot % 2 == 0 else 1.0
		kart["pos"] = _pts[k] + _nrm[k] * side * 2.0
		kart["yaw"] = atan2(-_tan[k].x, -_tan[k].z)
		kart["vel"] = Vector3.ZERO
		kart["k"] = k
		kart["lap"] = 0
		kart["half"] = false
		kart["finished"] = false
		kart["time"] = 0.0
		kart["lap_start"] = 0.0
		kart["best_lap"] = INF
		kart["last_lap"] = 0.0
		kart["drift"] = 0
		kart["drift_t"] = 0.0
		kart["boost"] = 0.0
		kart["lane"] = side * 1.5
		kart["progress"] = -float(_length - k) if k > _pts.size() / 2 else float(k)
		_place_kart(kart, 0.0)
	_set_start_lights(0)

func _physics_process(delta: float) -> void:
	if _karts.is_empty() or _paused_confirm:
		return
	_t += delta
	match _phase:
		Phase.INTRO:
			if _t > 3.2:
				_phase = Phase.COUNTDOWN
				_t = 0.0
		Phase.COUNTDOWN:
			var lights := clampi(int(_t / 0.8) + 1, 0, 5)
			if lights != _countdown_shown and _t < 4.0:
				_countdown_shown = lights
				_set_start_lights(lights)
				_play(_beep_lo, -4.0)
			if _t >= 4.4:
				_phase = Phase.RACE
				_set_start_lights(-1)
				_play(_beep_hi, -2.0)
				_show_banner("GO!", Color(0.3, 1.0, 0.4), 1.2)
				for kart in _karts:
					kart["lap_start"] = 0.0
		Phase.RACE, Phase.DONE:
			_race_time += delta
	var racing := _phase == Phase.RACE or _phase == Phase.DONE
	for i in _karts.size():
		var kart: Dictionary = _karts[i]
		var steer := 0.0
		var throttle := 0.0
		var drift := false
		if racing and not kart["finished"]:
			if kart["ai"] or (i == 0 and autopilot):
				var ai := _ai_inputs(i, delta)
				steer = ai.x
				throttle = ai.y
				drift = ai.z > 0.5
			else:
				steer = Input.get_axis("move_left", "move_right")
				throttle = Input.get_axis("move_down", "move_up")
				drift = Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SPACE)
		elif racing and kart["finished"]:
			# Cool-down lap: everyone who's done coasts round on autopilot.
			var ai := _ai_inputs(i, delta)
			steer = ai.x
			throttle = minf(ai.y, 0.45)
		elif _phase == Phase.COUNTDOWN and not kart["ai"]:
			# Revving on the grid: you can blip the throttle.
			kart["throttle"] = Input.get_axis("move_down", "move_up")
		_drive(kart, steer, throttle, drift, delta, racing)
	_collide_karts()
	for i in _karts.size():
		_track_progress(i)
		_place_kart(_karts[i], delta)
	_update_positions_and_finish()
	_update_camera(delta)

## The kart model: speed along the nose, slip across it, yaw from the wheel.
func _drive(kart: Dictionary, steer: float, throttle: float, drift_btn: bool, dt: float, racing: bool) -> void:
	var yaw: float = kart["yaw"]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var vel: Vector3 = kart["vel"]
	var fs := vel.dot(fwd)
	var ls := vel.dot(right)
	var k: int = kart["k"]
	var lat := _lateral(kart["pos"], k)
	var on_gravel := absf(lat) > TRACK_W / 2.0 + 0.3
	var boost: float = kart["boost"]
	var top := MAX_SPEED * (BOOST_SPEED if boost > 0.0 else 1.0)
	if kart["ai"]:
		top *= _ai_top_factor(kart)
	if on_gravel:
		top = minf(top, MAX_SPEED * GRAVEL_MAX)
	kart["throttle"] = throttle
	if not racing:
		throttle = 0.0
	# Throttle, brakes, reverse.
	if boost > 0.0:
		# A hard shove up to the boosted top speed, and no further.
		if fs < top:
			fs = minf(fs + ACCEL * 2.2 * dt, top)
	elif throttle > 0.0:
		fs += ACCEL * throttle * maxf(0.0, 1.0 - fs / top) * dt * (1.6 if fs < 6.0 else 1.0)
	elif throttle < 0.0:
		if fs > 0.5:
			fs -= BRAKE * -throttle * dt
		else:
			fs = maxf(fs - ACCEL * 0.6 * -throttle * dt, -REVERSE_MAX)
	# Rolling drag, and the governor above top speed.
	fs -= signf(fs) * minf(absf(fs), ROLL_DRAG * dt)
	if fs > top:
		fs = move_toward(fs, top, (14.0 if on_gravel else 6.0) * dt)
	# Steering. The wheel turns the kart harder at low speed, less at the top.
	kart["steer"] = move_toward(kart["steer"], steer, 7.0 * dt)
	var st: float = kart["steer"]
	var speed_f := clampf(absf(fs) / 5.0, 0.0, 1.0) * (1.0 - 0.35 * clampf(fs / MAX_SPEED, 0.0, 1.0))
	var yaw_rate := -st * STEER_RATE * speed_f * signf(fs if absf(fs) > 0.1 else 1.0)
	# Drifting: hop, swing the tail, build the mini-turbo.
	var drift: int = kart["drift"]
	if drift == 0 and drift_btn and absf(st) > 0.3 and fs > DRIFT_MIN_SPEED and not on_gravel and racing:
		drift = int(signf(st))
		kart["drift_t"] = 0.0
		kart["hop"] = 0.18
		if not kart["ai"]:
			_play(_hop_sfx, -8.0)
	if drift != 0:
		# Clipping the gravel is forgiven; ploughing into it isn't.
		if not drift_btn or fs < DRIFT_MIN_SPEED * 0.7 or absf(lat) > TRACK_W / 2.0 + 1.0:
			_release_drift(kart)
			drift = 0
		else:
			# Into the drift always; the wheel tightens or opens the arc,
			# from DRIFT_RADIUS.y with full counter-steer to .x at full
			# lock. An arc, not a turn rate, so it holds at any speed.
			var into := float(drift)
			var f := (st * into + 1.0) / 2.0
			var curvature := lerpf(1.0 / DRIFT_RADIUS.y, 1.0 / DRIFT_RADIUS.x, f)
			yaw_rate = -into * curvature * fs
			# Charges faster the harder you lean into it.
			kart["drift_t"] = float(kart["drift_t"]) + dt * (1.0 + 0.6 * clampf(st * into, 0.0, 1.0))
	kart["drift"] = drift
	yaw += yaw_rate * dt
	# Grip bleeds off sideways slip; drifting keeps most of it.
	var grip := DRIFT_GRIP if drift != 0 else GRIP
	if on_gravel:
		grip *= 0.7
	ls *= exp(-grip * dt)
	# A drift pushes the kart out a little, like the real thing.
	if drift != 0:
		ls -= float(drift) * fs * 0.12 * dt
	var new_fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var new_right := Vector3(-new_fwd.z, 0.0, new_fwd.x)
	vel = new_fwd * fs + new_right * ls
	var pos: Vector3 = kart["pos"] + vel * dt
	# Tyre wall: the edge of the run-off. Bounce back in, lose pace.
	var k2 := _nearest(pos, k)
	var lat2 := _lateral(pos, k2)
	var wall := TRACK_W / 2.0 + RUNOFF - KART_R * 0.6
	if absf(lat2) > wall:
		var n := _nrm[k2] * signf(lat2)
		pos -= n * (absf(lat2) - wall)
		var vn := vel.dot(n)
		if vn > 0.0:
			vel -= n * vn * 1.5
			vel *= WALL_KEEP + 0.35 * (1.0 - clampf(vn / 12.0, 0.0, 1.0))
			if float(kart["bump_cd"]) <= 0.0 and vn > 2.0:
				kart["bump_cd"] = 0.4
				if not kart["ai"]:
					_play(_bump_sfx, linear_to_db(clampf(vn / 10.0, 0.25, 1.0)), randf_range(0.85, 1.1))
					_cam_shake = clampf(vn / 10.0, 0.2, 0.9)
			if drift != 0:
				_release_drift(kart, true)
	kart["bump_cd"] = maxf(0.0, float(kart["bump_cd"]) - dt)
	kart["pos"] = pos
	kart["vel"] = vel
	kart["yaw"] = yaw
	kart["k"] = k2
	# Re-read: letting go of a drift this frame may have just granted one.
	kart["boost"] = maxf(0.0, float(kart["boost"]) - dt)
	kart["hop"] = maxf(0.0, float(kart["hop"]) - dt)
	kart["wheel_spin"] = float(kart["wheel_spin"]) + fs * dt / 0.15
	# Rubber on the asphalt from a drift or hard braking.
	var marking := (drift != 0 and fs > 8.0) or (throttle < -0.5 and fs > 10.0) or absf(ls) > 3.0
	if marking and not on_gravel and Engine.get_physics_frames() % 2 == 0:
		for x in [-0.62, 0.62]:
			_lay_skid(pos + new_right * x + new_fwd * 0.68, yaw)
	(kart["dust"] as GPUParticles3D).emitting = on_gravel and absf(fs) > 3.0
	(kart["flame"] as GPUParticles3D).emitting = kart["boost"] > 0.0
	var sparks := kart["sparks"] as GPUParticles3D
	var dt_drift: float = kart["drift_t"]
	sparks.emitting = drift != 0 and dt_drift >= BLUE_TIME * 0.5
	if sparks.emitting:
		var c := Color(1.0, 0.85, 0.5)
		if dt_drift >= ORANGE_TIME:
			c = Color(1.0, 0.45, 0.08)
		elif dt_drift >= BLUE_TIME:
			c = Color(0.35, 0.65, 1.0)
		var m := (sparks.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		m.albedo_color = c
		m.emission = c
		sparks.position.x = 0.5 * -float(drift)

func _release_drift(kart: Dictionary, crashed := false) -> void:
	var t: float = kart["drift_t"]
	kart["drift"] = 0
	kart["drift_t"] = 0.0
	if crashed:
		return
	var kind := 0
	var dur := 0.0
	if t >= ORANGE_TIME:
		kind = 2
		dur = ORANGE_BOOST
	elif t >= BLUE_TIME:
		kind = 1
		dur = BLUE_BOOST
	if kind == 0:
		return
	kart["boost"] = maxf(float(kart["boost"]), dur)
	kart["boost_kind"] = kind
	if not kart["ai"]:
		_play(_boost_sfx, -2.0 if kind == 2 else -5.0, 1.0 if kind == 2 else 1.15)
		_fov_boost = 10.0 if kind == 2 else 6.0
		_show_banner("ORANGE TURBO!" if kind == 2 else "BLUE TURBO!", Color(1.0, 0.55, 0.1) if kind == 2 else Color(0.35, 0.7, 1.0), 0.8)

func _collide_karts() -> void:
	for i in _karts.size():
		for j in range(i + 1, _karts.size()):
			var a: Dictionary = _karts[i]
			var b: Dictionary = _karts[j]
			var d: Vector3 = b["pos"] - a["pos"]
			d.y = 0.0
			var dist := d.length()
			if dist >= KART_R * 2.0 or dist < 0.001:
				continue
			var n := d / dist
			var push := (KART_R * 2.0 - dist) * 0.5
			a["pos"] = a["pos"] - n * push
			b["pos"] = b["pos"] + n * push
			var rel := (a["vel"] as Vector3 - b["vel"] as Vector3).dot(n)
			if rel <= 0.0:
				continue
			var imp := n * rel * 0.8
			a["vel"] = a["vel"] - imp
			b["vel"] = b["vel"] + imp
			if (not a["ai"] or not b["ai"]) and rel > 1.5:
				_play(_bump_sfx, linear_to_db(clampf(rel / 8.0, 0.2, 0.8)), randf_range(1.1, 1.3))
				_cam_shake = maxf(_cam_shake, clampf(rel / 10.0, 0.15, 0.6))

## Laps: crossing the line forwards counts once you've been past halfway,
## so backing over it doesn't, and neither does a shortcut.
func _track_progress(i: int) -> void:
	var kart: Dictionary = _karts[i]
	var k: int = kart["k"]
	var n := _pts.size()
	var prev: float = kart["progress"]
	var lap: int = kart["lap"]
	var base := float(lap) * _length
	var here := base + k * SAMPLE_STEP
	# Unwrap across the line either way.
	if here - prev > _length / 2.0:
		here -= _length
	elif prev - here > _length / 2.0:
		here += _length
	kart["progress"] = here
	if k > n / 2 - 10 and k < n / 2 + 10:
		kart["half"] = true
	if here >= float(lap + 1) * _length and kart["half"] and _phase != Phase.INTRO and _phase != Phase.COUNTDOWN:
		_complete_lap(i)
	# Wrong way: nose against the track, moving.
	var fwd := Vector3(-sin(kart["yaw"]), 0.0, -cos(kart["yaw"]))
	if fwd.dot(_tan[k]) < -0.4 and (kart["vel"] as Vector3).length() > 3.0:
		kart["wrong_way"] = float(kart["wrong_way"]) + get_physics_process_delta_time()
		if i == 0 and _phase == Phase.RACE:
			_wrong_way_total += get_physics_process_delta_time()
	else:
		kart["wrong_way"] = 0.0

func _complete_lap(i: int) -> void:
	var kart: Dictionary = _karts[i]
	if kart["finished"]:
		return
	var lap_time := _race_time - float(kart["lap_start"])
	kart["lap"] = int(kart["lap"]) + 1
	kart["half"] = false
	kart["last_lap"] = lap_time
	var was_best := lap_time < float(kart["best_lap"])
	kart["best_lap"] = minf(float(kart["best_lap"]), lap_time)
	kart["lap_start"] = _race_time
	if int(kart["lap"]) >= LAPS:
		kart["finished"] = true
		kart["time"] = _race_time
		_finish_order.append(i)
		if not kart["ai"]:
			_on_player_finished()
		return
	if not kart["ai"]:
		if int(kart["lap"]) == LAPS - 1:
			_show_banner("FINAL LAP", Color(1.0, 0.9, 0.3), 1.8)
			_play(_beep_hi, -6.0, 0.8)
		elif was_best:
			_show_banner("LAP %d  -  %s" % [kart["lap"], _fmt(lap_time)], Color(0.4, 1.0, 0.5), 1.4)

func _on_player_finished() -> void:
	var place := _finish_order.size()
	_phase = Phase.DONE
	_play(_cheer_sfx, -4.0)
	_show_banner("%s PLACE!" % ORDINALS[place - 1].to_upper() if place <= 3 else "FINISHED %s" % ORDINALS[place - 1].to_upper(), Color(1.0, 0.85, 0.2) if place == 1 else Color(0.9, 0.9, 0.95), 2.5)
	# Prize money for the podium, once a day (triple on Cup night).
	if place <= PRIZES.size() and GameState.daily_available(PRIZE_DAILY_KEY, true):
		_prize_paid = PRIZES[place - 1] * Headlines.kart_prize_mult()
		GameState.cash += _prize_paid
		GameState.cash_earned += _prize_paid
		GameState.cash_changed.emit(GameState.cash)
		SFX.play("cash")
	var you: Dictionary = _karts[0]
	GameState.log_event("Raced karts at the Southside Speedway: %s of %d, best lap %s.%s" % [ORDINALS[place - 1], _karts.size(), _fmt(you["best_lap"]), (" Won $%d." % _prize_paid) if _prize_paid > 0 else ""])
	_settle_deal(place)
	# For a couple of minutes there, nothing else was in your head.
	GameState.craving = minf(100.0, GameState.craving + 4.0)
	GameState.craving_changed.emit(GameState.craving)
	finished.emit(place)

## Pays out (or doesn't) on whatever hustle rode on this race.
func _settle_deal(place: int) -> void:
	match _deal.get("kind", ""):
		"bet":
			if place <= 3:
				var won: int = _deal["pays"]
				GameState.cash += won
				GameState.cash_earned += won
				GameState.cash_changed.emit(GameState.cash)
				_deal_line = "The kid in the stands pays out: $%d on your $%d." % [won, _deal["stake"]]
				GameState.log_event("Won $%d betting on yourself at the kart track." % won)
			else:
				_deal_line = "The kid in the stands keeps your $%d." % _deal["stake"]
		"throw":
			var who: String = _deal["by"]
			var you: Dictionary = _karts[0]
			var ahead_time := 0.0
			if place >= 2:
				# The kart that finished just ahead of you.
				ahead_time = float(_karts[_finish_order[place - 2]]["time"])
			var gap := float(you["time"]) - ahead_time
			if place < 4:
				_deal_line = "%s watched you take the podium. He's not happy." % who
				GameState.change_rep(who, -2, "Took the podium after promising %s you'd lose." % who)
			elif gap > THROW_GAP or _wrong_way_total > THROW_WRONG_WAY:
				_deal_line = "%s: \"Everybody saw that. You think I'm paying for that?\"" % who
				GameState.change_rep(who, -1, "Threw the race for %s, badly. No pay." % who)
			else:
				var pay: int = _deal["pay"]
				GameState.cash += pay
				GameState.cash_earned += pay
				GameState.cash_changed.emit(GameState.cash)
				_deal_line = "%s slips you $%d on the way out. \"Beautiful. Nobody suspected a thing.\"" % [who, pay]
				GameState.change_rep(who, 1, "Threw a kart race for %s. $%d." % [who, pay])

func _update_positions_and_finish() -> void:
	if _phase != Phase.DONE:
		return
	# Whoever's still out there when you've been done a few seconds gets
	# their time projected from their pace, so the board fills in.
	if not _results_shown and (_finish_order.size() == _karts.size() or _race_time - float(_karts[0]["time"]) > 6.0):
		for i in _karts.size():
			var kart: Dictionary = _karts[i]
			if kart["finished"]:
				continue
			var left := float(LAPS) * _length - float(kart["progress"])
			var pace := maxf(8.0, float(kart["progress"]) / maxf(_race_time, 1.0))
			kart["time"] = _race_time + left / pace
			kart["finished"] = true
			if float(kart["best_lap"]) == INF:
				kart["best_lap"] = _length / pace
		var rest: Array[int] = []
		for i in _karts.size():
			if not _finish_order.has(i):
				rest.append(i)
		rest.sort_custom(func(a, b): return _karts[a]["time"] < _karts[b]["time"])
		_finish_order.append_array(rest)
		_results_shown = true

## Running order: finished first (in order), then by distance covered.
func _standings() -> Array[int]:
	var order: Array[int] = []
	order.append_array(_finish_order)
	var rest: Array[int] = []
	for i in _karts.size():
		if not order.has(i):
			rest.append(i)
	rest.sort_custom(func(a, b): return _karts[a]["progress"] > _karts[b]["progress"])
	order.append_array(rest)
	return order

## Chase the rabbit: steer at a point ahead on the line, shifted into a
## lane; throttle for the speed the curvature ahead allows. Returns
## (steer, throttle, drift).
func _ai_inputs(i: int, dt: float) -> Vector3:
	var kart: Dictionary = _karts[i]
	var pos: Vector3 = kart["pos"]
	var k: int = kart["k"]
	var speed := (kart["vel"] as Vector3).length()
	var skill: float = kart["skill"] if kart["ai"] else 0.75
	# Look further ahead the faster you go.
	var ahead := int(5.0 + speed * 0.55)
	var tk := _idx(k + ahead)
	# Take the inside of what's coming: ease the lane toward the apex side
	# of the next bend, and out of the way of anyone just ahead.
	var bend := 0.0
	for o in range(4, 26, 3):
		bend += _curv[_idx(k + o)]
	var want_lane := clampf(bend * 18.0, -1.0, 1.0) * (TRACK_W / 2.0 - 1.3)
	for j in _karts.size():
		if j == i:
			continue
		var other: Dictionary = _karts[j]
		var d: Vector3 = other["pos"] - pos
		var fwd := Vector3(-sin(kart["yaw"]), 0.0, -cos(kart["yaw"]))
		var along := d.dot(fwd)
		if along > 0.0 and along < 9.0:
			var their_lane := _lateral(other["pos"], tk)
			if absf(their_lane - want_lane) < 2.0 and (other["vel"] as Vector3).length() < speed + 1.0:
				want_lane = their_lane + (2.4 if their_lane < 0.0 else -2.4)
	want_lane = clampf(want_lane, -(TRACK_W / 2.0 - 1.0), TRACK_W / 2.0 - 1.0)
	kart["lane"] = move_toward(float(kart["lane"]), want_lane, 3.0 * dt)
	var target := _pts[tk] + _nrm[tk] * float(kart["lane"])
	var to := target - pos
	var yaw: float = kart["yaw"]
	var fwd2 := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var ang := atan2(fwd2.cross(to.normalized()).y, fwd2.dot(to.normalized()))
	var steer := clampf(-ang * 2.6, -1.0, 1.0)
	# Speed for what's ahead.
	var max_c := 0.0
	for o in range(2, int(10 + speed * 1.4), 2):
		max_c = maxf(max_c, absf(_curv[_idx(k + o)]))
	var corner_v := sqrt(AI_LAT_ACCEL * lerpf(0.85, 1.12, skill) / maxf(max_c, 0.0005))
	var want_v := minf(corner_v, MAX_SPEED * _ai_top_factor(kart))
	var throttle := 1.0
	if speed > want_v + 1.5:
		throttle = -clampf((speed - want_v) / 6.0, 0.3, 1.0)
	elif speed > want_v:
		throttle = 0.15
	# Drift the long bends (the good ones do it better).
	var drift := 0.0
	var long_bend := absf(bend) / 8.0 > 0.022 and speed > DRIFT_MIN_SPEED + 2.0
	var drift_state: int = kart["drift"]
	if drift_state != 0:
		# Hold it while the bend still goes the same way and we're not
		# running wide; let go for the turbo on the way out.
		var running_wide := absf(_lateral(pos, k)) > TRACK_W / 2.0 - 0.8
		var still_bending := signf(bend) == float(drift_state) and absf(bend) / 8.0 > 0.012
		if still_bending and not running_wide:
			drift = 1.0
	elif long_bend and kart["ai"] and randf() < skill * 0.06:
		drift = 1.0
		steer = signf(bend)
	return Vector3(steer, throttle, drift)

## Rubber band: a little extra for the ones behind you, a little less for
## the ones well ahead. Skill decides the base.
func _ai_top_factor(kart: Dictionary) -> float:
	var base := lerpf(0.86, 0.985, float(kart["skill"]))
	if _karts.is_empty():
		return base
	var gap := float(kart["progress"]) - float(_karts[0]["progress"])
	return base * (1.0 + clampf(-gap / 120.0, -0.06, 0.07))

func _place_kart(kart: Dictionary, dt: float) -> void:
	var node := kart["node"] as Node3D
	var hop: float = kart["hop"]
	var y := 0.0
	if hop > 0.0:
		y = sin((1.0 - hop / 0.18) * PI) * 0.18
	node.position = kart["pos"] + Vector3.UP * y
	# Lean into a drift and pitch under braking/throttle -- all visual.
	var drift: int = kart["drift"]
	var vel: Vector3 = kart["vel"]
	var yaw: float = kart["yaw"]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var slip := vel.dot(right)
	var visual_yaw := yaw - float(drift) * 0.32
	node.rotation = Vector3(
		lerpf(node.rotation.x, -clampf(float(kart["throttle"]), -1.0, 1.0) * 0.025, minf(1.0, dt * 6.0)),
		visual_yaw,
		lerpf(node.rotation.z, clampf(-slip * 0.02, -0.08, 0.08), minf(1.0, dt * 6.0)))
	var wheels: Array = node.get_meta("wheels", [])
	for w in wheels.size():
		var pivot := wheels[w] as Node3D
		if w < 2:
			pivot.rotation.y = -float(kart["steer"]) * 0.45
		(pivot.get_child(0) as Node3D).rotation.x = -float(kart["wheel_spin"])
	var sw := node.get_meta("steering_wheel") as Node3D
	if sw:
		sw.rotation = Vector3(1.15, 0.0, float(kart["steer"]) * 1.2)

func _set_start_lights(n: int) -> void:
	for i in _start_lights.size():
		var on := n >= 0 and i < n
		var m := _start_lights[i].material_override as StandardMaterial3D
		if n < 0:
			m.albedo_color = Color(0.1, 0.9, 0.2)
			m.emission_enabled = true
			m.emission = Color(0.1, 1.0, 0.25)
			m.emission_energy_multiplier = 8.0
		elif on:
			m.albedo_color = Color(1.0, 0.08, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.08, 0.05)
			m.emission_energy_multiplier = 8.0
		else:
			m.albedo_color = Color(0.15, 0.02, 0.02)
			m.emission_enabled = false

# =============================================================================
# Camera
# =============================================================================

func _update_camera(delta: float) -> void:
	var you: Dictionary = _karts[0]
	var pos: Vector3 = you["pos"]
	var yaw: float = you["yaw"]
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var speed := (you["vel"] as Vector3).length()
	var want: Vector3
	var look: Vector3
	if _phase == Phase.INTRO:
		# A slow swing round the grid while the field settles in.
		var a := _t / 3.2
		var centre: Vector3 = _pts[_idx(-16)]
		var ang := lerpf(-0.9, 0.9, a) + atan2(_tan[0].x, _tan[0].z) + PI
		want = centre + Vector3(sin(ang), 0.0, cos(ang)) * lerpf(26.0, 9.0, a) + Vector3.UP * lerpf(12.0, 3.0, a)
		look = pos.lerp(centre, 1.0 - a) + Vector3.UP * 0.6
		_cam_pos = want
		_cam_ready = true
	elif _phase == Phase.DONE and _race_time - float(you["time"]) > 1.5:
		# Victory lap: orbit the kart.
		var ang := _t * 0.35
		want = pos + Vector3(sin(ang), 0.0, cos(ang)) * 6.0 + Vector3.UP * 2.4
		look = pos + Vector3.UP * 0.7
	else:
		# Chase cam: behind and above, swinging wide in a drift.
		var drift: int = you["drift"]
		var swing := Basis(Vector3.UP, float(drift) * -0.22)
		var back := swing * -fwd
		var dist := 4.4 + speed * 0.06
		want = pos + back * dist + Vector3.UP * (2.3 + speed * 0.02)
		look = pos + fwd * 4.5 + Vector3.UP * 0.7
	if not _cam_ready:
		_cam_pos = want
		_cam_ready = true
	_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-7.0 * delta))
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _cam_shake * 0.12
	_cam_shake = move_toward(_cam_shake, 0.0, delta * 2.5)
	# A rumble at speed, from the engine and the seams in the asphalt.
	shake += Vector3(0, sin(_t * 47.0), 0) * 0.008 * clampf(speed / MAX_SPEED, 0.0, 1.0)
	_camera.global_position = _cam_pos + shake
	if _camera.global_position.distance_to(look) > 0.1:
		_camera.look_at(look, Vector3.UP)
	_fov_boost = move_toward(_fov_boost, 0.0, delta * 6.0)
	var boosting := float(you["boost"]) > 0.0
	_camera.fov = lerpf(_camera.fov, 68.0 + 10.0 * clampf(speed / MAX_SPEED, 0.0, 1.0) + (_fov_boost if boosting else _fov_boost * 0.5), 1.0 - exp(-5.0 * delta))

# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.draw.connect(_draw_hud)
	_minimap = Control.new()
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_minimap)
	_minimap.draw.connect(_draw_minimap)
	_speedo = Control.new()
	_speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_speedo)
	_speedo.draw.connect(_draw_speedo)

func _process(delta: float) -> void:
	if _hud == null:
		return
	# Render the race like the rooms: below native and upscaled with FSR,
	# at whatever scale Graphics' frame-rate governor has settled on.
	var root_vp := get_tree().root
	_vp.scaling_3d_mode = root_vp.scaling_3d_mode
	_vp.scaling_3d_scale = root_vp.scaling_3d_scale
	_vp.fsr_sharpness = root_vp.fsr_sharpness
	_vp.screen_space_aa = root_vp.screen_space_aa
	var size := _hud.size
	_minimap.position = Vector2(size.x - 250, 20)
	_minimap.size = Vector2(230, 230)
	_speedo.position = Vector2(size.x - 250, size.y - 210)
	_speedo.size = Vector2(230, 190)
	_banner_t = maxf(0.0, _banner_t - delta)
	_hud.queue_redraw()
	_minimap.queue_redraw()
	_speedo.queue_redraw()
	_feed_engine()

func _show_banner(text: String, col: Color, secs: float) -> void:
	_banner_text = text
	_banner_color = col
	_banner_t = secs

func _fmt(t: float) -> String:
	if t == INF or t <= 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

func _panel(c: Control, rect: Rect2) -> void:
	c.draw_rect(rect, Color(0.02, 0.02, 0.03, 0.62))
	c.draw_rect(rect, Color(1.0, 0.55, 0.1, 0.55), false, 2.0)

func _text(c: Control, font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	c.draw_string_outline(font, pos, s, align, width, size, 6, Color(0, 0, 0, 0.85))
	c.draw_string(font, pos, s, align, width, size, col)

func _draw_hud() -> void:
	var c := _hud
	var font := ThemeDB.fallback_font
	var size := c.size
	var you: Dictionary = _karts[0]
	var order := _standings()
	var place := order.find(0) + 1
	# --- Position and laps, top left.
	_panel(c, Rect2(20, 20, 300, 150))
	_text(c, font, Vector2(36, 92), ORDINALS[place - 1], 72, Color(1.0, 0.85, 0.2) if place == 1 else Color.WHITE)
	_text(c, font, Vector2(170, 66), "/ %d" % _karts.size(), 30, Color(0.8, 0.8, 0.85))
	var lap_n := clampi(int(you["lap"]) + 1, 1, LAPS)
	_text(c, font, Vector2(170, 100), "LAP %d/%d" % [lap_n, LAPS], 26, Color(1.0, 0.75, 0.3))
	var cur := _race_time - float(you["lap_start"]) if _phase == Phase.RACE else 0.0
	_text(c, font, Vector2(36, 132), "TIME  %s" % _fmt(_race_time if _phase != Phase.INTRO and _phase != Phase.COUNTDOWN else 0.0), 22, Color.WHITE)
	_text(c, font, Vector2(36, 158), "LAP %s   BEST %s" % [_fmt(cur), _fmt(you["best_lap"])], 18, Color(0.8, 0.85, 0.9))
	# --- Running order, down the left.
	var y := 206.0 if not _deal.is_empty() else 196.0
	_panel(c, Rect2(20, y - 8, 300, 34.0 * order.size() + 14))
	for i in order.size():
		var kart: Dictionary = _karts[order[i]]
		var row_y := y + 26.0 + i * 34.0
		var me := order[i] == 0
		if me:
			c.draw_rect(Rect2(24, row_y - 24, 292, 32), Color(1.0, 0.55, 0.1, 0.25))
		c.draw_rect(Rect2(34, row_y - 18, 8, 22), kart["color"])
		_text(c, font, Vector2(52, row_y), "%d  %s" % [i + 1, kart["name"]], 22, Color.WHITE if me else Color(0.85, 0.85, 0.88))
		var gap := ""
		if i > 0 and not kart["finished"]:
			var leader: Dictionary = _karts[order[0]]
			var metres := float(leader["progress"]) - float(kart["progress"])
			gap = "+%.1fs" % (metres / maxf(10.0, (leader["vel"] as Vector3).length()))
		elif kart["finished"] and _results_shown:
			gap = _fmt(kart["time"])
		_text(c, font, Vector2(220, row_y), gap, 18, Color(0.75, 0.8, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 90)
	# --- The hustle, under the timing panel.
	if not _deal.is_empty() and not _results_shown:
		var note := ""
		if _deal["kind"] == "throw":
			note = "%s's money: 4th or worse. Make it look real." % _deal["by"]
		else:
			note = "$%d on yourself: podium pays $%d." % [_deal["stake"], _deal["pays"]]
		_text(c, font, Vector2(24, 186), note, 16, Color(1.0, 0.75, 0.3))
	# --- Drift charge, bottom centre.
	var drift_t: float = you["drift_t"]
	if int(you["drift"]) != 0 or float(you["boost"]) > 0.0:
		var bar := Rect2(size.x / 2 - 160, size.y - 70, 320, 18)
		c.draw_rect(bar, Color(0, 0, 0, 0.6))
		var f := clampf(drift_t / ORANGE_TIME, 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.5)
		if drift_t >= ORANGE_TIME:
			col = Color(1.0, 0.45, 0.08)
		elif drift_t >= BLUE_TIME:
			col = Color(0.35, 0.65, 1.0)
		if float(you["boost"]) > 0.0 and int(you["drift"]) == 0:
			f = clampf(float(you["boost"]) / ORANGE_BOOST, 0.0, 1.0)
			col = Color(1.0, 0.45, 0.08) if int(you["boost_kind"]) == 2 else Color(0.35, 0.65, 1.0)
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
		c.draw_line(Vector2(bar.position.x + bar.size.x * BLUE_TIME / ORANGE_TIME, bar.position.y - 3), Vector2(bar.position.x + bar.size.x * BLUE_TIME / ORANGE_TIME, bar.end.y + 3), Color.WHITE, 2.0)
		c.draw_rect(bar, Color(1, 1, 1, 0.7), false, 2.0)
		_text(c, font, Vector2(size.x / 2 - 160, size.y - 78), "TURBO" if float(you["boost"]) > 0.0 and int(you["drift"]) == 0 else "DRIFT", 18, col)
	# --- Countdown, banners, wrong way.
	if _phase == Phase.INTRO:
		_text(c, font, Vector2(0, size.y * 0.22), "SOUTHSIDE SPEEDWAY", 64, Color(1.0, 0.55, 0.1), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(c, font, Vector2(0, size.y * 0.22 + 46), "%d laps  -  %d drivers  -  $5 a ride" % [LAPS, _karts.size()], 26, Color(0.9, 0.9, 0.9), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	elif _phase == Phase.COUNTDOWN:
		var lights := clampi(int(_t / 0.8) + 1, 0, 5)
		var cx := size.x / 2.0
		for i in 5:
			var on := i < lights
			c.draw_circle(Vector2(cx + (i - 2) * 70, 110), 26, Color(0.08, 0.08, 0.08, 0.9))
			c.draw_circle(Vector2(cx + (i - 2) * 70, 110), 21, Color(1.0, 0.1, 0.05) if on else Color(0.25, 0.04, 0.04))
	if _banner_t > 0.0:
		var a := clampf(_banner_t * 3.0, 0.0, 1.0)
		var scale := 1.0 + maxf(0.0, (_banner_t - 0.6)) * 0.08
		_text(c, font, Vector2(0, size.y * 0.32), _banner_text, int(84 * scale), Color(_banner_color, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if float(you["wrong_way"]) > 0.8 and _phase == Phase.RACE and int(Time.get_ticks_msec() / 300) % 2 == 0:
		_text(c, font, Vector2(0, size.y * 0.45), "WRONG WAY", 72, Color(1.0, 0.2, 0.15), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# --- Results.
	if _results_shown and _race_time - float(you["time"]) > 3.0:
		_draw_results(c, font, size, order)
	# --- Controls hint / pause.
	var hint := "W/Up gas   S/Down brake   A/D steer   hold Shift/Space in a turn to drift, let go for a turbo   Esc quit"
	if _paused_confirm:
		_panel(c, Rect2(size.x / 2 - 300, size.y / 2 - 70, 600, 140))
		_text(c, font, Vector2(0, size.y / 2 - 14), "Leave the race? Your $5 stays here.", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(c, font, Vector2(0, size.y / 2 + 30), "Esc again to leave   -   any other key to keep racing", 20, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	elif not _results_shown:
		_text(c, font, Vector2(0, size.y - 20), hint, 16, Color(0.85, 0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x)

func _draw_results(c: Control, font: Font, size: Vector2, order: Array[int]) -> void:
	var w := 640.0
	var h := 120.0 + order.size() * 40.0 + 70.0 + (30.0 if _deal_line != "" else 0.0)
	var r := Rect2(size.x / 2 - w / 2, size.y / 2 - h / 2, w, h)
	c.draw_rect(r, Color(0.02, 0.02, 0.03, 0.88))
	c.draw_rect(r, Color(1.0, 0.55, 0.1, 0.9), false, 3.0)
	_text(c, font, Vector2(r.position.x, r.position.y + 54), "RESULTS", 44, Color(1.0, 0.55, 0.1), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(c, font, Vector2(r.position.x + 40, r.position.y + 96), "POS   DRIVER", 16, Color(0.7, 0.7, 0.75))
	_text(c, font, Vector2(r.position.x + 380, r.position.y + 96), "TIME        BEST LAP", 16, Color(0.7, 0.7, 0.75))
	for i in order.size():
		var kart: Dictionary = _karts[order[i]]
		var y := r.position.y + 132 + i * 40
		var me := order[i] == 0
		if me:
			c.draw_rect(Rect2(r.position.x + 20, y - 28, w - 40, 38), Color(1.0, 0.55, 0.1, 0.22))
		var medal := [Color(1.0, 0.82, 0.2), Color(0.8, 0.82, 0.86), Color(0.8, 0.5, 0.25)]
		if i < 3:
			c.draw_circle(Vector2(r.position.x + 52, y - 9), 13, medal[i])
		_text(c, font, Vector2(r.position.x + 46, y), str(i + 1), 20, Color(0.05, 0.05, 0.05) if i < 3 else Color.WHITE)
		c.draw_rect(Rect2(r.position.x + 82, y - 20, 8, 22), kart["color"])
		_text(c, font, Vector2(r.position.x + 100, y), kart["name"], 24, Color.WHITE if me else Color(0.88, 0.88, 0.9))
		_text(c, font, Vector2(r.position.x + 380, y), _fmt(kart["time"]), 22, Color.WHITE)
		_text(c, font, Vector2(r.position.x + 500, y), _fmt(kart["best_lap"]), 22, Color(0.75, 0.9, 0.8))
	var foot_y := r.end.y - 50
	if _deal_line != "":
		_text(c, font, Vector2(r.position.x, foot_y - 30), _deal_line, 18, Color(0.85, 0.95, 0.75), HORIZONTAL_ALIGNMENT_CENTER, w)
	var place := order.find(0) + 1
	var prize_line := "The day's prize pot's been paid out -- you raced for the board."
	if _prize_paid > 0:
		prize_line = "%s place pays $%d." % [ORDINALS[place - 1], _prize_paid]
	elif place > PRIZES.size():
		prize_line = "Off the podium. No prize."
	_text(c, font, Vector2(r.position.x, foot_y), prize_line, 20, Color(1.0, 0.9, 0.5), HORIZONTAL_ALIGNMENT_CENTER, w)
	var again := "E / Enter: race again ($5)" if GameState.cash >= 5 else "Not enough for another ride"
	_text(c, font, Vector2(r.position.x, foot_y + 32), again + "     Esc: leave", 18, Color(0.85, 0.85, 0.88), HORIZONTAL_ALIGNMENT_CENTER, w)

func _draw_minimap() -> void:
	var c := _minimap
	var rect := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(rect, Color(0.02, 0.02, 0.03, 0.55))
	c.draw_rect(rect, Color(1.0, 0.55, 0.1, 0.5), false, 2.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var span := hi - lo
	var s := minf((c.size.x - 30) / span.x, (c.size.y - 30) / span.y)
	var off := (c.size - span * s) / 2.0
	var to_map := func(p: Vector3) -> Vector2: return off + (Vector2(p.x, p.z) - lo) * s
	var line := PackedVector2Array()
	for k in range(0, _pts.size(), 3):
		line.append(to_map.call(_pts[k]))
	line.append(line[0])
	c.draw_polyline(line, Color(0, 0, 0, 0.8), 9.0, true)
	c.draw_polyline(line, Color(0.55, 0.55, 0.6), 5.0, true)
	# Start line.
	var sp: Vector2 = to_map.call(_pts[0])
	var sn := Vector2(_nrm[0].x, _nrm[0].z)
	c.draw_line(sp - sn * 6, sp + sn * 6, Color.WHITE, 3.0)
	for i in range(_karts.size() - 1, -1, -1):
		var kart: Dictionary = _karts[i]
		var mp: Vector2 = to_map.call(kart["pos"])
		if i == 0:
			c.draw_circle(mp, 7.5, Color.WHITE)
			c.draw_circle(mp, 5.5, kart["color"])
		else:
			c.draw_circle(mp, 5.0, Color(0, 0, 0))
			c.draw_circle(mp, 4.0, kart["color"])

func _draw_speedo() -> void:
	var c := _speedo
	var font := ThemeDB.fallback_font
	var you: Dictionary = _karts[0]
	var kmh := (you["vel"] as Vector3).length() * 3.6
	var centre := Vector2(c.size.x / 2, c.size.y - 40)
	var r := 92.0
	c.draw_circle(centre, r + 12, Color(0.02, 0.02, 0.03, 0.6))
	var max_kmh := 110.0
	var a0 := PI * 0.85
	var a1 := PI * 2.15
	# Ticks every 10 km/h, numbers every 20.
	for v in range(0, int(max_kmh) + 1, 10):
		var a := lerpf(a0, a1, v / max_kmh)
		var dir := Vector2(cos(a), sin(a))
		var big := v % 20 == 0
		c.draw_line(centre + dir * (r - (14 if big else 8)), centre + dir * r, Color(1, 1, 1, 0.85) if v < 90 else Color(1, 0.3, 0.2), 3.0 if big else 1.5)
		if big:
			_text(c, font, centre + dir * (r - 32) + Vector2(-12, 6), str(v), 14, Color(0.85, 0.85, 0.9))
	var f := clampf(kmh / max_kmh, 0.0, 1.0)
	var arc_col := Color(1.0, 0.45, 0.08) if float(you["boost"]) > 0.0 else Color(1.0, 0.75, 0.3)
	c.draw_arc(centre, r + 5, a0, lerpf(a0, a1, f), 48, arc_col, 6.0, true)
	var na := lerpf(a0, a1, f)
	c.draw_line(centre, centre + Vector2(cos(na), sin(na)) * (r - 6), Color(1.0, 0.25, 0.15), 4.0, true)
	c.draw_circle(centre, 8, Color(0.15, 0.15, 0.15))
	_text(c, font, Vector2(0, centre.y + 2), "%d" % int(kmh), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
	_text(c, font, Vector2(0, centre.y + 26), "KM/H", 14, Color(0.75, 0.75, 0.8), HORIZONTAL_ALIGNMENT_CENTER, c.size.x)

# =============================================================================
# Input
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if _paused_confirm:
		get_viewport().set_input_as_handled()
		_paused_confirm = false
		if key == KEY_ESCAPE:
			_close()
		else:
			get_tree().paused = false
		return
	if _results_shown and _race_time - float(_karts[0]["time"]) > 3.0:
		get_viewport().set_input_as_handled()
		if key == KEY_ESCAPE:
			_close()
		elif (key == KEY_E or key == KEY_ENTER or key == KEY_KP_ENTER) and GameState.spend_cash(5):
			SFX.play("cash")
			# A rerun is just a ride: the deal was for the race you ran.
			_deal = {}
			_reset_race()
		return
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _phase == Phase.DONE:
			_close()
			return
		_paused_confirm = true
		get_tree().paused = true
	elif key < KEY_F1 or key > KEY_F12:
		# The room behind (the walkman, the notebook, E) doesn't get keys
		# while you're racing; the function keys stay with Graphics.
		get_viewport().set_input_as_handled()

func _close() -> void:
	get_tree().paused = false
	queue_free()

# =============================================================================
# Sound: a two-stroke synthesised live, and short effects baked once.
# =============================================================================

const MIX_RATE := 22050.0

func _build_sound() -> void:
	_engine = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	_engine.stream = gen
	_engine.volume_db = -9.0
	_engine.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_engine)
	_engine.play()
	_engine_pb = _engine.get_stream_playback()
	_pack = AudioStreamPlayer.new()
	var gen2 := AudioStreamGenerator.new()
	gen2.mix_rate = MIX_RATE
	gen2.buffer_length = 0.12
	_pack.stream = gen2
	_pack.volume_db = -16.0
	_pack.bus = _engine.bus
	add_child(_pack)
	_pack.play()
	_pack_pb = _pack.get_stream_playback()
	_beep_lo = _tone(520.0, 0.28, 0.5)
	_beep_hi = _tone(1040.0, 0.7, 0.55)
	_bump_sfx = _thud()
	_boost_sfx = _whoosh()
	_hop_sfx = _tone(180.0, 0.08, 0.4)
	_cheer_sfx = _crowd()
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = _engine.bus
		add_child(p)
		_sfx_players.append(p)

func _play(stream: AudioStream, db := 0.0, pitch := 1.0) -> void:
	if stream == null:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return

## Your engine, and the rest of the field as one drone that swells as they
## get close. RPM follows speed through a two-speed clutch feel.
func _feed_engine() -> void:
	if _engine_pb == null or _karts.is_empty():
		return
	var you: Dictionary = _karts[0]
	var speed := (you["vel"] as Vector3).length()
	var thr := clampf(float(you["throttle"]), 0.0, 1.0)
	var rpm := 0.25 + 0.75 * clampf(speed / MAX_SPEED, 0.0, 1.2)
	if _phase == Phase.COUNTDOWN or _phase == Phase.INTRO:
		rpm = 0.22 + thr * 0.5
	if float(you["boost"]) > 0.0:
		rpm += 0.15
	var base_hz := 38.0 + rpm * 120.0
	var load := 0.35 + thr * 0.65
	var frames := _engine_pb.get_frames_available()
	for i in frames:
		_phase_a = fmod(_phase_a + base_hz / MIX_RATE, 1.0)
		_phase_b = fmod(_phase_b + base_hz * 2.0 / MIX_RATE, 1.0)
		_phase_c = fmod(_phase_c + base_hz * 0.5 / MIX_RATE, 1.0)
		# A pulse train (firing strokes) through a crude low-pass.
		var pulse := 1.0 if _phase_a < 0.22 else -0.25
		var saw := _phase_b * 2.0 - 1.0
		_noise_lp = lerpf(_noise_lp, randf_range(-1.0, 1.0), 0.25)
		var s := (pulse * 0.5 + saw * 0.22 + (_phase_c * 2.0 - 1.0) * 0.18 + _noise_lp * 0.18 * load) * (0.45 + 0.55 * load)
		_engine_pb.push_frame(Vector2(s, s) * 0.5)
	# The pack.
	var near := INF
	for i in range(1, _karts.size()):
		near = minf(near, (_karts[i]["pos"] as Vector3).distance_to(you["pos"]))
	var pack_gain := clampf(1.0 - near / 30.0, 0.0, 1.0)
	var pack_hz := 120.0
	var frames2 := _pack_pb.get_frames_available()
	for i in frames2:
		_pack_phase = fmod(_pack_phase + pack_hz / MIX_RATE, 1.0)
		var s2 := (1.0 if _pack_phase < 0.2 else -0.25) * 0.4 + randf_range(-0.1, 0.1)
		_pack_pb.push_frame(Vector2(s2, s2) * pack_gain * 0.5)
	# Tyre squeal while you're drifting.
	if _squeal == null:
		_squeal = AudioStreamPlayer.new()
		_squeal.stream = _squeal_loop()
		_squeal.bus = _engine.bus
		_squeal.volume_db = -80.0
		add_child(_squeal)
		_squeal.play()
	var drifting := int(you["drift"]) != 0
	_squeal.volume_db = lerpf(_squeal.volume_db, -14.0 if drifting else -60.0, 0.15)

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(MIX_RATE)
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

func _tone(hz: float, secs: float, vol: float) -> AudioStreamWAV:
	var n := int(secs * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := i / MIX_RATE
		var env := minf(1.0, t / 0.005) * minf(1.0, (secs - t) / 0.04)
		s[i] = (sin(TAU * hz * t) * 0.8 + sin(TAU * hz * 2.0 * t) * 0.2) * env * vol
	return _wav(s)

func _thud() -> AudioStreamWAV:
	var n := int(0.25 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := i / MIX_RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)
		s[i] = (lp * 0.8 + sin(TAU * 70.0 * t) * 0.6) * exp(-t * 18.0)
	return _wav(s)

func _whoosh() -> AudioStreamWAV:
	var n := int(0.9 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := i / MIX_RATE
		var cutoff := lerpf(0.05, 0.5, minf(1.0, t / 0.15)) * exp(-t * 1.5)
		lp = lerpf(lp, randf_range(-1.0, 1.0), cutoff)
		s[i] = (lp * 1.4 + sin(TAU * (90.0 + t * 160.0) * t) * 0.25) * minf(1.0, t / 0.02) * exp(-t * 2.2)
	return _wav(s)

func _crowd() -> AudioStreamWAV:
	var n := int(2.5 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := i / MIX_RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.3)
		lp2 = lerpf(lp2, lp, 0.3)
		var swell := minf(1.0, t / 0.3) * minf(1.0, (2.5 - t) / 1.2)
		var wobble := 0.75 + 0.25 * sin(TAU * 3.1 * t) * sin(TAU * 1.3 * t)
		s[i] = (lp - lp2) * 2.2 * swell * wobble
	return _wav(s)

func _squeal_loop() -> AudioStreamWAV:
	var n := int(0.5 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := i / MIX_RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.6)
		s[i] = (sin(TAU * (1450.0 + 60.0 * sin(TAU * 7.0 * t)) * t) * 0.25 + lp * 0.12) * 0.6
	return _wav(s, true)
