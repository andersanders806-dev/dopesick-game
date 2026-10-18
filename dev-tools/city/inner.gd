extends RefCounted
## The inside of the block (x -65..65, z -85..-16), behind Main Street's
## shops:
##
## - The park (west): worn grass and dead trees inside a chain-link fence,
##   a basketball court with its own taller fence, benches. Two gates --
##   West Ave and Back Street -- are the only ways in, so they're the
##   chokepoints.
## - The alley loop (middle): the pusher's two alleys at x = 14 and 21 now
##   run through to a service lane behind the shops; from the lane the back
##   alley runs north to Back Street. Dumpsters, back doors, fire escapes.
## - The lot (east) and the underpass: a gravel lot with a billboard and a
##   container, fenced from the camp under the overpass. The overpass is
##   the east landmark; under it, tents and a fire barrel. Its fence to
##   East Ave has one gap.

const Kit := preload("res://dev-tools/city/kit.gd")

static func build(b: Node, _root: Node3D) -> void:
	var c := Kit.cell(b, "Cell_Inner")
	var main := Kit.cell(b, "Cell_Main")
	_alleys(b, c, main)
	_park(b, c)
	_lot(b, c)
	_underpass(b, c)

# --- The alley loop ------------------------------------------------------------------

static func _alleys(b: Node, c: Node3D, main: Node3D) -> void:
	# Under Main's row of buildings, so the alley mouths and any slit
	# between buildings have ground (the old alley slabs sit on top).
	Kit.ground(b, main, "RowGround", -65.0, -16.0, 56.0, -4.5, "asphalt", -0.01)
	for ax in [14.0, 21.0]:
		b._box_mesh(main, "Alley%dNorth" % int(ax), Vector3(2.2, 0.1, 6.5), Vector3(ax, -0.04, -12.75), Kit.mat(b, "asphalt"))
	Kit.ground(b, c, "ServiceLane", -9.0, -19.0, 36.0, -16.0, "asphalt")
	Kit.ground(b, c, "BackAlley", -9.0, -85.0, -6.0, -19.0, "asphalt")
	# The lane: dumpsters along the inner block's back wall, bags, back
	# doors under security lights.
	Kit.dumpster(b, c, "LaneDumpster1", Vector3(16.6, 0, -18.4))
	Kit.dumpster(b, c, "LaneDumpster2", Vector3(18.6, 0, -18.4), 4.0)
	Kit.bags(b, c, "LaneBags1", Vector3(20.4, 0, -18.6), 4, 81)
	Kit.dumpster(b, c, "LaneDumpster3", Vector3(2.5, 0, -18.4))
	Kit.bags(b, c, "LaneBags2", Vector3(4.6, 0, -18.6), 3, 82)
	Kit.bags(b, c, "LaneBags3", Vector3(30.0, 0, -18.6), 2, 83)
	b._ph(c, "LaneCrates", "wooden_crate_01", Vector3(-3.4, 0, -18.5), 1.0, 12.0)
	b._ph(c, "LaneTyre", "old_tyre", Vector3(25.3, 0.3, -18.6), 1.0, 40.0)
	for d in [[0.0, -19.0], [8.5, -19.0], [24.0, -19.0], [33.0, -19.0]]:
		_back_door(b, c, "LaneDoor%d" % int(d[0] + 10), Vector3(d[0], 0, d[1]), 0.0)
	for d in [-30.0, -62.0]:
		_back_door(b, c, "AlleyDoorW%d" % int(-d), Vector3(-9.0, 0, d), 90.0)
		_back_door(b, c, "AlleyDoorE%d" % int(-d), Vector3(-6.0, 0, d - 6.0), -90.0)
	# The back alley: a skip and pallets half across it at the midpoint,
	# so it's not one 70 m straight shot to Back Street.
	Kit.dumpster(b, c, "AlleyDumpster", Vector3(-8.0, 0, -47.5), 90.0)
	b._solid(c, "AlleyPallets", Vector3(1.0, 1.8, 1.2), Vector3(-6.6, 0.9, -51.0), Kit.mat(b, "wood"))
	Kit.bags(b, c, "AlleyBags", Vector3(-8.2, 0, -44.8), 3, 84)
	Kit.bags(b, c, "AlleyBags2", Vector3(-6.8, 0, -72.0), 2, 85)
	b._ph(c, "AlleyCrate", "wooden_crate_02", Vector3(-8.3, 0, -66.0), 1.0, 30.0)
	Kit.place(b, "Place_AlleyDumpsters", Vector3(17.6, 0, -17.0))

## A steel back door flush with the wall, a step, and a caged security
## light over it that's on all night.
static func _back_door(b: Node, c: Node3D, n: String, pos: Vector3, yaw: float) -> void:
	var d := Node3D.new()
	d.name = n
	b._add(c, d)
	d.position = pos
	d.rotation_degrees.y = yaw
	b._box_mesh(d, "Door", Vector3(1.0, 2.1, 0.08), Vector3(0, 1.05, 0.05), Kit.mat(b, "metal"))
	b._box_mesh(d, "Step", Vector3(1.4, 0.12, 0.45), Vector3(0, 0.06, 0.24), Kit.mat(b, "concrete_dark"))
	b._ph(d, "Lamp", "security_light", Vector3(0, 2.55, 0.05), 1.0)
	Kit.night_light(b, d, "Light", Vector3(0, 2.4, 0.6), Color(1.0, 0.78, 0.5), 0.9, 5.0)

