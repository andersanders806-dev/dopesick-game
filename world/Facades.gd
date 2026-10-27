extends Node3D
## The block's buildings: real fronts assembled at load from Poly Haven's
## CC0 modular facade kits (brick apartment blocks for the shops, the
## factory kit for the tall narrow fillers), replacing Kenney's toy city.
## Pieces are 3 x 3 m modules, stretched to each front's measured width.
## The ground floor is what the top-down camera sees most: shop glass with
## a lit interior, and a roller shutter when the place is closed.
##
## Every front is laid out as if it faced south onto Main Street (local x
## along the street, its face on FACE_Z) and then turned and moved onto its
## own side of the block (SIDES), so one set of placement rules builds all
## four streets, the alley walls and the park's.
##
## Behind the fronts stand the buildings themselves (masses()): walls in the
## kit's own brick or plaster where no front covers them, and a tar-and-
## gravel roof, which is most of what the camera sees from above. Visual
## only: build_rooms_3d.gd gives each mass its collider from the same list,
## and the doors are the builder's and don't move. Fronts sit just behind
## their side's line, where the signs, hour plates and posters are.

const APT := "res://assets/polyhaven/modular_urban_apartments_facade/modular_urban_apartments_facade.gltf"
const FACTORY := "res://assets/polyhaven/modular_factory_facade/modular_factory_facade.gltf"
const SHUTTER := "res://assets/polyhaven/rollershutter_window_01/rollershutter_window_01.gltf"
const ESCAPE := "res://assets/polyhaven/modular_fire_escape/modular_fire_escape.gltf"
const AIRCON := "res://assets/polyhaven/exterior_aircon_unit/exterior_aircon_unit.gltf"
const CAMERA := "res://assets/polyhaven/security_camera_02/security_camera_02.gltf"
## What SceneLoader loads in the background ahead of the first street visit.
const WARM := [APT, FACTORY, ESCAPE, AIRCON, CAMERA, SHUTTER]
const STREET_Z := -4.5
const FACE_Z := STREET_Z - 0.03
const MODULE := 3.0
## name, x from, x to, kit, floors, place (GameState.OPENING_HOURS key, or "").
## The x extents are the old Kenney buildings', measured. Main Street's
## north side, facing south.
const FRONTS := [
	["Police", -26.71, -22.29, "apt", 2, ""], ["Home", -19.71, -15.29, "apt", 3, ""],
	["Pharmacy", -12.60, -8.40, "apt", 3, "pharmacy"], ["Bar", -5.93, -1.07, "apt", 4, "bar"],
	["Shop", 1.40, 5.60, "apt", 3, "convenience"], ["Liquor", 8.29, 12.71, "apt", 2, "liquor"],
	["Supermarket", 14.55, 20.45, "apt", 1, "supermarket"], ["Electronics", 22.29, 26.71, "apt", 3, "electronics"],
	["Karts", -15.25, -12.75, "factory", 4, "karts"], ["Pawn", -1.25, 1.25, "factory", 4, "pawn"],
	["Music", -8.25, -5.75, "factory", 4, "music"], ["Shelter", 5.75, 8.25, "factory", 4, "shelter"],
	# The block behind the backyard gate, and one at each end of the shops.
	["Gate", -22.25, -19.75, "factory", 4, ""], ["WestEnd", -34.60, -26.71, "apt", 2, ""],
	["EastEnd", 26.71, 29.60, "factory", 3, ""],
]

## The shops you can walk into from the sidewalk (dev-tools/city/walk_in.gd
## builds their rooms, world/WalkInShop.gd runs them), by the name of their
## front and building: the node under Cell_Main, the place GameState keeps
## hours for, and the x span of the building behind. Music and Pawn are only
## 2.5 m across on the street, so their buildings take the Bar's (whose room
## is its own scene, behind its door) between them; the Bar's front stays,
## in front of the two rooms' middle.
const WALK_INS := {
	"Music": {"node": "WalkIn_Music", "place": "music", "span": [-8.25, -3.5]},
	"Pawn": {"node": "WalkIn_Pawn", "place": "pawn", "span": [-3.5, 1.4]},
	"Shop": {"node": "WalkIn_Convenience", "place": "convenience", "span": [1.4, 5.75]},
	"Liquor": {"node": "WalkIn_Liquor", "place": "liquor", "span": [8.29, 12.71]},
}
## Buildings that no longer have a body of their own: a walk-in took their room.
const MASS_DROP := ["Bar"]
## Fronts in front of a walk-in room (the Bar's, in front of two): their
## walls dither out between the camera and you when you're inside.
const WALK_IN_FRONTS := ["Music", "Pawn", "Shop", "Liquor", "Bar"]
## Walls round a walk-in room (and in the building's collider).
const WALL_T := 0.2
## The front wall is a bit thicker than the sides: brick, between the
## street and the room.
const FRONT_WALL_T := 0.25
## How far the street camera must be from a walk-in for it to be drawn as a
## lit window rather than as the room.
const WALK_IN_NEAR := 12.0

## Where a walk-in's door is on the street (the middle of its front).
static func walk_in_door_x(front_name: String) -> float:
	for f in FRONTS:
		if f[0] == front_name:
			return (f[1] + f[2]) / 2.0
	return 0.0

## A walk-in front's ground floor: the doorway in the middle, a window
## either side of it. `gap` is the doorway's width, `pane` each window's.
static func shop_geometry(width: float) -> Dictionary:
	var gap := 1.4
	var pane := maxf(0.4, (width - gap) / 2.0 - 0.25)
	return {"gap": gap, "pane": pane, "offset": gap / 2.0 + 0.12 + pane / 2.0}

