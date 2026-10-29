extends RefCounted
## The four shops you walk into from Main Street's sidewalk (the corner shop,
## the liquor store, the pawnshop, Tape Deck), built inside their buildings
## (world/Facades.WALK_INS says where) instead of as scenes of their own.
## Each is a node under Cell_Main -- WalkIn_Convenience and so on, with the
## GameState place id as meta `place` -- running world/WalkInShop.gd, which
## gives it the theft, guards and closing time the old scenes had.
##
## A shop's own coordinates: x along the street from its door, z 0 at the
## inside face of the front wall and running back (-z) 11 m to the back
## wall; so the shop's origin is (door x, 0, -4.8) in the block. Fixtures
## stand against the side walls facing the aisle, or across it (layouts are
## (x, z, yaw) -- world/Store3D.gd).
##
## Everything inside is on visual layer 2 as well as 1 at run time
## (WalkInShop), and the room's lights light layer 2 only: a lamp in the
## shop never lights the street.

## kit.gd preloads this file, so it can only be loaded after.
static func _kit() -> GDScript:
	return load("res://dev-tools/city/kit.gd")
const Facades := preload("res://world/Facades.gd")

const FRONT_Z := -4.8
const BACK_Z := -15.8
const DEPTH := 11.0
const CEIL := 3.0
## The one visual layer interior lamps light.
const LIGHT_MASK := 2

# --- The buildings' bodies --------------------------------------------------------

## A walk-in building's collider: walls round a hollow, the doorway open.
## (Kit.building_colliders calls this instead of making a solid box.)
static func building(b: Node, cell: Node3D, m: Dictionary) -> void:
	var r: Rect2 = m["rect"]
	var h: float = m["floors"] * Facades.MODULE + Facades.ROOF_OVER + Facades.COPING.y
	var door_x := Facades.walk_in_door_x(m["name"])
	var gap: float = Facades.shop_geometry(_front_width(m["name"]))["gap"]
	var body := StaticBody3D.new()
	body.name = "Building" + m["name"]
	body.collision_layer = 1
	body.collision_mask = 0
	b._add(cell, body)
	body.position = Vector3(r.get_center().x, h / 2.0, r.get_center().y)
	var t := Facades.WALL_T
	var ft := Facades.FRONT_WALL_T
	# [x0, x1, z0, z1] in world.
	var parts := [
		[r.position.x, r.position.x + t, r.position.y, r.end.y],
		[r.end.x - t, r.end.x, r.position.y, r.end.y],
		[r.position.x, r.end.x, r.position.y, r.position.y + t],
		[r.position.x, door_x - gap / 2.0, r.end.y - ft, r.end.y],
		[door_x + gap / 2.0, r.end.x, r.end.y - ft, r.end.y],
	]
	var i := 0
	for p in parts:
		var cs := CollisionShape3D.new()
		cs.name = "Wall%d" % i
		i += 1
		cs.shape = b._box_shape(Vector3(p[1] - p[0], h, p[3] - p[2]))
		b._add(body, cs)
		cs.position = Vector3((p[0] + p[1]) / 2.0, h / 2.0, (p[2] + p[3]) / 2.0) - body.position
	# Same occluder as every building's (Kit.building_colliders): WalkInShop
	# takes it out of play while you're near, or it would hide the room.
	var occ := OccluderInstance3D.new()
	occ.name = "Occluder"
	var bounds: AABB = _kit().CELLS[m["cell"]]
	var solid := AABB(Vector3(r.position.x + 0.1, 0.1, r.position.y + 0.1), Vector3(r.size.x - 0.2, h - 0.2, r.size.y - 0.2)).intersection(bounds)
	var box := BoxOccluder3D.new()
	box.size = solid.size
	occ.occluder = box
	b._add(body, occ)
	occ.position = solid.get_center() - body.position

static func _front_width(front: String) -> float:
	for f in Facades.FRONTS:
		if f[0] == front:
			return f[2] - f[1]
	return 4.0

# --- The rooms ----------------------------------------------------------------------

