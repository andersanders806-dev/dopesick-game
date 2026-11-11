extends Node3D
## The block's parked cars, laid out like a street where nobody cares rather
## than a showroom (added by City3D._paint_parked_cars()).
##
## The builder (dev-tools/build_rooms_3d.gd) puts the cars at slots along the
## kerb; this node keeps those slots and their names (CarA/B/C stay the
## searchable ones) but, from a seed (world_seed; each car's own stream comes
## from its name, so the street looks the same every visit and doesn't depend
## on the order anything loads in):
##   - parks them crooked: 1-4 degrees of yaw, 0.15-0.45 m off the kerb, nose
##     or tail a little out of line. A candidate position is thrown away if it
##     would touch a wall, bin, hydrant (with room to get a hose on it), door,
##     lamp or another car; it then tries a straighter one, then stays put.
##   - turns the front wheels on about one car in four, lets a tyre go flat
##     (it sags), clamps one wheel, leaves one half up on the pavement.
##   - changes a few: three at the ends of the street become burnt-out wrecks,
##     two of the tarped ones are a real car with a tarp half dragged off it.
##   - double-parks a van on East Ave with its hazards ticking.
##   - grounds every car: a contact shadow with tyre patches, oil under the
##     engine, a wet patch under the exhaust when it rains.
##   - dresses every car (CarPaint: per-car dirt, rust, dust) and gives some
##     of them a story: a parking notice under the wiper, a FOR SALE card, a
##     bin bag taped over a window, a pine tree on the mirror, junk on the dash.
##
## In Dead Block (zombie) only the paint and the ground contact: the wrecks
## and the navmesh there are built round the cars where the builder put them.

const CarPaint := preload("res://world/CarPaint.gd")
const TarpShader := preload("res://assets/shaders/tarp.gdshader")
const DEC := "res://assets/decals/"

## Change it and the whole street parks differently (the smoke test does).
static var world_seed := 1990

## Metres between a car's side and the kerb face.
const KERB_GAP := Vector2(0.15, 0.45)
const YAW_DEG := Vector2(1.0, 4.0)
## The curb's face on the avenues (|x|) and Back Street (z), from the builder.
const AVENUE_FACE := 73.875
const BACK_N_FACE := -93.875
const BACK_S_FACE := -88.125
## Small props are only drawn this close.
const PROP_REACH := 24.0
## What a parked wreck can be, in the order they're dealt.
const WRECKS := ["wreck_burnt_b", "wreck_suv", "wreck_burnt_a", "wreck_sedan"]
const NOT_TOUCHED := ["CarA", "CarB", "CarC", "PoliceCruiser"]

var city: Node3D
var zombie := false
var cars: Array = []
## Per car: {"variant": String, "turned": bool, "props": Array[String]}.
var layout := {}
var _obstacles: Array = []
var _wet_decals: Array = []
var _tarp_mats: Array = []
var _hazard_mat: StandardMaterial3D
var _hazard_lights: Array = []
var _hazard_sound: AudioStreamPlayer3D
var _shared := {}

# --- Entry -----------------------------------------------------------------

func build(root: Node3D, zombie_mode: bool) -> void:
	city = root
	zombie = zombie_mode
	name = "ParkedRow"
	cars = find_cars(root)
	if not zombie:
		_obstacles = gather_obstacles(root)
		_make_variants()
		_add_double_parked()
	# Placement last among the layout steps: footprints must be the final models'.
	if not zombie:
		_park_all()
	for car in cars:
		_finish_car(car)
	if not _wet_decals.is_empty() or not _tarp_mats.is_empty():
		GameState.weather_changed.connect(_on_weather)
		_on_weather(GameState.is_raining())
	set_process(_hazard_mat != null)

## Parked cars under `root`, by name: a car is a StaticBody3D called Car* (or
## the cruiser) with a Model from assets/cars or the tarped car.
static func find_cars(root: Node) -> Array:
	var out: Array = []
	for c in root.find_children("Car*", "StaticBody3D", true, false) + root.find_children("PoliceCruiser", "StaticBody3D", true, false):
		var m := c.get_node_or_null("Model")
		if m != null and (String(m.scene_file_path).begins_with("res://assets/cars/") or String(m.scene_file_path).contains("covered_car")):
			out.append(c)
	out.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	return out

