extends Node3D
## The far side of Main Street. The block was built to be seen from up over it, from the south, so only
## the north side has buildings and the street ended at the sidewalk (z 4.5) with nothing past it: from eye
## height that is the edge of the world. This closes it with a continuous row of brick fronts in the same
## kit, brick and window glass as the north side (the windows are the apartment kit's, in Facades' own dark
## and lit glass, so about a third glow after dark and the clock moves them), shuttered ground floors, a
## roof line at 10-16 m, and a solid face along the kerb so nothing walks off the edge.
## Walls and shutters are one mesh per building; windows are two MultiMeshes per building (dark, lit);
## every material is shared; everything fades out past VIEW_RANGE.
##   var row := preload("res://world/SouthRow.gd").new(); row.facades = facades; city.add_child(row)

const Facades := preload("res://world/Facades.gd")
## The street's south edge, and how far the row reaches either way along it.
const FRONT_Z := 4.5
const DEPTH := 12.0
const X_MIN := -80.0
const X_MAX := 80.0
const FLOOR_H := Facades.MODULE
const GROUND_H := 4.0
const VIEW_RANGE := 150.0
## The overpass (City3D.tscn: deck at y 10.0-11.6, x 56-66) runs on south over this row. Under it the
## row is a low two-floor block, so the deck and its pillars pass over the roof.
const OVERPASS_X := Vector2(54.0, 68.0)
const OVERPASS_FLOORS := 2

## The city's Facades node (its kit meshes and window glass).
var facades: Node3D
## Windows (kit meshes, glass) are only drawn this close; the wall behind them stays to VIEW_RANGE.
const WINDOW_RANGE := 70.0
static var _brick: StandardMaterial3D
static var _shutter: StandardMaterial3D
static var _roof: StandardMaterial3D