## Each row of fronts: the way it faces and where its wall line is (z for
## rows facing north or south, x for rows facing east or west).
const SIDES := {
	"main": [Vector3.BACK, -4.5],      # Main Street's north side
	"jut": [Vector3.BACK, -3.1],       # two buildings that step out onto Main's sidewalk
	"west_in": [Vector3.LEFT, -65.0],  # West Ave, the block's side
	"west_out": [Vector3.RIGHT, -77.0],
	"east_out": [Vector3.LEFT, 77.0],
	"back_n": [Vector3.BACK, -99.0],   # Back Street's far side: stoops, the projects
	"back_s": [Vector3.FORWARD, -85.0],
	"lane": [Vector3.BACK, -19.0],     # the service lane behind Main's shops
	"alley_w": [Vector3.RIGHT, -9.0],  # the back alley's two walls
	"alley_e": [Vector3.LEFT, -6.0],
	"underpass": [Vector3.RIGHT, 56.0],
	"park_e": [Vector3.LEFT, -30.0],   # windows over the park
	"park_n": [Vector3.BACK, -70.0],
	"park_ne": [Vector3.RIGHT, -50.0],
}
## The rest of the block: name, from, to (along the side, ascending world
## x or z), kit, floors, place, side, the building (mass) it's the face of,
## and dressing ("escape", "aircon", "shutter" for a garage door that's
## always down, "shop" for shop glass lit 8-21, "closed" for a shop that's
## shuttered for good).
const BLOCK_FRONTS := [
	# Main Street, extended west and east of the shops.
	["WestCorner", -65.0, -57.0, "apt", 4, "", "main", "WestCorner", "aircon,shop"],
	["CheckCash", -57.0, -49.0, "apt", 2, "", "main", "CheckCash", "aircon,shop"],
	["Wigs", -49.0, -42.0, "factory", 3, "", "main", "Wigs", "closed"],
	["WestJut", -42.0, -34.6, "apt", 3, "", "jut", "WestJut", "escape,shop"],
	["EastJut", 29.6, 37.0, "apt", 3, "", "jut", "EastJut", "aircon,shop"],
	["Tires", 37.0, 44.0, "factory", 2, "", "main", "Tires", "shutter"],
	["Noodles", 44.0, 50.0, "apt", 3, "", "main", "Noodles", "escape,shop"],
	["EastCorner", 50.0, 56.0, "apt", 4, "", "main", "EastCorner", "closed"],
	["WestCornerSide", -16.0, -4.5, "apt", 4, "", "west_in", "WestCorner", ""],
	["EastCornerSide", -16.0, -4.5, "apt", 4, "", "underpass", "EastCorner", "aircon"],
	# West Ave's far side, south to north... west_out and east_out run in z.
	["WO1", -99.0, -87.0, "apt", 4, "", "west_out", "WO1", "escape"],
	["WO2", -87.0, -75.0, "factory", 3, "", "west_out", "WO2", "closed"],
	["WO3", -75.0, -63.0, "apt", 5, "", "west_out", "WO3", "aircon"],
	["WO4", -63.0, -51.0, "apt", 3, "", "west_out", "WO4", "escape,shop"],
	["WO5", -51.0, -39.0, "factory", 4, "", "west_out", "WO5", ""],
	["WO6", -39.0, -27.0, "apt", 3, "", "west_out", "WO6", "shutter"],
	["WO7", -27.0, -15.0, "apt", 4, "", "west_out", "WO7", "escape,closed"],
	["WO8", -15.0, 4.6, "apt", 5, "", "west_out", "WO8", "aircon"],
	["EO1", -99.0, -87.0, "apt", 4, "", "east_out", "EO1", "aircon"],
	["EO2", -87.0, -75.0, "apt", 3, "", "east_out", "EO2", "escape,shop"],
	["EO3", -75.0, -63.0, "factory", 4, "", "east_out", "EO3", ""],
	["EO4", -63.0, -51.0, "apt", 5, "", "east_out", "EO4", "escape"],
	["EO5", -51.0, -39.0, "apt", 3, "", "east_out", "EO5", "shutter"],
	["EO6", -39.0, -27.0, "factory", 3, "", "east_out", "EO6", "closed"],
	["EO7", -27.0, -15.0, "apt", 4, "", "east_out", "EO7", "aircon"],
	["EO8", -15.0, 4.6, "apt", 3, "", "east_out", "EO8", "escape,shop"],
	# Back Street's north side: brownstones with stoops, and the projects.
	["NWOuter", -77.0, -62.0, "apt", 4, "", "back_n", "NWOuter", "escape,shop"],
	["Row1", -62.0, -56.0, "apt", 3, "", "back_n", "Row1", ""],
	["Row2", -56.0, -50.0, "factory", 3, "", "back_n", "Row2", ""],
	["Row3", -50.0, -44.0, "apt", 3, "", "back_n", "Row3", "aircon"],
	["Row4", -44.0, -38.0, "apt", 3, "", "back_n", "Row4", ""],
	["Row5", -38.0, -32.0, "factory", 3, "", "back_n", "Row5", ""],
	["Row6", -32.0, -26.0, "apt", 3, "", "back_n", "Row6", "aircon"],
	["Projects", -26.0, 6.0, "apt", 7, "", "back_n", "Projects", "aircon"],
	["Row7", 6.0, 12.0, "apt", 3, "", "back_n", "Row7", ""],
	["Row8", 12.0, 18.0, "factory", 3, "", "back_n", "Row8", "aircon"],
	["Row9", 18.0, 24.0, "apt", 3, "", "back_n", "Row9", ""],
	["Row10", 24.0, 30.0, "apt", 3, "", "back_n", "Row10", ""],
	["Row11", 30.0, 36.0, "factory", 3, "", "back_n", "Row11", "aircon"],
	["Row12", 36.0, 42.0, "apt", 3, "", "back_n", "Row12", ""],
	["NEMid", 42.0, 56.0, "factory", 4, "", "back_n", "NEMid", "escape,closed"],
	["NEOuter", 66.0, 77.0, "apt", 4, "", "back_n", "NEOuter", "aircon,shop"],
	# Back Street's near side and the block's inside: tenements, a garage,
	# the backs of things onto the service lane and the back alley.
	["NWCornerN", -65.0, -50.0, "apt", 3, "", "back_s", "NWCorner", ""],
	["NWCornerW", -85.0, -70.0, "apt", 3, "", "west_in", "NWCorner", "escape"],
	["NWCornerPark", -65.0, -50.0, "apt", 3, "", "park_n", "NWCorner", "escape"],
	["NWCornerParkE", -85.0, -70.0, "apt", 3, "", "park_ne", "NWCorner", ""],
	["TenementN", -30.0, -9.0, "apt", 4, "", "back_s", "Tenement", "closed"],
	["TenementAlley", -85.0, -50.0, "apt", 4, "", "alley_w", "Tenement", "escape"],
	["TenementPark", -85.0, -50.0, "apt", 4, "", "park_e", "Tenement", "aircon"],
	["GarageAlley", -50.0, -16.0, "factory", 2, "", "alley_w", "Garage", "shutter"],
	["GaragePark", -50.0, -16.0, "factory", 2, "", "park_e", "Garage", ""],
	["InnerSWLane", -6.0, 15.0, "factory", 3, "", "lane", "InnerSW", "escape"],
	["InnerSWAlley", -50.0, -19.0, "factory", 3, "", "alley_e", "InnerSW", ""],
	["InnerSELane", 15.0, 36.0, "apt", 2, "", "lane", "InnerSE", "aircon"],
	["InnerNWN", -6.0, 15.0, "apt", 3, "", "back_s", "InnerNW", ""],
	["InnerNWAlley", -85.0, -50.0, "apt", 3, "", "alley_e", "InnerNW", "escape"],
	["InnerNEN", 15.0, 36.0, "factory", 2, "", "back_s", "InnerNE", ""],
]
## Buildings with no front of their own on Main Street or the outer rows:
## name, x0, z0, x1, z1, floors, kit (for the walls), cell.
const BLOCK_MASSES := [
	["NWCorner", -65.0, -85.0, -50.0, -70.0, 3, "apt", "Cell_Inner"],
	["Garage", -30.0, -50.0, -9.0, -16.0, 2, "factory", "Cell_Inner"],
	["Tenement", -30.0, -85.0, -9.0, -50.0, 4, "apt", "Cell_Inner"],
	["InnerSW", -6.0, -50.0, 15.0, -19.0, 3, "factory", "Cell_Inner"],
	["InnerSE", 15.0, -50.0, 36.0, -19.0, 2, "apt", "Cell_Inner"],
	["InnerNW", -6.0, -85.0, 15.0, -50.0, 3, "apt", "Cell_Inner"],
	["InnerNE", 15.0, -85.0, 36.0, -50.0, 2, "factory", "Cell_Inner"],
]
## How deep the rows' buildings run behind their fronts: Main's to the
## service lane and the park, the outer rows 10 m (no one sees their backs).
const ROW_BACK := {"main": -16.0, "jut": -16.0, "west_out": -87.0, "east_out": 87.0, "back_n": -109.0}
const ROW_CELL := {"main": "Cell_Main", "jut": "Cell_Main", "west_out": "Cell_West", "east_out": "Cell_East", "back_n": "Cell_Back"}
## Roofs sit just under the crown's top, so the cornice reads as a parapet.
const ROOF_OVER := 0.15
const COPING := Vector2(0.3, 0.45)