static func build(b: Node, _root: Node3D) -> void:
	var main: Node3D = _kit().cell(b, "Cell_Main")
	for front in Facades.WALK_INS:
		var info: Dictionary = Facades.WALK_INS[front]
		var door_x := Facades.walk_in_door_x(front)
		var span: Array = info["span"]
		var shop := Node3D.new()
		shop.name = info["node"]
		shop.set_script(load("res://world/WalkInShop.gd"))
		shop.set_meta("place", info["place"])
		b._add(main, shop)
		shop.position = Vector3(door_x, 0.0, FRONT_Z)
		b._shop = shop
		var xl: float = span[0] + Facades.WALL_T - door_x
		var xr: float = span[1] - Facades.WALL_T - door_x
		var spec: Dictionary = _shell(b, shop, front, xl, xr, door_x)
		match front:
			"Shop":
				_convenience(b, shop, xl, xr, spec)
			"Liquor":
				_liquor(b, shop, xl, xr, spec)
			"Pawn":
				_pawn(b, shop, xl, xr, spec)
			"Music":
				_music(b, shop, xl, xr, spec)
		b._shop = null

## Per shop: the floor, the paint, the lamps' colour.
const SPECS := {
	"Shop": {"floor": "pbr:tiles_beige", "floor_uv": 1.0, "floor_tint": Color(1, 1, 1), "paint": Color(0.74, 0.8, 0.7), "light": Color(0.85, 0.95, 1.0), "energy": 1.7},
	"Liquor": {"floor": "pbr:tiles_beige", "floor_uv": 1.0, "floor_tint": Color(0.7, 0.62, 0.55), "paint": Color(0.5, 0.36, 0.26), "light": Color(1.0, 0.88, 0.7), "energy": 1.6},
	"Pawn": {"floor": "pbr:wood_floor", "floor_uv": 0.5, "floor_tint": Color(0.8, 0.75, 0.7), "paint": Color(0.46, 0.4, 0.31), "light": Color(1.0, 0.9, 0.7), "energy": 1.5},
	"Music": {"floor": "pbr:checker_tiles", "floor_uv": 0.5, "floor_tint": Color(0.85, 0.8, 0.9), "paint": Color(0.3, 0.2, 0.4), "light": Color(1.0, 0.82, 0.95), "energy": 1.5},
}

