extends Node3D
## The far side of Main Street. The block was built to be seen from up over it, from the south, so only
## the north side has buildings and the street ends at the sidewalk (z 4.5), with nothing past it: from eye
## height that is the edge of the world. This closes it with a continuous row of brick fronts (shuttered
## ground floors, windows, some lit at night), a roof line at 9-15 m, and a solid face along the kerb so
## nothing walks off the edge. One mesh per building, no shadows, no lights.
##   city.add_child(preload("res://world/SouthRow.gd").new())

const Facades := preload("res://world/Facades.gd")
## The street's south edge, and how far the row reaches either way along it.
const FRONT_Z := 4.5
const DEPTH := 12.0
const X_MIN := -80.0
const X_MAX := 80.0
const FLOOR_H := 3.0
const GROUND_H := 4.0

var _lit_mat: StandardMaterial3D

func _ready() -> void:
	name = "SouthRow"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4511
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.13, 0.18, 0.25)
	glass.roughness = 0.25
	glass.metallic = 0.4
	var shutter := StandardMaterial3D.new()
	shutter.albedo_color = Color(0.22, 0.23, 0.24)
	shutter.roughness = 0.7
	shutter.metallic = 0.5
	_lit_mat = StandardMaterial3D.new()
	_lit_mat.albedo_color = Color(0.9, 0.7, 0.4)
	_lit_mat.emission_enabled = true
	_lit_mat.emission = Color(1.0, 0.72, 0.38)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.2, 0.2, 0.21)
	roof.roughness = 0.95
	var x := X_MIN
	var i := 0
	while x < X_MAX:
		var w := rng.randf_range(9.0, 15.0)
		w = minf(w, X_MAX - x)
		var floors := rng.randi_range(3, 5)
		_building(x, w, floors, rng, glass, shutter, roof, i)
		x += w
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
	GameState.clock_changed.connect(func(_m): _light())
	_light()

func _light() -> void:
	# Lit panes glow with the dark: off by day, full by night.
	_lit_mat.emission_energy_multiplier = 3.0 * (1.0 - GameState.daylight())

func _building(x: float, w: float, floors: int, rng: RandomNumberGenerator, glass: Material, shutter: Material, roof: Material, idx: int) -> void:
	var h := GROUND_H + (floors - 1) * FLOOR_H
	var z0 := FRONT_Z
	var z1 := FRONT_Z + DEPTH
	# Brick body: the front, the sides (the first and last show, the rest are party walls), the top.
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth_v := Vector3(0, 0, z1 - z0)
	_quad(walls, Vector3(x + w, -2.0, z0), Vector3(x, -2.0, z0), h, Vector3.FORWARD)
	_quad(walls, Vector3(x, -2.0, z0), Vector3(x, -2.0, z1), h, Vector3.LEFT)
	_quad(walls, Vector3(x + w, -2.0, z1), Vector3(x + w, -2.0, z0), h, Vector3.RIGHT)
	walls.generate_tangents()
	var mesh := ArrayMesh.new()
	walls.commit(mesh)
	mesh.surface_set_material(0, Facades._mass_mat("apt"))
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	top.set_normal(Vector3.UP)
	for v in [Vector3(x, h, z0), Vector3(x + w, h, z0), Vector3(x + w, h, z1), Vector3(x, h, z0), Vector3(x + w, h, z1), Vector3(x, h, z1)]:
		top.add_vertex(v)
	top.commit(mesh)
	mesh.surface_set_material(1, roof)
	var mi := MeshInstance3D.new()
	mi.name = "Front%d" % idx
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Panes: dark glass, some lit; the ground floor is roller shutters and a door or two.
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shut := SurfaceTool.new()
	shut.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := maxi(int(w / 2.6), 2)
	var pitch := w / cols
	for c in cols:
		var cx := x + pitch * (c + 0.5)
		# Ground floor: a shutter in most bays, the odd bay left a dark doorway.
		if rng.randf() < 0.8:
			_pane(shut, cx, 0.2, pitch * 0.82, 3.1, z0 - 0.04)
		else:
			_pane(dark, cx, 0.1, pitch * 0.5, 2.5, z0 - 0.04)
		for f in range(1, floors):
			var y := GROUND_H + (f - 1) * FLOOR_H + 0.7
			_pane(lit if rng.randf() < 0.4 else dark, cx, y, pitch * 0.5, 1.5, z0 - 0.04)
	for pair in [[dark, glass], [lit, _lit_mat], [shut, shutter]]:
		var st: SurfaceTool = pair[0]
		var pm := ArrayMesh.new()
		st.commit(pm)
		if pm.get_surface_count() == 0:
			continue
		pm.surface_set_material(0, pair[1])
		var pi := MeshInstance3D.new()
		pi.mesh = pm
		pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(pi)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, h: float, normal: Vector3) -> void:
	# a -> b along the wall at the base, up to height h. UVs at 3 m per brick tile.
	var len := a.distance_to(b)
	var u := len / 3.0
	var v := (h + 2.0) / 3.0
	var top_a := a + Vector3(0, h + 2.0, 0)
	var top_b := b + Vector3(0, h + 2.0, 0)
	st.set_normal(normal)
	st.set_uv(Vector2(0, v)); st.add_vertex(a)
	st.set_uv(Vector2(u, v)); st.add_vertex(b)
	st.set_uv(Vector2(u, 0)); st.add_vertex(top_b)
	st.set_uv(Vector2(0, v)); st.add_vertex(a)
	st.set_uv(Vector2(u, 0)); st.add_vertex(top_b)
	st.set_uv(Vector2(0, 0)); st.add_vertex(top_a)

## A flat pane on the front face (facing -Z, the street): centre x, bottom y, size.
func _pane(st: SurfaceTool, cx: float, y: float, w: float, h: float, z: float) -> void:
	st.set_normal(Vector3.FORWARD)
	var l := cx - w * 0.5
	var r := cx + w * 0.5
	for p in [Vector3(l, y, z), Vector3(r, y, z), Vector3(l, y + h, z), Vector3(r, y, z), Vector3(r, y + h, z), Vector3(l, y + h, z)]:
		st.add_vertex(p)
