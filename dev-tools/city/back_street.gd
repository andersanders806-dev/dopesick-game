extends RefCounted
## Back Street, along the north of the block (road z -94..-88). The far
## side is where people live: a row of brownstones with stoops either side
## of the projects, whose entrance is lit all night. The near side is the
## backs of the block -- the park's north gate, the tenement, the lot's
## fence -- and the bus stop. Stoops every 6 m break the long view down
## the sidewalk; people sit on them (Place_Stoop1..3).

const Kit := preload("res://dev-tools/city/kit.gd")

## Row house centres (Facades' Row1..Row12): each has a stoop.
const STOOP_X := [-59.0, -53.0, -47.0, -41.0, -35.0, -29.0, 9.0, 15.0, 21.0, 27.0, 33.0, 39.0]
const STOOP_FRONT := -95.8
const LINE := -99.0

static func build(b: Node, _root: Node3D) -> void:
	var c := Kit.cell(b, "Cell_Back")
	Kit.ground(b, c, "BackRoad", -74.0, -94.0, 74.0, -88.0, "road")
	Kit.ground(b, c, "BackSidewalkN", -77.0, -99.0, 77.0, -94.0, "sidewalk", 0.01)
	Kit.ground(b, c, "BackSidewalkS", -68.0, -88.0, 68.0, -85.0, "sidewalk", 0.01)
	Kit.curb_x(b, c, "BackCurbN", -74.0, 74.0, -94.0)
	Kit.curb_x(b, c, "BackCurbS", -68.0, 68.0, -88.0)
	Kit.dashes(b, c, "BackLaneDash", Vector3(-66.5, 0, -91.0), Vector3(66.5, 0, -91.0))
	for i in STOOP_X.size():
		_stoop(b, c, "Stoop%d" % (i + 1), STOOP_X[i])
	_projects_entrance(b, c)
	_bus_shelter(b, c, 20.0)
	var lamps := [-68.0, -56.0, -44.0, -32.0, -20.0, -8.0, 4.0, 16.0, 28.0, 40.0, 52.0, 64.0]
	for i in lamps.size():
		b._streetlight("StreetlightBack%d" % (i + 1), lamps[i], -94.3, 30 + i, c)
	for i in 2:
		b._streetlight("StreetlightBackS%d" % (i + 1), [-46.0, 50.0][i], -87.7, 40 + i, c, 180.0)
	# Parked both sides; nobody moves their car on Back Street.
	var north := [[-63.0, "sedan"], [-44.0, "covered"], [-24.0, "suv"], [-3.0, "hatchback-sports"], [24.5, "sedan"], [43.0, "van"]]
	for i in north.size():
		b._car("CarBackN%d" % (i + 1), Vector3(north[i][0], 0, -93.0), true, north[i][1], c)
	var south := [[-54.0, "covered"], [-14.0, "sedan-sports"], [36.0, "suv"]]
	for i in south.size():
		b._car("CarBackS%d" % (i + 1), Vector3(south[i][0], 0, -89.0), false, south[i][1], c)
	# Under the overpass the north side's just a fenced-off patch of weeds.
	Kit.fence(b, c, "UnderpassFenceN", Vector3(56.0, 0, LINE), Vector3(66.0, 0, LINE))
	Kit.ground(b, c, "UnderpassWeedsN", 56.0, -103.0, 66.0, -99.0, "park")
	Kit.hydrant(b, c, "HydrantBack", Vector3(-8.5, 0, -94.35))
	Kit.trash_can(b, c, "BinBack1", Vector3(-30.5, 0, -94.35))
	Kit.trash_can(b, c, "BinBack2", Vector3(17.5, 0, -94.35))
	Kit.trash_can(b, c, "BinBack3", Vector3(-20.0, 0, -87.6))
	# Breaking up the 154 m: newsstands on the stoops' side (where there's
	# no stoop), cabinets and a newsstand on the near side, and a box truck
	# each side of the middle of the road. People step round them.
	Kit.kiosk(b, c, "NewsstandBack1", Vector3(-22.0, 0, -94.75), Vector2(1.4, 1.3), Vector3.BACK, Color(0.12, 0.26, 0.18))
	Kit.kiosk(b, c, "NewsstandBack2", Vector3(11.5, 0, -94.75), Vector2(1.4, 1.3), Vector3.BACK, Color(0.18, 0.2, 0.35), "COFFEE\nBAGELS\nPAPERS")
	Kit.kiosk(b, c, "NewsstandBack3", Vector3(47.0, 0, -94.75), Vector2(1.4, 1.3), Vector3.BACK, Color(0.3, 0.12, 0.1))
	Kit.kiosk(b, c, "NewsstandBackS", Vector3(-44.0, 0, -85.7), Vector2(1.4, 1.2), Vector3.FORWARD, Color(0.12, 0.26, 0.18))
	Kit.cabinet(b, c, "CabinetBack1", Vector3(4.0, 0, -85.7), 180.0)
	Kit.cabinet(b, c, "CabinetBack2", Vector3(52.0, 0, -85.7), 180.0)
	Kit.box_truck(b, c, "TruckBackW", Vector3(-25.0, 0, -89.9), 0.0, "MARTINEZ PLUMBING", Color(0.85, 0.85, 0.82))
	Kit.box_truck(b, c, "TruckBackE", Vector3(25.0, 0, -89.9), 180.0, "CITY LINEN", Color(0.4, 0.5, 0.42))
	for i in [1, 4, 8, 11]:
		Kit.bags(b, c, "StoopBags%d" % i, Vector3(STOOP_X[i] + 2.2, 0, -98.4), 2, 70 + i)
	b._ph(c, "ManholeBack", "water_manhole_cover", Vector3(-12.0, 0.005, -90.2))
	# The places: the bus stop, and the gaps between stoops where people sit.
	Kit.place(b, "Place_Stoop1", Vector3(-56.0, 0, -96.6))
	Kit.place(b, "Place_Stoop2", Vector3(-39.3, 0, -96.6))
	Kit.place(b, "Place_Stoop3", Vector3(24.0, 0, -96.6))