static func car_rng(car_name: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s/%d" % [car_name, world_seed])
	return r

static func kind_of(car: Node3D) -> String:
	return String((car.get_node("Model") as Node).scene_file_path).get_file().get_basename()

## The car's visible extent in its own frame (x nose, z across).
static func local_box(car: Node3D) -> AABB:
	var model := car.get_node("Model") as Node3D
	return model.transform * CarPaint.bounds(model)

## The ground footprint (xz, world) of an oriented box `ab` in `xf`'s frame,
## grown by `margin`.
static func footprint(xf: Transform3D, ab: AABB, margin := 0.0) -> PackedVector2Array:
	var c := ab.get_center()
	var hx := ab.size.x * 0.5 + margin
	var hz := ab.size.z * 0.5 + margin
	var out := PackedVector2Array()
	for s in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var p := xf * Vector3(c.x + s[0] * hx, 0.0, c.z + s[1] * hz)
		out.append(Vector2(p.x, p.z))
	return out

static func car_footprint(car: Node3D, margin := 0.0) -> PackedVector2Array:
	return footprint(car.global_transform, local_box(car), margin)

## Separating-axis test for two convex polygons.
static func poly_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		for i in poly.size():
			var e: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
			var axis := Vector2(-e.y, e.x)
			var amin := INF
			var amax := -INF
			for p in a:
				var d := axis.dot(p)
				amin = minf(amin, d)
				amax = maxf(amax, d)
			var bmin := INF
			var bmax := -INF
			for p in b:
				var d := axis.dot(p)
				bmin = minf(bmin, d)
				bmax = maxf(bmax, d)
			if amax < bmin or bmax < amin:
				return false
	return true

## What a car must not touch: every solid thing standing on the ground
## ({"poly": footprint, "name": ...}), hydrants with a metre and a half of
## clearance, doors and the spots people come out of with one metre.
static func gather_obstacles(root: Node) -> Array:
	var out: Array = []
	for cs in root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := cs as CollisionShape3D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var body := shape_node.get_parent()
		if not (body is StaticBody3D) or String(body.name).begins_with("Car") or body.name == "PoliceCruiser" or body.name == "Floor":
			continue
		var local: AABB
		if shape_node.shape is BoxShape3D:
			local = AABB(-(shape_node.shape as BoxShape3D).size * 0.5, (shape_node.shape as BoxShape3D).size)
		else:
			local = shape_node.shape.get_debug_mesh().get_aabb()
		var world := shape_node.global_transform * local
		if world.end.y < 0.15 or world.position.y > 1.8:
			continue
		var margin := 1.5 if String(body.name).begins_with("Hydrant") else 0.0
		out.append({"poly": footprint(shape_node.global_transform, local, margin), "name": String(body.name)})
	for n in root.find_children("*Door*", "Node3D", true, false) + root.find_children("SpawnFrom*", "Node3D", true, false):
		var p := (n as Node3D).global_position
		if absf(p.y) < 3.0:
			out.append({"poly": PackedVector2Array([Vector2(p.x - 1.0, p.z - 1.0), Vector2(p.x + 1.0, p.z - 1.0), Vector2(p.x + 1.0, p.z + 1.0), Vector2(p.x - 1.0, p.z + 1.0)]), "name": String(n.name)})
	return out

## Which kerb a car at `p` is parked against: {"dir": toward it, "face": its
## coordinate along `dir`, or NAN where the lane has none (Main Street's
## parking lane runs out along the world's edge).
static func kerb_at(p: Vector3) -> Dictionary:
	if p.z < -86.0:
		if p.z < -91.0:
			return {"dir": Vector3(0, 0, -1), "face": -BACK_N_FACE}
		return {"dir": Vector3(0, 0, 1), "face": BACK_S_FACE}
	if absf(p.x) > 66.0:
		var sgn := signf(p.x)
		return {"dir": Vector3(sgn, 0, 0), "face": AVENUE_FACE}
	return {"dir": Vector3(0, 0, 1), "face": NAN}

func _hits(poly: PackedVector2Array, skip: Node3D = null) -> String:
	for o in _obstacles:
		if poly_overlap(poly, o["poly"]):
			return o["name"]
	for other in cars:
		if other == skip or not (other is Node3D):
			continue
		if poly_overlap(poly, car_footprint(other as Node3D, 0.3)):
			return String((other as Node).name)
	return ""

# --- Placement ----------------------------------------------------------------

func _park_all() -> void:
	# The one half up on the kerb is picked first, then everyone else.
	var climber := _pick_climber()
	for car in cars:
		if layout[String(car.name)]["variant"] == "wreck" and kind_of(car).begins_with("wreck") and String(car.name).contains("Lot"):
			continue  # a wreck the builder already left where it fell
		var rng := car_rng(String(car.name) + "/park")
		if car == climber:
			if _place(car, rng, true):
				(layout[String(car.name)] as Dictionary)["variant"] = "kerb"
				continue
			rng = car_rng(String(car.name) + "/park2")
		_place(car, rng, false)

func _pick_climber() -> Node3D:
	var cands: Array = []
	for car in cars:
		var k := kind_of(car)
		var p := (car as Node3D).global_position
		if k in ["sedan_generic", "hatch_generic", "wagon_generic", "suv_generic", "minivan_generic"] and not is_nan(kerb_at(p)["face"]):
			cands.append(car)
	if cands.is_empty():
		return null
	var r := RandomNumberGenerator.new()
	r.seed = world_seed * 31 + 7
	var start := r.randi() % cands.size()
	for i in cands.size():
		var car: Node3D = cands[(start + i) % cands.size()]
		# Only if it can actually be put there; _place tells.
		var saved := car.global_transform
		var ok := _place(car, car_rng(String(car.name) + "/park"), true, true)
		car.global_transform = saved
		if ok:
			return car
	return null

## Move `car` to a crooked spot at its slot; `climb` puts its kerb-side
## wheels on the pavement. `dry` only asks if that's possible.
func _place(car: Node3D, rng: RandomNumberGenerator, climb := false, dry := false) -> bool:
	var g0 := car.global_transform
	var ab := local_box(car)
	var kerb := kerb_at(g0.origin)
	var kdir: Vector3 = kerb["dir"]
	var face: float = kerb["face"]
	for t in 6:
		var s := 1.0 - t * 0.17
		var yaw_deg := rng.randf_range(YAW_DEG.x, YAW_DEG.y) * s * (1.0 if rng.randf() < 0.5 else -1.0)
		if climb:
			yaw_deg = rng.randf_range(4.0, 7.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var along := rng.randf_range(-0.45, 0.45) * s
		var xf := g0
		xf.basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * g0.basis
		xf.origin = g0.origin + g0.basis.x * along
		if is_nan(face):
			xf.origin += kdir * rng.randf_range(-0.2, 0.25) * s
		else:
			var fs := face
			# Coordinate along the kerb direction: grows toward the kerb.
			var reach := -INF
			for q in footprint(xf, ab):
				reach = maxf(reach, kdir.x * q.x + kdir.z * q.y)
			var gap := rng.randf_range(KERB_GAP.x, KERB_GAP.y)
			var target := fs + 0.7 if climb else fs - gap
			xf.origin += kdir * (target - reach)
		if _hits(footprint(xf, ab, 0.05), car) == "":
			if not dry:
				car.global_transform = xf
			return true
	return false

# --- Variants ---------------------------------------------------------------

func _make_variants() -> void:
	for car in cars:
		var kind := kind_of(car)
		layout[String(car.name)] = {"variant": "tarp" if kind == "covered_car" else ("wreck" if kind.begins_with("wreck") else "plain"), "turned": false, "props": []}
		if kind_of(car) == "covered_car":
			_scale_covered(car)
	# Three wrecks, at the far ends of the street: the cars furthest from the
	# middle of the block (some of the five, by the seed).
	var ends: Array = []
	for car in cars:
		if String(car.name) in NOT_TOUCHED or kind_of(car) in CarPaint.LIVERY or layout[String(car.name)]["variant"] == "wreck":
			continue
		var p := (car as Node3D).global_position
		ends.append([absf(p.x) + absf(p.z + 5.0) * 0.6, car])
	ends.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 17 + 3
	var pool: Array = ends.slice(0, mini(5, ends.size())).map(func(e: Array) -> Node: return e[1])
	for i in mini(3, pool.size()):
		var car: Node3D = pool.pop_at(rng.randi() % pool.size())
		_make_wreck(car, WRECKS[(rng.randi() + i) % WRECKS.size()])
	# Two tarps half off: a real car with the cloth dragged back.
	var tarped: Array = cars.filter(func(c: Node) -> bool: return layout[String(c.name)]["variant"] == "tarp" and not (String(c.name) in NOT_TOUCHED))
	for i in mini(2, tarped.size()):
		var car: Node3D = tarped.pop_at(rng.randi() % tarped.size())
		_make_half_tarp(car, rng)
	# Flat tyres (two) and a clamp (one) among the plain cars.
	var plain: Array = cars.filter(func(c: Node) -> bool: return layout[String(c.name)]["variant"] == "plain" and kind_of(c as Node3D) != "van_shvan92" and kind_of(c as Node3D) not in CarPaint.LIVERY)
	for i in mini(3, plain.size()):
		var car: Node3D = plain.pop_at(rng.randi() % plain.size())
		layout[String(car.name)]["variant"] = "flat" if i < 2 else "clamp"
	# Front wheels turned on about one in four of the rest.
	for car in cars:
		if layout[String(car.name)]["variant"] in ["plain", "clamp"] and car_rng(String(car.name) + "/turn").randf() < 0.28:
			layout[String(car.name)]["turned"] = true

func _swap_model(car: Node3D, path: String) -> Node3D:
	var old := car.get_node("Model")
	car.remove_child(old)
	old.queue_free()
	var m: Node3D = (load(path) as PackedScene).instantiate()
	m.name = "Model"
	car.add_child(m)
	car.move_child(m, 0)
	return m

func _resize_box(car: Node3D, model: Node3D) -> void:
	var cs := car.find_children("*", "CollisionShape3D", false, false)
	if cs.is_empty():
		return
	var box := local_box(car)
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, box.size.y, maxf(box.size.z - 0.2, 1.0))
	(cs[0] as CollisionShape3D).shape = shape
	(cs[0] as CollisionShape3D).position = Vector3(box.get_center().x, box.size.y * 0.5, box.get_center().z)

func _make_wreck(car: Node3D, kind: String) -> void:
	var m := _swap_model(car, "res://assets/cars/%s.glb" % kind)
	_resize_box(car, m)
	layout[String(car.name)]["variant"] = "wreck"

func _make_half_tarp(car: Node3D, rng: RandomNumberGenerator) -> void:
	var kinds := ["sedan_generic", "hatch_generic", "wagon_generic", "suv_generic"]
	var m := _swap_model(car, "res://assets/cars/%s.glb" % kinds[rng.randi() % kinds.size()])
	_resize_box(car, m)
	layout[String(car.name)]["variant"] = "tarp_half"
	var ab := CarPaint.bounds(m)
	var mesh := _tarp_mesh(ab, rng.randf_range(0.5, 0.62), rng)
	var mi := MeshInstance3D.new()
	mi.name = "Tarp"
	mi.mesh = mesh
	mi.material_override = _tarp_material(rng.randi() % 3, false)
	mi.set_instance_shader_parameter("flutter", Color(rng.randf(), 1.0, rng.randf_range(0.2, 0.9), 0.0))
	mi.visibility_range_end = CarPaint.PARKED_REACH
	m.add_child(mi)

## A tarp draped over a car: a grid over its bounds, held up by the car's
## profile (nose and tail low, the cabin high), falling in folds to a ragged
## hem along the sides. It covers from the tail to `cover` of the car's
## length, and ends on the bonnet or the screen.
func _tarp_mesh(ab: AABB, cover: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var profile := [[0.0, 0.36], [0.05, 0.5], [0.2, 0.66], [0.3, 0.9], [0.42, 1.0], [0.62, 1.0], [0.72, 0.84], [0.8, 0.7], [0.97, 0.62], [1.0, 0.44]]
	var nx := 22
	var nz := 12
	var x0 := ab.position.x - 0.06
	var x1 := ab.position.x + ab.size.x * cover
	var hw := ab.size.z * 0.5 + 0.04
	var H := ab.size.y
	var ph := rng.randf() * 6.28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for i in nx + 1:
		var x := lerpf(x0, x1, float(i) / nx)
		var tn := clampf((x - ab.position.x) / ab.size.x, 0.0, 1.0)
		var env := 0.5
		for k in profile.size() - 1:
			if tn >= profile[k][0] and tn <= profile[k + 1][0]:
				var f := smoothstep(0.0, 1.0, inverse_lerp(profile[k][0], profile[k + 1][0], tn))
				env = lerpf(profile[k][1], profile[k + 1][1], f)
		env = env * H + 0.04
		var row: Array = []
		for j in nz + 1:
			var u := float(j) / nz * 2.0 - 1.0
			var au := absf(u)
			var top := env * (1.0 - pow(au, 8.0) * 0.3)
			var hem := 0.14 + 0.14 * (0.5 + 0.5 * sin(x * 3.1 + ph + signf(u) * 1.7))
			var d := smoothstep(0.8, 1.0, au)
			var y := lerpf(top, hem, d)
			y += 0.022 * sin(x * 6.0 + ph) * cos(u * 4.5 + ph * 2.0) * (1.0 - d * 0.5)
			if i == nx:
				y = lerpf(y, env * 0.93, 0.5) + 0.025
			row.append(Vector3(x, maxf(y, 0.1), u * hw * lerpf(0.93, 1.02, d)))
		grid.append(row)
	for i in nx:
		for j in nz:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i + 1][j]
			var c: Vector3 = grid[i + 1][j + 1]
			var d2: Vector3 = grid[i][j + 1]
			for v in [a, b, c, a, c, d2]:
				st.set_smooth_group(0)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _tarp_material(variant: int, glb: bool) -> ShaderMaterial:
	var key := "tarp%d%s" % [variant, glb]
	if not _shared.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = TarpShader
		var tints := [Color(0.2, 0.3, 0.42), Color(0.34, 0.37, 0.36), Color(0.3, 0.33, 0.2)]
		sm.set_shader_parameter("tint", tints[variant % tints.size()])
		sm.set_shader_parameter("hem_top", 0.75)
		_shared[key] = sm
		_tarp_mats.append(sm)
	return _shared[key]

# --- Per car: paint, ground, details ------------------------------------------

func _finish_car(car: Node3D) -> void:
	var info: Dictionary = layout.get(car.name, {"variant": "plain", "turned": false, "props": []})
	layout[String(car.name)] = info
	var model := car.get_node("Model") as Node3D
	var kind := kind_of(car)
	var rng := car_rng(String(car.name) + "/detail")
	var seed_i := absi(hash("%s/%d" % [car.name, world_seed]))
	if kind == "covered_car":
		_dress_covered(car, model, rng)
	else:
		CarPaint.dress(model, CarPaint.paint_index(car.name), true, CarPaint.PARKED_REACH, seed_i)
	_add_ground(car, info, rng)
	if zombie or info["variant"] == "wreck" or kind == "covered_car" or kind in CarPaint.LIVERY:
		_save(car, info)
		return
	if info["turned"]:
		_turn_wheels(model, rng)
	var road := _road_side(car)
	match info["variant"]:
		"flat":
			_flat_tyre(car, model, rng, road)
		"clamp":
			_clamp(model, road)
	_add_props(car, model, info, rng, road)
	_save(car, info)

func _save(car: Node3D, info: Dictionary) -> void:
	car.set_meta("parked", info)
	# The searchable car's spot moves with it.
	var zone := city.find_child("Scavenge" + String(car.name), true, false) as Node3D
	if zone != null:
		zone.global_position = Vector3(car.global_position.x, 0.0, car.global_position.z - 1.4)

## Not every tarped car is the same length and height.
func _scale_covered(car: Node3D) -> void:
	var rng := car_rng(String(car.name) + "/scale")
	var model := car.get_node("Model") as Node3D
	var sc := Vector3(rng.randf_range(0.94, 1.06), rng.randf_range(0.92, 1.08), rng.randf_range(0.94, 1.08))
	model.transform.basis = model.transform.basis * Basis.from_scale(sc)

func _dress_covered(car: Node3D, model: Node3D, rng: RandomNumberGenerator) -> void:
	CarPaint.limit_range(model, CarPaint.PARKED_REACH)
	var variant := rng.randi() % 3
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "covered_car" and (mi as MeshInstance3D).mesh != null:
			var base := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			var key := "covered%d" % variant
			if not _shared.has(key):
				var sm := ShaderMaterial.new()
				sm.shader = TarpShader
				sm.set_shader_parameter("use_tex", 1.0)
				if base != null:
					sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				sm.set_shader_parameter("tint", [Color(1, 1, 1), Color(0.8, 0.86, 0.9), Color(0.9, 0.88, 0.78)][variant])
				sm.set_shader_parameter("hem_top", 0.7)
				_shared[key] = sm
				_tarp_mats.append(sm)
			(mi as MeshInstance3D).material_override = _shared[key]
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			(mi as MeshInstance3D).set_instance_shader_parameter("flutter", Color(rng.randf(), rng.randf_range(0.6, 1.2), rng.randf_range(0.2, 0.9), 0.0))
		elif mi is MeshInstance3D:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _turn_wheels(model: Node3D, rng: RandomNumberGenerator) -> void:
	var a := deg_to_rad(rng.randf_range(9.0, 26.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	for w in CarPaint.wheels(model):
		if String(w.name).begins_with("wheel_f"):
			w.transform.basis = Basis(Vector3.UP, a + rng.randf_range(-0.03, 0.03)) * w.transform.basis

## Which side of the car (sign of local z) faces the street, not the kerb.
func _road_side(car: Node3D) -> float:
	var kd: Vector3 = kerb_at(car.global_position)["dir"]
	var local := car.global_basis.inverse() * kd
	return -signf(local.z) if absf(local.z) > 0.1 else 1.0

func _flat_tyre(car: Node3D, model: Node3D, rng: RandomNumberGenerator, road: float) -> void:
	var ws := CarPaint.wheels(model)
	if ws.is_empty():
		return
	var pool: Array = ws
	var seen := ws.filter(func(x: Node3D) -> bool: return signf(x.position.z) == road)
	if rng.randf() < 0.8 and not seen.is_empty():
		pool = seen
	var w: Node3D = pool[rng.randi() % pool.size()]
	var o := w.transform.origin
	w.transform = Transform3D(Basis.from_scale(Vector3(1.1, 0.74, 1.0)), Vector3(o.x, o.y * 0.74, o.z))
	# The car leans onto it.
	var roll := deg_to_rad(1.6) * signf(w.position.z)
	model.transform.basis = Basis(Vector3.RIGHT, roll) * model.transform.basis

func _clamp(model: Node3D, road: float) -> void:
	var ws := CarPaint.wheels(model)
	var w: Node3D = null
	for c in ws:
		if String(c.name).begins_with("wheel_f") and signf(c.position.z) == road:
			w = c
	if w == null:
		return
	var mat := _mat("clamp", Color(0.78, 0.6, 0.04), 0.5, 0.45)
	var out := signf(w.position.z)
	var plate := _box_mi(Vector3(0.36, 0.44, 0.035), mat)
	plate.position = Vector3(0, 0, out * 0.17)
	w.add_child(plate)
	var bar := _box_mi(Vector3(0.07, 0.07, 0.34), mat)
	bar.position = Vector3(0.0, 0.33, out * 0.02)
	w.add_child(bar)
	var lock := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.045
	cyl.height = 0.06
	lock.mesh = cyl
	lock.material_override = _mat("clamp_lock", Color(0.05, 0.05, 0.06), 0.35, 0.8)
	lock.rotation_degrees.x = 90
	lock.position = Vector3(0.08, -0.05, out * 0.21)
	w.add_child(lock)
	for mi in [plate, bar, lock]:
		_prop_flags(mi)

# --- Ground contact -------------------------------------------------------------

func _add_ground(car: Node3D, info: Dictionary, rng: RandomNumberGenerator) -> void:
	var ab := local_box(car)
	var c := ab.get_center()
	# AO and tyre patches: a slab only 0.2 m tall, so it takes the ground and
	# the tyre bottoms and none of the body above.
	var sh := _decal("car_shadow", Vector3(ab.size.x * 1.12, 0.2, ab.size.z * 1.12))
	sh.name = "GroundShadow"
	sh.position = Vector3(c.x, 0.04, c.z)
	sh.upper_fade = 0.4
	sh.lower_fade = 0.4
	car.add_child(sh)
	if info["variant"] == "wreck":
		# A burnt hull sits in its own black.
		sh.modulate = Color(1, 1, 1, 1)
		return
	if rng.randf() < 0.7:
		var oil := _decal("stain_oil", Vector3.ONE)
		var sz := rng.randf_range(0.6, 1.1)
		oil.size = Vector3(sz, 0.2, sz * rng.randf_range(0.7, 1.0))
		oil.name = "OilStain"
		oil.position = Vector3(c.x + ab.size.x * rng.randf_range(0.12, 0.3), 0.04, c.z + rng.randf_range(-0.3, 0.3))
		oil.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		oil.modulate.a = rng.randf_range(0.6, 0.95)
		car.add_child(oil)
	# Rain drips off the exhaust and darkens the road under the tail pipe.
	var wet := _decal("puddle", Vector3(0.9, 0.2, 0.7))
	wet.name = "ExhaustWet"
	wet.texture_orm = load(DEC + "puddle_orm.png")
	wet.position = Vector3(ab.position.x + 0.1, 0.04, c.z + ab.size.z * 0.5 * rng.randf_range(0.35, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0))
	wet.visible = false
	car.add_child(wet)
	_wet_decals.append(wet)

func _decal(tex: String, size: Vector3) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load(DEC + tex + ".png")
	d.albedo_mix = 1.0
	d.size = size
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 24.0
	d.distance_fade_length = 8.0
	return d

func _on_weather(raining: bool) -> void:
	for d in _wet_decals:
		(d as Decal).visible = raining
		(d as Decal).modulate.a = 0.85
	for sm in _tarp_mats:
		(sm as ShaderMaterial).set_shader_parameter("wet", 1.0 if raining else 0.0)

# --- Story props ----------------------------------------------------------------

func _mat(key: String, color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if not _shared.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		_shared[key] = m
	return _shared[key]

func _tex_mat(key: String, tex: String, rough: float, emission := 0.0, scissor := false) -> StandardMaterial3D:
	if not _shared.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DEC + tex + ".png")
		m.roughness = rough
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if emission > 0.0:
			m.emission_enabled = true
			m.emission_texture = m.albedo_texture
			m.emission_energy_multiplier = emission
		if scissor:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_shared[key] = m
	return _shared[key]

func _box_mi(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

func _quad_mi(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	return mi

func _prop_flags(mi: GeometryInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = PROP_REACH
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

## A basis for something lying on a pane: z out of the glass, y up its slope.
static func pane_basis(n: Vector3, roll := 0.0) -> Basis:
	var s := (Vector3.UP - n * n.y).normalized()
	if s.length() < 0.1:
		s = Vector3.UP
	var b := Basis(s.cross(n), s, n)
	return b * Basis(Vector3(0, 0, 1), roll)

func _add_props(car: Node3D, model: Node3D, info: Dictionary, rng: RandomNumberGenerator, road: float) -> void:
	var panels := CarPaint.glass_panels(model)
	var props: Array = info["props"]
	if panels.has("front"):
		var f: Dictionary = panels["front"]
		var n: Vector3 = f["n"]
		var ext: Vector3 = f["ext"]
		var slope := ext.y / maxf(sqrt(maxf(1.0 - n.y * n.y, 0.0)), 0.3)
		var s := (Vector3.UP - n * n.y).normalized()
		var c: Vector3 = f["c"]
		var has_ticket: bool = info["variant"] == "clamp" or rng.randf() < 0.22
		if has_ticket:
			var t := _quad_mi(Vector2(0.21, 0.13), _tex_mat("ticket", "car_ticket", 0.3))
			t.basis = pane_basis(n, rng.randf_range(-0.35, 0.35))
			t.position = c + Vector3(0, 0, -ext.z * 0.2) + s * (-slope * 0.3) + n * 0.012
			_prop_flags(t)
			model.add_child(t)
			props.append("ticket")
		var sale: bool = (not has_ticket or info["variant"] != "clamp") and rng.randf() < 0.09
		if sale:
			var card := _quad_mi(Vector2(0.36, 0.23), _tex_mat("forsale", "car_forsale", 0.85, 1.1))
			card.basis = pane_basis(n, rng.randf_range(-0.12, 0.12))
			card.position = c + Vector3(0, 0, ext.z * 0.2) + s * (-slope * 0.12) - n * 0.035
			_prop_flags(card)
			model.add_child(card)
			props.append("forsale")
		if rng.randf() < 0.26:
			var pine := _quad_mi(Vector2(0.075, 0.125), _tex_mat("pine", "car_pine", 0.9, 0.0, true))
			pine.position = c + s * (slope * 0.46) - n * 0.07 + Vector3(0, -0.07, ext.z * rng.randf_range(-0.05, 0.1))
			pine.rotation = Vector3(0, rng.randf_range(-0.8, 0.8), 0)
			_prop_flags(pine)
			model.add_child(pine)
			props.append("pine")
		if rng.randf() < 0.3:
			var base := c - s * (slope * 0.46) - n * 0.14
			var picks := [0, 1, 2]
			picks.shuffle()
			for pick in picks.slice(0, 2):
				var mi: MeshInstance3D
				match pick:
					0:
						mi = MeshInstance3D.new()
						var cup := CylinderMesh.new()
						cup.top_radius = 0.04
						cup.bottom_radius = 0.03
						cup.height = 0.11
						mi.mesh = cup
						mi.material_override = _mat("cup", Color(0.82, 0.76, 0.62), 0.7)
						mi.position = base + Vector3(0, 0.07, ext.z * 0.18)
					1:
						mi = _box_mi(Vector3(0.22, 0.012, 0.16), _mat("papers", Color(0.74, 0.73, 0.66), 0.9))
						mi.position = base + Vector3(0, 0.02, -ext.z * 0.1)
						mi.rotation = Vector3(0, rng.randf_range(-0.5, 0.5), 0.15)
					_:
						mi = _box_mi(Vector3(0.13, 0.15, 0.07), _mat("bag", Color(0.5, 0.36, 0.22), 0.9))
						mi.position = base + Vector3(0, 0.08, ext.z * 0.05)
						mi.rotation = Vector3(0, rng.randf_range(-0.9, 0.9), 0)
				_prop_flags(mi)
				model.add_child(mi)
			props.append("junk")
	# A smashed window under a bin bag and tape.
	if not props.has("forsale") and rng.randf() < 0.07:
		var side: String = "right" if (road > 0.0) == (rng.randf() < 0.8) else "left"
		if panels.has(side):
			_add_bag(model, panels[side], rng)
			props.append("bag")

func _add_bag(model: Node3D, pane: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = pane["c"]
	var ext: Vector3 = pane["ext"]
	var n: Vector3 = pane["n"]
	var sx := ext.x * 0.5
	var sy := ext.y * 0.92
	var cx := c.x - ext.x * rng.randf_range(0.05, 0.2)
	var black := rng.randf() < 0.65
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 8
	var ny := 5
	var ph := rng.randf() * 6.0
	var g: Array = []
	for i in nx + 1:
		var row: Array = []
		for j in ny + 1:
			var u := float(i) / nx * 2.0 - 1.0
			var v := float(j) / ny * 2.0 - 1.0
			var bulge := (1.0 - u * u) * (1.0 - v * v) * 0.028
			var crease := 0.012 * sin(u * 9.0 + ph) * cos(v * 7.0 + ph * 1.3) * (1.0 - absf(u) * 0.6)
			row.append(Vector3(cx + u * sx * 0.5, c.y + v * sy * 0.5, c.z + n.z * (0.014 + bulge + crease)))
		g.append(row)
	for i in nx:
		for j in ny:
			for v in [g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j], g[i + 1][j + 1], g[i][j + 1]]:
				st.set_smooth_group(0)
				st.add_vertex(v)
	st.generate_normals()
	var bag := MeshInstance3D.new()
	bag.mesh = st.commit()
	bag.name = "TapedBag"
	var key := "bag_black" if black else "bag_clear"
	if not _shared.has(key):
		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if black:
			m.albedo_color = Color(0.015, 0.015, 0.018)
			m.roughness = 0.28
			m.metallic_specular = 0.8
		else:
			m.albedo_color = Color(0.8, 0.84, 0.88, 0.5)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.12
		_shared[key] = m
	bag.material_override = _shared[key]
	_prop_flags(bag)
	model.add_child(bag)
	var tape := _mat("tape", Color(0.58, 0.6, 0.6), 0.32, 0.35)
	var z := c.z + n.z * 0.03
	var w := sx * 0.5 * 2.0 + 0.04
	var h := sy * 0.5 * 2.0 + 0.04
	for e in [[0.0, h * 0.5, w, 0.04], [0.0, -h * 0.5, w, 0.04], [-w * 0.5, 0.0, 0.04, h], [w * 0.5, 0.0, 0.04, h]]:
		var strip := _box_mi(Vector3(e[2], e[3], 0.004), tape)
		strip.position = Vector3(cx + e[0], c.y + e[1], z)
		strip.rotation.z = rng.randf_range(-0.03, 0.03)
		_prop_flags(strip)
		model.add_child(strip)

# --- The double-parked van ------------------------------------------------------------

func _add_double_parked() -> void:
	var ref := city.find_child("CarEastAve3", true, false) as Node3D
	var cell := city.get_node_or_null("Cell_East") as Node3D
	if ref == null or cell == null:
		return
	var van := StaticBody3D.new()
	van.name = "CarEastAveDP"
	cell.add_child(van)
	var model: Node3D = (load("res://assets/cars/van_shvan92.glb") as PackedScene).instantiate()
	model.name = "Model"
	van.add_child(model)
	var box := CarPaint.bounds(model)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, box.size.y, box.size.z - 0.2)
	cs.shape = shape
	cs.position = Vector3(0, box.size.y * 0.5, 0)
	van.add_child(cs)
	var rng := car_rng("CarEastAveDP/park")
	var placed := false
	for t in 12:
		var xf := ref.global_transform
		xf.basis = Basis(Vector3.UP, deg_to_rad(rng.randf_range(2.0, 6.0) * (1.0 if rng.randf() < 0.5 else -1.0))) * ref.global_transform.basis
		xf.origin = Vector3(rng.randf_range(70.0, 70.7), 0.0, ref.global_position.z - rng.randf_range(0.8, 2.2))
		if _hits(footprint(xf, local_box(van), 0.1), van) == "":
			van.global_transform = xf
			placed = true
			break
	if not placed:
		van.queue_free()
		return
	cars.append(van)
	layout[String(van.name)] = {"variant": "double", "turned": false, "props": ["hazards"]}
	_build_hazards(van, box)

func _build_hazards(van: Node3D, box: AABB) -> void:
	_hazard_mat = StandardMaterial3D.new()
	_hazard_mat.albedo_color = Color(0.35, 0.18, 0.02)
	_hazard_mat.emission_enabled = true
	_hazard_mat.emission = Color(1.0, 0.55, 0.08)
	_hazard_mat.emission_energy_multiplier = 0.0
	for end in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			var lamp := _box_mi(Vector3(0.08, 0.1, 0.16), _hazard_mat)
			lamp.position = Vector3((box.end.x - 0.03) if end > 0.0 else (box.position.x + 0.03), 0.7 if end > 0.0 else 0.8, side * 0.78)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lamp.visibility_range_end = CarPaint.PARKED_REACH
			van.add_child(lamp)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.1)
		light.omni_range = 4.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = Vector3(((box.end.x + 0.5) if end > 0.0 else (box.position.x - 0.5)), 0.8, 0.0)
		light.visible = false
		# Switched by the blink and the hour here, not by the street's night lights.
		light.add_to_group("always_lit", true)
		van.add_child(light)
		_hazard_lights.append(light)
	_hazard_sound = AudioStreamPlayer3D.new()
	_hazard_sound.stream = load("res://assets/sfx/hazard_relay_loop.wav")
	_hazard_sound.volume_db = -13.0
	_hazard_sound.unit_size = 2.0
	_hazard_sound.max_distance = 14.0
	_hazard_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_hazard_sound.finished.connect(_hazard_sound.play)
	_hazard_sound.autoplay = true
	van.add_child(_hazard_sound)

func _process(_delta: float) -> void:
	if _hazard_mat == null:
		return
	# On for the first half of the relay's 1.2 s loop, in step with its tick.
	var t := _hazard_sound.get_playback_position() if _hazard_sound != null and _hazard_sound.playing else fmod(Time.get_ticks_msec() / 1000.0, 1.2)
	var on := fmod(t, 1.2) < 0.6
	var night := GameState.daylight() < 0.5
	_hazard_mat.emission_energy_multiplier = (2.6 if night else 1.4) if on else 0.0
	for l in _hazard_lights:
		(l as OmniLight3D).visible = on and night
		(l as OmniLight3D).light_energy = 0.9 if on else 0.0