const KIT_PIECES := {
	"apt": {"wall": "wall_standard_standard_01", "bay": "wall_window_centered_large_01", "window": "window_centered_large_01",
		"band": "cornice_standard_standard_01", "crown": "crown_standard_standard_01", "base": "base_standard_01"},
	"factory": {"wall": "wall_standard_standard_01", "bay": "wall_window_centered_large_01", "window": "window_centered_large_01",
		"band": "cornice02_standard_standard_01", "crown": "crown_standard_standard_01", "base": "base_standard_standard_01"},
}

## Kit meshes by piece name, kept for the session: re-reading the two kits
## on every visit to the street was 1.5 s of the door freeze.
static var _meshes := {}
## The kits' window glass is alpha-blended with a depth pre-pass -- an extra
## pass for every window on the street. From outside, dark glass with a
## sheen looks the same, opaque.
var _window_glass: StandardMaterial3D

func _ready() -> void:
	for f in FRONTS:
		_build_front(f)
	for f in BLOCK_FRONTS:
		_build_front(f)
	for m in masses():
		_build_mass(m)
	_build_roof_units()
	_apply_cutaway()
	set_detail(not Graphics.lean())
	GameState.clock_changed.connect(_on_clock)
	refresh()

const Cutaway := preload("res://world/Cutaway.gd")
## The buildings the street camera can end up behind: it hangs south of
## you, so those just south of somewhere you walk -- Main's row (behind it
## the service lane, the park and the lot) and the four along Back Street's
## south side. Their walls and roofs dither out between the camera and you
## (world/Cutaway.gd). Main's own shop fronts face the camera, never stand
## between, and keep their plain materials.
const CUT_MASSES := ["NWCorner", "Tenement", "InnerNW", "InnerNE"]

static func cut_mass(m: Dictionary) -> bool:
	return m["cell"] == "Cell_Main" or m["name"] in CUT_MASSES

func _apply_cutaway() -> void:
	var cut := {}
	for m in masses():
		if cut_mass(m):
			cut[m["name"]] = true
	for n in get_children():
		if n.name.begins_with("Mass") and cut.has(String(n.name).substr(4)):
			Cutaway.apply(n)
		elif n.name.begins_with("Roof") and cut.has(String(n.name).substr(4)):
			Cutaway.apply(n)
		elif n.name.begins_with("Front") and String(n.name).substr(5) in WALK_IN_FRONTS:
			# With you inside a shop, its front is the wall between you and the camera.
			Cutaway.apply(n)
		elif n.has_meta("mass") and cut.has(n.get_meta("mass")) and n.get_meta("side", "main") not in ["main", "jut"]:
			Cutaway.apply(n)
		elif n.name.begins_with("RoofAirCons") and n.get_meta("cell", "") in ["Cell_Main", "Cell_Inner"]:
			Cutaway.apply(n)

## The fire escape, air-con, camera and shutter models, kept for the
## session for the same reason (half a second a visit).
static var _scenes := {}

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## Normal-mapped bricks, or flat (Graphics.lean(): laptop graphics on
## Medium, where the bump costs 1.5 ms a frame for detail the street camera
## hardly shows). On the kits' own materials, so every front follows.
static var _detail := true

static func set_detail(on: bool) -> void:
	_detail = on
	for m in _mass_mats.values():
		(m as BaseMaterial3D).normal_enabled = on
	for kit in _meshes:
		for mesh in _meshes[kit].values():
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				if m == null:
					continue
				if not m.has_meta("built_normal"):
					m.set_meta("built_normal", m.normal_enabled)
				m.normal_enabled = on and m.get_meta("built_normal")
	# ...and the cutaway copies of them follow.
	Cutaway.sync_all()

