extends Node3D
## GHETTO WARS' SET: what the block looks like when two crews are at it. World/ZombieBlock.gd adds
## this over the Dead Block's arena, only when ZombieMode.gangs is set; story mode and the zombie
## mode never see any of it. All of it sits on the existing block (Main Street, the alleys, the lot):
##
##   the pill corner     a stoop, crates, a lookout chair, a fire barrel, a table of product, the
##                       Eastside Kings' paint -- on the sidewalk by the alley mouth (CORNER)
##   burning cars        flames, smoke, a flickering light, a heat shimmer where the screen is worth it
##   the street's wear   smashed shop windows and their glass, overturned bins, trash, needles, rats,
##                       streetlights shot out (the corner's first)
##   crew graffiti       a decal pool on the shop fronts: the Kings' crowns, and as the Dock Boys gain
##                       ground each is crossed out and painted over with their anchor (set_wave())
##   the overdosed       people slumped in doorways, still, with no collision at all: not targetable, not
##                       harmable, bullets go through; more of them in TAINTED
##   the helicopter      world/ghetto/GhettoHeli.gd: circles between waves, a searchlight, finds you in THE BUST
##   the drive-by        drive_by(path_id): a car at speed down a path, muzzle flashes at its windows;
##                       drive_by_finished when it is gone (world/ghetto/GhettoVehicles.gd)
##   THE BUST            police cars with lightbars on a wet street, a SWAT van, tape, the getaway car at
##                       the lot's exit
##   moods               a tint on the night's fog and ambient light per chapter, over whatever the base
##                       night is (it is re-read when something else changes it)
##   pickups             pill bottles, stash bags, cash rolls and the burst when you take one
##
## The core (GhettoMode: wave_started, wave_cleared, enemy_killed, player_downed) and the story
## (GhettoStory: chapter_started, beat) are found by their signals (attach() does it by hand) and
## answered; with neither there, the set stands and can be driven by set_wave() / set_chapter().
## Hard lines: the crews' marks are our own (a crown, an anchor); no brand, place or hate symbol; the
## overdosed are people, not props: nothing about them is a joke.

signal drive_by_started(path_id: String, car: Node3D)
signal drive_by_finished(path_id: String)
signal territory_changed(stage_points: int)
signal chapter_dressed(chapter: String)
signal searchlight_found_player
signal pickup_collected(kind: String, at: Vector3)

const CarPaint := preload("res://world/CarPaint.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const Mat := preload("res://world/ghetto/GhettoMat.gd")
const HeliScript := preload("res://world/ghetto/GhettoHeli.gd")
const LaundromatScript := preload("res://world/ghetto/GhettoLaundromat.gd")
const VehiclesScript := preload("res://world/ghetto/GhettoVehicles.gd")
const MarkersScript := preload("res://world/ghetto/GhettoMarkers.gd")
const SouthScript := preload("res://world/ghetto/GhettoSouth.gd")
const HEAT_SHADER := preload("res://assets/shaders/ghetto_heat.gdshader")
const TEX := "res://assets/ghetto/"
const SFX_DIR := "res://assets/sfx/ghetto/"
const POLY := "res://assets/polyhaven/%s/%s.gltf"

const CHAPTERS := ["THE CORNER", "STASH RUN", "THE SNITCH", "TAINTED", "THE BUST"]

## The pill corner: the sidewalk by the alley mouth between the liquor store and the supermarket.
const CORNER := Vector3(13.6, 0.0, -3.1)
## Main Street's north wall (the shop fronts), the face the graffiti goes on.
const WALL_Z := -4.5

# --- Pools and caps (the smoke test reads these) -------------------------------------
const FIRE_MAX := 4
const PICKUP_MAX := 14
const BURST_POOL := 6
const OD_BASE := 3
const GRAFFITI_POOL := 32

var city: Node3D
var heli: Node3D
var vehicles: Node
var laundromat: Node3D
var markers: Node3D
var south: Node3D
var raid_active := false
var ending := ""
var mode: Object
var story: Object
var chapter := ""
var wave := 0
var wave_clear := false

var _env: Environment
var _rng := RandomNumberGenerator.new()
var _fires: Array = []                 # [light, seconds to next jump, factor]
var _fire_nodes: Array[Node3D] = []
var _burning_cars: Array[StaticBody3D] = []
var dead_lamps: Array[Light3D] = []
var _window_decals: Array[Decal] = []
var bins: Array[Node3D] = []
var litter_count := 0
var rats: Array[Node3D] = []
var ods: Array[Node3D] = []            # every overdosed person, base ones visible
var _od_specs: Array = []
var corner_root: Node3D
var corner_props: Array[Node3D] = []

# --- Graffiti ----------------------------------------------------------------------
## One entry per contested wall spot: {"x", "y", "kings": Decal, "over": Decal, "stage": 0..2, "word": bool}.
var slots: Array[Dictionary] = []
var stage_points := 0
var _reveals: Array = []               # [decal, seconds in, target alpha]
var decal_count := 0

# --- Pickups -----------------------------------------------------------------------
var _pickups: Array[Node3D] = []
var _bursts: Array[GPUParticles3D] = []
var _flash: Array[OmniLight3D] = []
var _pops: Array[AudioStreamPlayer3D] = []
var _burst_i := 0
var _t := 0.0

# --- Mood ---------------------------------------------------------------------------
const MOODS := {
	"THE CORNER": [Color(1.0, 0.6, 0.28), 0.2, 1.0],
	"STASH RUN": [Color(0.35, 0.55, 1.0), 0.22, 0.9],
	"THE SNITCH": [Color(0.4, 0.95, 0.5), 0.2, 1.25],
	"TAINTED": [Color(0.7, 0.28, 0.95), 0.32, 1.2],
	"THE BUST": [Color(0.45, 0.5, 0.9), 0.16, 0.85],
}
var _tint := Color(1, 1, 1)
var _tint_w := 0.0
var _dens := 1.0
var _base_fog := Color.BLACK
var _base_amb := Color.BLACK
var _base_dens := 0.05
var _w_fog := Color.BLACK
var _w_amb := Color.BLACK
var _w_dens := 0.0
var _mood_tween: Tween
var _mood_from := [Color(1, 1, 1), 0.0, 1.0]

## Whether this run is Ghetto Wars: the set is built for nothing else.
static func wanted() -> bool:
	var zm = Engine.get_main_loop().root.get_node_or_null("ZombieMode")
	return zm != null and bool(zm.get("gangs")) and bool(zm.get("active"))

func _ready() -> void:
	name = "GhettoSet"
	add_to_group("ghetto_set")
	if city == null:
		city = get_parent() as Node3D
	_env = city.get("_env") as Environment
	_rng.seed = 1812
	_build_corner()
	_build_burning_cars()
	_build_windows()
	_build_litter()
	_build_lamps()
	_build_graffiti()
	_build_crew_tags()
	_build_ods()
	_build_pickup_pools()
	laundromat = LaundromatScript.new()
	laundromat.name = "Laundromat"
	laundromat.set("set_node", self)
	add_child(laundromat)
	heli = HeliScript.new()
	heli.name = "Helicopter"
	heli.set("set_node", self)
	add_child(heli)
	vehicles = VehiclesScript.new()
	vehicles.name = "Vehicles"
	vehicles.set("set_node", self)
	add_child(vehicles)
	markers = MarkersScript.new()
	markers.name = "Markers"
	add_child(markers)
	south = SouthScript.new()
	south.set("set_node", self)
	add_child(south)
	_build_far_sirens()
	_build_ambience()
	_dress_night()
	_capture_base()
	_find_hooks()
	set_chapter("THE CORNER")

# --- Shared builders ---------------------------------------------------------------------

static func mat(color: Color, rough := 0.85, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	return Mat.mat(color, rough, metal, glow)

static func box(parent: Node, size: Vector3, pos: Vector3, m: Material, yaw_deg := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	return mi

static func cyl(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	return mi

func _model(path_name: String, parent: Node, pos: Vector3, yaw_deg := 0.0, scale := 1.0) -> Node3D:
	var path := POLY % [path_name, path_name]
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * scale
	return n

func _solid(parent: Node, size: Vector3, pos: Vector3, yaw_deg := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	var s := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	s.shape = bs
	b.add_child(s)
	parent.add_child(b)
	b.position = pos
	b.rotation_degrees.y = yaw_deg
	return b

func _sound(stream_name: String, pos: Vector3, vol := 0.0, pitch := 1.0, max_d := 60.0) -> void:
	var path := stream_name if stream_name.begins_with("res://") else SFX_DIR + stream_name + ".wav"
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.volume_db = vol
	p.pitch_scale = pitch
	p.max_distance = max_d
	p.unit_size = 8.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

# --- Fire -----------------------------------------------------------------------------

static var _flame_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D

static func _radial(c0: Color, c1: Color) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	tex.gradient = g
	return tex

static func flame_material() -> StandardMaterial3D:
	if _flame_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _radial(Color(1.0, 0.82, 0.38, 1.0), Color(0.95, 0.22, 0.0, 0.0))
		_flame_mat = m
	return _flame_mat

static func smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _radial(Color(0.2, 0.2, 0.21, 0.55), Color(0.1, 0.1, 0.11, 0.0))
		_smoke_mat = m
	return _smoke_mat

func _particles(amount: int, life: float, v: Vector2, spread: float, grav: Vector3, scale: Vector2, radius: float, quad: Vector2, m: Material, ramp: Gradient = null) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 9, 6))
	p.visibility_range_end = 70.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.gravity = grav
	pm.scale_min = scale.x
	pm.scale_max = scale.y
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 1.0 if m == _smoke_mat else 0.05))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	if ramp:
		var gt := GradientTexture1D.new()
		gt.gradient = ramp
		pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	q.material = m
	p.draw_pass_1 = q
	return p

## A thin exhaust haze at `pos` under `parent` (an idling car).
func make_exhaust(parent: Node, pos: Vector3) -> Node3D:
	smoke_material()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.2, Color(1, 1, 1, 0.55))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var sm := _particles(8, 2.4, Vector2(0.4, 0.8), 18.0, Vector3(-0.5, 0.35, 0), Vector2(0.3, 0.7), 0.05, Vector2(0.5, 0.5), _smoke_mat, ramp)
	sm.name = "Exhaust"
	parent.add_child(sm)
	sm.position = pos
	return sm

