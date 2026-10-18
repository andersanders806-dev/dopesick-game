extends RefCounted
## Main Street past the shops: x -77..-29 and 29..77, the same sidewalk,
## road and curb as the middle (which build_rooms_3d.gd lays the full
## length of the block), plus what's on it out here. The street doesn't
## run dead straight: a building at each end of the shops steps out onto
## the sidewalk (Facades' "jut" side), so you never see more than ~50 m
## down it, and it ends in a T at each avenue -- under the overpass to the
## east, and at the neon pharmacy tower to the west.

const Kit := preload("res://dev-tools/city/kit.gd")
const StreetLife := preload("res://world/StreetLife.gd")

static func build(b: Node, _root: Node3D) -> void:
	var main := Kit.cell(b, "Cell_Main")
	_shop_signs(b, main)
	# Lamps every ~13 m, like the middle; the east end stays darker.
	var lamps := [-63.0, -50.0, -37.0, 41.0, 53.0]
	for i in lamps.size():
		b._streetlight("StreetlightMain%d" % (i + 1), lamps[i], -1.8, 7 + i, main)
	# Parked along the far curb, where the middle's are. A van and a box van
	# stand taller than the cars: the road doesn't read as one long strip.
	b._car("CarMainW1", Vector3(-58.0, 0, 2.6), false, "van", main)
	b._car("CarMainW2", Vector3(-52.0, 0, 2.7), true, "sedan", main)
	b._car("CarMainE1", Vector3(38.5, 0, 2.6), true, "van", main)
	# What keeps the street from being one 154 m strip at eye level: a
	# newsstand at each end of the shops (people step round them on the
	# building side) and a box truck unloading at each end of the parking.
	# The shops' stretch between them is just under 55 m.
	Kit.kiosk(b, main, "NewsstandMainW", Vector3(-28.1, 0, -2.625), Vector2(1.4, 1.45), Vector3.BACK, Color(0.12, 0.26, 0.18))
	Kit.kiosk(b, main, "NewsstandMainE", Vector3(27.7, 0, -2.625), Vector2(1.4, 1.45), Vector3.BACK, Color(0.3, 0.12, 0.1), "DAILY NEWS\nLOTTO\nPHONE CARDS")
	Kit.box_truck(b, main, "TruckMainW", Vector3(-30.2, 0, 2.6), 0.0, "ACE MOVING", Color(0.75, 0.72, 0.66))
	Kit.box_truck(b, main, "TruckMainE", Vector3(30.2, 0, 2.6), 180.0, "SUNRISE BAKERY", Color(0.55, 0.62, 0.7))
	# ...and roadworks in the driving lane, under 55 m apart; the traffic
	# swings out round them into the parking lane (StreetLife.ROADWORKS,
	# which is kept clear of parked cars there). They stop short of the
	# curb, where the beat cop walks.
	for x in StreetLife.ROADWORKS:
		Kit.roadworks(b, main, "RoadworksMain%d" % int(x.x), Rect2(x.x, -0.9, x.y - x.x, 2.2))
	b._car("CarMainE2", Vector3(47.0, 0, 2.7), false, "suv", main)
	b._ph(main, "ManholeW", "water_manhole_cover", Vector3(-48.0, 0.005, 0.9))
	b._ph(main, "ManholeE", "water_manhole_cover", Vector3(43.0, 0.005, 1.4))
	Kit.hydrant(b, main, "HydrantW", Vector3(-55.5, 0, -1.85))
	Kit.hydrant(b, main, "HydrantE", Vector3(49.0, 0, -1.85))
	Kit.trash_can(b, main, "BinW1", Vector3(-49.6, 0, -1.8))
	Kit.trash_can(b, main, "BinW2", Vector3(-32.0, 0, -1.8))
	Kit.trash_can(b, main, "BinE1", Vector3(40.2, 0, -1.8))
	b._ph(main, "UtilityBoxW", "utility_box_01", Vector3(-60.5, 0, -4.2))
	b._ph(main, "UtilityBoxE", "utility_box_02", Vector3(51.0, 0, -4.2))
	Kit.bags(b, main, "BagsTires", Vector3(42.6, 0, -4.1), 3, 41)
	Kit.bags(b, main, "BagsWigs", Vector3(-45.0, 0, -4.1), 2, 42)
	b._ph(main, "TyresTires1", "old_tyre", Vector3(38.4, 0.3, -4.0), 1.0, 70.0)
	b._ph(main, "TyresTires2", "old_tyre", Vector3(38.9, 0.3, -3.9), 1.0, 20.0)
	_pharmacy_tower(b, main)
	# The places on Main that people will keep (Task 4): behind the jut's
	# line, so the jut is what ends the view down the sidewalk.
	Kit.place(b, "Place_PoliceStation", Vector3(-24.5, 0, -3.4))
	Kit.place(b, "Place_RayCrate", Vector3(-12.1, 0, -3.2))
	# Beside his post, clear of his body (a nav obstacle when the bake runs).
	Kit.place(b, "Place_PusherCorner", Vector3(12.9, 0, -3.4))