func _mesh(kit: String, piece: String) -> Mesh:
	if not _meshes.has(kit):
		var scene: Node = load(APT if kit == "apt" else FACTORY).instantiate()
		var by_name := {}
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			by_name[String(mi.name)] = mi.mesh
		scene.free()
		_meshes[kit] = by_name
	return _meshes[kit][piece]

## One kit piece, its left edge at x, bottom at y, its front face on FACE_Z
## (less `inset`), stretched along x by `sx`.
func _piece(parent: Node3D, kit: String, piece: String, x: float, y: float, sx := 1.0, inset := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kit, piece)
	# The street lamps hang in front of the walls, so a wall's shadow falls
	# on itself: drawing every front into the lamps' shadow maps cost ~5 ms
	# a frame on a UHD 620 for nothing you can see.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The kit models every brick; from the street camera the import's coarser
	# LODs look the same and cost a fraction.
	mi.lod_bias = 0.25
	if piece.begins_with("window_"):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mi.set_surface_override_material(i, _glass())
	parent.add_child(mi)
	var b: AABB = mi.mesh.get_aabb()
	mi.scale = Vector3(sx, 1.0, 1.0)
	mi.position = Vector3(x - b.position.x * sx, y - b.position.y, FACE_Z - b.end.z - inset)
	return mi

## Percent of upper-floor windows with a light on after dark.
const LIT_WINDOWS := 32
## Shared by every lit window; its glow follows the daylight (refresh()).
static var _lit_window: StandardMaterial3D

func _lit_glass() -> StandardMaterial3D:
	if _lit_window == null:
		_lit_window = _glass().duplicate() as StandardMaterial3D
		_lit_window.albedo_color = Color(0.3, 0.22, 0.14)
		_lit_window.emission_enabled = true
		_lit_window.emission = Color(1.0, 0.72, 0.42)
	return _lit_window

func _glass() -> StandardMaterial3D:
	if _window_glass == null:
		_window_glass = StandardMaterial3D.new()
		_window_glass.albedo_color = Color(0.05, 0.06, 0.08)
		_window_glass.metallic = 0.7
		_window_glass.roughness = 0.12
	return _window_glass

func _build_front(f: Array) -> void:
	var front := Node3D.new()
	front.name = "Front" + f[0]
	add_child(front)
	var side: String = f[6] if f.size() > 6 else "main"
	front.transform = side_transform(side)
	front.set_meta("side", side)
	front.set_meta("cell", _cell_of(f[7]) if f.size() > 7 else "Cell_Main")
	front.set_meta("mass", f[7] if f.size() > 7 else f[0])
	var kit: String = f[3]
	var p: Dictionary = KIT_PIECES[kit]
	var x0: float = local_from(side, f[1], f[2])
	var width: float = f[2] - f[1]
	var bays := maxi(1, ceili(width / MODULE - 0.2))
	var sx := width / (bays * MODULE)
	var bay_w := MODULE * sx
	# Ground floor: a flat wall in the same brick behind the shop glass and
	# the door (the kit's plain wall module is 4,608 triangles of bricks).
	var walk_in: bool = f.size() <= 6 and WALK_INS.has(f[0])
	if walk_in:
		_open_wall(front, x0, width, kit)
	else:
		_flat_wall(front, x0, width, MODULE, kit)
		for i in bays:
			_piece(front, kit, p["base"], x0 + i * bay_w, 0.0, sx)
	# Upper floors: window bays, a band between floors, the crown on top.
	var win: AABB = _mesh(kit, p["window"]).get_aabb()
	for floor_i in range(1, f[4]):
		var y := floor_i * MODULE
		for i in bays:
			var bx := x0 + i * bay_w
			_piece(front, kit, p["bay"], bx, y, sx)
			var w := _piece(front, kit, p["window"], bx + (bay_w - win.size.x) / 2.0, y + (MODULE - win.size.y) / 2.0)
			# Someone's home behind about a third of the windows: lit at night.
			if absi(("%s%d%d" % [f[0], floor_i, i]).hash()) % 100 < LIT_WINDOWS:
				for k in w.mesh.get_surface_count():
					if w.get_surface_override_material(k) == _glass():
						w.set_surface_override_material(k, _lit_glass())
			_piece(front, kit, p["band"], bx, y - 0.1, sx)
	for i in bays:
		_piece(front, kit, p["crown"], x0 + i * bay_w, f[4] * MODULE, sx)
	front.set_meta("place", f[5])
	if f[5] != "":
		_storefront(front, x0, width, walk_in)
	_dress(front, f)

## Fire escapes on the apartment blocks, an air-con unit hung under an upper
## window, a camera over each shop door. Each is placed by its measured
## bounds so its back sits on the wall and nothing pokes past street_z.
func _dress(front: Node3D, f: Array) -> void:
	var x0: float = local_from(f[6] if f.size() > 6 else "main", f[1], f[2])
	var width: float = f[2] - f[1]
	if f.size() > 8:
		_dress_block(front, f, x0, width)
		return
	if f[0] in ["Home", "Electronics"] and f[4] >= 3:
		_fire_escape(front, "FireEscape" + f[0], x0, width, f[4])
	if f[3] == "apt" and f[4] >= 2 and f[0] != "Home":
		_on_wall(front, AIRCON, "AirCon", x0 + width * 0.75, MODULE + 0.35)
	if f[5] != "" and f[5] != "bar":
		_on_wall(front, CAMERA, "Camera", x0 + width / 2.0 + 0.9, 2.45)