## Floor, walls, ceiling, lamps and hum; the Inside area; the markers, the
## gate that shuts the doorway when the shop's closed. Returns the spec.
static func _shell(b: Node, shop: Node3D, front: String, xl: float, xr: float, door_x: float) -> Dictionary:
	var spec: Dictionary = SPECS[front]
	var w := xr - xl
	var cx := (xl + xr) / 2.0
	var floor_mat: StandardMaterial3D = b._tex_mat(spec["floor"], spec["floor_uv"], 0.85)
	floor_mat.albedo_color = spec["floor_tint"]
	b._box_mesh(shop, "FloorTiles", Vector3(w, 0.02, DEPTH), Vector3(cx, 0.01, -DEPTH / 2.0), floor_mat)
	var paint: StandardMaterial3D = b._tex_mat("pbr:plaster_painted", 1.0)
	paint.albedo_color = spec["paint"]
	var t := Facades.WALL_T
	var ft := Facades.FRONT_WALL_T
	# Side and back walls, to the inside of the building's own.
	var long := DEPTH + ft + t
	var zc := (ft - DEPTH - t) / 2.0
	b._box_mesh(shop, "WallWest", Vector3(t, CEIL, long), Vector3(xl - t / 2.0, CEIL / 2.0, zc), paint)
	b._box_mesh(shop, "WallEast", Vector3(t, CEIL, long), Vector3(xr + t / 2.0, CEIL / 2.0, zc), paint)
	b._box_mesh(shop, "WallBack", Vector3(w + 2 * t, CEIL, t), Vector3(cx, CEIL / 2.0, -DEPTH - t / 2.0), paint)
	# The front wall where the shop's own front (Facades) doesn't cover it:
	# the neighbours' fronts stand over the rest.
	var fx0 := 0.0
	var fx1 := 0.0
	for f in Facades.FRONTS:
		if f[0] == front:
			fx0 = f[1] - door_x
			fx1 = f[2] - door_x
	for seg in [[xl - t, minf(fx0, xr + t)], [maxf(fx1, xl - t), xr + t]]:
		if seg[1] - seg[0] > 0.01:
			b._box_mesh(shop, "WallFront%s" % ("W" if seg[0] < 0 else "E"), Vector3(seg[1] - seg[0], CEIL, ft), Vector3((seg[0] + seg[1]) / 2.0, CEIL / 2.0, ft / 2.0), paint)
	# The ceiling faces down: the camera above never sees it, a first-person
	# one sees nothing else. (Its back is culled.)
	var ceil_mesh := QuadMesh.new()
	ceil_mesh.size = Vector2(w + 2 * t, DEPTH + ft + t)
	ceil_mesh.material = paint
	var ceiling := MeshInstance3D.new()
	ceiling.name = "Ceiling"
	ceiling.mesh = ceil_mesh
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._add(shop, ceiling)
	ceiling.position = Vector3(cx, CEIL, zc)
	ceiling.rotation_degrees.x = 90.0
	# Lamps: tubes on the ceiling, a light under each, on only near you.
	var lamps := 3
	for i in lamps:
		var z := -DEPTH * (i + 0.5) / lamps
		# A glowing strip that faces down, like the ceiling: from above it's
		# culled, from inside (first person) it's the tube.
		var tube_mesh := QuadMesh.new()
		tube_mesh.size = Vector2(0.16, 1.6)
		tube_mesh.material = b._color_mat(Color(0.95, 0.97, 1.0), 0.3, 3.0)
		var tube := MeshInstance3D.new()
		tube.name = "Tube%d" % i
		tube.mesh = tube_mesh
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b._add(shop, tube)
		tube.position = Vector3(cx, CEIL - 0.02, z)
		tube.rotation_degrees.x = 90.0
		var lamp: OmniLight3D = b._light(shop, "Lamp%d" % i, Vector3(cx, CEIL - 0.45, z), spec["light"], spec["energy"], 6.0, false)
		lamp.light_cull_mask = LIGHT_MASK
		lamp.add_to_group("walk_in_lights", true)
		lamp.add_to_group("always_lit", true)
	b._sound(shop, "FluorescentHum", "fluorescent_hum_loop.wav", Vector3(cx, 2.3, -DEPTH / 2.0), -22.0, 5.0, 14.0)
	b._ph(shop, "Camera", "security_camera_01", Vector3(xr - 0.25, 2.55, -DEPTH + 0.3), 1.0, 225.0)
	# The Inside area: just the player, a little in from the door.
	var inside := Area3D.new()
	inside.name = "Inside"
	inside.collision_layer = 0
	inside.collision_mask = 2
	inside.monitorable = false
	b._add(shop, inside)
	b._collision(inside, b._box_shape(Vector3(w, CEIL, DEPTH - 0.4)), Vector3(cx, CEIL / 2.0, -0.4 - (DEPTH - 0.4) / 2.0))
	_keep(b, inside)
	var spawn := _marker(b, shop, "SpawnInside", Vector3(0.0, 0.0, -1.1))
	spawn.set_meta("front", front)
	# The police come to the doorstep.
	_marker(b, shop, "PoliceSpawn", Vector3(0.9, 0.0, 1.3))
	_marker(b, shop, "OutsideSpawn", Vector3(0.0, 0.0, 1.5))
	# Shut at closing time: a body in the doorway, and E on it says why.
	var gate := StaticBody3D.new()
	gate.name = "Gate"
	gate.collision_layer = 1
	gate.collision_mask = 0
	b._add(shop, gate)
	gate.position = Vector3(0.0, 0.0, ft / 2.0)
	b._collision(gate, b._box_shape(Vector3(Facades.shop_geometry(_front_width(front))["gap"], CEIL, ft)), Vector3(0, CEIL / 2.0, 0))
	var locked := Area3D.new()
	locked.name = "Locked"
	locked.collision_layer = 4
	locked.collision_mask = 0
	locked.monitoring = false
	locked.set_script(load("res://interactables/ShopGate3D.gd"))
	locked.set_meta("prompt", "Locked door")
	b._add(shop, locked)
	locked.position = Vector3(0.0, 0.0, ft + 0.5)
	b._collision(locked, b._box_shape(Vector3(1.8, 2.2, 1.0)), Vector3(0, 1.1, 0))
	_keep(b, gate)
	_keep(b, locked)
	return spec