# --- The park ------------------------------------------------------------------------

const COURT := Rect2(-56.0, -62.0, 15.0, 28.0)

static func _park(b: Node, c: Node3D) -> void:
	Kit.ground(b, c, "ParkGround", -65.0, -70.0, -30.0, -16.0, "park")
	Kit.ground(b, c, "ParkGroundN", -50.0, -85.0, -30.0, -70.0, "park")
	# Paths: in from the West Ave gate along the south, up the east side
	# to the north gate, and a spur to the court's door.
	Kit.ground(b, c, "ParkPathW", -65.0, -25.6, -38.0, -22.4, "sidewalk", 0.012)
	Kit.ground(b, c, "ParkPathN", -38.0, -85.0, -35.0, -22.4, "sidewalk", 0.012)
	Kit.ground(b, c, "ParkPathCourt", -40.5, -45.6, -38.0, -42.4, "sidewalk", 0.012)
	# The fence and its two gates.
	Kit.fence(b, c, "ParkFenceW1", Vector3(-65.0, 0, -70.0), Vector3(-65.0, 0, -26.0))
	Kit.fence(b, c, "ParkFenceW2", Vector3(-65.0, 0, -22.0), Vector3(-65.0, 0, -16.0))
	Kit.fence(b, c, "ParkFenceN1", Vector3(-50.0, 0, -85.0), Vector3(-38.5, 0, -85.0))
	Kit.fence(b, c, "ParkFenceN2", Vector3(-34.5, 0, -85.0), Vector3(-30.0, 0, -85.0))
	_gate(b, c, "ParkGateW", Vector3(-65.0, 0, -24.0), 90.0, "MEMORIAL PARK\nCLOSES 10 PM")
	_gate(b, c, "ParkGateN", Vector3(-36.5, 0, -85.0), 0.0, "PARK CLOSES 10 PM")
	# The court: patched asphalt, worn lines, two hoops, its own fence with
	# a door on the path side.
	var court_mid := COURT.get_center()
	Kit.ground(b, c, "Court", COURT.position.x, COURT.position.y, COURT.end.x, COURT.end.y, "court", 0.008)
	var lines: Decal = b._decal("CourtLines", "res://assets/decals/court_lines.png", Vector3(court_mid.x, 0.0, court_mid.y), COURT.size.x, COURT.size.y, "floor", 0.0, Color(1, 1, 1, 0.85), c)
	lines.size.y = 0.3
	var fx0 := COURT.position.x - 0.5
	var fx1 := COURT.end.x + 0.5
	var fz0 := COURT.position.y - 0.5
	var fz1 := COURT.end.y + 0.5
	Kit.fence(b, c, "CourtFenceW", Vector3(fx0, 0, fz0), Vector3(fx0, 0, fz1), 4.0)
	Kit.fence(b, c, "CourtFenceN", Vector3(fx0, 0, fz0), Vector3(fx1, 0, fz0), 4.0)
	Kit.fence(b, c, "CourtFenceS", Vector3(fx0, 0, fz1), Vector3(fx1, 0, fz1), 4.0)
	Kit.fence(b, c, "CourtFenceE1", Vector3(fx1, 0, fz0), Vector3(fx1, 0, -45.6), 4.0)
	Kit.fence(b, c, "CourtFenceE2", Vector3(fx1, 0, -42.4), Vector3(fx1, 0, fz1), 4.0)
	_hoop(b, c, "HoopN", Vector3(court_mid.x, 0, COURT.position.y + 0.3), 0.0)
	_hoop(b, c, "HoopS", Vector3(court_mid.x, 0, COURT.end.y - 0.3), 180.0)
	Kit.place(b, "Place_Court", Vector3(court_mid.x, 0, court_mid.y))
	# Benches on the path; the regulars' one looks across at the court.
	Kit.bench(b, c, "ParkBench1", Vector3(-46.0, 0, -27.6), 0.0)
	Kit.bench(b, c, "ParkBench2", Vector3(-55.0, 0, -27.6), 0.0)
	Kit.bench(b, c, "ParkBench3", Vector3(-33.4, 0, -50.0), -90.0)
	Kit.bench(b, c, "ParkBench4", Vector3(-33.4, 0, -74.0), -90.0)
	Kit.place(b, "Place_ParkBench", Vector3(-46.0, 0, -26.6))
	_chess_table(b, c, Vector3(-58.0, 0, -19.4))
	var trees := [Vector3(-62.0, 0, -30.0), Vector3(-60.5, 0, -38.5), Vector3(-61.0, 0, -50.0), Vector3(-63.0, 0, -55.5),
		Vector3(-52.0, 0, -67.0), Vector3(-44.0, 0, -67.5), Vector3(-32.5, 0, -30.0), Vector3(-32.5, 0, -40.0),
		Vector3(-32.5, 0, -61.0), Vector3(-46.0, 0, -79.0), Vector3(-41.5, 0, -81.5), Vector3(-32.5, 0, -81.0),
		Vector3(-51.0, 0, -19.6), Vector3(-41.0, 0, -19.0)]
	for i in trees.size():
		Kit.tree(b, c, "Tree%d" % (i + 1), trees[i], i)
	var lamps := [Vector3(-58.0, 0, -21.8), Vector3(-44.0, 0, -21.8), Vector3(-34.6, 0, -56.0), Vector3(-34.6, 0, -78.0)]
	for i in lamps.size():
		b._streetlight("StreetlightPark%d" % (i + 1), lamps[i].x, lamps[i].z, 50 + i, c, [180.0, 180.0, -90.0, -90.0][i])
	Kit.trash_can(b, c, "ParkBin1", Vector3(-47.9, 0, -27.9))
	Kit.trash_can(b, c, "ParkBin2", Vector3(-34.6, 0, -64.0))
	Kit.trash_can(b, c, "ParkBin3", Vector3(-33.6, 0, -78.0))
	Kit.bags(b, c, "ParkBags", Vector3(-63.6, 0, -18.0), 2, 86)
	Kit.bags(b, c, "ParkBags2", Vector3(-33.4, 0, -46.6), 2, 91)
	Kit.bench(b, c, "ParkBench5", Vector3(-52.0, 0, -21.0), 180.0)
	Kit.bench(b, c, "ParkBench6", Vector3(-33.4, 0, -37.0), -90.0)
	_swings(b, c, Vector3(-61.0, 0, -65.0))
	_picnic_table(b, c, "Picnic1", Vector3(-60.0, 0, -44.0), 10.0)
	_picnic_table(b, c, "Picnic2", Vector3(-45.0, 0, -74.0), -15.0)
	Kit.cart(b, c, "ParkCart", Vector3(-62.8, 0, -36.0), 100.0)
	b._box_mesh(c, "ParkMattress", Vector3(1.9, 0.18, 0.95), Vector3(-36.6, 0.09, -82.4), b._tex_mat("res://assets/env3d/mattress_stained.png", 0.6, 0.95)).rotation_degrees.y = 12.0