func _ready() -> void:
	name = "SouthRow"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4511
	var i := 0
	for seg in _segments(rng):
		_building(seg[0], seg[1], seg[2], rng, i)
		i += 1
	# A solid face along the kerb: the row's own collider, so the edge of the street is a wall.
	var body := StaticBody3D.new()
	body.name = "Face"
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(X_MAX - X_MIN, 14.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3((X_MIN + X_MAX) * 0.5, 6.0, FRONT_Z + 0.5)

## [x, width, floors] along the row, a low block under the overpass.
func _segments(rng: RandomNumberGenerator) -> Array:
	var out := []
	for span in [[X_MIN, OVERPASS_X.x, 0], [OVERPASS_X.x, OVERPASS_X.y, OVERPASS_FLOORS], [OVERPASS_X.y, X_MAX, 0]]:
		var x: float = span[0]
		while x < span[1] - 0.01:
			var w := rng.randf_range(9.0, 15.0)
			if span[1] - (x + w) < 6.0:
				w = span[1] - x
			out.append([x, w, span[2] if span[2] > 0 else rng.randi_range(3, 5)])
			x += w
	return out

## The north side's brick without its normal map: this side is seen across the street, and the normal map
## costs more fill than it shows at that distance.
func _brick_mat() -> StandardMaterial3D:
	if _brick == null:
		_brick = Facades._mass_mat("apt").duplicate() as StandardMaterial3D
		_brick.normal_enabled = false
		_brick.roughness_texture = null
		_brick.roughness = 0.9
	return _brick

func _shutter_mat() -> StandardMaterial3D:
	if _shutter == null:
		_shutter = StandardMaterial3D.new()
		_shutter.albedo_color = Color(0.3, 0.31, 0.32)
		_shutter.albedo_texture = load("res://assets/pbr/bricks_old_rough.jpg")
		_shutter.roughness = 0.65
		_shutter.metallic = 0.5
		_shutter.uv1_scale = Vector3(1.0, 6.0, 1.0)
	return _shutter

func _roof_mat() -> StandardMaterial3D:
	if _roof == null:
		_roof = StandardMaterial3D.new()
		_roof.albedo_texture = load("res://assets/pbr/gravel_diff.jpg")
		_roof.albedo_color = Color(0.36, 0.35, 0.34)
		_roof.uv1_triplanar = true
		_roof.uv1_world_triplanar = true
		_roof.uv1_scale = Vector3.ONE / 0.75
	return _roof

func _building(x: float, w: float, floors: int, rng: RandomNumberGenerator, idx: int) -> void:
	var h := GROUND_H + (floors - 1) * FLOOR_H
	var z0 := FRONT_Z
	var z1 := FRONT_Z + DEPTH
	var below := -2.0
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Front (faces the street, -Z), the two ends (the outer ones show; the rest are party walls).
	_quad(walls, Vector3(x + w, below, z0), Vector3(x, below, z0), h, Vector3.FORWARD)
	_quad(walls, Vector3(x, below, z0), Vector3(x, below, z1), h, Vector3.LEFT)
	_quad(walls, Vector3(x + w, below, z1), Vector3(x + w, below, z0), h, Vector3.RIGHT)
	walls.generate_tangents()
	var mesh := ArrayMesh.new()
	walls.commit(mesh)
	mesh.surface_set_material(0, _brick_mat())
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	top.set_normal(Vector3.UP)
	# Facing up: clockwise seen from above.
	for v in [Vector3(x, h, z0), Vector3(x + w, h, z0), Vector3(x + w, h, z1), Vector3(x, h, z0), Vector3(x + w, h, z1), Vector3(x, h, z1)]:
		top.add_vertex(v)
	top.commit(mesh)
	mesh.surface_set_material(1, _roof_mat())
	# Roller shutters across most ground-floor bays.
	var bays := maxi(int(w / Facades.MODULE), 2)
	var bay_w := w / bays
	var shut := SurfaceTool.new()
	shut.begin(Mesh.PRIMITIVE_TRIANGLES)
	shut.set_normal(Vector3.FORWARD)
	shut.set_uv(Vector2.ZERO)
	var any_shutter := false
	for c in bays:
		if rng.randf() < 0.8:
			any_shutter = true
			var cx := x + bay_w * (c + 0.5)
			var l := cx - bay_w * 0.4
			var r := cx + bay_w * 0.4
			# The wall quad's order (clockwise from the street).
			var pts := [Vector3(r, 0.2, z0 - 0.04), Vector3(l, 3.2, z0 - 0.04), Vector3(l, 0.2, z0 - 0.04), Vector3(r, 0.2, z0 - 0.04), Vector3(r, 3.2, z0 - 0.04), Vector3(l, 3.2, z0 - 0.04)]
			var uvs := [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
			for k in 6:
				shut.set_uv(uvs[k])
				shut.add_vertex(pts[k])
	if any_shutter:
		shut.generate_tangents()
		shut.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _shutter_mat())
	var mi := MeshInstance3D.new()
	mi.name = "Front%d" % idx
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIEW_RANGE
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(mi)
	_windows(x, w, floors, bays, bay_w, idx)

## One kit window per bay and upper floor, standing on the wall, in Facades' glass (a third of them lit).
func _windows(x: float, w: float, floors: int, bays: int, bay_w: float, idx: int) -> void:
	if facades == null or floors < 2:
		return
	var kit := "apt"
	var win_mesh: Mesh = facades._mesh(kit, Facades.KIT_PIECES[kit]["window"])
	var b: AABB = win_mesh.get_aabb()
	var dark := _glassed(win_mesh, facades._glass())
	var lit := _glassed(win_mesh, facades._lit_glass())
	var dark_t: Array[Transform3D] = []
	var lit_t: Array[Transform3D] = []
	for f in range(1, floors):
		var y := GROUND_H + (f - 1) * FLOOR_H + (FLOOR_H - b.size.y) * 0.5
		for c in bays:
			var cx := x + bay_w * (c + 0.5)
			# Facing the street: turned half a circle, its back on the wall plane.
			var basis := Basis(Vector3.UP, PI)
			var origin := Vector3(cx + b.get_center().x, y - b.position.y, FRONT_Z + b.position.z)
			var t := Transform3D(basis, origin)
			if absi(("S%d_%d_%d" % [idx, f, c]).hash()) % 100 < Facades.LIT_WINDOWS:
				lit_t.append(t)
			else:
				dark_t.append(t)
	for pair in [[dark, dark_t, "WindowsDark%d"], [lit, lit_t, "WindowsLit%d"]]:
		var transforms: Array = pair[1]
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = transforms.size()
		for k in transforms.size():
			mm.set_instance_transform(k, transforms[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = pair[2] % idx
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = WINDOW_RANGE
		mmi.visibility_range_end_margin = 8.0
		add_child(mmi)

static var _glassed_meshes := {}

## The kit window with its see-through surfaces in `glass` (one copy per glass, shared by every row).
func _glassed(src: Mesh, glass: Material) -> Mesh:
	var key := "%d_%d" % [src.get_instance_id(), glass.get_instance_id()]
	if _glassed_meshes.has(key):
		return _glassed_meshes[key]
	var m: Mesh = src.duplicate()
	for i in m.get_surface_count():
		var mat := src.surface_get_material(i) as BaseMaterial3D
		if mat and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.surface_set_material(i, glass)
	_glassed_meshes[key] = m
	return m

## Same order as Facades._quad (clockwise from outside, as Godot wants), UVs at the kit's 3 m per tile.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, h: float, normal: Vector3) -> void:
	var top := h + 2.0
	var u := a.distance_to(b) / Facades.MODULE
	var v := top / Facades.MODULE
	var corners := [[a, Vector2(0, v)], [b, Vector2(u, v)], [b + Vector3(0, top, 0), Vector2(u, 0)], [a + Vector3(0, top, 0), Vector2(0, 0)]]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(corners[i][1])
		st.add_vertex(corners[i][0])