## Flames, smoke and a flickering light at `pos`: `size` 1 is a barrel, 2 a car.
func make_fire(parent: Node, pos: Vector3, size := 1.0, smoke := true, light_range := 8.0) -> Node3D:
	var fire := Node3D.new()
	fire.name = "Fire"
	parent.add_child(fire)
	fire.position = pos
	var fl := _particles(int(10 + 8 * size), 0.85, Vector2(0.7, 1.4), 16.0, Vector3(0, 0.7, 0), Vector2(0.55, 1.0), 0.2 * size, Vector2(0.6, 0.78) * size, flame_material())
	fl.name = "Flames"
	fire.add_child(fl)
	if smoke:
		smoke_material()
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.0))
		ramp.add_point(0.15, Color(1, 1, 1, 1.0))
		ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
		var sm := _particles(int(7 + 4 * size), 3.6, Vector2(1.0, 1.7), 10.0, Vector3(0.25, 0.9, 0), Vector2(1.2, 2.0) * size, 0.3 * size, Vector2(1.4, 1.4) * size, _smoke_mat, ramp)
		sm.name = "Smoke"
		sm.position.y = 0.5 * size
		sm.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 14, 10))
		fire.add_child(sm)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.48, 0.16)
	light.light_energy = 2.4 * size
	light.omni_range = light_range * (0.8 + 0.3 * size)
	light.shadow_enabled = false
	light.position.y = 1.0 * size
	fire.add_child(light)
	_fires.append([light, randf_range(0.05, 0.2), 1.0, light.light_energy])
	_fire_nodes.append(fire)
	# The fire crackles: a car's loud and carries, a barrel's low (the same bed, pitched and quietened).
	var crackle := Mat.loop_player(fire, SFX_DIR + "car_fire_loop.wav", Vector3(0, 0.6, 0), -3.0 if size > 1.5 else -9.0, 42.0 if size > 1.5 else 16.0, 6.0 if size > 1.5 else 3.0)
	if crackle:
		crackle.name = "Crackle"
		crackle.pitch_scale = 1.0 if size > 1.5 else 1.18
		crackle.seek(_rng.randf_range(0.0, 10.0))
	return fire

# --- The pill corner ----------------------------------------------------------------