## A swing set with one seat left: steel A-frames, a top bar, chains.
static func _swings(b: Node, c: Node3D, pos: Vector3) -> void:
	var s := StaticBody3D.new()
	s.name = "Swings"
	b._add(c, s)
	s.position = pos
	var steel := Kit.mat(b, "steel")
	b._cylinder(s, "TopBar", 0.05, 4.2, Vector3(0, 2.4, 0), steel).rotation_degrees.z = 90.0
	for ex in [-2.0, 2.0]:
		for lean in [-1.0, 1.0]:
			var leg: MeshInstance3D = b._cylinder(s, "Leg", 0.05, 2.55, Vector3(ex, 1.2, lean * 0.42), steel)
			leg.rotation_degrees.x = lean * 20.0
	for sx in [-1.0, 1.0]:
		b._box_mesh(s, "Chain", Vector3(0.02, 1.8, 0.02), Vector3(sx - 0.22, 1.5, 0), steel)
		b._box_mesh(s, "Chain", Vector3(0.02, 1.8, 0.02), Vector3(sx + 0.22, 1.5, 0), steel)
	b._box_mesh(s, "Seat", Vector3(0.5, 0.04, 0.2), Vector3(-1.0, 0.6, 0), b._color_mat(Color(0.1, 0.1, 0.1), 0.8))
	b._box_mesh(s, "Seat2", Vector3(0.5, 0.04, 0.2), Vector3(1.0, 0.25, 0.15), b._color_mat(Color(0.5, 0.15, 0.1), 0.8)).rotation_degrees.x = 50.0
	b._collision(s, b._box_shape(Vector3(4.2, 2.5, 0.3)), Vector3(0, 1.25, 0))

## A wooden picnic table, benches built on.
static func _picnic_table(b: Node, c: Node3D, n: String, pos: Vector3, yaw: float) -> void:
	var t: StaticBody3D = b._solid(c, n, Vector3(1.8, 0.75, 1.6), pos + Vector3(0, 0.375, 0), null)
	t.rotation_degrees.y = yaw
	var wood := Kit.mat(b, "wood")
	b._box_mesh(t, "Top", Vector3(1.8, 0.06, 0.8), Vector3(0, 0.36, 0), wood)
	for side in [-1.0, 1.0]:
		b._box_mesh(t, "Seat", Vector3(1.8, 0.05, 0.28), Vector3(0, -0.06, side * 0.66), wood)
		b._box_mesh(t, "Legs", Vector3(0.08, 0.72, 1.5), Vector3(side * 0.7, -0.02, 0), wood)