## The rest of the block's fronts dress by their flags.
func _dress_block(front: Node3D, f: Array, x0: float, width: float) -> void:
	var flags: String = f[8]
	if flags.contains("escape") and f[4] >= 3:
		_fire_escape(front, "FireEscape" + f[0], x0 + width * 0.1, minf(width * 0.8, 5.0), f[4])
	if flags.contains("aircon") and f[4] >= 2:
		_on_wall(front, AIRCON, "AirCon", x0 + width * 0.3, MODULE + 0.35)
		if width > 9.0:
			_on_wall(front, AIRCON, "AirCon2", x0 + width * 0.8, MODULE * 2.0 + 0.35 if f[4] >= 3 else MODULE + 0.35)
	# A shop that isn't one of the game's: glass and a glow while it's
	# open (8-21), the shutter after; or one that's closed for good.
	if flags.contains("shop") or flags.contains("closed"):
		_storefront(front, x0, width)
		front.set_meta("hours", [8, 21] if flags.contains("shop") else [0, 0])
	if flags.contains("shutter"):
		var shutter: Node3D = _scene(SHUTTER).instantiate()
		shutter.name = "GarageShutter"
		front.add_child(shutter)
		var sb := AABB()
		for mi in shutter.find_children("*", "MeshInstance3D", true, false):
			if not String(mi.name).contains("graffiti"):
				mi.free()
				continue
			var mb: AABB = mi.transform * mi.get_aabb()
			sb = mb if sb.size == Vector3.ZERO else sb.merge(mb)
		var w := minf(width - 0.6, 4.0)
		var ssx := w / sb.size.x
		shutter.scale = Vector3(ssx, 2.6 / sb.size.y, 1.0)
		shutter.position = Vector3(x0 + (width - w) / 2.0 - sb.position.x * ssx, 0.05 - sb.position.y * shutter.scale.y, FACE_Z - sb.end.z)

# --- Sides of the block --------------------------------------------------------

## The transform that turns a front laid out facing south on Main Street
## (local x along the street, its face on FACE_Z) onto `side`.
static func side_transform(side: String) -> Transform3D:
	var facing: Vector3 = SIDES[side][0]
	var along := Vector3.UP.cross(facing)
	var origin := facing * (float(SIDES[side][1]) * _axis_sign(facing) - STREET_Z)
	return Transform3D(Basis(along, Vector3.UP, facing), origin)

## +1 if `facing` points along +x or +z, -1 if along -x or -z.
static func _axis_sign(facing: Vector3) -> float:
	return facing.x + facing.z

## Where a front from world `a` to `b` (along its side) starts in its own
## local x: rows facing north or west run against the world axis.
static func local_from(side: String, a: float, b: float) -> float:
	var along := Vector3.UP.cross(SIDES[side][0])
	var s := along.x + along.z
	return a if s > 0.0 else -b

func _cell_of(mass_name: String) -> String:
	for m in masses():
		if m["name"] == mass_name:
			return m["cell"]
	return "Cell_Main"

## The list is fixed: worked out once per session.
static var _masses: Array = []

## Every building on the block: {name, rect (Rect2 in x/z), floors, kit,
## cell}. The rows' buildings come from their fronts (one per front, out
## to the row's depth, butted up so there are no slits between them); the
## rest are BLOCK_MASSES. build_rooms_3d.gd gives each one its collider.
static func masses() -> Array:
	if not _masses.is_empty():
		return _masses
	var out := _masses
	var rows := {}
	for f in FRONTS:
		rows.get_or_add("main", []).append([f[0], f[1], f[2], f[3], f[4]])
	for f in BLOCK_FRONTS:
		if ROW_BACK.has(f[6]) and f[7] == f[0]:
			rows.get_or_add(f[6], []).append([f[0], f[1], f[2], f[3], f[4]])
	for side in rows:
		var list: Array = rows[side]
		if side == "main":
			list = _main_row(list)
		list.sort_custom(func(a, b): return a[1] < b[1])
		var line: float = SIDES[side][1]
		var back: float = ROW_BACK[side]
		var along_x := absf(Vector3(SIDES[side][0]).z) > 0.5
		for i in list.size():
			var a: float = list[i][1]
			var b: float = list[i][2]
			# Trim into the neighbour that's already there; close slits.
			if i > 0:
				a = maxf(a, list[i - 1][2])
			if i + 1 < list.size() and list[i + 1][1] - b < 0.3 and list[i + 1][1] > b:
				b = list[i + 1][1]
			var r := Rect2(a, minf(line, back), b - a, absf(line - back)) if along_x else Rect2(minf(line, back), a, absf(line - back), b - a)
			out.append({"name": list[i][0], "rect": r, "floors": list[i][4], "kit": list[i][3], "cell": ROW_CELL[side]})
	for m in BLOCK_MASSES:
		out.append({"name": m[0], "rect": Rect2(m[1], m[2], m[3] - m[1], m[4] - m[2]), "floors": m[5], "kit": m[6], "cell": m[7]})
	return out

## Main Street's row of buildings with the walk-ins' bodies widened to their
## rooms (WALK_INS) and the Bar's gone.
static func _main_row(list: Array) -> Array:
	var out := []
	for e in list:
		if e[0] in MASS_DROP:
			continue
		if WALK_INS.has(e[0]):
			var span: Array = WALK_INS[e[0]]["span"]
			e = [e[0], span[0], span[1], e[3], e[4]]
		out.append(e)
	return out

static var _roof_mat: StandardMaterial3D
## The buildings' own walls (where no front covers them): old brick, a shade
## per kit, triplanar so it tiles at true size on any wall.
static var _mass_mats := {}

static func _mass_mat(kit: String) -> StandardMaterial3D:
	if not _mass_mats.has(kit):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/pbr/bricks_old_diff.jpg")
		m.normal_enabled = _detail
		m.normal_texture = load("res://assets/pbr/bricks_old_nor.jpg")
		m.roughness_texture = load("res://assets/pbr/bricks_old_rough.jpg")
		m.albedo_color = Color(0.62, 0.5, 0.44) if kit == "apt" else Color(0.5, 0.44, 0.4)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / 2.0
		_mass_mats[kit] = m
	return _mass_mats[kit]