func _build_corner() -> void:
	corner_root = Node3D.new()
	corner_root.name = "PillCorner"
	add_child(corner_root)
	var gold := mat(Color(0.93, 0.74, 0.2), 0.55, 0.3)
	var purple := mat(Color(0.34, 0.12, 0.5), 0.7)
	var concrete := mat(Color(0.36, 0.35, 0.34), 0.95)
	# The stoop: three steps against the supermarket's front.
	var stoop := Node3D.new()
	stoop.name = "Stoop"
	corner_root.add_child(stoop)
	box(stoop, Vector3(1.9, 0.15, 0.85), Vector3(16.0, 0.075, WALL_Z + 0.425), concrete)
	box(stoop, Vector3(1.9, 0.30, 0.57), Vector3(16.0, 0.15, WALL_Z + 0.285), concrete)
	box(stoop, Vector3(1.9, 0.45, 0.29), Vector3(16.0, 0.225, WALL_Z + 0.145), concrete)
	box(stoop, Vector3(1.9, 0.02, 0.06), Vector3(16.0, 0.16, WALL_Z + 0.85), purple)   # a painted edge
	_solid(stoop, Vector3(1.9, 0.45, 0.85), Vector3(16.0, 0.225, WALL_Z + 0.425))
	corner_props.append(stoop)
	# Crates by the liquor store, one on the other.
	var crates := Node3D.new()
	crates.name = "Crates"
	corner_root.add_child(crates)
	_model("wooden_crate_01", crates, Vector3(11.5, 0, -4.05), 8.0, 1.0)
	_model("wooden_crate_02", crates, Vector3(12.35, 0, -4.1), -14.0, 1.0)
	var top := _model("wooden_crate_01", crates, Vector3(11.85, 0.62, -4.05), 31.0, 0.85)
	if top == null:
		box(crates, Vector3(0.7, 0.7, 0.7), Vector3(11.8, 0.35, -4.05), mat(Color(0.4, 0.28, 0.16)))
	_solid(crates, Vector3(1.6, 0.8, 0.7), Vector3(11.95, 0.4, -4.05))
	box(crates, Vector3(1.4, 0.07, 0.01), Vector3(11.95, 0.5, -3.69), purple)
	_model("boombox", crates, Vector3(12.35, 0.62, -4.1), 190.0, 1.3)
	corner_props.append(crates)
	# The lookout's chair, facing up the street, a can on the pavement.
	var chair := Node3D.new()
	chair.name = "LookoutChair"
	corner_root.add_child(chair)
	chair.position = Vector3(12.9, 0, -2.75)
	chair.rotation_degrees.y = 20.0
	var cm := _model("plastic_monobloc_chair_01", chair, Vector3.ZERO, 0.0, 1.0)
	if cm:
		for mi in cm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = purple
	else:
		box(chair, Vector3(0.45, 0.05, 0.45), Vector3(0, 0.45, 0), purple)
		box(chair, Vector3(0.45, 0.45, 0.04), Vector3(0, 0.7, -0.22), purple)
	_model("can_rusted", chair, Vector3(0.6, 0, 0.2), 40.0, 1.0)
	corner_props.append(chair)
	# A fire barrel for warmth, and the only light the corner has left.
	var barrel := Node3D.new()
	barrel.name = "FireBarrel"
	corner_root.add_child(barrel)
	barrel.position = Vector3(14.6, 0, -2.5)
	var bm := _model("barrel_stove", barrel, Vector3.ZERO, 0.0, 1.2)
	if bm == null:
		cyl(barrel, 0.3, 0.3, 0.9, Vector3(0, 0.45, 0), mat(Color(0.2, 0.15, 0.12), 0.7, 0.6))
	make_fire(barrel, Vector3(0, 0.95, 0), 0.8, false, 10.0)
	corner_props.append(barrel)
	# The table: product laid out, a cash roll or two.
	var table := Node3D.new()
	table.name = "Table"
	corner_root.add_child(table)
	table.position = Vector3(13.4, 0, -3.95)
	if _model("painted_wooden_table", table, Vector3.ZERO, 0.0, 0.9) == null:
		box(table, Vector3(1.1, 0.05, 0.6), Vector3(0, 0.75, 0), mat(Color(0.5, 0.4, 0.3)))
	for i in 4:
		var b := make_pickup_model("pills")
		table.add_child(b)
		b.position = Vector3(-0.35 + i * 0.13, 0.82, -0.05 + (i % 2) * 0.08)
		b.rotation_degrees.y = i * 50.0
	for i in 2:
		var s := make_pickup_model("stash")
		table.add_child(s)
		s.position = Vector3(0.2 + i * 0.2, 0.83, 0.06)
	for i in 3:
		var c := make_pickup_model("cash")
		table.add_child(c)
		c.position = Vector3(-0.1 + i * 0.1, 0.83, 0.18)
		c.rotation_degrees.z = 90.0 if i == 1 else 0.0
	corner_props.append(table)
	# The crew's colours: the crown and the name over the stoop, a painted kerb.
	var crown := _wall_decal(TEX + "tag_kings_crown.png", Vector3(16.0, 2.1, WALL_Z), Vector2(1.9, 1.9), 0.0, true)
	crown.name = "CornerCrown"
	var word := _wall_decal(TEX + "tag_kings_word.png", Vector3(13.6, 1.35, WALL_Z), Vector2(3.0, 1.1), -2.0, true)
	word.name = "CornerName"
	var kerb := Decal.new()
	kerb.texture_albedo = _solid_tex(Color(0.45, 0.16, 0.65, 0.85))
	kerb.size = Vector3(7.0, 0.5, 0.2)
	kerb.position = Vector3(14.0, 0.0, -1.62)
	corner_root.add_child(kerb)
	# The kerb's pale sodium glow so the corner reads from down the street even with its lamp shot out.
	var glow := OmniLight3D.new()
	glow.name = "CornerGlow"
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 1.1
	glow.omni_range = 9.0
	glow.shadow_enabled = false
	glow.position = Vector3(13.8, 2.6, -2.6)
	corner_root.add_child(glow)
	_fires.append([glow, 0.1, 1.0, glow.light_energy])

static func _solid_tex(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

## A decal on a wall facing +Z (Main Street's shop fronts), `at` the point on the wall's face.
func _wall_decal(tex_path: String, at: Vector3, size: Vector2, roll_deg := 0.0, fade := false) -> Decal:
	var d := Decal.new()
	if ResourceLoader.exists(tex_path):
		d.texture_albedo = load(tex_path)
	d.albedo_mix = 1.0
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	var depth := 0.7
	d.size = Vector3(size.x, depth, size.y)
	var normal := Vector3.BACK
	var down := Vector3.DOWN.rotated(normal, deg_to_rad(roll_deg))
	d.basis = Basis(normal.cross(down), normal, down)
	d.position = at - normal * (depth / 2.0 - 0.05)
	if fade:
		d.distance_fade_enabled = true
		d.distance_fade_begin = 55.0
		d.distance_fade_length = 25.0
	add_child(d)
	decal_count += 1
	return d

# --- Burning cars ---------------------------------------------------------------------

## [model, position, yaw]. In the parking lane, angled, where they cover and don't close the street.
const BURNERS := [
	["wreck_burnt_b", Vector3(-1.2, 0, 3.3), 24.0],
	["wreck_suv", Vector3(30.5, 0, 3.2), -33.0],
]

func _build_burning_cars() -> void:
	for b in BURNERS:
		var body := StaticBody3D.new()
		body.name = "Burner_%s" % b[0]
		add_child(body)
		body.position = b[1]
		body.rotation_degrees.y = b[2]
		var model := (load("res://assets/cars/%s.glb" % b[0]) as PackedScene).instantiate() as Node3D
		model.name = "Model"
		body.add_child(model)
		CarPaint.limit_range(model, 90.0)
		var box_aabb := CarPaint.bounds(model)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(box_aabb.size.x, box_aabb.size.y, maxf(box_aabb.size.z - 0.2, 1.0))
		shape.shape = bs
		shape.position = Vector3(0, box_aabb.size.y / 2.0, 0)
		body.add_child(shape)
		body.add_to_group("wrecks")
		_burning(body, box_aabb)
	# One of the Dead Block's own wrecks at the east end burns too.
	for w in get_tree().get_nodes_in_group("wrecks"):
		if w is StaticBody3D and (w as Node3D).global_position.distance_to(Vector3(63.0, 0, 2.9)) < 1.5 and not _burning_cars.has(w):
			_burning(w as StaticBody3D, CarPaint.bounds(w.get_node("Model")))
			break

func _burning(body: StaticBody3D, aabb: AABB) -> void:
	if _burning_cars.size() >= FIRE_MAX:
		return
	_burning_cars.append(body)
	var top := Vector3(aabb.position.x + aabb.size.x * 0.45, aabb.size.y * 0.8, aabb.position.z + aabb.size.z * 0.5)
	make_fire(body, top, 2.0, true, 11.0)
	var g := _graphics_preset()
	if g >= 1:
		var heat := MeshInstance3D.new()
		heat.name = "HeatShimmer"
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 4.0)
		heat.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = HEAT_SHADER
		heat.material_override = sm
		heat.position = top + Vector3(0, 2.6, 0)
		heat.visibility_range_end = 45.0
		heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(heat)

func _graphics_preset() -> int:
	var g := get_tree().root.get_node_or_null("Graphics")
	return int(g.get("preset")) if g else 1

# --- The street's wear -------------------------------------------------------------------

## Smashed shop windows: [x] on the walk-in shops' glass (Facades.shop_geometry), the glass on the pavement.
const WINDOWS := [2.1, 4.9, 9.05, 11.95]