## A marker the street keeps whether or not the room is built.
static func _marker(b: Node, shop: Node3D, name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = name
	b._add(shop, m)
	m.position = pos
	m.owner = b._root
	return m

## What stays in City3D.tscn: the doorway's parts. (Everything else of a
## shop is owned by the shop, so it saves into the shop's own scene.)
static func _keep(b: Node, node: Node) -> void:
	node.owner = b._root
	for c in node.get_children():
		_keep(b, c)

## Each shop's room as a scene of its own (world/walkin/<Front>.tscn), and
## out of the street: world/WalkInShop.gd builds it into the placeholder
## left in City3D when you come near.
static func split(b: Node) -> void:
	DirAccess.make_dir_recursive_absolute(Facades.WALK_IN_DIR)
	var main: Node3D = _kit().cell(b, "Cell_Main")
	for front in Facades.WALK_INS:
		var shop := main.get_node(String(Facades.WALK_INS[front]["node"]))
		var packed := PackedScene.new()
		var err := packed.pack(shop)
		if err != OK:
			push_error("walk-in %s: pack failed (%d)" % [front, err])
			continue
		ResourceSaver.save(packed, Facades.walk_in_scene(front))
		for c in shop.get_children():
			if c.owner != b._root:
				shop.remove_child(c)
				c.free()

## What every store of the three that steal tells Store3D.
static func _stock(shop: Node3D, store_id: String, window: float, items: Array[String], layouts: Array) -> void:
	shop.set("store_id", store_id)
	shop.set("theft_window", window)
	shop.set("item_ids", items)
	shop.set("fixture_layouts", layouts)

## A framed poster or sign flat on a wall: `wall` is the direction the wall faces.
static func _poster(b: Node, shop: Node3D, name: String, size: Vector2, pos: Vector3, yaw: float, color: Color, emission := 0.4) -> void:
	var p: MeshInstance3D = b._box_mesh(shop, name, Vector3(size.x, size.y, 0.03), pos, b._color_mat(color, 0.7, emission))
	p.rotation_degrees.y = yaw

# --- Corner shop (the 24/7) -----------------------------------------------------------

static func _convenience(b: Node, shop: Node3D, xl: float, xr: float, _spec: Dictionary) -> void:
	var colors := [Color(0.8, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.45, 0.8), Color(0.3, 0.7, 0.3)]
	for i in 5:
		b._fixture_shelf(i + 1, colors)
	# The till along the east wall, by the door, with the cigarettes behind.
	var counter: StaticBody3D = b._counter(shop, "Counter", Vector3(0.85, 0, -3.9), 3)
	counter.rotation_degrees.y = -90.0
	b._ph(counter, "Register", "CashRegister_01", Vector3(0.8, 1.05, -0.4), 0.65, 180.0)
	var rack: MeshInstance3D = b._box_mesh(shop, "CigRack", Vector3(0.25, 0.7, 2.2), Vector3(xr - 0.15, 1.75, -2.3), b._color_mat(Color(0.15, 0.15, 0.15), 0.6))
	for row in 3:
		for k in 10:
			b._box_mesh(rack, "Pack%d_%d" % [row, k], Vector3(0.04, 0.16, 0.16), Vector3(-0.13, -0.22 + row * 0.22, -0.95 + k * 0.21), b._color_mat([Color(0.9, 0.9, 0.9), Color(0.8, 0.15, 0.1), Color(0.2, 0.3, 0.7), Color(0.85, 0.75, 0.2)][(k + row) % 4], 0.6))
	b._label(shop, "LottoSign", "LOTTO", Vector3(xr - 0.05, 2.45, -2.3), -90.0, Color(1.0, 0.8, 0.1), 64, true)
	b._label(shop, "OpenSign", "OPEN 24 HRS", Vector3(xl + 0.05, 2.45, -2.0), 90.0, Color(0.3, 1.0, 0.5), 40, true)
	# A drinks cooler across the back, its glass doors glowing.
	var fridge: Node3D = b._model(shop, "Cooler", "furniture/kitchenFridge.glb", Vector3(0.2, 0, -DEPTH + 0.5), 2.5)
	fridge.rotation_degrees.y = 0.0
	b._model(shop, "Cooler2", "furniture/kitchenFridge.glb", Vector3(-1.0, 0, -DEPTH + 0.5), 2.5)
	b._sound(shop, "CoolerHum", "cooler_hum_loop.wav", Vector3(0.2, 1.0, -DEPTH + 1.0), -9.0, 2.5, 14.0)
	var glow: OmniLight3D = b._light(shop, "LightCooler", Vector3(-0.4, 1.4, -DEPTH + 1.6), Color(0.6, 0.85, 1.0), 0.8, 2.5, false)
	glow.light_cull_mask = LIGHT_MASK
	glow.add_to_group("walk_in_lights", true)
	glow.add_to_group("always_lit", true)
	b._ph(shop, "Clock", "wall_clock", Vector3(xr - 0.1, 2.45, -4.6), 1.0, -90.0)
	# Tins and a sack of crisps on the floor display by the door.
	b._ph(shop, "CrateStack", "plastic_crate_01", Vector3(xl + 0.4, 0, -0.5), 1.0, 20.0)
	b._guard("Shopkeeper", Vector3(xr - 0.4, 0, -2.3), 180.0, 9.0, 45.0, 120.0, 0.45, "", "", "", "clerk_convenience")
	var layouts := [
		PackedVector3Array([Vector3(xl + 0.31, -3.0, 90), Vector3(xl + 0.31, -5.6, 90), Vector3(xl + 0.31, -8.2, 90), Vector3(xr - 0.31, -6.0, -90), Vector3(xr - 0.31, -8.6, -90)]),
		PackedVector3Array([Vector3(xl + 0.31, -2.6, 90), Vector3(xl + 0.31, -5.2, 90), Vector3(xr - 0.31, -5.2, -90), Vector3(xr - 0.31, -7.8, -90), Vector3(xl + 0.31, -8.0, 90)]),
	]
	var items: Array[String] = ["cigs", "charger", "batteries", "energy", "sunglasses"]
	_stock(shop, "convenience", b.TUNE["convenience_window"], items, layouts)

# --- Liquor store -----------------------------------------------------------------------

static func _liquor(b: Node, shop: Node3D, xl: float, xr: float, _spec: Dictionary) -> void:
	for i in 4:
		b._fixture_bottles(i + 1)
	# The till along the west wall behind scratched plexiglass, with pints
	# stacked on the counter.
	var counter: StaticBody3D = b._counter(shop, "Counter", Vector3(-0.7, 0, -0.9), 3)
	counter.rotation_degrees.y = 90.0
	var plexi: StandardMaterial3D = b._color_mat(Color(0.85, 0.9, 0.95, 0.2), 0.15)
	plexi.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b._box_mesh(counter, "Plexiglass", Vector3(3.3, 1.2, 0.03), Vector3(1.6, 1.65, 0.0), plexi)
	b._box_mesh(counter, "PassThrough", Vector3(0.5, 0.15, 0.04), Vector3(1.6, 1.12, 0.0), b._color_mat(Color(0.3, 0.3, 0.3), 0.5))
	for k in 6:
		b._model(counter, "Pint%d" % k, "food/soda-bottle.glb" if k % 2 else "food/wine-red.glb", Vector3(0.3 + k * 0.4, 1.05, -0.35), 0.35)
	b._ph(counter, "Register", "CashRegister_01", Vector3(0.6, 1.05, -0.3), 0.6, 180.0)
	# A convex mirror in the far east corner.
	var mirror_mesh := SphereMesh.new()
	mirror_mesh.radius = 0.35
	mirror_mesh.height = 0.35
	mirror_mesh.is_hemisphere = true
	var mirror_mat: StandardMaterial3D = b._color_mat(Color(0.8, 0.8, 0.85), 0.02)
	mirror_mat.metallic = 1.0
	mirror_mesh.material = mirror_mat
	var mirror := MeshInstance3D.new()
	mirror.name = "SecurityMirror"
	mirror.mesh = mirror_mesh
	b._add(shop, mirror)
	mirror.position = Vector3(xr - 0.25, 2.3, -DEPTH + 0.25)
	mirror.rotation_degrees = Vector3(110, 135, 0)
	b._label(shop, "CameraSign", "SMILE, YOU'RE ON CAMERA", Vector3(xl + 1.4, 2.3, -DEPTH - 0.02), 0.0, Color(0.9, 0.9, 0.85), 26)
	b._label(shop, "LiquorNeon", "COLD BEER & WINE", Vector3(0.0, 2.45, -DEPTH - 0.02), 0.0, Color(1.0, 0.2, 0.15), 40, true)
	b._label(shop, "LottoNeon", "LOTTO", Vector3(xr - 0.05, 2.3, -2.0), -90.0, Color(1.0, 0.8, 0.1), 56, true)
	var neon: OmniLight3D = b._light(shop, "NeonGlow", Vector3(0.0, 2.2, -DEPTH + 0.8), Color(1.0, 0.25, 0.2), 1.0, 4.0, false)
	neon.light_cull_mask = LIGHT_MASK
	neon.add_to_group("walk_in_lights", true)
	neon.add_to_group("always_lit", true)
	# A case of beer on the floor, bottles on the back shelf.
	b._ph(shop, "BeerCrate", "wooden_crate_02", Vector3(xr - 0.5, 0, -DEPTH + 0.5), 1.0, 10.0)
	b._ph(shop, "WineRack", "wine_bottles_01", Vector3(xl + 0.35, 0.0, -DEPTH + 0.4), 1.0, 90.0)
	b._guard("Clerk", Vector3(-1.62, 0, -2.5), 0.0, 9.5, 70.0, 130.0, 0.6, "Clerk",
		"You buying or browsing?\nI see you in the mirror. I see everybody in the mirror.\nNo, I don't do credit.\nTouch the top shelf and I'm calling it in.",
		"res://assets/portraits/liquor_clerk.png", "clerk_liquor")
	var mirror_eyes: Node3D = b._guard("MirrorWatch", Vector3(xr - 0.4, 0, -DEPTH + 0.4), 130.0, b.TUNE["mirror_range"], 70.0, 50.0, 0.3)
	mirror_eyes.set("watcher_only", true)
	var w := xr - 0.31
	var e := xl + 0.31
	var layouts := [
		PackedVector3Array([Vector3(e, -5.3, 90), Vector3(e, -7.9, 90), Vector3(w, -4.0, -90), Vector3(w, -6.6, -90)]),
		PackedVector3Array([Vector3(e, -5.8, 90), Vector3(w, -3.4, -90), Vector3(w, -6.0, -90), Vector3(w, -8.6, -90)]),
	]
	var items: Array[String] = ["whiskey", "vodka", "cognac", "vodka"]
	_stock(shop, "liquor", b.TUNE["liquor_window"], items, layouts)

# --- Pawnshop ------------------------------------------------------------------------------

static func _pawn(b: Node, shop: Node3D, xl: float, xr: float, _spec: Dictionary) -> void:
	# The counter across the whole room, behind scratched plexiglass: you
	# deal with the pawnbroker over it.
	var pieces := int(ceil((xr - xl) / (0.43 * 2.5)))
	var counter: StaticBody3D = b._counter(shop, "Counter", Vector3(xl - 0.05, 0, -6.0), pieces)
	var cw := pieces * 0.43 * 2.5
	var plexi: StandardMaterial3D = b._color_mat(Color(0.85, 0.9, 0.95, 0.18), 0.15)
	plexi.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b._box_mesh(counter, "Plexiglass", Vector3(cw, 1.2, 0.03), Vector3(cw / 2.0, 1.65, -0.02), plexi)
	b._box_mesh(counter, "Tray", Vector3(0.5, 0.06, 0.4), Vector3(cw / 2.0 + 0.4, 1.08, 0.1), b._color_mat(Color(0.3, 0.3, 0.3), 0.5))
	b._ph(counter, "Register", "CashRegister_01", Vector3(cw - 0.6, 1.05, -0.3), 0.6, 180.0)
	# Open-ended: the pawnbroker's side of the counter is the back of the room.
	b._person("Pawnbroker", Vector3(xl + (xr - xl) * 0.45, 0, -7.2), "pawnbroker", "", 0.0, "idle", "res://npc/PawnBroker3D.gd")
	# Guitars on the west wall, a stack of TVs, a watch case, the signs.
	for g in 4:
		b._ph(shop, "Guitar%d" % g, "Ukulele_01", Vector3(xl + 0.06, 1.55, -1.1 - g * 0.85), 1.35, [0.0, 4.0, -3.0, 2.0][g] + 90.0)
	for t in 3:
		b._ph(shop, "PawnTV%d" % t, "television_02", Vector3(xr - 0.45, t * 0.66, -DEPTH + 0.6), 1.6, [0.0, -6.0, 4.0][t])
	b._solid(shop, "WatchCase", Vector3(0.6, 0.9, 1.6), Vector3(xr - 0.5, 0.45, -2.7), b._color_mat(Color(0.15, 0.12, 0.1), 0.4))
	var glass: StandardMaterial3D = b._color_mat(Color(0.8, 0.9, 1.0, 0.25), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b._box_mesh(shop, "WatchGlass", Vector3(0.6, 0.25, 1.6), Vector3(xr - 0.5, 1.02, -2.7), glass)
	b._ph(shop, "Watch0", "digital_wrist_watch", Vector3(xr - 0.5, 0.9, -2.2), 1.0, 80.0)
	b._ph(shop, "Watch1", "digital_wrist_watch", Vector3(xr - 0.5, 0.9, -2.6), 1.0, 100.0)
	b._ph(shop, "Camcorder", "vintage_video_camera", Vector3(xr - 0.5, 0.9, -3.0), 1.2, 30.0)
	b._ph(shop, "Walkman", "portable_cassette_player", Vector3(xr - 0.5, 0.96, -3.3), 1.0, -20.0)
	# Display shelves along the west wall, the boombox, a drill, a
	# suitcase, a bat -- what people bring in when the rent's due.
	b._solid(shop, "DisplayShelves", Vector3(0.4, 1.55, 1.1), Vector3(xl + 0.25, 0.775, -4.6), null)
	b._ph(shop, "DisplayShelvesModel", "wooden_display_shelves_01", Vector3(xl + 0.25, 0, -4.6), 1.0, 90.0)
	b._ph(shop, "Drill", "Drill_01", Vector3(xl + 0.25, 1.06, -4.35), 1.0, 90.0)
	b._ph(shop, "Boombox", "boombox", Vector3(xl + 0.5, 0, -2.8), 0.8, 90.0)
	b._ph(shop, "Suitcase", "vintage_suitcase", Vector3(xl + 0.5, 0, -3.5), 0.6, 80.0)
	var bat: Node3D = b._ph(shop, "Bat", "baseball_bat", Vector3(xr - 0.2, 0.45, -4.9), 1.0)
	bat.rotation_degrees.z = 14.0
	# Behind the counter: gold, shelves of stuff.
	b._label(shop, "GoldNeon", "WE BUY GOLD", Vector3((xl + xr) / 2.0, 2.3, -DEPTH - 0.02), 0.0, Color(1.0, 0.75, 0.1), 56, true)
	b._label(shop, "IdSign", "NO ID  NO SALE (MOSTLY)", Vector3(xl + 1.6, 1.9, -5.97), 0.0, Color(0.9, 0.9, 0.85), 24)
	b._ph(shop, "BackShelves", "wooden_display_shelves_01", Vector3(xr - 1.6, 0, -DEPTH + 0.35), 1.0, 0.0)
	b._ph(shop, "BackShelves2", "wooden_display_shelves_01", Vector3(xl + 1.2, 0, -DEPTH + 0.35), 1.0, 0.0)
	b._ph(shop, "Cabinet", "drawer_cabinet", Vector3((xl + xr) / 2.0, 0, -DEPTH + 0.4), 1.0, 0.0)
	var gold: OmniLight3D = b._light(shop, "GoldGlow", Vector3((xl + xr) / 2.0, 2.0, -DEPTH + 1.0), Color(1.0, 0.75, 0.2), 1.0, 4.0, false)
	gold.light_cull_mask = LIGHT_MASK
	gold.add_to_group("walk_in_lights", true)
	gold.add_to_group("always_lit", true)

# --- Tape Deck ---------------------------------------------------------------------------------

static func _music(b: Node, shop: Node3D, xl: float, xr: float, _spec: Dictionary) -> void:
	var tape_colors := [Color(0.95, 0.75, 0.2), Color(0.9, 0.2, 0.4), Color(0.2, 0.7, 0.9), Color(0.95, 0.95, 0.9), Color(0.1, 0.1, 0.12)]
	for i in 5:
		b._fixture_shelf(i + 1, tape_colors)
	# The counter along the east wall by the door.
	var counter: StaticBody3D = b._counter(shop, "Counter", Vector3(xr - 1.3, 0, -3.9), 3)
	counter.rotation_degrees.y = -90.0
	b._ph(counter, "Register", "CashRegister_01", Vector3(0.6, 1.05, -0.3), 0.65, 180.0)
	b._ph(counter, "DemoDeck", "cassette_player", Vector3(1.6, 1.03, -0.3), 1.2, 180.0)
	b._ph(counter, "Boombox", "boombox", Vector3(2.6, 1.03, -0.3), 0.6, 170.0)
	b._ph(counter, "Walkman", "portable_cassette_player", Vector3(1.15, 1.09, -0.15), 1.0, 160.0)
	b._guard("Clerk", Vector3(xr - 0.4, 0, -2.5), 180.0, 8.0, 55.0, 120.0, 0.45, "Clerk",
		"\"You looking for anything specific or just vibing?\"\n\"That one's a classic. Don't let anyone tell you different.\"\n\"Tapes are coming back. Any day now.\"\n\"I see you. Hands where I can see them in the dub section.\"",
		"", "clerk_music")
	b._zone(shop, "CounterZone", Vector3(xr - 1.75, 0, -2.4), Vector3(0.9, 1.4, 3.0))
	# A listening booth, crates of records, posters.
	var booth := StaticBody3D.new()
	booth.name = "ListeningBooth"
	b._add(shop, booth)
	booth.position = Vector3(xl + 1.4, 0, -DEPTH + 0.8)
	b._box_mesh(booth, "Walls", Vector3(1.4, 2.1, 1.1), Vector3(0, 1.05, 0), b._color_mat(Color(0.15, 0.1, 0.2), 0.7))
	b._box_mesh(booth, "Window", Vector3(0.8, 0.6, 0.02), Vector3(0, 1.4, 0.56), b._color_mat(Color(1.0, 0.4, 0.8), 0.2, 1.5))
	b._collision(booth, b._box_shape(Vector3(1.4, 2.1, 1.1)), Vector3(0, 1.05, 0))
	b._ph(shop, "BoothChair", "GreenChair_01", Vector3(xl + 2.6, 0, -DEPTH + 0.9), 1.0, 200.0)
	for k in 3:
		var crate_at := Vector3(xl + 0.5 + k * 0.7, 0, -DEPTH + 2.2)
		b._solid(shop, "RecordCrate%d" % k, Vector3(0.6, 0.5, 0.6), crate_at + Vector3(0, 0.25, 0), null)
		b._ph(shop, "RecordCrateModel%d" % k, "wooden_crate_01", crate_at, 1.0, k * 3.0)
	b._solid(shop, "BackRack", Vector3(0.9, 1.9, 0.6), Vector3(xr - 1.0, 0.95, -DEPTH + 0.4), null)
	b._ph(shop, "BackRackModel", "worn_metal_rack", Vector3(xr - 1.0, 0, -DEPTH + 0.4), 1.0, 0.0)
	var poster_colors := [Color(0.9, 0.2, 0.3), Color(0.2, 0.8, 0.7), Color(0.95, 0.8, 0.2), Color(0.5, 0.3, 0.9)]
	for k in 4:
		_poster(b, shop, "Poster%d" % k, Vector2(0.6, 0.85), Vector3(xl + 0.5 + k * 1.0, 1.7, -DEPTH - 0.02), 0.0, poster_colors[k], 0.4)
	b._label(shop, "TapeNeon", "TAPE DECK", Vector3((xl + xr) / 2.0, 2.45, -DEPTH - 0.02), 0.0, Color(1.0, 0.3, 0.8), 56, true)
	b._label(shop, "UsedSign", "USED TAPES - ALL GENRES", Vector3(xl + 0.05, 2.35, -6.0), 90.0, Color(0.9, 0.9, 0.8), 24)
	var glow: OmniLight3D = b._light(shop, "NeonGlow", Vector3((xl + xr) / 2.0, 2.0, -DEPTH + 0.9), Color(1.0, 0.3, 0.8), 1.2, 5.0, false)
	glow.light_cull_mask = LIGHT_MASK
	glow.add_to_group("walk_in_lights", true)
	glow.add_to_group("always_lit", true)
	var a := xl + 0.31
	var c := xr - 0.31
	var layouts := [
		PackedVector3Array([Vector3(a, -3.2, 90), Vector3(a, -5.8, 90), Vector3(a, -8.4, 90), Vector3(c, -6.2, -90), Vector3(c, -8.6, -90)]),
		PackedVector3Array([Vector3(a, -2.8, 90), Vector3(a, -5.4, 90), Vector3(c, -5.6, -90), Vector3(c, -8.2, -90), Vector3(a, -8.0, 90)]),
	]
	var items: Array[String] = ["tape:lofi_loop"]
	_stock(shop, "music", b.TUNE["music_window"], items, layouts)
