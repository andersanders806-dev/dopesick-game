extends RefCounted
## West Ave and East Ave: the two short sides of the block, from Main
## Street north to Back Street. Each has a road (x -74..-68 and 68..74), a
## sidewalk on either side, lamps, parked cars nose to tail, and enough on
## the sidewalks and road (newsstands, a double-parked box truck) that you
## don't see clean down the full 100 m. The outer rows' buildings are Facades.gd's; West
## Ave's inner side is the park's fence and gate (inner.gd), East Ave's the
## overpass and the camp's fence.

const Kit := preload("res://dev-tools/city/kit.gd")

static func build(b: Node, _root: Node3D) -> void:
	_avenue(b, Kit.cell(b, "Cell_West"), "West", -1.0)
	_avenue(b, Kit.cell(b, "Cell_East"), "East", 1.0)

## `side` -1 for West Ave, +1 for East Ave: everything mirrors in x.
static func _avenue(b: Node, c: Node3D, n: String, side: float) -> void:
	var road_mid := 71.0 * side
	# Ground: the road runs from Main's road to Back Street's; the outer
	# sidewalk the full depth of the block, the inner one between the
	# corners (Main's and Back Street's sidewalks take the corners).
	Kit.ground(b, c, n + "Road", road_mid - 3.0, -88.0, road_mid + 3.0, -1.5, "road")
	Kit.ground(b, c, n + "SidewalkOut", _x(side, 74.0, 77.0)[0], -94.0, _x(side, 74.0, 77.0)[1], 4.6, "sidewalk", 0.01)
	Kit.ground(b, c, n + "SidewalkIn", _x(side, 65.0, 68.0)[0], -85.0, _x(side, 65.0, 68.0)[1], -4.5, "sidewalk", 0.01)
	Kit.curb_z(b, c, n + "CurbOut", -94.0, 4.5, 74.0 * side)
	Kit.curb_z(b, c, n + "CurbIn", -88.0, -1.5, 68.0 * side)
	Kit.dashes(b, c, n + "LaneDash", Vector3(road_mid, 0, -86.5), Vector3(road_mid, 0, -3.0))
	# Lamps, alternating sides, hanging over the road.
	var zs := [-10.0, -19.0, -28.0, -37.0, -46.0, -55.0, -64.0, -73.0, -82.0]
	for i in zs.size():
		var outer := i % 2 == 1
		var x := (74.3 if outer else 67.7) * side
		var yaw := (-90.0 if outer else 90.0) * side
		b._streetlight("Streetlight%s%d" % [n, i + 1], x, zs[i], 20 + i, c, yaw)
	# Parked cars along the outer curb, facing the way the lane runs.
	var cars := [[-9.0, "sedan_generic"], [-16.0, "covered"], [-34.0, "hatch_generic"], [-52.0, "van_shvan92"], [-58.5, "sedan_generic"], [-71.0, "suv_generic"], [-80.0, "covered"]]
	for i in cars.size():
		var kind: String = cars[i][1]
		if side > 0.0 and kind == "covered":
			kind = "minivan_generic" if i % 2 == 0 else "covered"
		b._car("Car%sAve%d" % [n, i + 1], Vector3(73.0 * side, 0, cars[i][0] + (0.7 if side > 0 else 0.0)), false, kind, c, 90.0 * -side if side > 0 else 90.0)
	# A newsstand on each sidewalk and a box truck double-parked, halfway up:
	# no clean 100 m view down the avenue.
	Kit.kiosk(b, c, n + "Newsstand", Vector3(76.3 * side, 0, -48.0), Vector2(1.4, 3.0), Vector3(-side, 0, 0), Color(0.12, 0.26, 0.18))
	Kit.kiosk(b, c, n + "NewsstandIn", Vector3(66.2 * side, 0, -50.0), Vector2(1.4, 3.0), Vector3(side, 0, 0), Color(0.3, 0.12, 0.1), "FLOWERS\nCOFFEE")
	Kit.box_truck(b, c, n + "Truck", Vector3(71.8 * side, 0, -45.0), 90.0 if side < 0 else -90.0, "DELI SUPPLY" if side < 0 else "QUICK FREIGHT", Color(0.7, 0.68, 0.6))
	# The truck takes the outer lane; roadworks take the inner one.
	for z in [-20.0, -70.0]:
		Kit.roadworks(b, c, n + "Roadworks%d" % int(-z), Rect2(minf(68.2 * side, 70.8 * side), z - 2.0, 2.6, 4.0))
	# Bins, a hydrant, bags out at the curb.
	Kit.hydrant(b, c, n + "Hydrant", Vector3(67.5 * side, 0, -24.0))
	Kit.trash_can(b, c, n + "Bin1", Vector3(67.5 * side, 0, -55.0))
	Kit.trash_can(b, c, n + "Bin2", Vector3(74.6 * side, 0, -23.5))
	Kit.bags(b, c, n + "Bags1", Vector3(74.7 * side, 0, -31.0), 3, 50 + int(side))
	Kit.bags(b, c, n + "Bags2", Vector3(74.7 * side, 0, -66.5), 2, 60 + int(side))
	b._ph(c, n + "Manhole", "water_manhole_cover", Vector3(road_mid + 1.0 * side, 0.005, -36.0))
	b._ph(c, n + "UtilityBox", "utility_box_02", Vector3(74.4 * side, 0, -57.0), 1.0, 90.0 * side)
	# Doors along the outer row, so it reads as places people live.
	for z in [-93.0, -81.0, -69.0, -57.0, -45.0, -33.0, -21.0, -6.0]:
		b._box_mesh(c, n + "OuterDoor%d" % int(-z), Vector3(0.1, 2.0, 1.0), Vector3(76.94 * side, 1.0, z), Kit.mat(b, "door"))

## [min, max] of the span a..b mirrored to this avenue's side.
static func _x(side: float, a: float, c: float) -> Array:
	return [minf(a * side, c * side), maxf(a * side, c * side)]