func _build_windows() -> void:
	for x: float in WINDOWS:
		var d := _wall_decal(TEX + "window_smash.png", Vector3(x, 1.45, WALL_Z - 0.05), Vector2(1.5, 1.5), _rng.randf_range(-6, 6), true)
		_window_decals.append(d)
		var shards := Decal.new()
		shards.texture_albedo = load(TEX + "glass_shards.png")
		shards.size = Vector3(2.6, 0.4, 1.8)
		shards.position = Vector3(x + _rng.randf_range(-0.2, 0.2), 0.0, -3.7)
		shards.rotation_degrees.y = _rng.randf_range(-12, 12)
		shards.distance_fade_enabled = true
		shards.distance_fade_begin = 40.0
		shards.distance_fade_length = 20.0
		add_child(shards)
		decal_count += 1

static var _syringe: ArrayMesh
static var _litter_mesh: ArrayMesh

## Needles, caps, trash bags and bins knocked over.
func _build_litter() -> void:
	# Overturned bins with their spill: [x, z, yaw].
	for b in [[-6.2, -3.7, 70.0], [19.2, -3.5, -20.0], [-27.5, -3.6, 140.0], [21.4, -6.6, 15.0], [14.5, -9.0, 100.0]]:
		var bin := Node3D.new()
		bin.name = "OverturnedBin"
		add_child(bin)
		bin.position = Vector3(b[0], 0, b[1])
		bin.rotation_degrees.y = b[2]
		var can := _model("metal_trash_can", bin, Vector3(0, 0.38, 0), 0.0, 1.0)
		if can == null:
			can = cyl(bin, 0.3, 0.28, 0.8, Vector3(0, 0.38, 0), mat(Color(0.25, 0.27, 0.26), 0.6, 0.5))
		can.rotation_degrees.z = 88.0
		for i in 3:
			_model("trashbag", bin, Vector3(0.7 + i * 0.35, 0, _rng.randf_range(-0.45, 0.45)), _rng.randf_range(0, 360), 0.8)
		bins.append(bin)
	# Rats where the trash is.
	for r in [Vector3(-6.0, 0, -3.4), Vector3(19.6, 0, -3.2)]:
		var rat := _model("street_rat", self, r, _rng.randf_range(0, 360), 1.0)
		if rat:
			rats.append(rat)
	# Needles and other litter on the sidewalk, as two MultiMeshes.
	var syringes := _litter_multimesh("Needles", _syringe_mesh(), 48)
	var junk := _litter_multimesh("Litter", _junk_mesh(), 60)
	# More of it round the corner and the doorways.
	for i in 48:
		var around_corner := i < 26
		var x := _rng.randfn(14.0, 3.0) if around_corner else _rng.randf_range(-30.0, 28.0)
		var z := _rng.randf_range(-4.3, -1.8)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)), Vector3(x, 0.012, z))
		syringes.multimesh.set_instance_transform(i, t)
		litter_count += 1
	for i in 60:
		var x := _rng.randfn(14.0, 5.0) if i < 30 else _rng.randf_range(-32.0, 29.0)
		var z := _rng.randf_range(-4.4, -1.6)
		var b := Basis(Vector3.UP, _rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, _rng.randf_range(0, 0.4))
		junk.multimesh.set_instance_transform(i, Transform3D(b, Vector3(x, 0.01, z)))
		litter_count += 1

func _litter_multimesh(nm: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.visibility_range_end = 40.0
	inst.visibility_range_end_margin = 6.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(inst)
	return inst

## A used syringe lying on its side: a barrel and an orange cap, as one mesh with two surfaces.
func _syringe_mesh() -> ArrayMesh:
	if _syringe == null:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.009
		barrel.bottom_radius = 0.009
		barrel.height = 0.1
		barrel.radial_segments = 6
		barrel.rings = 1
		var cap := CylinderMesh.new()
		cap.top_radius = 0.006
		cap.bottom_radius = 0.01
		cap.height = 0.025
		cap.radial_segments = 6
		cap.rings = 1
		var lay := Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO)
		var out := ArrayMesh.new()
		_add_part(out, barrel, lay, mat(Color(0.8, 0.82, 0.78), 0.3))
		_add_part(out, cap, Transform3D(lay.basis, lay.basis * Vector3(0, 0.062, 0)), mat(Color(0.95, 0.45, 0.1), 0.5, 0.0, 0.3))
		_syringe = out
	return _syringe

static func _add_part(into: ArrayMesh, src: Mesh, xf: Transform3D, m: Material) -> void:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		normals[i] = xf.basis * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	into.surface_set_material(into.get_surface_count() - 1, m)

func _junk_mesh() -> ArrayMesh:
	if _litter_mesh == null:
		# A crumpled bag / wrapper: a flat low-poly slab, grimy white.
		var q := BoxMesh.new()
		q.size = Vector3(0.11, 0.012, 0.075)
		_litter_mesh = ArrayMesh.new()
		_add_part(_litter_mesh, q, Transform3D.IDENTITY, mat(Color(0.7, 0.68, 0.6), 0.9))
	return _litter_mesh

## Streetlights shot out: the one over the corner first, then every third.
func _build_lamps() -> void:
	var zb := city.get_node_or_null("ZombieBlock")
	var flick: Array = zb.get("_flickering") if zb else []
	var lamps: Array = []
	for entry in city.get("_night_lights"):
		var l := entry[0] as Light3D
		if l.get_parent().name.begins_with("Streetlight"):
			lamps.append(entry)
	lamps.sort_custom(func(a, b): return (a[0] as Node3D).global_position.distance_to(CORNER) < (b[0] as Node3D).global_position.distance_to(CORNER))
	var heads: Array = city.get("_street_lamp_heads")
	for i in lamps.size():
		if not (i == 0 or i % 3 == 1):
			continue
		var entry: Array = lamps[i]
		var light := entry[0] as Light3D
		entry[1] = 0.0
		city._set_light(entry)
		for f in flick.duplicate():
			if f[0] == light:
				flick.erase(f)
		for h in heads.duplicate():
			if (h as Node).get_parent() == light.get_parent():
				heads.erase(h)
				var hm := (h as MeshInstance3D).get_active_material(0)
				if hm is StandardMaterial3D:
					var dark := (hm as StandardMaterial3D).duplicate() as StandardMaterial3D
					dark.emission_enabled = false
					(h as MeshInstance3D).set_surface_override_material(0, dark)
		dead_lamps.append(light)

# --- Graffiti ---------------------------------------------------------------------------

## The other crews' names (all invented: KRAIT, VOLT, OXBLOOD, NOVA, HOLLOW, ZAR) where the Kings and the Dock Boys do not
## reach: the end walls, the lane behind the shops, the shutters. [tag, position, yaw (0 faces +Z, 180 faces -Z), width].
const CREW_TAGS := [
	["krait", Vector3(-27.6, 1.2, -4.5), 0.0, 1.6], ["volt", Vector3(-6.7, 0.9, -4.5), 0.0, 1.3], ["oxblood", Vector3(40.8, 1.5, -4.5), 0.0, 1.7],
	["nova", Vector3(47.9, 1.0, -4.5), 0.0, 1.3], ["hollow", Vector3(38.2, 1.1, -4.5), 0.0, 1.2], ["zar", Vector3(-45.5, 1.4, -4.5), 0.0, 1.6],
	["volt", Vector3(24.7, 1.1, -19.0), 180.0, 1.5], ["krait", Vector3(5.0, 1.3, -19.0), 180.0, 1.8], ["hollow", Vector3(-3.0, 1.0, -19.0), 180.0, 1.4],
	["nova", Vector3(40.0, 1.3, -19.0), 180.0, 1.5], ["zar", Vector3(32.8, 1.5, -19.0), 180.0, 1.7],
]
## Soot up the wall behind each burning car: [x, z of the wall, yaw].
const SOOT := [[-1.2, 4.5, 0.0], [30.5, 4.5, 0.0]]

