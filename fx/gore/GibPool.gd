extends Node3D
## The pieces that come off: 24 pooled gibs (a limb, a head) thrown from the cut, tumbling on a
## small ballistic sim of their own (no physics bodies: they never fall through a floor and
## cost nothing at rest), landing with a wet thud and a smear. The oldest is recycled.

const SIZE := 24
const GRAVITY := 9.8

var _gibs: Array = []
## Small chunks (skull, flesh): a second pool of the same kind of piece.
var _chunks: Array = []
var _chunk_next := 0
var chunks_spawned := 0
const CHUNKS := 24
var _next := 0
var spawned := 0

class Gib:
	var node: Node3D
	var mesh: MeshInstance3D
	var cap: MeshInstance3D
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var ground := 0.0
	var radius := 0.05
	var resting := true
	var age := 0.0
	var bounces := 0

func _ready() -> void:
	name = "GibPool"
	for i in SIZE:
		var g := Gib.new()
		g.node = Node3D.new()
		g.node.visible = false
		g.mesh = MeshInstance3D.new()
		g.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.node.add_child(g.mesh)
		g.cap = MeshInstance3D.new()
		g.cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.node.add_child(g.cap)
		add_child(g.node)
		_gibs.append(g)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	for i in CHUNKS:
		var g := Gib.new()
		g.node = Node3D.new()
		g.node.visible = false
		g.mesh = MeshInstance3D.new()
		g.mesh.mesh = sphere
		g.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.node.add_child(g.mesh)
		add_child(g.node)
		_chunks.append(g)

## Every gib put away, the counters at zero.
func clear() -> void:
	for g: Gib in _gibs + _chunks:
		g.node.visible = false
		g.resting = true
		g.vel = Vector3.ZERO
	spawned = 0
	chunks_spawned = 0
	_next = 0
	_chunk_next = 0

## Throws a gib: `data` from GoreRig.limb(), carrying `materials` (per source surface) and the
## zombie's rot / seed; its world transform, a launch velocity and the ground height under it.
func spawn(data: Dictionary, materials: Array, rot: float, seed_value: float, xf: Transform3D, vel: Vector3, ground: float, cap_mat: Material, cap_radius: float) -> Gib:
	var g: Gib = _gibs[_next]
	_next = (_next + 1) % _gibs.size()
	spawned += 1
	g.mesh.mesh = data["mesh"]
	var surfs: Array = data["surfaces"]
	for k in surfs.size():
		var mat = materials[surfs[k]] if surfs[k] < materials.size() else null
		g.mesh.set_surface_override_material(k, mat)
	g.mesh.set_instance_shader_parameter("rot", rot)
	g.mesh.set_instance_shader_parameter("seed", seed_value)
	# The cut end: a flat disc of flesh with a bone in it, facing out of the cut.
	var cut: Vector3 = data["cut"]
	g.cap.mesh = _cap_mesh(cap_radius)
	g.cap.material_override = cap_mat
	var axis := (-cut).normalized() if cut.length() > 0.001 else Vector3.UP
	var up := axis
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(ref).normalized()
	g.cap.transform = Transform3D(Basis(x, up, x.cross(up)), cut)
	g.node.global_transform = xf
	g.node.visible = true
	g.vel = vel
	g.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	g.ground = ground
	var sz: Vector3 = data["size"]
	g.radius = clampf(minf(sz.x, minf(sz.y, sz.z)) * 0.5 * xf.basis.get_scale().x, 0.04, 0.14)
	g.resting = false
	g.age = 0.0
	g.bounces = 0
	return g

## A chunky bit (size metres, `bone` white or flesh red) thrown from `at`.
func spawn_chunk(at: Vector3, vel: Vector3, ground: float, size: float, mat: Material) -> void:
	var g: Gib = _chunks[_chunk_next]
	_chunk_next = (_chunk_next + 1) % _chunks.size()
	chunks_spawned += 1
	g.mesh.material_override = mat
	g.node.scale = Vector3(size, size * randf_range(0.6, 1.0), size * randf_range(0.7, 1.2))
	g.node.global_position = at
	g.node.visible = true
	g.vel = vel
	g.spin = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	g.ground = ground
	g.radius = size * 0.4
	g.resting = false
	g.age = 0.0
	g.bounces = 0

static var _cap: Mesh
static func _cap_mesh(r: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r * 1.05
	m.height = r * 0.3
	m.radial_segments = 12
	m.rings = 1
	return m

func _physics_process(delta: float) -> void:
	for g: Gib in _gibs:
		_step(g, delta, true)
	for g: Gib in _chunks:
		_step(g, delta, false)

func _step(g: Gib, delta: float, big: bool) -> void:
	for once in 1:
		if g.resting or not g.node.visible:
			continue
		g.age += delta
		g.vel.y -= GRAVITY * delta
		g.node.global_position += g.vel * delta
		var t := g.node.global_transform
		t.basis = Basis(Vector3.UP, g.spin.y * delta) * Basis(Vector3.RIGHT, g.spin.x * delta) * Basis(Vector3.BACK, g.spin.z * delta) * t.basis
		g.node.global_transform = t
		if g.node.global_position.y - g.radius <= g.ground and g.vel.y < 0.0:
			g.node.global_position.y = g.ground + g.radius
			g.bounces += 1
			var impact := absf(g.vel.y)
			g.vel.y = impact * 0.25
			g.vel.x *= 0.55
			g.vel.z *= 0.55
			g.spin *= 0.5
			if g.bounces == 1:
				gib_landed.emit(g.node.global_position, impact if big else -impact)
			if impact < 1.2 or g.bounces > 3:
				g.resting = true
				g.vel = Vector3.ZERO

signal gib_landed(at: Vector3, impact: float)

func in_flight() -> int:
	var n := 0
	for g: Gib in _gibs:
		if g.node.visible and not g.resting:
			n += 1
	return n

func shown() -> int:
	var n := 0
	for g: Gib in _gibs:
		if g.node.visible:
			n += 1
	return n

func chunks_shown() -> int:
	var n := 0
	for g: Gib in _chunks:
		if g.node.visible:
			n += 1
	return n
