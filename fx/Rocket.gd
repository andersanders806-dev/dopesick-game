extends Node3D
## The launcher's rocket (SHIP 16 B2): it leaves the muzzle at speed, accelerates as the motor burns, drops a little,
## and trails smoke and flame; the first thing it meets (a wall, the street, a zombie's hit zone) or the end of its
## reach sets it off. The blast is the game's one explosion (fx/Explosion.gd, power 1.4: the same picture and sound the
## grenades have, one fill-cheap card instead of thirty alpha quads); player/WeaponHolder.gd's rocket_blast() does the
## damage. Two are kept per holder and reused: a shot makes no node.

const ImpactFX := preload("res://fx/ImpactFX.gd")
const Explosion := preload("res://fx/Explosion.gd")
const GunSounds := preload("res://weapons/GunSounds.gd")
const SPEED := 55.0
const SPEED_MAX := 85.0
const ACCEL := 90.0
const DROP := 1.6
const REACH := 160.0
var holder: Node
var flying := false
var data: Resource
## For the tests: the last blast's position, what set it off, and how many there have been.
var last_blast := Vector3.INF
var last_struck := ""
var blasts := 0
var _v := Vector3.ZERO
var _travel := 0.0
var _body: Node3D
var _flame: OmniLight3D
var _trail: CPUParticles3D
var _hum: AudioStreamPlayer3D

func _ready() -> void:
	top_level = true
	_build()
	visible = false

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.24, 0.27, 0.15)
	olive.roughness = 0.6
	olive.metallic = 0.3
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.12, 0.13)
	steel.metallic = 0.6
	steel.roughness = 0.45
	# The warhead (a cone and a fat body), the motor tube and the fins, nose down -Z.
	_part(_cone(0.0, 0.042, 0.16), olive, Vector3(0, 0, -0.22))
	_part(_cyl(0.042, 0.042, 0.14), olive, Vector3(0, 0, -0.07))
	_part(_cyl(0.028, 0.042, 0.06), steel, Vector3(0, 0, 0.03))
	_part(_cyl(0.02, 0.02, 0.36), steel, Vector3(0, 0, 0.24))
	for i in 4:
		var fin := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.002, 0.07, 0.08)
		fin.mesh = bm
		fin.material_override = steel
		fin.position = Vector3(0, 0, 0.4)
		fin.rotation.z = PI * 0.5 * i + PI * 0.25
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(fin)
	# The motor's glow: a small light that lights the street right round the rocket only (a wide one moving down the
	# street relit every surface it passed).
	_flame = OmniLight3D.new()
	_flame.light_color = Color(1.0, 0.6, 0.25)
	_flame.light_energy = 2.0
	_flame.omni_range = 2.2
	_flame.shadow_enabled = false
	_flame.position = Vector3(0, 0, 0.5)
	_body.add_child(_flame)
	var smoke_mat := ImpactFX._particle_material(Color(0.62, 0.6, 0.57, 0.55), false, false)
	# The motor's trail: a steady stream of puffs left hanging in the air.
	_trail = CPUParticles3D.new()
	_trail.emitting = false
	_trail.amount = 48
	_trail.lifetime = 1.3
	_trail.local_coords = false
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 0.4
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3(0, 0.35, 0)
	_trail.scale_amount_min = 0.24
	_trail.scale_amount_max = 0.46
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	_trail.scale_amount_curve = grow
	var tg := Gradient.new()
	tg.set_color(0, Color(1.0, 0.75, 0.45, 0.9))
	tg.add_point(0.08, Color(0.75, 0.72, 0.68, 0.6))
	tg.set_color(tg.get_point_count() - 1, Color(0.5, 0.5, 0.5, 0.0))
	_trail.color_ramp = tg
	_trail.mesh = _quad(smoke_mat)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.position = Vector3(0, 0, 0.45)
	_body.add_child(_trail)
	_hum = _voice(10.0, 120.0)