## Signs over the new shopfronts (none of them open: they're dressing).
static func _shop_signs(b: Node, main: Node3D) -> void:
	var signs := [
		["CheckCash", "CHECKS CASHED", -53.0, -4.48, Color(0.3, 1.0, 0.4)],
		["Wigs", "WIGS", -45.5, -4.48, Color(1.0, 0.35, 0.7)],
		["WestJut", "DISCOUNT", -38.3, -3.08, Color(1.0, 0.85, 0.3)],
		["EastJut", "LAUNDROMAT", 33.3, -3.08, Color(0.4, 0.75, 1.0)],
		["Tires", "TIRE SHOP", 40.5, -4.48, Color(1.0, 0.55, 0.15)],
		["Noodles", "NOODLES", 47.0, -4.48, Color(1.0, 0.2, 0.15)],
	]
	for sg in signs:
		Kit.shop_sign(b, main, sg[0], sg[1], Vector3(sg[2], 3.1, sg[3]), sg[4])
	for sg in [["WestJut", -38.3, -3.1], ["EastJut", 33.3, -3.1], ["Noodles", 47.0, -4.5], ["CheckCash", -53.0, -4.5]]:
		b._box_mesh(main, sg[0] + "Door", Vector3(1.0, 2.0, 0.1), Vector3(sg[1], 1.0, sg[2] + 0.06), Kit.mat(b, "door"))

## The west landmark: a tall vertical PHARMACY sign with a green cross on
## the corner block, readable from the length of Main Street and up West
## Ave, the way the old drugstore signs were. Never hidden (group
## "landmark").
static func _pharmacy_tower(b: Node, main: Node3D) -> void:
	var tower := Node3D.new()
	tower.name = "PharmacyTower"
	b._add(main, tower)
	tower.position = Vector3(-63.8, 0, -3.9)
	Kit.landmark(tower)
	var green := Color(0.25, 1.0, 0.45)
	b._box_mesh(tower, "Backing", Vector3(1.25, 8.4, 0.3), Vector3(0, 8.6, 0), Kit.mat(b, "iron"))
	b._box_mesh(tower, "Trim", Vector3(1.35, 8.5, 0.1), Vector3(0, 8.6, -0.18), b._color_mat(Color(0.75, 0.72, 0.62), 0.5))
	var letters := Label3D.new()
	letters.name = "Text"
	letters.text = "P\nH\nA\nR\nM\nA\nC\nY"
	letters.font_size = 112
	letters.pixel_size = 0.0085
	letters.line_spacing = -18.0
	letters.outline_size = 0
	letters.modulate = Color(green.r * 2.6, green.g * 2.6, green.b * 2.6)
	letters.shaded = false
	b._add(tower, letters)
	letters.position = Vector3(0, 8.6, 0.16)
	# The cross on top, above the roofline.
	var glow := b._color_mat(green, 0.4, 4.0) as Material
	b._box_mesh(tower, "CrossV", Vector3(0.45, 1.5, 0.2), Vector3(0, 14.1, 0.05), glow)
	b._box_mesh(tower, "CrossH", Vector3(1.5, 0.45, 0.2), Vector3(0, 14.1, 0.05), glow)
	b._box_mesh(tower, "Mast", Vector3(0.18, 1.0, 0.18), Vector3(0, 13.0, -0.1), Kit.mat(b, "iron"))
	b._light(tower, "PharmacyTowerSignGlow", Vector3(0, 9.0, 1.2), green, 2.2, 9.0, false)
	Kit.night_light(b, tower, "CrossGlow", Vector3(0, 14.1, 0.8), green, 1.6, 6.0)