func _build_crew_tags() -> void:
	for t in CREW_TAGS:
		var path: String = TEX + "tag_%s.png" % t[0]
		var yaw: float = t[2]
		var normal := Vector3.BACK if yaw == 0.0 else Vector3.FORWARD
		var w: float = t[3]
		var d := Decal.new()
		d.texture_albedo = load(path)
		if ResourceLoader.exists(path.replace(".png", "_n.png")):
			d.texture_normal = load(path.replace(".png", "_n.png"))
		d.albedo_mix = 0.92
		d.upper_fade = 0.05
		d.lower_fade = 0.05
		d.distance_fade_enabled = true
		d.distance_fade_begin = 50.0
		d.distance_fade_length = 20.0
		d.size = Vector3(w, 0.4, w * 0.62)
		var down := Vector3.DOWN.rotated(normal, deg_to_rad(_rng.randf_range(-5, 5)))
		d.basis = Basis(normal.cross(down), normal, down)
		var at: Vector3 = t[1]
		d.position = at - normal * 0.17
		add_child(d)
		decal_count += 1
	for sp in SOOT:
		var d := Decal.new()
		d.texture_albedo = load(TEX + "burn_soot.png")
		d.albedo_mix = 0.9
		d.size = Vector3(5.5, 0.4, 5.0)
		d.distance_fade_enabled = true
		d.distance_fade_begin = 55.0
		d.distance_fade_length = 20.0
		var normal := Vector3.BACK
		d.basis = Basis(normal.cross(Vector3.DOWN), normal, Vector3.DOWN)
		d.position = Vector3(sp[0], 2.6, sp[1] - 4.5 - 0.17)
		add_child(d)
		decal_count += 1


## The shop fronts' contested spots, from the ends towards the corner (the Dock Boys come from outside).
const TAG_X := [-30.6, -24.5, -17.5, -10.5, -3.5, 3.5, 24.5, 28.0, 10.5, 17.5, 19.2, 7.6]

func _build_graffiti() -> void:
	var xs: Array = TAG_X.duplicate()
	xs.sort_custom(func(a, b): return absf(a - CORNER.x) > absf(b - CORNER.x))
	for i in xs.size():
		var x: float = xs[i]
		var word := i % 3 == 1
		var y := _rng.randf_range(1.5, 2.2)
		var size := Vector2(2.4, 0.9) if word else Vector2(1.15, 1.15)
		var roll := _rng.randf_range(-7, 7)
		var kings := _wall_decal(TEX + ("tag_kings_word.png" if word else "tag_kings_crown.png"), Vector3(x, y, WALL_Z), size, roll, true)
		var over := _wall_decal(TEX + "tag_xout_dock.png", Vector3(x, y, WALL_Z), size * (1.0 if word else 1.15), roll, true)
		over.visible = false
		kings.name = "TagKings%d" % i
		over.name = "TagOver%d" % i
		slots.append({"x": x, "y": y, "size": size, "roll": roll, "word": word, "kings": kings, "over": over, "stage": 0})

## The enemy's ground: 0 is none, each contested spot takes two (crossed out, painted over).
func set_stage_points(p: int) -> void:
	p = clampi(p, 0, slots.size() * 2)
	if p == stage_points:
		return
	stage_points = p
	for i in slots.size():
		var s: Dictionary = slots[i]
		var want := clampi(p - 2 * i, 0, 2)
		if want == s["stage"]:
			continue
		var over := s["over"] as Decal
		var kings := s["kings"] as Decal
		s["stage"] = want
		over.visible = want > 0
		if want == 1:
			over.texture_albedo = load(TEX + "tag_xout_dock.png")
			over.size = Vector3((s["size"] as Vector2).x * (1.0 if s["word"] else 1.15), 0.7, (s["size"] as Vector2).y * (1.0 if s["word"] else 1.15))
		elif want == 2:
			over.texture_albedo = load(TEX + ("tag_dock_word.png" if s["word"] else "tag_dock_anchor.png"))
			over.size = Vector3((s["size"] as Vector2).x, 0.7, (s["size"] as Vector2).y)
			kings.visible = false
		over.modulate.a = 0.0
		_reveals.append([over, 0.0, 1.0])
		var at := Vector3(s["x"], s["y"], WALL_Z)
		if want > 0:
			_sound("spray_hiss", at, -6.0, randf_range(0.9, 1.1), 45.0)
	territory_changed.emit(stage_points)

func graffiti_stage_counts() -> Array:
	var c := [0, 0, 0]
	for s in slots:
		c[s["stage"]] += 1
	return c

## Dock Boys decals showing (crossed out or painted).
func enemy_tags() -> int:
	var n := 0
	for s in slots:
		if s["stage"] > 0:
			n += 1
	return n

## The wave started: the enemy takes a little more of the wall each wave.
func set_wave(n: int) -> void:
	wave = n
	wave_clear = false
	set_stage_points(1 + (maxi(n, 1) - 1) * 3)
	if heli:
		heli.call("set_between_waves", false)

func _on_wave_cleared(n: int) -> void:
	wave_clear = true
	if heli:
		heli.call("set_between_waves", true)

# --- The overdosed ---------------------------------------------------------------------

## [body, x, y facing (yaw degrees), tainted only]. Each sits on a doorstep against a shop front.
const OD_SPOTS := [
	["Male_Adult_09", -9.3, 0.0, false],
	["Female_Adult_05", -18.7, 0.0, false],
	["Male_Adult_13", 25.8, 0.0, false],
	["Female_Adult_09", -2.4, 0.0, true],
	["Male_Adult_17", 4.5, 0.0, true],
	["Female_Adult_03", 21.5, 0.0, true],
	["Male_Adult_05", -29.5, 0.0, true],
]
const OD_CLIP_AT := 5.0

func _build_ods() -> void:
	for i in OD_SPOTS.size():
		var spec: Array = OD_SPOTS[i]
		var root := Node3D.new()
		root.name = "Overdosed%d" % i
		add_child(root)
		root.position = Vector3(spec[1], 0, -4.15)
		root.rotation_degrees.y = float(spec[2]) + _rng.randf_range(-8, 8)
		# The step they have sat down on: a doorstep of concrete.
		var step := box(root, Vector3(1.0, 0.4, 0.5), Vector3(0, 0.2, 0.0), mat(Color(0.34, 0.33, 0.32), 0.95))
		step.name = "Step"
		root.set_meta("od", true)
		root.set_meta("tainted_only", bool(spec[3]))
		_od_specs.append(root)
		_pose_od(root, str(spec[0]), i)
		ods.append(root)
		root.visible = not bool(spec[3])
	# A candle someone left, by the first one.
	var candle := OmniLight3D.new()
	candle.name = "Candle"
	candle.light_color = Color(1.0, 0.65, 0.3)
	candle.light_energy = 0.35
	candle.omni_range = 2.5
	candle.shadow_enabled = false
	candle.position = Vector3(0.9, 0.15, 0.35)
	ods[0].add_child(candle)
	cyl(ods[0], 0.025, 0.025, 0.09, Vector3(0.9, 0.045, 0.35), mat(Color(0.9, 0.88, 0.8), 0.7))
	_fires.append([candle, 0.1, 1.0, candle.light_energy])

