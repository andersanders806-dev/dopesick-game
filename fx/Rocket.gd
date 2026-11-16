extends Node3D
## The launcher's rocket (SHIP 16 B2): it leaves the muzzle at speed, accelerates as the motor burns, drops a little,
## and trails smoke and flame; the first thing it meets (a wall, the street, a zombie's hit zone) or the end of its
## reach sets it off. The blast is the Ghetto Wars grenade's (its boom and its flash, fx/GangGrenade.gd) with the
## launcher's own explosion over it, a fireball, smoke and grit; player/WeaponHolder.gd's rocket_blast() does the
## damage. Two are kept per holder and reused: a shot makes no node.

const ImpactFX := preload("res://fx/ImpactFX.gd")
const GunSounds := preload("res://weapons/GunSounds.gd")
const SPEED := 55.0
const SPEED_MAX := 85.0
const ACCEL := 90.0
const DROP := 1.6
const REACH := 160.0
## Seconds the fireball, the flash and the smoke stay after the blast.
const AFTER := 2.8

var holder: Node
var flying := false
var data: Resource
## For the tests: the last blast's position, what set it off, and how many there have been.
var last_blast := Vector3.INF
var last_struck := ""
var blasts := 0
var _v := Vector3.ZERO
var _travel := 0.0
var _after := 0.0
var _body: Node3D
var _flame: OmniLight3D
var _trail: CPUParticles3D
var _fire: CPUParticles3D
var _smoke: CPUParticles3D
var _grit: CPUParticles3D
var _flash: OmniLight3D
var _hum: AudioStreamPlayer3D
var _boom: AudioStreamPlayer3D
var _boom2: AudioStreamPlayer3D

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
	var fire_mat := ImpactFX._particle_material(Color(1.0, 0.65, 0.3, 1.0), true, true)
	var grit_mat := ImpactFX._particle_material(Color(1.0, 1.0, 1.0, 1.0), false, false)
	# The blast's smoke takes its colour from the ramp alone (a grey you can see against the night).
	var cloud_mat := ImpactFX._particle_material(Color(1.0, 1.0, 1.0, 1.0), false, false)
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
	# The blast: a fireball, a column of smoke, grit thrown out.
	# (Counts and sizes kept down for the floor: a screenful of big alpha quads is what costs on a laptop GPU.)
	_fire = _burst(fire_mat, 18, 0.7, 1.8, 3.2, 2.0, 7.0, 180.0, Vector3(0, 2.5, 0), Color(1.0, 0.9, 0.62, 1.0), Color(0.7, 0.22, 0.04, 0.0), 1.6)
	_smoke = _burst(cloud_mat, 12, AFTER, 1.9, 3.2, 1.2, 3.6, 60.0, Vector3(0, 1.3, 0), Color(0.46, 0.43, 0.4, 0.8), Color(0.32, 0.31, 0.3, 0.0), 2.0)
	_grit = _burst(grit_mat, 36, 1.2, 0.07, 0.17, 6.0, 15.0, 75.0, Vector3(0, -12.0, 0), Color(0.42, 0.37, 0.32, 1.0), Color(0.3, 0.27, 0.24, 0.0), 0.0)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.4)
	_flash.light_energy = 0.0
	_flash.omni_range = 11.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	_hum = _voice(10.0, 120.0)
	_boom = _voice(30.0, 400.0)
	_boom2 = _voice(30.0, 400.0)

static func _quad(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q

func _burst(mat: Material, amount: int, life: float, s0: float, s1: float, v0: float, v1: float, spread: float, gravity: Vector3, c0: Color, c1: Color, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = gravity
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	if grow > 0.0:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, minf(0.5 + grow * 0.5, 1.0)))
		p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	p.mesh = _quad(mat)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

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

## Drawn once at `at` with every part on (fx/Prewarm.gd, behind the loading black), and put away.
func show_for_warm(at: Vector3) -> void:
	global_position = at
	visible = true
	_body.visible = true
	_flame.visible = true
	_trail.emitting = true
	for p in [_fire, _smoke, _grit]:
		(p as CPUParticles3D).global_position = at
		(p as CPUParticles3D).restart()
	_flash.visible = true
	_flash.light_energy = 1.0

func hide_after_warm() -> void:
	_trail.emitting = false
	_body.visible = false
	_flame.visible = false
	_flash.visible = false
	for p in [_fire, _smoke, _grit]:
		(p as CPUParticles3D).emitting = false
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
		_explode(hit.position - step.normalized() * 0.15, hit.get("zombie"))
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

func _process(delta: float) -> void:
	if _after > 0.0:
		_after -= delta
		# (Short: a big light over the whole street is a cost on every lit surface for as long as it burns.)
		_flash.light_energy = maxf(_flash.light_energy - delta * 60.0, 0.0)
		if _flash.light_energy <= 0.0:
			_flash.visible = false
		if _after <= 0.0:
			visible = false

func _explode(at: Vector3, struck: Node) -> void:
	flying = false
	_trail.emitting = false
	_body.visible = false
	_flame.visible = false
	_hum.stop()
	global_position = at
	last_blast = at
	blasts += 1
	# The Ghetto Wars grenade's boom, and the launcher's own blast over it.
	var gb := GunSounds.file("grenade_boom")
	if gb != null:
		_boom.stream = gb
		_boom.volume_db = 3.0
		_boom.pitch_scale = randf_range(0.92, 1.02)
		_boom.play()
	var rb := GunSounds.file("common/rpg_explode")
	if rb != null:
		_boom2.stream = rb
		_boom2.volume_db = 4.0
		_boom2.play()
	for p in [_fire, _smoke, _grit]:
		(p as CPUParticles3D).global_position = at
		(p as CPUParticles3D).restart()
	_flash.visible = true
	_flash.light_energy = 14.0
	_flash.global_position = at + Vector3(0, 0.8, 0)
	_after = AFTER
	var fx := ImpactFX.of(self)
	if fx != null:
		fx.bullet_hit(at, Vector3.UP)
	if holder != null and holder.has_method("rocket_blast"):
		holder.rocket_blast(at, data, struck)