## A brownstone stoop: six steps up to a landing at the front door, iron
## rails either side. One collider, the height of the landing.
static func _stoop(b: Node, c: Node3D, n: String, x: float) -> void:
	var stoop := StaticBody3D.new()
	stoop.name = n
	b._add(c, stoop)
	stoop.position = Vector3(x, 0, LINE)
	var stone := Kit.mat(b, "brownstone")
	for k in 6:
		var front := STOOP_FRONT - LINE - k * 0.4
		b._box_mesh(stoop, "Step%d" % k, Vector3(2.0, (k + 1) * 0.25, front), Vector3(0, (k + 1) * 0.125, front / 2.0), stone)
	var iron := Kit.mat(b, "iron")
	for side in [-1.0, 1.0]:
		var rx: float = side * 0.95
		# The rail climbs with the steps, then runs level along the landing.
		var run := Vector3(0, 1.5, -2.0)
		var rail: MeshInstance3D = b._box_mesh(stoop, "Rail", Vector3(0.05, 0.05, run.length()), Vector3(rx, 1.0 + 0.75, STOOP_FRONT - LINE - 1.0), iron)
		rail.rotation.x = atan2(run.y, -run.z)
		b._box_mesh(stoop, "RailTop", Vector3(0.05, 0.05, 1.2), Vector3(rx, 2.5, 0.6), iron)
		b._box_mesh(stoop, "Newel", Vector3(0.09, 1.0, 0.09), Vector3(rx, 0.5, STOOP_FRONT - LINE - 0.05), iron)
		for k in 4:
			b._box_mesh(stoop, "Baluster%d" % k, Vector3(0.025, 0.9, 0.025), Vector3(rx, 0.7 + k * 0.35, STOOP_FRONT - LINE - 0.35 - k * 0.5), iron)
	b._box_mesh(stoop, "Door", Vector3(1.0, 2.1, 0.1), Vector3(0, 2.55, 0.06), Kit.mat(b, "door"))
	b._collision(stoop, b._box_shape(Vector3(2.0, 1.6, STOOP_FRONT - LINE)), Vector3(0, 0.8, (STOOP_FRONT - LINE) / 2.0))