static func _quad(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q

func _voice(unit: float, reach: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.unit_size = unit
	a.max_distance = reach
	a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(a)
	return a

func _part(mesh: Mesh, mat: Material, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation.x = -PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)

static func _cyl(r0: float, r1: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r0
	m.bottom_radius = r1
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return m

static func _cone(r0: float, r1: float, h: float) -> CylinderMesh:
	return _cyl(r0, r1, h)

## Drawn once at `at` with the body, the motor's glow and the trail on (fx/Prewarm.gd, behind the loading black), and put away.
## (The blast is the shared pool's: Prewarm draws fx/Explosion.gd on its own.)
func show_for_warm(at: Vector3) -> void:
	global_position = at
	visible = true
	_body.visible = true
	_flame.visible = true
	_trail.emitting = true

func hide_after_warm() -> void:
	_trail.emitting = false
	_body.visible = false
	_flame.visible = false
	visible = false

## Off it goes from `from` along `dir`.
func fire(from: Vector3, dir: Vector3, d: Resource) -> void:
	data = d
	flying = true
	visible = true
	_body.visible = true
	_flame.visible = true
	_travel = 0.0
	_v = dir.normalized() * SPEED
	global_position = from
	_face(dir)
	_trail.emitting = true
	var fl := GunSounds.file("common/rocket_flight")
	if fl != null:
		_hum.stream = fl
		_hum.volume_db = -2.0
		_hum.play()

func _face(dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT
	_body.global_basis = Basis.looking_at(dir, up)

## A step of the flight (the holder's clock): moves, looks along the way for what it meets, goes off there.
func advance(delta: float) -> void:
	if not flying:
		return
	var speed := minf(_v.length() + ACCEL * delta, SPEED_MAX)
	_v = _v.normalized() * speed + Vector3(0, -DROP * delta, 0)
	var step := _v * delta
	var from := global_position
	var hit: Dictionary = {}
	if holder != null and holder.has_method("_cast"):
		hit = holder._cast(from, step.normalized(), step.length() + 0.3)
	if not hit.is_empty():
		var c = hit.get("collider")
		last_struck = String(c.name) if c != null else ""
		_explode(hit.position - step.normalized() * 0.15, hit.get("zombie"), hit.get("normal", -step.normalized()))
		return
	# A body brushed in passing sets it off too (the warhead's nose is not a needle): within PROXIMITY of its middle.
	var near := _brushed(from, from + step)
	if near != null:
		last_struck = String(near.name)
		var c2: Vector3 = (near as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		var along: float = clampf((c2 - from).dot(step.normalized()), 0.0, step.length())
		_explode(from + step.normalized() * along, near)
		return
	global_position = from + step
	_face(_v)
	_travel += step.length()
	if _travel >= REACH:
		_explode(global_position, null)

## The first zombie (or gangster) whose body the segment passes within PROXIMITY of: its upright middle, the knees
## to the head, as a line.
const PROXIMITY := 0.5

func _brushed(a: Vector3, b: Vector3) -> Node:
	var best: Node = null
	var best_t := INF
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or (z.has_method("is_alive") and not z.is_alive()):
			continue
		var base: Vector3 = (z as Node3D).global_position
		var t := clampf((base - a).dot(ab) / len2, 0.0, 1.0)
		var p := a + ab * t
		var y := clampf(p.y, base.y + 0.4, base.y + 1.75)
		if Vector3(p.x - base.x, p.y - y, p.z - base.z).length() < PROXIMITY and t < best_t:
			best_t = t
			best = z
	return best

func _explode(at: Vector3, struck: Node, normal := Vector3.UP) -> void:
	flying = false
	_trail.emitting = false
	_body.visible = false
	_flame.visible = false
	_hum.stop()
	global_position = at
	last_blast = at
	blasts += 1
	visible = false
	# The shared explosion: the picture, the A/C pair of recordings, the shake (power 1.4: the launcher's).
	var fx := Explosion.of(self)
	if fx != null:
		fx.detonate(at, normal, 1.4)
	if holder != null and holder.has_method("rocket_blast"):
		holder.rocket_blast(at, data, struck)