## A building behind its fronts: its walls where no front covers them, in
## the kit's own brick or plaster (UVs at the kit's 3 m per tile), a coping
## along their tops, and a gravel roof. One mesh, two surfaces.
func _build_mass(m: Dictionary) -> void:
	var r: Rect2 = m["rect"]
	var h: float = m["floors"] * MODULE + ROOF_OVER
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	# x0,z0 -> x1,z1 corners per face, outward normal.
	var faces := [
		[Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y), Vector3.BACK],
		[Vector3(r.end.x, 0, r.position.y), Vector3(r.position.x, 0, r.position.y), Vector3.FORWARD],
		[Vector3(r.end.x, 0, r.end.y), Vector3(r.end.x, 0, r.position.y), Vector3.RIGHT],
		[Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y), Vector3.LEFT],
	]
	var any_wall := false
	for face in faces:
		for seg in _uncovered(m["name"], face[0], face[1], face[2]):
			any_wall = true
			_quad(walls, seg[0], seg[1], 0.0, h + COPING.y, face[2])
			# The coping: a lip along the top, so the roof reads as a roof.
			var inward: Vector3 = -face[2] * COPING.x
			_cap(walls, seg[0] + Vector3(0, h + COPING.y, 0), seg[1] + Vector3(0, h + COPING.y, 0), inward)
			_quad(walls, seg[1] + inward, seg[0] + inward, h, h + COPING.y, -face[2])
	var mesh := ArrayMesh.new()
	if any_wall:
		walls.generate_tangents()
		walls.commit(mesh)
		mesh.surface_set_material(0, _mass_mat(m["kit"]))
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(roof, Vector3(r.position.x, h, r.end.y), Vector3(r.end.x, h, r.end.y), Vector3(0, 0, -r.size.y))
	roof.generate_tangents()
	# A walk-in's roof is a node of its own: it comes off while you're
	# inside (world/WalkInShop.gd), and the room shows.
	var split: bool = WALK_INS.has(m["name"])
	var roof_mesh := ArrayMesh.new() if split else mesh
	roof.commit(roof_mesh)
	if _roof_mat == null:
		_roof_mat = StandardMaterial3D.new()
		_roof_mat.albedo_texture = load("res://assets/pbr/gravel_diff.jpg")
		_roof_mat.normal_enabled = true
		_roof_mat.normal_texture = load("res://assets/pbr/gravel_nor.jpg")
		_roof_mat.roughness_texture = load("res://assets/pbr/gravel_rough.jpg")
		_roof_mat.albedo_color = Color(0.36, 0.35, 0.34)
		_roof_mat.uv1_triplanar = true
		_roof_mat.uv1_world_triplanar = true
		# Roofing gravel is small: the set's 1.5 m tile at half size.
		_roof_mat.uv1_scale = Vector3.ONE / 0.75
	roof_mesh.surface_set_material(roof_mesh.get_surface_count() - 1, _roof_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Mass" + m["name"]
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("cell", m["cell"])
	add_child(mi)
	var roof_holder: MeshInstance3D = mi
	if split:
		roof_holder = MeshInstance3D.new()
		roof_holder.name = "Roof" + m["name"]
		roof_holder.mesh = roof_mesh
		roof_holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roof_holder.set_meta("cell", m["cell"])
		add_child(roof_holder)
		if not any_wall:
			mi.queue_free()
	_roof_clutter(roof_holder, m, h)

## What's on a flat roof: air-con units, a hatch, vent stacks; the bigger
## roofs a water tank. Placed from the building's name, so it's the same
## every visit.
func _roof_clutter(mass: Node3D, m: Dictionary, h: float) -> void:
	var r: Rect2 = m["rect"]
	var rng := RandomNumberGenerator.new()
	rng.seed = String(m["name"]).hash()
	var inner := r.grow(-1.2)
	if inner.size.x < 1.0 or inner.size.y < 1.0:
		return
	var spot := func() -> Vector3:
		return Vector3(rng.randf_range(inner.position.x, inner.end.x), h, rng.randf_range(inner.position.y, inner.end.y))
	var count := clampi(int(r.get_area() / 150.0), 1, 3)
	for i in count:
		var at: Vector3 = spot.call()
		_roof_units.get_or_add(m["cell"], []).append(Transform3D(Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0), at))
	var dark := _roof_bits()
	_bar(mass, dark, Vector3(1.0, 0.5, 1.0), spot.call() + Vector3(0, 0.25, 0))
	for i in mini(3, count):
		var p: Vector3 = spot.call()
		var stack := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.12
		cyl.height = 1.1
		cyl.radial_segments = 8
		cyl.material = dark
		stack.mesh = cyl
		mass.add_child(stack)
		stack.position = p + Vector3(0, 0.55, 0)
	if r.get_area() > 400.0:
		var tank := MeshInstance3D.new()
		var t := CylinderMesh.new()
		t.top_radius = 1.6
		t.bottom_radius = 1.7
		t.height = 3.0
		t.material = _tank_mat()
		tank.mesh = t
		mass.add_child(tank)
		var tp: Vector3 = spot.call()
		tank.position = tp + Vector3(0, 3.5, 0)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 1.75
		cm.height = 0.9
		cm.material = dark
		cone.mesh = cm
		mass.add_child(cone)
		cone.position = tp + Vector3(0, 5.45, 0)
		for k in 4:
			var leg := Vector3(cos(k * PI / 2.0 + 0.78), 0, sin(k * PI / 2.0 + 0.78)) * 1.3
			_bar(mass, dark, Vector3(0.12, 2.0, 0.12), tp + leg + Vector3(0, 1.0, 0))

## Roof air-con units, by cell: [Transform3D], drawn as one MultiMesh per
## unit mesh per cell (instancing ~100 model scenes was most of a load).
var _roof_units := {}