## The projects' way in: a concrete canopy on two posts, glass doors, the
## building number lit up, and planters with nothing left in them.
static func _projects_entrance(b: Node, c: Node3D) -> void:
	var x := -10.0
	b._box_mesh(c, "ProjectsCanopy", Vector3(6.0, 0.25, 3.0), Vector3(x, 3.3, LINE + 1.5), Kit.mat(b, "concrete"))
	for px in [x - 2.7, x + 2.7]:
		b._solid(c, "ProjectsPost%d" % int(px - x + 3), Vector3(0.22, 3.2, 0.22), Vector3(px, 1.6, LINE + 2.8), Kit.mat(b, "steel"))
	b._box_mesh(c, "ProjectsDoors", Vector3(2.4, 2.4, 0.06), Vector3(x, 1.2, LINE + 0.05), Kit.mat(b, "glass"))
	b._box_mesh(c, "ProjectsLobby", Vector3(2.4, 2.4, 0.02), Vector3(x, 1.2, LINE + 0.01), b._color_mat(Color(0.75, 0.82, 0.7), 0.6, 0.6))
	var number := Label3D.new()
	number.name = "ProjectsNumber"
	number.text = "1150"
	number.font_size = 64
	number.pixel_size = 0.008
	number.modulate = Color(1.0, 0.95, 0.8)
	number.outline_modulate = Color(0, 0, 0, 0.9)
	b._add(c, number)
	number.position = Vector3(x, 3.7, LINE + 2.98)
	Kit.night_light(b, c, "ProjectsLight", Vector3(x, 3.0, LINE + 1.6), Color(0.85, 1.0, 0.8), 1.4, 6.0)
	for px in [-21.0, 1.0]:
		b._solid(c, "ProjectsPlanter%d" % int(px), Vector3(6.0, 0.6, 1.2), Vector3(px, 0.3, LINE + 0.7), Kit.mat(b, "concrete_dark"))
		b._box_mesh(c, "ProjectsSoil%d" % int(px), Vector3(5.7, 0.05, 0.9), Vector3(px, 0.61, LINE + 0.7), Kit.mat(b, "park"))

## A bus shelter on the near sidewalk: glass on three sides, a bench, a lit
## ad, the stop's sign. The open side faces the road; Place_BusStop is
## inside it.
static func _bus_shelter(b: Node, c: Node3D, x: float) -> void:
	var back_z := -86.3
	var front_z := -87.7
	var glass := Kit.mat(b, "glass")
	var steel := Kit.mat(b, "steel")
	# Built in place, then the holder moved onto its spot (so the shelter's
	# origin is where it stands).
	var s := Node3D.new()
	s.name = "BusShelter"
	b._add(c, s)
	var spot := Vector3(x, 0, (back_z + front_z) / 2.0)
	b._solid(s, "BackPanel", Vector3(4.0, 2.2, 0.05), Vector3(x, 1.25, back_z), glass)
	for side in [-1.0, 1.0]:
		b._solid(s, "SidePanel", Vector3(0.05, 2.2, 1.2), Vector3(x + side * 2.0, 1.25, back_z - 0.6), glass)
		for z in [back_z, front_z + 0.1]:
			b._box_mesh(s, "Post", Vector3(0.08, 2.45, 0.08), Vector3(x + side * 2.0, 1.225, z), steel)
	b._box_mesh(s, "Roof", Vector3(4.3, 0.1, 1.7), Vector3(x, 2.5, (back_z + front_z) / 2.0), steel)
	b._box_mesh(s, "Bench", Vector3(3.0, 0.06, 0.38), Vector3(x, 0.46, back_z - 0.28), Kit.mat(b, "wood"))
	for bx in [-1.2, 1.2]:
		b._box_mesh(s, "BenchLeg", Vector3(0.06, 0.45, 0.3), Vector3(x + bx, 0.225, back_z - 0.28), steel)
	# The ad, lit from behind, on the east panel.
	b._box_mesh(s, "AdPanel", Vector3(0.12, 1.5, 1.0), Vector3(x + 2.06, 1.25, back_z - 0.6), b._color_mat(Color(0.85, 0.9, 1.0), 0.4, 1.2))
	var ad := Label3D.new()
	ad.name = "Ad"
	ad.text = "INJURED?\nCALL\n1-800-\nWIN-BIG"
	ad.font_size = 30
	ad.pixel_size = 0.006
	ad.modulate = Color(0.15, 0.15, 0.3)
	ad.outline_size = 0
	b._add(s, ad)
	ad.position = Vector3(x + 2.125, 1.3, back_z - 0.6)
	ad.rotation_degrees.y = 90.0
	Kit.night_light(b, s, "AdGlow", Vector3(x + 2.6, 1.3, back_z - 0.6), Color(0.8, 0.88, 1.0), 0.6, 3.0)
	b._cylinder(s, "StopPole", 0.04, 2.8, Vector3(x + 3.0, 1.4, front_z + 0.2), steel)
	var stop := Label3D.new()
	stop.name = "StopSign"
	stop.text = "BUS\n14  22"
	stop.font_size = 36
	stop.pixel_size = 0.006
	stop.modulate = Color(1, 1, 1)
	stop.outline_modulate = Color(0.1, 0.25, 0.6, 1.0)
	stop.outline_size = 18
	b._add(s, stop)
	stop.position = Vector3(x + 3.0, 2.6, front_z + 0.22)
	for child in s.get_children():
		(child as Node3D).position -= spot
	s.position = spot
	Kit.place(b, "Place_BusStop", Vector3(x, 0, -87.2))