## An open gate in the park fence: two swung-back leaves and the park's
## sign on the frame above. `yaw` 90 for a gate in a north-south fence.
static func _gate(b: Node, c: Node3D, n: String, pos: Vector3, yaw: float, sign: String) -> void:
	var g := Node3D.new()
	g.name = n
	b._add(c, g)
	g.position = pos
	g.rotation_degrees.y = yaw
	var leaf := Kit._kit_mesh(Kit.CHAINLINK, "modular_chainlink_fence_door_gate")
	var lb := leaf.get_aabb()
	for side in [-1.0, 1.0]:
		# Hinged on its post, swung back (80 degrees) out of the way.
		var hinge := Node3D.new()
		hinge.name = "Hinge"
		b._add(g, hinge)
		hinge.position = Vector3(side * 2.0, 0, 0)
		hinge.rotation_degrees.y = side * -80.0
		var mi := MeshInstance3D.new()
		mi.name = "Leaf"
		mi.mesh = leaf
		b._add(hinge, mi)
		mi.position = Vector3(-side * lb.size.x / 2.0 - lb.get_center().x, -lb.position.y, -lb.get_center().z)
	var steel := Kit.mat(b, "steel")
	for side in [-1.0, 1.0]:
		b._solid(g, "GatePost", Vector3(0.14, 2.9, 0.14), Vector3(side * 2.0, 1.45, 0), steel)
	b._box_mesh(g, "Bar", Vector3(4.1, 0.1, 0.1), Vector3(0, 2.85, 0), steel)
	var label := Label3D.new()
	label.name = "Sign"
	label.text = sign
	label.font_size = 30
	label.pixel_size = 0.006
	label.modulate = Color(0.95, 0.92, 0.8)
	label.outline_modulate = Color(0.08, 0.2, 0.1, 1.0)
	label.outline_size = 14
	b._add(g, label)
	label.position = Vector3(0, 2.55, -0.08)
	label.rotation_degrees.y = 180.0
	var back := label.duplicate() as Label3D
	back.name = "SignBack"
	b._add(g, back)
	back.position = Vector3(0, 2.55, 0.08)
	back.rotation_degrees.y = 0.0

## A hoop on a bent pole, facing into the court from `pos` (yaw 0: the
## board faces south).
static func _hoop(b: Node, c: Node3D, n: String, pos: Vector3, yaw: float) -> void:
	var h := StaticBody3D.new()
	h.name = n
	b._add(c, h)
	h.position = pos
	h.rotation_degrees.y = yaw
	var steel := Kit.mat(b, "steel")
	b._cylinder(h, "Pole", 0.07, 3.4, Vector3(0, 1.7, -0.6), steel)
	b._box_mesh(h, "Arm", Vector3(0.1, 0.1, 1.0), Vector3(0, 3.35, -0.1), steel)
	b._box_mesh(h, "Board", Vector3(1.8, 1.05, 0.05), Vector3(0, 3.35, 0.4), b._color_mat(Color(0.8, 0.8, 0.78), 0.6))
	b._box_mesh(h, "Square", Vector3(0.6, 0.45, 0.01), Vector3(0, 3.2, 0.43), b._color_mat(Color(0.6, 0.15, 0.1), 0.6))
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.21
	torus.outer_radius = 0.24
	torus.material = b._color_mat(Color(0.8, 0.3, 0.08), 0.5)
	rim.mesh = torus
	b._add(h, rim)
	rim.position = Vector3(0, 3.05, 0.68)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.12
	cyl.height = 3.4
	b._collision(h, cyl, Vector3(0, 1.7, -0.6))

## A concrete chess table and two stools, by the West Ave gate.
static func _chess_table(b: Node, c: Node3D, pos: Vector3) -> void:
	var stone := Kit.mat(b, "concrete")
	var t: StaticBody3D = b._solid(c, "ChessTable", Vector3(0.8, 0.75, 0.8), pos + Vector3(0, 0.375, 0), null)
	b._box_mesh(t, "Top", Vector3(0.9, 0.08, 0.9), Vector3(0, 0.34, 0), stone)
	b._cylinder(t, "Leg", 0.15, 0.7, Vector3(0, -0.02, 0), stone)
	b._box_mesh(t, "Board", Vector3(0.5, 0.01, 0.5), Vector3(0, 0.385, 0), b._color_mat(Color(0.15, 0.13, 0.12), 0.7))
	for side in [-1.0, 1.0]:
		b._cylinder(c, "ChessStool", 0.18, 0.45, pos + Vector3(side * 0.85, 0.225, 0), stone)

# --- The lot -------------------------------------------------------------------------