func _build_roof_units() -> void:
	var model: Node3D = _scene(AIRCON).instantiate()
	var parts := []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p != model:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		parts.append([mi.mesh, xf])
	model.free()
	for cell in _roof_units:
		var units: Array = _roof_units[cell]
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = units.size()
			for i in units.size():
				mm.set_instance_transform(i, units[i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "RoofAirCons"
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.set_meta("cell", cell)
			add_child(mmi)

static var _bits_mat: StandardMaterial3D
static var _tank: StandardMaterial3D

func _roof_bits() -> StandardMaterial3D:
	if _bits_mat == null:
		_bits_mat = StandardMaterial3D.new()
		_bits_mat.albedo_color = Color(0.2, 0.2, 0.21)
		_bits_mat.metallic = 0.5
		_bits_mat.roughness = 0.6
	return _bits_mat

## The old wooden water tanks on New York roofs.
func _tank_mat() -> StandardMaterial3D:
	if _tank == null:
		_tank = StandardMaterial3D.new()
		_tank.albedo_texture = load("res://assets/pbr/planks_diff.jpg")
		_tank.albedo_color = Color(0.5, 0.42, 0.34)
		_tank.uv1_triplanar = true
		_tank.uv1_world_triplanar = true
		_tank.uv1_scale = Vector3.ONE / 2.0
	return _tank

## The parts of a face from `a` to `b` (outward `normal`) that no front of
## this building covers: those get a plain wall.
func _uncovered(mass_name: String, a: Vector3, b: Vector3, normal: Vector3) -> Array:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var covered := []
	var fronts := FRONTS.map(func(f): return [f[0], f[1], f[2], "", 0, "", "main", f[0]]) + BLOCK_FRONTS
	for f in fronts:
		# A walk-in's room runs behind its neighbour's front too.
		var covers: bool = f[7] == mass_name or (f[6] == "main" and WALK_INS.has(mass_name))
		if not covers or Vector3(SIDES[f[6]][0]) != normal:
			continue
		# The front's span, measured from `a` along the face.
		var p0 := Vector3(f[1], 0, 0) if absf(normal.z) > 0.5 else Vector3(0, 0, f[1])
		var p1 := Vector3(f[2], 0, 0) if absf(normal.z) > 0.5 else Vector3(0, 0, f[2])
		var t0 := (p0 - a).dot(dir)
		var t1 := (p1 - a).dot(dir)
		covered.append([minf(t0, t1), maxf(t0, t1)])
	covered.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	var t := 0.0
	for c in covered:
		if c[0] > t + 0.01:
			out.append([a + dir * t, a + dir * minf(c[0], length)])
		t = maxf(t, c[1])
	if t < length - 0.01:
		out.append([a + dir * t, b])
	return out

## A vertical quad from `a` to `b` between heights y0 and y1, facing
## `normal`; UVs in kit tiles (3 m).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, y0: float, y1: float, normal: Vector3) -> void:
	var w := a.distance_to(b) / MODULE
	var corners := [[a + Vector3(0, y0, 0), Vector2(0, y1 / MODULE)], [b + Vector3(0, y0, 0), Vector2(w, y1 / MODULE)],
		[b + Vector3(0, y1, 0), Vector2(w, y0 / MODULE)], [a + Vector3(0, y1, 0), Vector2(0, y0 / MODULE)]]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(Vector2(corners[i][1].x, (y1 - corners[i][0].y + y0) / MODULE))
		st.add_vertex(corners[i][0])

## A horizontal strip facing up, from the edge a-b reaching `depth` across.
func _cap(st: SurfaceTool, a: Vector3, b: Vector3, depth: Vector3) -> void:
	var corners := [a, b, b + depth, a + depth]
	var tri := [0, 1, 2, 0, 2, 3]
	# Wind so the face points up, whichever way the edge runs.
	if (b - a).cross(depth).y > 0.0:
		tri = [0, 2, 1, 0, 3, 2]
	for i in tri:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(corners[i].x, corners[i].z) / MODULE)
		st.add_vertex(corners[i])

## A fire escape up the upper floors, scaled from the kit's showcase stack
## to the building: it starts above the signs (3.5 m) and stands out from
## the wall the way real ones do, over the sidewalk, never down to it.
func _fire_escape(front: Node3D, node_name: String, x0: float, width: float, floors: int) -> void:
	var m: Node3D = _scene(ESCAPE).instantiate()
	m.name = node_name
	front.add_child(m)
	var b := AABB()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mb: AABB = mi.transform * mi.get_aabb()
		b = mb if b.size == Vector3.ZERO else b.merge(mb)
	var bottom := 3.5
	var top := floors * MODULE - 0.2
	var s := Vector3(minf(1.0, (width - 0.6) / b.size.x), (top - bottom) / b.size.y, 0.6)
	m.scale = s
	m.position = Vector3(x0 + width / 2.0 - (b.position.x + b.size.x / 2.0) * s.x, bottom - b.position.y * s.y, FACE_Z - b.position.z * s.z)

## Instances `path` centred on x, its bottom at y, flush against the wall
## and entirely behind STREET_Z.
func _on_wall(front: Node3D, path: String, node_name: String, x: float, y: float) -> Node3D:
	var m: Node3D = _scene(path).instantiate()
	m.name = node_name
	front.add_child(m)
	var b := AABB()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mb: AABB = mi.transform * mi.get_aabb()
		b = mb if b.size == Vector3.ZERO else b.merge(mb)
	# Models face +z (out of the wall) as authored; sit the back on the wall
	# only if it fits in front of the facade, otherwise flush to street_z.
	var z := STREET_Z - 0.01 - b.end.z
	m.position = Vector3(x - (b.position.x + b.size.x / 2.0), y - b.position.y, z)
	return m

var _brick: Dictionary = {}

## A flat wall panel textured like the kit's own brick (its wall module's
## material), inset like the module was.
func _flat_wall(front: Node3D, x0: float, width: float, height: float, kit: String) -> void:
	if not _brick.has(kit):
		_brick[kit] = _mesh(kit, KIT_PIECES[kit]["wall"]).surface_get_material(0)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	q.material = _brick[kit]
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	front.add_child(mi)
	mi.position = Vector3(x0 + width / 2.0, height / 2.0, FACE_Z - 0.02)
	# The kit's UVs are 0-1 per 3 m module: keep the bricks their real size.
	var mat := (q.material as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.uv1_scale = Vector3(width / MODULE, height / MODULE, 1.0)
	q.material = mat

## Shop glass either side of the door, a warm glow behind it while open,
## and a roller shutter over the whole front while closed.
func _storefront(front: Node3D, x0: float, width: float, walk_in := false) -> void:
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.1, 0.12, 0.55)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.3
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.5, 0.42, 0.3)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.8, 0.52)
	glow_mat.emission_energy_multiplier = 0.55
	# Shelves seen through the glass, and the window's own frame.
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.06, 0.05, 0.05)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.12, 0.12, 0.13)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.45
	var door_gap := 1.3
	var pane_w := maxf(0.4, (width - door_gap) / 2.0 - 0.25)
	if walk_in:
		door_gap = shop_geometry(width)["gap"]
		pane_w = shop_geometry(width)["pane"]
	var glass := Node3D.new()
	glass.name = "Glass"
	front.add_child(glass)
	var glow := Node3D.new()
	glow.name = "Glow"
	front.add_child(glow)
	for side in [-1, 1]:
		var cx: float = x0 + width / 2.0 + side * (door_gap / 2.0 + 0.12 + pane_w / 2.0)
		var pane := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(pane_w, 1.6, 0.02)
		pm.material = glass_mat
		pane.mesh = pm
		glass.add_child(pane)
		pane.position = Vector3(cx, 1.45, FACE_Z - 0.01)
		var lit := MeshInstance3D.new()
		var lm := QuadMesh.new()
		lm.size = Vector2(pane_w, 1.6)
		lm.material = glow_mat
		lit.mesh = lm
		glow.add_child(lit)
		# Between the ground-floor wall (inset 0.02) and the glass (0.01).
		lit.position = Vector3(cx, 1.45, FACE_Z - 0.015)
		for sy in [0.95, 1.4, 1.85]:
			_bar(lit, shelf_mat, Vector3(pane_w * 0.9, 0.06, 0.004), Vector3(0, sy - 1.45, 0.002))
		for fx in [-pane_w / 2.0, 0.0, pane_w / 2.0]:
			_bar(glass, frame_mat, Vector3(0.06, 1.66, 0.04), Vector3(cx + fx, 1.45, FACE_Z - 0.005))
		_bar(glass, frame_mat, Vector3(pane_w + 0.06, 0.06, 0.04), Vector3(cx, 2.25, FACE_Z - 0.005))
		_bar(glass, frame_mat, Vector3(pane_w + 0.06, 0.06, 0.04), Vector3(cx, 0.65, FACE_Z - 0.005))
	if walk_in:
		# From afar the room behind the doorway is a glow like the windows'.
		var door_lit := MeshInstance3D.new()
		var dm := QuadMesh.new()
		dm.size = Vector2(door_gap, 2.25)
		dm.material = glow_mat
		door_lit.mesh = dm
		door_lit.name = "DoorGlow"
		glow.add_child(door_lit)
		door_lit.position = Vector3(x0 + width / 2.0, 1.125, FACE_Z - 0.015)
	var shutter: Node3D = _scene(SHUTTER).instantiate()
	shutter.name = "Shutter"
	front.add_child(shutter)
	# Only the plain shutter: the kit also ships a graffiti one.
	var sb := AABB()
	for mi in shutter.find_children("*", "MeshInstance3D", true, false):
		# The kit's other variant stands beside this one: gone, not just
		# hidden, so nothing of it sits out in the street.
		if String(mi.name).contains("graffiti"):
			mi.free()
			continue
		sb = mi.get_aabb() if sb.size == Vector3.ZERO else sb.merge(mi.get_aabb())
	var ssx := (width - 0.2) / sb.size.x
	shutter.scale = Vector3(ssx, 2.4 / sb.size.y, 1.0)
	shutter.position = Vector3(x0 + 0.1 - sb.position.x * ssx, 0.1 - sb.position.y * shutter.scale.y, FACE_Z - sb.end.z)

