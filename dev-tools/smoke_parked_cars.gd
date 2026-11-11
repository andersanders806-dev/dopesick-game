extends "res://dev-tools/smoke_test_3d.gd"
## The parked cars (world/ParkedRow.gd): laid out crooked but from a seed, none
## touching the kerb, a wall, a door or each other, all grounded, the searchable
## ones still searchable, the livery cars still painted, the mix and the
## special cars all there.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_parked_cars.gd
## Loaded in _run (the script uses the GameState autoload, which a preload here would compile too early for).
var ParkedRow: GDScript

func _snapshot(city: Node) -> Dictionary:
	var out := {}
	for car in ParkedRow.find_cars(city):
		var xf: Transform3D = (car as Node3D).global_transform
		out[String(car.name)] = [snappedf(xf.origin.x, 0.001), snappedf(xf.origin.z, 0.001), snappedf(xf.basis.get_euler().y, 0.001), ParkedRow.kind_of(car), String((car.get_meta("parked") as Dictionary)["variant"])]
	return out

func _run() -> void:
	ParkedRow = load("res://world/ParkedRow.gd")
	await _section("Parked cars: seeded crooked layout, grounded, searchable")
	var gs := _gs()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var row: Node3D = city.get("parked_row")
	_check(row != null and row.cars.size() >= 30, "  ParkedRow laid out %d cars" % (row.cars.size() if row else 0))
	var a := _snapshot(city)
	var xfs := {}
	for car in row.cars:
		xfs[String(car.name)] = (car as Node3D).global_transform
	# Same seed, same street.
	city = await _load("res://world/City3D.tscn")
	var b := _snapshot(city)
	_check(a == b, "  the same seed gives the same layout, models and variants (%d cars)" % a.size())
	ParkedRow.set("world_seed", 7)
	city = await _load("res://world/City3D.tscn")
	var c := _snapshot(city)
	var moved := 0
	for k in a:
		if c.has(k) and (c[k][0] != a[k][0] or c[k][2] != a[k][2]):
			moved += 1
	_check(moved > a.size() / 2, "  another seed parks them differently (%d of %d moved)" % [moved, a.size()])
	ParkedRow.set("world_seed", 1990)
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	row = city.get("parked_row")
	var cars: Array = row.cars
	# Crooked, but only a little: yaw off the street's axis.
	var odd := []
	for car in cars:
		var info: Dictionary = car.get_meta("parked")
		if info["variant"] in ["plain", "flat", "clamp", "tarp", "kerb"] and String(car.name) != "CarEastAveDP":
			var bx: Vector3 = (car as Node3D).global_basis.x
			var yaw := rad_to_deg(atan2(-bx.z, bx.x))
			var off := fmod(absf(yaw) + 45.0, 90.0) - 45.0
			if absf(off) > 7.5 or (absf(off) < 0.5 and info["variant"] != "tarp"):
				odd.append("%s %.1f" % [car.name, off])
	_check(odd.size() <= 2, "  yaws are a degree or three off true, not dead straight and not skewed %s" % [odd])
	# Nothing touches anything.
	var obstacles: Array = ParkedRow.gather_obstacles(city)
	var touching := []
	for car in cars:
		var poly: PackedVector2Array = ParkedRow.car_footprint(car as Node3D)
		for o in obstacles:
			if ParkedRow.poly_overlap(poly, o["poly"]):
				touching.append("%s x %s" % [car.name, o["name"]])
		for other in cars:
			if other != car and String(other.name) > String(car.name) and ParkedRow.poly_overlap(poly, ParkedRow.car_footprint(other as Node3D, 0.1)):
				touching.append("%s x %s" % [car.name, other.name])
	_check(touching.is_empty(), "  no car touches a wall, bin, hydrant, door, lamp or another car %s" % [touching])
	# The kerb: a gap of 0.1-0.5 m (the climber is the exception, and wrecks lie as they fell).
	var gaps := []
	var climbers := 0
	for car in cars:
		var info: Dictionary = car.get_meta("parked")
		var kerb: Dictionary = ParkedRow.kerb_at((car as Node3D).global_position)
		if is_nan(kerb["face"]) or info["variant"] == "double":
			continue
		var reach := -INF
		for q in ParkedRow.car_footprint(car as Node3D):
			reach = maxf(reach, kerb["dir"].x * q.x + kerb["dir"].z * q.y)
		var gap: float = kerb["face"] - reach
		if info["variant"] == "kerb":
			climbers += 1
			if gap > -0.3:
				gaps.append("%s climber at %.2f" % [car.name, gap])
		elif info["variant"] != "wreck" and (gap < 0.1 or gap > 0.5):
			gaps.append("%s %.2f" % [car.name, gap])
	_check(gaps.is_empty(), "  every car on a kerb is 0.15-0.45 m off it (%d with two wheels up) %s" % [climbers, gaps])
	_check(climbers == 1, "  one car is parked half up on the kerb (%d)" % climbers)
	# Grounded.
	var floating := cars.filter(func(car: Node) -> bool: return car.get_node_or_null("GroundShadow") == null)
	_check(floating.is_empty(), "  every car has its contact shadow %s" % [floating.map(func(c: Node) -> String: return String(c.name))])
	var low := []
	for car in cars:
		var box: AABB = ParkedRow.local_box(car as Node3D)
		var lowest: float = ((car as Node3D).global_transform * Vector3(0, box.position.y, 0)).y
		if absf(lowest) > 0.05:
			low.append("%s %.2f" % [car.name, lowest])
	_check(low.is_empty(), "  every car sits on the ground (no float or sink over 5 cm) %s" % [low])
	_check(city.find_children("ExhaustWet", "Decal", true, false).all(func(d: Node) -> bool: return not (d as Decal).visible), "  dry: no wet patches under the tail pipes")
	# The mix.
	var count := {}
	for car in cars:
		var v: String = (car.get_meta("parked") as Dictionary)["variant"]
		count[v] = count.get(v, 0) + 1
	var tarps: int = count.get("tarp", 0) + count.get("tarp_half", 0)
	_check(count.get("wreck", 0) >= 3 and count.get("flat", 0) == 2 and count.get("clamp", 0) == 1 and count.get("tarp_half", 0) == 2 and count.get("double", 0) == 1,
		"  the mix: %s" % [count])
	_check(tarps >= 6 and tarps <= 12, "  about a fifth under tarps (%d of %d)" % [tarps, cars.size()])
	var turned := cars.filter(func(car: Node) -> bool: return (car.get_meta("parked") as Dictionary)["turned"])
	_check(turned.size() >= 2 and turned.size() <= cars.size() / 2, "  front wheels turned on %d cars" % turned.size())
	var wrecks := cars.filter(func(car: Node) -> bool: return (car.get_meta("parked") as Dictionary)["variant"] == "wreck")
	_check(wrecks.all(func(car: Node) -> bool: return absf((car as Node3D).global_position.x) > 40.0 or (car as Node3D).global_position.z < -60.0), "  wrecks stand toward the ends of the street")
	# Props are there and small.
	var props := 0
	for car in cars:
		props += ((car.get_meta("parked") as Dictionary)["props"] as Array).size()
	_check(props >= 8, "  story props on the cars (%d)" % props)
	# The double-parked van blinks.
	var van := city.find_child("CarEastAveDP", true, false) as Node3D
	_check(van != null and van.find_children("*", "OmniLight3D", false, false).size() == 2 and van.find_children("*", "AudioStreamPlayer3D", false, false).size() == 1,
		"  a van double-parked on East Ave with hazard lamps and the relay's tick")
	if van != null:
		_check(van.find_children("*", "OmniLight3D", false, false).all(func(l: Node) -> bool: return l.is_in_group("always_lit")), "  ...its lamps are tagged so the street's after-dark switch check leaves them to the blink")
		var mat: StandardMaterial3D = null
		for mi in van.find_children("*", "MeshInstance3D", false, false):
			if (mi as MeshInstance3D).material_override is StandardMaterial3D and ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled:
				mat = (mi as MeshInstance3D).material_override
		var seen := {}
		for i in 80:
			await process_frame
			if mat != null:
				seen[snappedf(mat.emission_energy_multiplier, 0.1)] = true
			await create_timer(0.03).timeout
		_check(mat != null and seen.size() >= 2, "  ...and they blink (%d energy levels seen)" % seen.size())
	# Searchable cars still are.
	var zones := get_nodes_in_group("scavenge").filter(func(z: Node) -> bool: return z.get_meta("car", false))
	var near := 0
	for z in zones:
		var car := city.find_child(String(z.get_meta("spot")), true, false) as Node3D
		if car != null and absf(car.global_position.x - (z as Node3D).global_position.x) < 1.5 and absf(car.global_position.z - (z as Node3D).global_position.z) < 2.5:
			near += 1
	_check(zones.size() == 3 and near == 3, "  CarA, CarB and CarC are still searchable, their spots with the cars (%d, %d near)" % [zones.size(), near])
	# Livery cars still painted, and cleaner than the rest.
	var cruiser := city.find_child("PoliceCruiser", true, false)
	var body := cruiser.get_node("Model").find_child("body", true, false) as MeshInstance3D
	var sm := body.get_surface_override_material(0) as ShaderMaterial
	var w: Vector4 = body.get_instance_shader_parameter("wear")
	_check(sm != null and float(sm.get_shader_parameter("livery")) == 1.0 and w.x < 0.35 and w.y == 0.0, "  the cruiser keeps its livery, clean-ish, no rust (dirt %.2f rust %.2f)" % [w.x, w.y])
	var dirty := 0
	for car in cars:
		var bm := car.get_node("Model").find_child("body", true, false) as MeshInstance3D
		if bm != null and bm.get_surface_override_material(0) is ShaderMaterial and (bm.get_instance_shader_parameter("wear") as Vector4).x > 0.5:
			dirty += 1
	_check(dirty >= 5, "  and the rest are dirtier, each its own (%d dirty)" % dirty)
	# Rain: patches under the exhausts.
	gs.set_raining(true)
	await _frames(4)
	var wet := city.find_children("ExhaustWet", "Decal", true, false)
	_check(wet.size() >= 20 and wet.all(func(d: Node) -> bool: return (d as Decal).visible), "  raining: a wet patch under each tail pipe (%d)" % wet.size())
	gs.set_raining(false)
	# Dead Block: paint and grounding only, the layout the wrecks were built round.
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	var zcity := await _load("res://world/City3D.tscn")
	await _frames(3)
	var zrow: Node3D = zcity.get("parked_row")
	_check(zrow != null and zrow.cars.all(func(car: Node) -> bool: return car.get_node_or_null("GroundShadow") != null), "  Dead Block: cars are grounded too (%d)" % zrow.cars.size())
	_check(zcity.find_children("*", "StaticBody3D", true, false).filter(func(x: Node) -> bool: return x.is_in_group("wrecks")).size() >= 4, "  ...and its wrecks are still there")
	zm.leave()
	DirAccess.remove_absolute(zm.PATH)