static func _lot(b: Node, c: Node3D) -> void:
	Kit.ground(b, c, "LotGround", 36.0, -85.0, 56.0, -16.0, "gravel")
	Kit.fence(b, c, "LotFenceN1", Vector3(36.0, 0, -85.0), Vector3(44.0, 0, -85.0))
	Kit.fence(b, c, "LotFenceN2", Vector3(48.0, 0, -85.0), Vector3(56.0, 0, -85.0))
	_gate(b, c, "LotGate", Vector3(46.0, 0, -85.0), 0.0, "NO DUMPING")
	# Between the lot and the camp: whole, for now.
	Kit.fence(b, c, "LotFenceE", Vector3(56.0, 0, -85.0), Vector3(56.0, 0, -16.0))
	# A container the lane looks straight at, and a burnt-out car.
	var box: StaticBody3D = b._solid(c, "Container", Vector3(2.44, 2.59, 6.06), Vector3(45.5, 1.295, -21.5), Kit.mat(b, "corrugated"))
	(box.get_node("Mesh") as MeshInstance3D).material_override = _rust(b, Color(0.52, 0.27, 0.17))
	var box2: StaticBody3D = b._solid(c, "Container2", Vector3(6.06, 2.59, 2.44), Vector3(41.0, 1.295, -58.0), Kit.mat(b, "corrugated"))
	(box2.get_node("Mesh") as MeshInstance3D).material_override = _rust(b, Color(0.22, 0.3, 0.38))
	# A burnt-out car: Kenney's sedan, blackened, on its rims.
	var wreck := StaticBody3D.new()
	wreck.name = "CarLotWreck"
	b._add(c, wreck)
	wreck.position = Vector3(50.5, 0, -44.0)
	wreck.rotation_degrees.y = 30.0
	Kit.copy_model(b, wreck, "Model", "res://assets/kenney/cars/sedan.glb",
		Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * 1.6), Vector3(0, 0.3, 0)), b._color_mat(Color(0.08, 0.07, 0.065), 0.95))
	b._collision(wreck, b._box_shape(Vector3(3.8, 1.2, 1.7)), Vector3(0, 0.6, 0))
	for i in 4:
		b._ph(c, "LotTyre%d" % i, "old_tyre", Vector3(39.0 + (i % 2) * 0.5, 0.3 + (i / 2) * 0.25, -70.0 + (i % 2) * 0.3), 1.0, i * 40.0)
	b._ph(c, "LotCrate1", "wooden_crate_01", Vector3(53.2, 0, -66.0), 1.0, 20.0)
	b._ph(c, "LotCrate2", "wooden_crate_02", Vector3(53.9, 0, -67.2), 1.0, 70.0)
	b._ph(c, "LotPropane", "propane_tank", Vector3(38.5, 0, -33.0), 1.0, 0.0)
	Kit.bags(b, c, "LotBags", Vector3(37.4, 0, -46.0), 5, 87)
	Kit.dumpster(b, c, "LotDumpster", Vector3(37.4, 0, -40.0), 90.0)
	# Rusted drums (the stove barrels, cold) and a porta-john nobody empties.
	for i in 4:
		b._ph(c, "LotDrum%d" % i, "barrel_stove", Vector3(54.4 + (i % 2) * 0.75, 0, -55.5 - (i / 2) * 0.75), 1.2, i * 70.0)
	var john: StaticBody3D = b._solid(c, "PortaJohn", Vector3(1.2, 2.3, 1.2), Vector3(38.2, 1.15, -78.5), b._color_mat(Color(0.18, 0.32, 0.55), 0.6))
	b._box_mesh(john, "Roof", Vector3(1.3, 0.1, 1.3), Vector3(0, 1.2, 0), b._color_mat(Color(0.85, 0.85, 0.82), 0.6))
	b._box_mesh(john, "Door", Vector3(0.8, 1.9, 0.02), Vector3(0, -0.1, 0.61), b._color_mat(Color(0.15, 0.27, 0.48), 0.6))
	b._solid(c, "LotPallets2", Vector3(1.2, 1.6, 1.0), Vector3(54.8, 0.8, -26.0), Kit.mat(b, "wood"))
	Kit.cart(b, c, "LotCart", Vector3(52.0, 0, -30.5), 120.0)
	b._box_mesh(c, "LotMattress", Vector3(1.9, 0.18, 0.95), Vector3(48.0, 0.09, -72.5), b._tex_mat("res://assets/env3d/mattress_stained.png", 0.6, 0.95)).rotation_degrees.y = 35.0
	b._solid(c, "LotPallets", Vector3(1.2, 1.1, 1.0), Vector3(54.6, 0.55, -36.0), Kit.mat(b, "wood"))
	for i in 6:
		var p := Vector3(38.0 + fmod(i * 7.3, 17.0), 0.0, -24.0 - i * 9.5)
		b._decal("LotWeeds%d" % i, "res://assets/decals/stain_dark.png", p, 3.5, 2.6, "floor", i * 47.0, Color(0.35, 0.42, 0.22, 0.85), c)
	_billboard(b, c, Vector3(46.0, 0, -80.5))