## Someone sitting on the step, in a still pose: the Rocketbox 'sit' clip frozen, the spine and head let go.
func _pose_od(root: Node3D, body_name: String, idx: int) -> void:
	var path := "res://assets/rocketbox/%s.glb" % body_name
	if not ResourceLoader.exists(path):
		return
	var model := CharacterCast.scene_for(path).instantiate() as Node3D
	model.name = "Body"
	root.add_child(model)
	model.position = Vector3(0, 0.4, 0.17)
	CharacterLook.apply(model, {"tint": Color(0.84, 0.8, 0.78)})
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if ap and ap.has_animation("sit"):
		ap.play("sit", 0.0)
		ap.seek(OD_CLIP_AT, true)
		ap.advance(0.0)
		ap.pause()
		_slump.call_deferred(ap, sk, idx)

func _slump(ap: AnimationPlayer, sk: Skeleton3D, idx: int) -> void:
	if not is_instance_valid(sk) or not is_instance_valid(ap):
		return
	await get_tree().process_frame
	if not is_instance_valid(sk):
		return
	ap.active = false
	var side := -1.0 if idx % 2 == 0 else 1.0
	_bend(sk, "Bip01 Spine1", Vector3.RIGHT, 0.32)
	_bend(sk, "Bip01 Spine2", Vector3.RIGHT, 0.24)
	_bend(sk, "Bip01 Neck", Vector3.RIGHT, 0.4)
	_bend(sk, "Bip01 Head", Vector3.RIGHT, 0.28)
	_bend(sk, "Bip01 Head", Vector3.BACK, 0.3 * side)
	_bend(sk, "Bip01 L UpperArm", Vector3.BACK, 0.5)
	_bend(sk, "Bip01 R UpperArm", Vector3.BACK, -0.5)

