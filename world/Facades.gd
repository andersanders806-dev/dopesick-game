extends Node3D
## The block's buildings: real fronts assembled at load from Poly Haven's
## CC0 modular facade kits (brick apartment blocks for the shops, the
## factory kit for the tall narrow fillers), replacing Kenney's toy city.
## Pieces are 3 x 3 m modules, stretched to each front's measured width.
## The ground floor is what the top-down camera sees most: shop glass with
## a lit interior, and a roller shutter when the place is closed.
##
## Visual only: the street's colliders (BoundsNorth) and doors are the
## builder's and don't move. Fronts sit just behind the street_z plane the
## signs, hour plates and posters are on.

const APT := "res://assets/polyhaven/modular_urban_apartments_facade/modular_urban_apartments_facade.gltf"
const FACTORY := "res://assets/polyhaven/modular_factory_facade/modular_factory_facade.gltf"
const SHUTTER := "res://assets/polyhaven/rollershutter_window_01/rollershutter_window_01.gltf"
const ESCAPE := "res://assets/polyhaven/modular_fire_escape/modular_fire_escape.gltf"
const AIRCON := "res://assets/polyhaven/exterior_aircon_unit/exterior_aircon_unit.gltf"
const CAMERA := "res://assets/polyhaven/security_camera_02/security_camera_02.gltf"
const STREET_Z := -4.5
const FACE_Z := STREET_Z - 0.03
const MODULE := 3.0
## name, x from, x to, kit, floors, place (GameState.OPENING_HOURS key, or "").
## The x extents are the old Kenney buildings', measured.
const FRONTS := [
	["Police", -26.71, -22.29, "apt", 2, ""], ["Home", -19.71, -15.29, "apt", 3, ""],
	["Pharmacy", -12.60, -8.40, "apt", 3, "pharmacy"], ["Bar", -5.93, -1.07, "apt", 3, "bar"],
	["Shop", 1.40, 5.60, "apt", 3, "convenience"], ["Liquor", 8.29, 12.71, "apt", 2, "liquor"],
	["Supermarket", 14.55, 20.45, "apt", 1, "supermarket"], ["Electronics", 22.29, 26.71, "apt", 3, "electronics"],
	["Karts", -15.25, -12.75, "factory", 4, "karts"], ["Pawn", -1.25, 1.25, "factory", 4, "pawn"],
	["Music", -8.25, -5.75, "factory", 4, "music"], ["Shelter", 5.75, 8.25, "factory", 4, "shelter"],
	# The block behind the backyard gate, and one at each end of the street.
	["Gate", -22.25, -19.75, "factory", 4, ""], ["WestEnd", -34.60, -26.71, "apt", 2, ""],
	["EastEnd", 28.29, 32.71, "apt", 2, ""],
]
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
	GameState.clock_changed.connect(_on_clock)
	refresh()

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
	var kit: String = f[3]
	var p: Dictionary = KIT_PIECES[kit]
	var x0: float = f[1]
	var width: float = f[2] - f[1]
	var bays := maxi(1, ceili(width / MODULE - 0.2))
	var sx := width / (bays * MODULE)
	var bay_w := MODULE * sx
	# Ground floor: a flat wall in the same brick behind the shop glass and
	# the door (the kit's plain wall module is 4,608 triangles of bricks).
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
			_piece(front, kit, p["window"], bx + (bay_w - win.size.x) / 2.0, y + (MODULE - win.size.y) / 2.0)
			_piece(front, kit, p["band"], bx, y - 0.1, sx)
	for i in bays:
		_piece(front, kit, p["crown"], x0 + i * bay_w, f[4] * MODULE, sx)
	front.set_meta("place", f[5])
	if f[5] != "":
		_storefront(front, x0, width)
	_dress(front, f)

## Fire escapes on the apartment blocks, an air-con unit hung under an upper
## window, a camera over each shop door. Each is placed by its measured
## bounds so its back sits on the wall and nothing pokes past street_z.
func _dress(front: Node3D, f: Array) -> void:
	var x0: float = f[1]
	var width: float = f[2] - f[1]
	if f[0] in ["Home", "Electronics"] and f[4] >= 3:
		_fire_escape(front, "FireEscape" + f[0], x0, width, f[4])
	if f[3] == "apt" and f[4] >= 2 and f[0] != "Home":
		_on_wall(front, AIRCON, "AirCon", x0 + width * 0.75, MODULE + 0.35)
	if f[5] != "" and f[5] != "bar":
		_on_wall(front, CAMERA, "Camera", x0 + width / 2.0 + 0.9, 2.45)

## A fire escape up the upper floors, scaled from the kit's showcase stack
## to the building: it starts above the signs (3.5 m) and stands out from
## the wall the way real ones do, over the sidewalk, never down to it.
func _fire_escape(front: Node3D, node_name: String, x0: float, width: float, floors: int) -> void:
	var m: Node3D = load(ESCAPE).instantiate()
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
	var m: Node3D = load(path).instantiate()
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
func _storefront(front: Node3D, x0: float, width: float) -> void:
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
	var shutter: Node3D = load(SHUTTER).instantiate()
	shutter.name = "Shutter"
	front.add_child(shutter)
	# Only the plain shutter: the kit also ships a graffiti one.
	var sb := AABB()
	for mi in shutter.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).contains("graffiti"):
			mi.visible = false
			continue
		sb = mi.get_aabb() if sb.size == Vector3.ZERO else sb.merge(mi.get_aabb())
	var ssx := (width - 0.2) / sb.size.x
	shutter.scale = Vector3(ssx, 2.4 / sb.size.y, 1.0)
	shutter.position = Vector3(x0 + 0.1 - sb.position.x * ssx, 0.1 - sb.position.y * shutter.scale.y, FACE_Z - sb.end.z)

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
	for front in get_children():
		var place: String = front.get_meta("place", "")
		if place == "" or not front.has_node("Shutter"):
			continue
		var open: bool = GameState.is_open(place)
		front.get_node("Shutter").visible = not open
		front.get_node("Glow").visible = open