## Container steel in a faded paint.
static func _rust(b: Node, paint: Color) -> Material:
	var m := (Kit.mat(b, "corrugated") as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = paint
	return m

## A billboard on two steel legs at the back of the lot, facing south down
## it, lit at night by two lamps on its catwalk.
static func _billboard(b: Node, c: Node3D, pos: Vector3) -> void:
	var bb := Node3D.new()
	bb.name = "Billboard"
	b._add(c, bb)
	bb.position = pos
	var steel := Kit.mat(b, "steel")
	for lx in [-2.5, 2.5]:
		b._solid(bb, "Leg", Vector3(0.4, 6.0, 0.4), Vector3(lx, 3.0, 0), steel)
	b._box_mesh(bb, "Face", Vector3(9.0, 4.0, 0.2), Vector3(0, 8.0, 0), b._color_mat(Color(0.86, 0.84, 0.78), 0.8))
	b._box_mesh(bb, "Catwalk", Vector3(9.0, 0.08, 0.8), Vector3(0, 5.95, 0.45), steel)
	var ad := Label3D.new()
	ad.name = "Ad"
	ad.text = "HURT AT WORK?\nGET PAID."
	ad.font_size = 120
	ad.pixel_size = 0.012
	ad.modulate = Color(0.75, 0.12, 0.1)
	ad.outline_size = 0
	b._add(bb, ad)
	ad.position = Vector3(0, 8.4, 0.11)
	var phone := Label3D.new()
	phone.name = "Phone"
	phone.text = "555-0142  DIAZ & DIAZ"
	phone.font_size = 64
	phone.pixel_size = 0.012
	phone.modulate = Color(0.1, 0.1, 0.12)
	phone.outline_size = 0
	b._add(bb, phone)
	phone.position = Vector3(0, 6.75, 0.11)
	for lx in [-2.8, 2.8]:
		Kit.night_light(b, bb, "BillboardLight%d" % int(lx + 3), Vector3(lx, 6.4, 1.6), Color(1.0, 0.85, 0.6), 2.0, 6.5)

# --- The underpass -------------------------------------------------------------------

## Where the overpass's pillars stand (z), both sides of its deck.
const PILLAR_Z := [8.0, -8.0, -22.0, -36.0, -50.0, -64.0, -80.0, -103.0]
const PILLAR_X := [57.4, 64.0]
## Everything hanging under the deck (caps, girders) stays above 10 m: the
## camera rides 6.75 m over you, 9.45 m zoomed right out, and must never
## pass through it.
const DECK_CLEAR := 10.0
const DECK := AABB(Vector3(56.0, DECK_CLEAR + 0.4, -112.0), Vector3(10.0, 1.2, 126.0))

static func _underpass(b: Node, c: Node3D) -> void:
	Kit.ground(b, c, "UnderpassGround", 56.0, -85.0, 65.0, -4.5, "concrete_dark")
	_overpass(b)
	# Sodium lights on the pillars, for the camp, after dark.
	for z in PILLAR_Z:
		if z < -10.0 and z > -90.0:
			var lamp: Node3D = b._ph(c, "UnderLamp%d" % int(-z), "security_light", Vector3(PILLAR_X[0] + 0.62, 4.2, z), 1.0, 90.0)
			lamp.rotation_degrees.y = 90.0
			Kit.night_light(b, c, "UnderLight%d" % int(-z), Vector3(PILLAR_X[0] + 1.6, 3.9, z + 0.6), Color(1.0, 0.62, 0.3), 2.6, 10.0)
	# Its fence to East Ave, with one gap: the way in from the avenue.
	Kit.fence(b, c, "CampFenceE1", Vector3(65.2, 0, -80.0), Vector3(65.2, 0, -44.0))
	Kit.fence(b, c, "CampFenceE2", Vector3(65.2, 0, -40.0), Vector3(65.2, 0, -8.0))
	_camp(b, c)
	Kit.place(b, "Place_UnderpassCamp", Vector3(61.8, 0, -55.5))
	Kit.place(b, "Place_PusherNight", Vector3(61.5, 0, -36.0))

## The east landmark: an elevated road on concrete pillars, its deck 10 m
## up, running north-south over the camp and across both Main Street and
## Back Street. Never hidden (group "landmark") and longer than any cell,
## so it stands on the scene root, outside them.
static func _overpass(b: Node) -> void:
	var o := Node3D.new()
	o.name = "Overpass"
	b._add(b._root, o)
	Kit.landmark(o)
	var concrete := Kit.mat(b, "concrete")
	var deck_mid := DECK.get_center()
	b._box_mesh(o, "Deck", DECK.size, deck_mid, concrete)
	b._box_mesh(o, "DeckRoad", Vector3(DECK.size.x - 1.2, 0.05, DECK.size.z), deck_mid + Vector3(0, DECK.size.y / 2.0 + 0.02, 0), Kit.mat(b, "road"))
	for side in [-1.0, 1.0]:
		var bx: float = deck_mid.x + side * (DECK.size.x / 2.0 - 0.3)
		b._box_mesh(o, "Barrier", Vector3(0.45, 0.85, DECK.size.z), Vector3(bx, DECK.end.y + 0.42, deck_mid.z), concrete)
		b._box_mesh(o, "Girder", Vector3(0.4, 0.3, DECK.size.z), Vector3(deck_mid.x + side * 2.5, DECK_CLEAR + 0.15, deck_mid.z), Kit.mat(b, "steel"))
	for z in PILLAR_Z:
		b._box_mesh(o, "Cap%d" % int(z), Vector3(9.4, 0.4, 1.4), Vector3(deck_mid.x, DECK_CLEAR + 0.2, z), concrete)
		for px in PILLAR_X:
			b._solid(o, "Pillar%d_%d" % [int(px), int(z)], Vector3(1.2, DECK_CLEAR, 1.2), Vector3(px, DECK_CLEAR / 2.0, z), Kit.mat(b, "concrete_dark"))
	# Lamps on the deck, for the silhouette at night.
	for z in [-100.0, -70.0, -40.0, -10.0]:
		b._ph(o, "DeckLamp%d" % int(-z), "street_lamp_01", Vector3(DECK.end.x - 0.6, DECK.end.y, z), 1.6, -90.0)

## The camp under the overpass: tents and tarps between the pillars, two
## fire barrels, carts, a couch someone dragged here, a washing line. Dense
## enough to read as people living here, lit by the fires all the time and
## the sodium lamps after dark.
static func _camp(b: Node, c: Node3D) -> void:
	_tent(b, c, "Tent1", Vector3(61.5, 0, -47.0), 10.0, "tarp_blue")
	_tent(b, c, "Tent2", Vector3(61.2, 0, -63.0), -15.0, "tarp_green")
	_dome(b, c, "Dome1", Vector3(58.9, 0, -57.5), "tarp_grey")
	_dome(b, c, "Dome2", Vector3(63.3, 0, -27.0), "tarp_blue")
	_dome(b, c, "Dome3", Vector3(59.2, 0, -75.0), "tarp_green")
	_dome(b, c, "Dome4", Vector3(62.9, 0, -71.0), "tarp_grey")
	_lean_to(b, c, "LeanTo1", Vector3(58.4, 0, -36.0))
	_lean_to(b, c, "LeanTo2", Vector3(58.4, 0, -64.5))
	_fire(b, c, "FireBarrel", Vector3(60.3, 0, -55.0))
	_fire(b, c, "FireBarrel2", Vector3(60.6, 0, -30.5))
	Kit.cart(b, c, "CampCart1", Vector3(63.6, 0, -52.0), 70.0)
	Kit.cart(b, c, "CampCart2", Vector3(58.8, 0, -24.5), -20.0)
	Kit.cart(b, c, "CampCart3", Vector3(63.8, 0, -76.5), 10.0)
	b._ph(c, "CampCouch", "sofa_02", Vector3(63.5, 0, -58.5), 1.0, -90.0)
	var mattress := b._tex_mat("res://assets/env3d/mattress_stained.png", 0.6, 0.95) as Material
	b._box_mesh(c, "CampMattress", Vector3(1.9, 0.18, 0.95), Vector3(63.3, 0.09, -66.5), mattress)
	b._box_mesh(c, "CampMattress2", Vector3(1.9, 0.18, 0.95), Vector3(58.3, 0.09, -42.0), mattress).rotation_degrees.y = 80.0
	b._box_mesh(c, "CampBlanket", Vector3(1.0, 0.1, 1.6), Vector3(58.4, 0.22, -42.1), b._color_mat(Color(0.3, 0.14, 0.12), 1.0))
	b._solid(c, "CampPallets", Vector3(1.2, 1.0, 1.0), Vector3(63.8, 0.5, -33.5), Kit.mat(b, "wood"))
	b._ph(c, "CampCrate", "plastic_crate_01", Vector3(61.0, 0, -52.6), 1.0, 15.0)
	b._ph(c, "CampCrate2", "wooden_crate_01", Vector3(59.4, 0, -53.2), 1.0, 40.0)
	b._ph(c, "CampTyre", "old_tyre", Vector3(64.0, 0.3, -38.0), 1.0, 20.0)
	Kit.bags(b, c, "CampBags", Vector3(57.3, 0, -44.0), 4, 88)
	Kit.bags(b, c, "CampBags2", Vector3(64.2, 0, -68.5), 3, 89)
	Kit.bags(b, c, "CampBags3", Vector3(57.4, 0, -79.0), 3, 90)
	var cardboard := b._color_mat(Color(0.52, 0.4, 0.26), 0.95) as Material
	for i in 5:
		var box: MeshInstance3D = b._box_mesh(c, "CampBox%d" % i, Vector3(0.55, 0.4, 0.45), Vector3(57.8 + (i % 2) * 0.6, 0.2, -50.5 + i * 0.5), cardboard)
		box.rotation_degrees.y = i * 23.0
	# A tarp hung on the lot's fence for a wall, and a washing line.
	var wall: MeshInstance3D = b._box_mesh(c, "CampTarpWall", Vector3(0.02, 2.0, 9.0), Vector3(56.25, 1.1, -29.0), Kit.mat(b, "tarp_blue"))
	wall.rotation_degrees.x = 2.0
	b._box_mesh(c, "WashLine", Vector3(5.4, 0.015, 0.015), Vector3(60.7, 2.3, -50.0), Kit.mat(b, "iron"))
	var colors := [Color(0.6, 0.15, 0.12), Color(0.8, 0.78, 0.7), Color(0.15, 0.25, 0.45), Color(0.3, 0.32, 0.2), Color(0.7, 0.55, 0.2)]
	for i in colors.size():
		b._box_mesh(c, "Washing%d" % i, Vector3(0.55, 0.7, 0.02), Vector3(58.6 + i * 1.0, 1.95, -50.0), b._color_mat(colors[i], 1.0))
	# A battery lantern on the crate by the main fire.
	b._box_mesh(c, "Lantern", Vector3(0.14, 0.24, 0.14), Vector3(59.4, 0.62, -53.2), b._color_mat(Color(1.0, 0.85, 0.55), 0.4, 3.0))

## A ridge tent of tarp (a prism), a second, darker tarp thrown over its
## ridge, and a collider as tall as it is.
static func _tent(b: Node, c: Node3D, n: String, pos: Vector3, yaw: float, tarp: String) -> void:
	var t := StaticBody3D.new()
	t.name = n
	b._add(c, t)
	t.position = pos
	t.rotation_degrees.y = yaw
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh" if k == 0 else "Fly"
		var prism := PrismMesh.new()
		prism.size = Vector3(2.2, 1.65, 2.5) if k == 0 else Vector3(2.5, 1.2, 1.6)
		prism.material = Kit.mat(b, tarp if k == 0 else "tarp_grey")
		mi.mesh = prism
		b._add(t, mi)
		mi.position = Vector3(0, 0.825, 0) if k == 0 else Vector3(0, 1.1, 0.2)
	b._collision(t, b._box_shape(Vector3(2.2, 1.65, 2.5)), Vector3(0, 0.825, 0))

## A cheap dome tent: half a squashed sphere of tarp.
static func _dome(b: Node, c: Node3D, n: String, pos: Vector3, tarp: String) -> void:
	var t := StaticBody3D.new()
	t.name = n
	b._add(c, t)
	t.position = pos
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var dome := SphereMesh.new()
	dome.radius = 1.25
	# A hemisphere's height is its radius.
	dome.height = 1.25
	dome.is_hemisphere = true
	dome.radial_segments = 16
	dome.rings = 6
	dome.material = Kit.mat(b, tarp)
	mi.mesh = dome
	mi.scale = Vector3(1.0, 0.95, 1.15)
	b._add(t, mi)
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.2
	cyl.height = 1.2
	b._collision(t, cyl, Vector3(0, 0.6, 0))

## A tarp tied off against a pillar, cardboard and a blanket under it.
static func _lean_to(b: Node, c: Node3D, n: String, pos: Vector3) -> void:
	var l := Node3D.new()
	l.name = n
	b._add(c, l)
	l.position = pos
	var tarp: MeshInstance3D = b._box_mesh(l, "Tarp", Vector3(2.4, 0.02, 2.8), Vector3(0.9, 1.0, 0), Kit.mat(b, "tarp_blue"))
	tarp.rotation_degrees.z = -38.0
	b._box_mesh(l, "Cardboard", Vector3(1.2, 0.02, 2.0), Vector3(0.9, 0.01, 0), b._color_mat(Color(0.52, 0.4, 0.26), 0.95))
	b._box_mesh(l, "Blanket", Vector3(0.9, 0.08, 1.7), Vector3(0.9, 0.05, 0.1), b._color_mat(Color(0.35, 0.15, 0.14), 1.0))

## A barrel stove with a fire in it: flames, glowing coals and a warm light
## that's lit day and night (group "always_lit").
static func _fire(b: Node, c: Node3D, n: String, pos: Vector3) -> void:
	var f := StaticBody3D.new()
	f.name = n
	b._add(c, f)
	f.position = pos
	b._ph(f, "Model", "barrel_stove", Vector3.ZERO, 1.3)
	# Dark coals glowing red (lit from above by the fire's own light, a pale
	# albedo burns out to a white square).
	var coals := StandardMaterial3D.new()
	coals.albedo_color = Color(0.08, 0.03, 0.02)
	coals.emission_enabled = true
	coals.emission = Color(1.0, 0.3, 0.05)
	coals.emission_energy_multiplier = 1.5
	b._box_mesh(f, "Coals", Vector3(0.44, 0.04, 0.44), Vector3(0, 1.0, 0), coals)
	var light: OmniLight3D = b._light(f, "Fire", Vector3(0, 2.2, 0), Color(1.0, 0.5, 0.18), 3.6, 9.0, false)
	light.add_to_group("always_lit", true)
	var flames := CPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 14
	flames.lifetime = 0.7
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.16
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 0.6, 0)
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.1))
	flames.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	flames.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.42)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.albedo_color = Color(1.0, 0.8, 0.55)
	# A soft tongue, not a card: bright at the heart, gone at the edge.
	var tongue := GradientTexture2D.new()
	tongue.width = 64
	tongue.height = 64
	tongue.fill = GradientTexture2D.FILL_RADIAL
	tongue.fill_from = Vector2(0.5, 0.6)
	tongue.fill_to = Vector2(0.5, 0.05)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tongue.gradient = g
	fm.albedo_texture = tongue
	quad.material = fm
	flames.mesh = quad
	b._add(f, flames)
	flames.position = Vector3(0, 1.15, 0)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 1.1
	b._collision(f, cyl, Vector3(0, 0.55, 0))