## The ground floor of a walk-in's front: brick, with a doorway in the middle
## and a window either side (the glass is _storefront's). Boxes, not the
## flat quad, so the brick shows from the room too and the openings go
## right through.
func _open_wall(front: Node3D, x0: float, width: float, kit: String) -> void:
	if not _brick.has(kit):
		_brick[kit] = _mesh(kit, KIT_PIECES[kit]["wall"]).surface_get_material(0)
	var mat := (_brick[kit] as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / MODULE
	var g := shop_geometry(width)
	var cx := x0 + width / 2.0
	var gap: float = g["gap"]
	var pane: float = g["pane"]
	var win_in: float = cx - gap / 2.0 - 0.12
	var spans := []
	for side in [-1.0, 1.0]:
		# Outermost brick, window sill and head, the post beside the door.
		var a: float = cx + side * (gap / 2.0 + 0.12 + pane)
		var b: float = cx + side * (gap / 2.0 + 0.12)
		var edge: float = x0 if side < 0.0 else x0 + width
		var post: float = cx + side * (gap / 2.0)
		spans.append([minf(edge, a), maxf(edge, a), 0.0, MODULE])
		spans.append([minf(a, b), maxf(a, b), 0.0, 0.65])
		spans.append([minf(a, b), maxf(a, b), 2.25, MODULE])
		spans.append([minf(b, post), maxf(b, post), 0.0, MODULE])
	spans.append([cx - gap / 2.0, cx + gap / 2.0, 2.25, MODULE])
	for sp in spans:
		if sp[1] - sp[0] < 0.01:
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sp[1] - sp[0], sp[3] - sp[2], FRONT_WALL_T)
		bm.material = mat
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		front.add_child(mi)
		mi.position = Vector3((sp[0] + sp[1]) / 2.0, (sp[2] + sp[3]) / 2.0, FACE_Z - 0.02 - FRONT_WALL_T / 2.0)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.12, 0.13)
	frame.metallic = 0.6
	frame.roughness = 0.45
	# The doorway's frame.
	for side in [-1.0, 1.0]:
		_bar(front, frame, Vector3(0.07, 2.25, 0.07), Vector3(cx + side * gap / 2.0, 1.125, FACE_Z - 0.03))
	_bar(front, frame, Vector3(gap + 0.07, 0.07, 0.07), Vector3(cx, 2.25, FACE_Z - 0.03))

func _bar(parent: Node3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	parent.add_child(mi)
	mi.position = pos

func _on_clock(_minute: int) -> void:
	refresh()

## Shutters down while closed, glass lit while open.
func refresh() -> void:
	if _lit_window:
		_lit_window.emission_energy_multiplier = 1.4 * (1.0 - smoothstep(0.3, 0.7, GameState.daylight()))
		Cutaway.sync(_lit_window)
	for front in get_children():
		var place: String = front.get_meta("place", "")
		var hours: Array = front.get_meta("hours", [])
		if (place == "" and hours.is_empty()) or not front.has_node("Glow"):
			continue
		var open: bool = GameState.is_open(place) if place != "" else GameState.hours_contain(hours, GameState.hour())
		front.get_node("Shutter").visible = not open
		# A walk-in near you is the room itself behind the glass: no painted glow.
		front.get_node("Glow").visible = open and not front.get_meta("near", false)

## A walk-in's window: the painted glow from afar, the lit room (world/
## WalkInShop.gd turns its lights on) when you're near.
func set_near(front_name: String, near: bool) -> void:
	var front := get_node_or_null("Front" + front_name)
	if front == null or not front.has_node("Glow"):
		return
	front.set_meta("near", near)
	var place: String = front.get_meta("place", "")
	front.get_node("Glow").visible = GameState.is_open(place) and not near