## Rotates a bone about a skeleton-space axis, whatever its own orientation is.
func _bend(sk: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	var b := sk.find_bone(bone)
	if b < 0:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var gb := sk.get_bone_global_pose(b).basis
	var ng := Basis(axis, angle) * gb
	sk.set_bone_pose_rotation(b, (pg.inverse() * ng).get_rotation_quaternion())

func _show_tainted_ods(count := 99) -> void:
	for o in ods:
		if count <= 0:
			break
		if not o.visible:
			count -= 1
			o.visible = true
			o.scale = Vector3(1, 0.001, 1)
			var tw := create_tween()
			tw.tween_property(o, "scale", Vector3.ONE, 1.6).set_trans(Tween.TRANS_SINE)

func od_count() -> int:
	var n := 0
	for o in ods:
		if o.visible:
			n += 1
	return n

# --- Pickups ---------------------------------------------------------------------------

## What a pickup is made of: a pill bottle (amber, white cap and label), a stash bag (a tied pouch) or a
## roll of cash (a banded roll). At table size; spawn_pickup() scales it up to be seen.
func make_pickup_model(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Model_" + kind
	match kind:
		"pills":
			var amber := mat(Color(0.8, 0.4, 0.06, 0.82), 0.12, 0.0, 0.25)
			cyl(n, 0.034, 0.034, 0.095, Vector3(0, 0.048, 0), amber)
			cyl(n, 0.037, 0.037, 0.022, Vector3(0, 0.105, 0), mat(Color(0.93, 0.93, 0.9), 0.5))
			cyl(n, 0.0345, 0.0345, 0.04, Vector3(0, 0.05, 0), mat(Color(0.95, 0.95, 0.92), 0.8))
		"stash":
			var bag := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.06
			sp.height = 0.1
			sp.radial_segments = 10
			sp.rings = 6
			bag.mesh = sp
			bag.material_override = mat(Color(0.09, 0.08, 0.08), 0.5, 0.1)
			bag.position.y = 0.05
			n.add_child(bag)
			cyl(n, 0.012, 0.03, 0.05, Vector3(0, 0.12, 0), mat(Color(0.09, 0.08, 0.08), 0.5, 0.1))
			cyl(n, 0.02, 0.02, 0.012, Vector3(0, 0.1, 0), mat(Color(0.93, 0.74, 0.2), 0.4, 0.5, 0.3))
		_:
			cyl(n, 0.04, 0.04, 0.07, Vector3(0, 0.04, 0), mat(Color(0.5, 0.64, 0.46), 0.85))
			cyl(n, 0.0425, 0.0425, 0.02, Vector3(0, 0.04, 0), mat(Color(0.8, 0.72, 0.52), 0.9))
	return n

const PICKUP_COLORS := {"pills": Color(1.0, 0.6, 0.15), "stash": Color(0.95, 0.78, 0.25), "cash": Color(0.55, 0.95, 0.5)}

## A pickup floating at `pos`: the thing big enough to see, a ring, a small light; it bobs and turns.
func spawn_pickup(kind: String, pos: Vector3) -> Node3D:
	var p: Node3D
	if _pickups.size() >= PICKUP_MAX:
		p = _pickups.pop_front()
		for c in p.get_children():
			c.queue_free()
	else:
		p = Node3D.new()
		add_child(p)
	p.name = "Pickup_" + kind
	_pickups.append(p)
	p.visible = true
	p.position = pos
	p.set_meta("kind", kind)
	p.set_meta("base_y", pos.y)
	p.set_meta("phase", randf() * TAU)
	var model := make_pickup_model(kind)
	model.scale = Vector3.ONE * 3.2
	model.position.y = -0.2
	p.add_child(model)
	var col: Color = PICKUP_COLORS.get(kind, Color.WHITE)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.3
	tm.rings = 14
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = mat(col, 0.5, 0.0, 2.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = -0.55
	p.add_child(ring)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.7
	l.omni_range = 3.5
	l.shadow_enabled = false
	p.add_child(l)
	return p

## Takes a pickup: a burst of what it is, a flash and the sound. Returns its kind.
func collect_pickup(p: Node3D) -> String:
	var kind: String = p.get_meta("kind", "cash")
	var at := p.global_position
	_pickups.erase(p)
	p.queue_free()
	_burst(at, PICKUP_COLORS.get(kind, Color.WHITE), kind)
	pickup_collected.emit(kind, at)
	return kind

func pickup_count() -> int:
	return _pickups.size()

func _build_pickup_pools() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	for i in BURST_POOL:
		var p := GPUParticles3D.new()
		p.amount = 22
		p.lifetime = 0.7
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.local_coords = false
		p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 80.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 3.5
		pm.gravity = Vector3(0, -4.0, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.0
		pm.color = Color(1, 1, 1, 1)
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.09)
		q.material = m
		p.draw_pass_1 = q
		add_child(p)
		_bursts.append(p)
	for i in 2:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 5.0
		l.shadow_enabled = false
		add_child(l)
		_flash.append(l)

func _burst(at: Vector3, col: Color, kind: String) -> void:
	var p := _bursts[_burst_i % _bursts.size()]
	var f := _flash[_burst_i % _flash.size()]
	_burst_i += 1
	p.global_position = at
	(p.process_material as ParticleProcessMaterial).color = col
	p.restart()
	p.emitting = true
	f.global_position = at
	f.light_color = col
	f.light_energy = 3.0
	_sound("pickup_pill" if kind == "pills" else "pickup_cash", at, -2.0, randf_range(0.95, 1.08), 30.0)

# --- Signals from the core and the story ----------------------------------------------------

func attach(m: Object, s: Object = null) -> void:
	if m and mode != m:
		mode = m
		if m.has_signal("wave_started"):
			m.connect("wave_started", set_wave)
		if m.has_signal("wave_cleared"):
			m.connect("wave_cleared", _on_wave_cleared)
		if m.has_signal("player_downed"):
			m.connect("player_downed", _on_player_downed)
	if s and story != s:
		story = s
		if s.has_signal("chapter_started"):
			s.connect("chapter_started", set_chapter)
		if s.has_signal("beat"):
			s.connect("beat", on_story_beat)
		if s.has_signal("story_finished"):
			s.connect("story_finished", on_story_ending)
		if s.has_signal("raid_started"):
			s.connect("raid_started", func(): on_story_beat("raid_start"))

func _on_player_downed() -> void:
	if heli:
		heli.call("search_player", false)

func _find_hooks() -> void:
	var seen: Array[Node] = []
	var roots: Array[Node] = [city, get_tree().root]
	var zb := city.get_node_or_null("ZombieBlock")
	if zb:
		roots.append(zb)
	for r in roots:
		for c in r.get_children():
			seen.append(c)
	for c in seen:
		if c == self:
			continue
		if mode == null and c.has_signal("wave_started") and c.has_signal("wave_cleared"):
			attach(c, null)
		if story == null and c.has_signal("chapter_started"):
			attach(null, c)

## Whatever the story calls its chapters (a name, an index), as one of CHAPTERS.
static func chapter_key(id: Variant) -> String:
	if typeof(id) == TYPE_INT:
		return CHAPTERS[clampi(int(id), 0, CHAPTERS.size() - 1)]
	var s := str(id).to_upper().replace("_", " ")
	for c in CHAPTERS:
		var short := String(c).replace("THE ", "").split(" ")[0]
		if s == c or (s.length() >= 4 and (c.find(s) >= 0 or s.find(short) >= 0)):
			return c
	return ""

func set_chapter(id: Variant) -> void:
	var key := chapter_key(id)
	if key == "":
		return
	chapter = key
	ending = ""
	_mood_to(key)
	match key:
		"STASH RUN":
			laundromat.call("stash_pulse", true)
		"TAINTED":
			_show_tainted_ods()
		"THE BUST":
			on_story_beat("raid_start")
	if key != "STASH RUN":
		laundromat.call("stash_pulse", false)
	if key != "THE BUST":
		heli.call("search_player", false)
		if raid_active:
			_raid_off()
	chapter_dressed.emit(key)

## The story's beats (fx/GhettoStory.gd): cops_circling, stash_pressure, drive_by, snitch_revealed, ods_street,
## ods_more, raid_start, heli, flushed, escaped, busted, batch_dumped, batch_sold. The story calls this through the
## `beat` signal (attach() connects it); anything else may call it directly.
func on_story_beat(id: Variant) -> void:
	var s := str(id).to_lower()
	match s:
		"cops_circling", "heli":
			heli.call("set_between_waves", true)
			_sirens(1)
		"drive_by":
			drive_by(["main_east", "main_west", "swerve"][_rng.randi() % 3])
		"ods_street":
			_show_tainted_ods(2)
		"ods_more":
			_show_tainted_ods(99)
		"raid_start":
			if raid_active:
				return
			raid_active = true
			laundromat.call("raid", true)
			vehicles.call("build_bust")
			heli.call("set_between_waves", true)
			heli.call("search_player", true)
			_sirens(2)
			_power_cut(true)
			_mood_set(Color(0.45, 0.5, 1.0), 0.3, 0.9, 2.5)
		"flushed":
			if markers.has("sink"):
				markers.call("clear", "sink")
			_sound("res://assets/sfx/ghetto/chapter_hit.ogg", laundromat.call("point", "sink"), 0.0, 0.8, 30.0)
		"escaped":
			vehicles.call("getaway_leave")
			markers.call("clear_all")
		"busted":
			heli.call("search_player", true)
			markers.call("clear_all")
		"snitch_revealed":
			_mood_flash(Color(0.4, 1.0, 0.5))
		"stash_pressure":
			_mood_flash(Color(1.0, 0.5, 0.2))
		"batch_sold":
			for k in ["cash", "cash", "stash"]:
				spawn_pickup(k, CORNER + Vector3(_rng.randf_range(-0.5, 0.5), 1.1, _rng.randf_range(-0.2, 0.2)))
		"batch_dumped":
			_mood_flash(Color(0.5, 0.8, 1.0))

## Back to an ordinary night (a new run, a chapter before THE BUST).
func _raid_off() -> void:
	raid_active = false
	laundromat.call("raid", false)
	_power_cut(false)
	_sirens(0)

## The story is over (`story_finished(ending)`: "clean_dumped", "bag_sold", "busted_sold"...): the set takes
## the ending's tone. Clean: dawn comes up and the police leave. Bag: dusk, the sirens still on you. Busted: floodlit,
## cuffs, the searchlight stays.
func on_story_ending(key: Variant) -> void:
	ending = str(key)
	markers.call("clear_all")
	laundromat.call("stash_pulse", false)
	if ending.begins_with("clean"):
		_mood_set(Color(1.0, 0.8, 0.55), 0.38, 0.55, 6.0)
		heli.call("search_player", false)
		heli.call("set_between_waves", false)
		_sirens(0)
		_power_cut(false)
	elif ending.begins_with("bag"):
		_mood_set(Color(1.0, 0.5, 0.2), 0.32, 0.8, 4.0)
		_sirens(1)
	else:
		_mood_set(Color(0.6, 0.7, 1.0), 0.42, 0.7, 2.0)
		heli.call("search_player", true)
		_sirens(2)

# --- Sirens, the blackout, objective markers -----------------------------------------------------

var _far_sirens: Array = []     # [AudioStreamPlayer3D, OmniLight3D, phase]
var _siren_level := 0
var _lamp_saved: Array = []     # [entry, energy]
var _obj_t := 0.0

## The night the set stands in: a cool fill from the other side of the moon (so the facades have a lit edge and a dark
## one, as in the references), window glass that is moonlit rather than black, the parked bakery truck that sat on the
## burning SUV taken off the street.
func _dress_night() -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "NightFill"
	fill.light_color = Color(0.42, 0.52, 0.95)
	fill.light_energy = 0.2
	fill.shadow_enabled = false
	add_child(fill)
	fill.rotation_degrees = Vector3(-38.0, 205.0, 0.0)
	fill.light_cull_mask = 1
	var fac := city.get_node_or_null("Facades")
	if fac:
		var glass = fac.get("_window_glass")
		if glass is StandardMaterial3D:
			var g := glass as StandardMaterial3D
			g.albedo_color = Color(0.07, 0.09, 0.13)
			g.emission_enabled = true
			g.emission = Color(0.1, 0.16, 0.3)
			g.emission_energy_multiplier = 0.55
	var truck := city.find_child("TruckMainE", true, false)
	if truck:
		truck.queue_free()

func _build_far_sirens() -> void:
	for spec in [[Vector3(71.0, 0, -52.0), "siren_wail_loop", 0.0], [Vector3(-71.0, 0, -35.0), "siren_yelp_loop", 1.7]]:
		var root := Node3D.new()
		root.name = "FarSiren"
		add_child(root)
		root.position = spec[0]
		var p := Mat.loop_player(root, SFX_DIR + String(spec[1]) + ".wav", Vector3(0, 3, 0), -80.0, 230.0, 30.0)
		if p == null:
			root.queue_free()
			continue
		p.stop()
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 38.0
		l.shadow_enabled = false
		l.position = Vector3(0, 6.0, 0)
		root.add_child(l)
		_far_sirens.append([p, l, spec[2]])

## 0 off, 1 far away (the block hears them coming), 2 close (the raid): the level of the sirens and their lights.
func _sirens(level: int) -> void:
	_siren_level = level
	for e in _far_sirens:
		var p := e[0] as AudioStreamPlayer3D
		if level > 0 and not p.playing:
			p.play()
		elif level == 0 and p.playing:
			p.stop()
		p.volume_db = -14.0 if level == 1 else -4.0
		p.max_distance = 230.0 if level == 1 else 300.0

## The streetlights near the laundromat go out for the raid and come back after.
func _power_cut(on: bool) -> void:
	if on and _lamp_saved.is_empty():
		for entry in city.get("_night_lights"):
			var l := entry[0] as Light3D
			if l.get_parent().name.begins_with("Streetlight") and l.global_position.distance_to(Vector3(33.3, 0, -3.0)) < 34.0 and float(entry[1]) > 0.0:
				_lamp_saved.append([entry, float(entry[1])])
				entry[1] = 0.0
				city._set_light(entry)
	elif not on:
		for e in _lamp_saved:
			(e[0] as Array)[1] = e[1]
			city._set_light(e[0])
		_lamp_saved.clear()

func _build_ambience() -> void:
	# The block's own bed: a fire somewhere always burning, dogs and a crowd a long way off.
	for spec in [["burning_block_loop", -16.0], ["crowd_dogs_loop", -20.0]]:
		var p := Mat.loop_player(self, SFX_DIR + String(spec[0]) + ".wav", Vector3.ZERO, spec[1], 1.0e6, 1.0e6)
		if p:
			p.name = "Bed_" + String(spec[0])
			# Not a point in the world: a bed the player hears everywhere (the 3D player is moved to the camera).
			p.set_meta("bed", true)

func _track_beds() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for c in get_children():
		if c is AudioStreamPlayer3D and c.has_meta("bed"):
			c.global_position = cam.global_position

func _poll_objectives() -> void:
	var pp := Vector3(INF, 0, INF)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		pp = player.global_position
	var lm_in := pp.x > 29.8 and pp.x < 36.8 and pp.z < -3.4 and pp.z > -15.8
	if ending != "":
		markers.call("clear_all")
		return
	if laundromat.get("raid_on"):
		for k in ["door", "bag_a", "bag_b", "bag_c", "bag_d"]:
			markers.call("clear", k)
		var flushed: bool = story != null and bool(story.get("is_flushed"))
		if not flushed and not markers.has("sink"):
			markers.call("mark", "sink", laundromat.call("point", "sink"), Color(0.4, 0.85, 1.0), 1.1, true)
		if not markers.has("car"):
			markers.call("mark", "car", laundromat.call("point", "car"), Color(0.4, 1.0, 0.5), 1.8, true)
		return
	if chapter == "STASH RUN":
		if lm_in:
			markers.call("clear", "door")
			var got: Dictionary = story.get("_collected") if story != null and story.get("_collected") != null else {}
			for k in ["a", "b", "c", "d"]:
				if got.has("stash_" + k):
					markers.call("clear", "bag_" + k)
				elif not markers.has("bag_" + k):
					markers.call("mark", "bag_" + k, laundromat.call("point", "stash_" + k), Color(1.0, 0.75, 0.25), 0.7, false)
		else:
			if not markers.has("door"):
				markers.call("mark", "door", laundromat.call("front_door"), Color(1.0, 0.75, 0.25), 1.1, true)
	else:
		for k in ["door", "bag_a", "bag_b", "bag_c", "bag_d"]:
			markers.call("clear", k)

## A short wash of colour on the night (a beat's sting), settling back to the chapter's.
func _mood_flash(c: Color) -> void:
	_tint = c
	_tint_w = 0.55
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		if raid_active or ending != "":
			return
		_mood_to(chapter if chapter != "" else "THE CORNER"))

func drive_by(path_id: String, speed := 19.0) -> Node3D:
	return vehicles.call("drive_by", path_id, speed)

# --- Mood --------------------------------------------------------------------------------

func _capture_base() -> void:
	if _env == null:
		return
	_base_fog = _env.fog_light_color
	_base_amb = _env.ambient_light_color
	_base_dens = _env.fog_density
	_w_fog = _base_fog
	_w_amb = _base_amb
	_w_dens = _base_dens

func _mood_to(key: String) -> void:
	var m: Array = MOODS[key]
	_mood_set(m[0], m[1], m[2], 3.0)

## Any tint, its weight and the fog's density factor, reached over `secs`.
func _mood_set(col: Color, w: float, dens: float, secs: float) -> void:
	if _mood_tween:
		_mood_tween.kill()
	_mood_from = [_tint, _tint_w, _dens]
	_mood_tween = create_tween()
	_mood_tween.tween_method(func(t: float):
		_tint = (_mood_from[0] as Color).lerp(col, t)
		_tint_w = lerpf(_mood_from[1], w, t)
		_dens = lerpf(_mood_from[2], dens, t), 0.0, 1.0, secs)

func _apply_mood() -> void:
	if _env == null:
		return
	# Whatever else rewrites the night's fog and ambient is the new base; the accent goes over it.
	if not _env.fog_light_color.is_equal_approx(_w_fog):
		_base_fog = _env.fog_light_color
	if not _env.ambient_light_color.is_equal_approx(_w_amb):
		_base_amb = _env.ambient_light_color
	if absf(_env.fog_density - _w_dens) > 0.00001:
		_base_dens = _env.fog_density
	var lum_f := maxf(_base_fog.get_luminance(), 0.05)
	_w_fog = _base_fog.lerp(_tint * (lum_f * 1.6 + 0.04), _tint_w)
	_w_amb = _base_amb.lerp(_tint * 0.55, _tint_w * 0.7)
	_w_dens = _base_dens * _dens
	_env.fog_light_color = _w_fog
	_env.ambient_light_color = _w_amb
	_env.fog_density = _w_dens

func mood_tint() -> Color:
	return _tint

# --- Frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_apply_mood()
	_track_beds()
	_obj_t += delta
	if _obj_t > 0.4:
		_obj_t = 0.0
		_poll_objectives()
	for e in _far_sirens:
		var l := e[1] as OmniLight3D
		var ph := fposmod(_t * 1.8 + float(e[2]), 1.0)
		var red := ph < 0.5
		l.light_color = Color(1.0, 0.1, 0.08) if red else Color(0.1, 0.25, 1.0)
		l.light_energy = (0.0 if _siren_level == 0 else (2.0 if _siren_level == 1 else 4.0)) * (0.35 + 0.65 * absf(sin(ph * PI * 2.0)))
	for f in _fires:
		f[1] -= delta
		if f[1] <= 0.0:
			f[1] = randf_range(0.04, 0.16)
			f[2] = randf_range(0.65, 1.15)
		var l := f[0] as Light3D
		if is_instance_valid(l):
			l.light_energy = f[3] * f[2]
	for f in _flash:
		if f.light_energy > 0.0:
			f.light_energy = maxf(0.0, f.light_energy - delta * 14.0)
	for p in _pickups:
		if is_instance_valid(p):
			var ph: float = p.get_meta("phase")
			p.position.y = float(p.get_meta("base_y")) + 0.08 * sin(_t * 2.4 + ph)
			p.rotation.y += delta * 1.6
	var i := _reveals.size() - 1
	while i >= 0:
		var r: Array = _reveals[i]
		r[1] += delta
		var d := r[0] as Decal
		if is_instance_valid(d):
			d.modulate.a = clampf(r[1] / 0.9, 0.0, 1.0)
		if r[1] >= 0.9 or not is_instance_valid(d):
			_reveals.remove_at(i)
		i -= 1
	if mode == null or story == null:
		_hook_t += delta
		if _hook_t > 1.0:
			_hook_t = 0.0
			_find_hooks()

var _hook_t := 0.0
