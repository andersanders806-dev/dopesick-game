extends Node3D
## The block's one HIGH GROUND: the overpass deck in the east lot (assets in the scene: Overpass/Deck), reached
## by a concrete evacuation stair that is built here, with a safe zone on the deck. fx/Tsunami.gd points the
## player to it (an emergency beacon, a HUD marker) and lets whoever stands in the zone at 0:00 live through
## the wave.
##
## The block's floors are flat (bodies walk a plane, no gravity), so the climb is scripted: bodies inside the
## stair's footprint are lifted along its profile; one that walks off the top is "up" and stands on the deck
## (until it walks back down); the deck outside the zone is closed off with barriers. The dead follow you up:
## a runtime navigation region (the stair as a strip of polygons and the deck as a quad) joined to the street
## by a link. The stair is one 2.6 m wide corridor with solid sides: a choke point.
##
## Built once by ZombieBlock. `beacon(true)` lights the warning (rotating amber light, flare smoke).

const STAIR_X0 := 37.0
const STAIR_X1 := 56.0
const STAIR_Z := -29.5
const STAIR_HALF := 1.3
## Where the side walls start (the first steps are low enough to be stepped onto from the side).
const WALL_FROM := 40.0
const STEPS := 60
## The deck's surface, and the safe zone on it (x, z ranges).
const DECK_Y := 11.65
const ZONE_X := Vector2(56.4, 65.6)
const ZONE_Z := Vector2(-42.0, -17.0)
const NAV_LIFT := 0.3
## Godot wants navigation polygons wound a certain way seen from above; set by what the probe showed.
const WIND_REVERSED := false

var city: Node3D
var nav_region: NavigationRegion3D
var nav_link: NavigationLink3D
var up := {}
var active := false
var lit := false
var beacon_head: Node3D
var beacon_light: OmniLight3D
var beacon_spot: SpotLight3D
var flare_smoke: Array[CPUParticles3D] = []
var _t := 0.0
var _mat_concrete: StandardMaterial3D
var _mat_steel: StandardMaterial3D
var _mat_yellow: StandardMaterial3D
var _mat_sign: StandardMaterial3D
var _mat_glow: StandardMaterial3D
var _freed := 0

func _ready() -> void:
	name = "HighGround"
	process_priority = 200
	add_to_group("high_ground")
	_make_materials()
	_clear_props()
	_build_stair()
	_build_walls()
	_build_deck()
	_build_navigation()
	_build_beacon()
	_build_signs()

# --- Geometry --------------------------------------------------------------------------------------

func _make_materials() -> void:
	_mat_concrete = StandardMaterial3D.new()
	_mat_concrete.albedo_color = Color(0.4, 0.39, 0.37)
	_mat_concrete.vertex_color_use_as_albedo = true
	_mat_concrete.roughness = 0.92
	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.2, 0.21, 0.22)
	_mat_steel.metallic = 0.55
	_mat_steel.roughness = 0.5
	_mat_yellow = StandardMaterial3D.new()
	_mat_yellow.albedo_color = Color(0.82, 0.66, 0.08)
	_mat_yellow.roughness = 0.55
	_mat_yellow.metallic = 0.2
	_mat_sign = StandardMaterial3D.new()
	_mat_sign.albedo_color = Color(0.02, 0.18, 0.08)
	_mat_sign.roughness = 0.6
	_mat_glow = StandardMaterial3D.new()
	_mat_glow.albedo_color = Color(0.5, 1.0, 0.6)
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

## Props in the way of the stair (the lot is cluttered) are cleared.
func _clear_props() -> void:
	var cell := city.get_node_or_null("Cell_Inner")
	if cell == null:
		return
	for c in cell.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var p := n.global_position
		if p.x > STAIR_X0 - 1.5 and p.x < STAIR_X1 + 3.0 and absf(p.z - STAIR_Z) < STAIR_HALF + 1.4:
			if n is MeshInstance3D and (n.name.begins_with("Lot") and (n as MeshInstance3D).get_aabb().size.x > 12.0):
				continue
			n.queue_free()
			_freed += 1

## The stair's height at x (0 at the foot, DECK_Y at the deck).
static func height_at_x(x: float) -> float:
	return clampf((x - STAIR_X0) / (STAIR_X1 - STAIR_X0), 0.0, 1.0) * DECK_Y

func _box(st: SurfaceTool, c: Vector3, s: Vector3, color: Color) -> void:
	var h := s * 0.5
	var v := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	# faces (counter-clockwise from outside)
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f in faces:
		var idx := [f[0], f[1], f[2], f[0], f[2], f[3]]
		for i in idx:
			st.set_color(color)
			st.add_vertex(c + v[i])

func _build_stair() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var dx := (STAIR_X1 - STAIR_X0) / STEPS
	var w := STAIR_HALF * 2.0
	for i in STEPS:
		var x := STAIR_X0 + dx * (i + 0.5)
		var top := DECK_Y * float(i + 1) / STEPS
		var shade := rng.randf_range(0.88, 1.08)
		# a solid concrete block per step, down to the ground
		_box(st, Vector3(x, top * 0.5, STAIR_Z), Vector3(dx, top, w), Color(shade, shade, shade * 0.98))
		# a yellow nosing every step
		_box(st, Vector3(x - dx * 0.44, top + 0.008, STAIR_Z), Vector3(dx * 0.12, 0.016, w), Color(1.6, 1.25, 0.15))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Stair"
	mi.mesh = st.commit()
	mi.material_override = _mat_concrete
	add_child(mi)

## Solid sides (a choke point: nothing gets round it), tall enough to be a rail; yellow rails and posts for show.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "StairWalls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for side in [-1.0, 1.0]:
		var z: float = STAIR_Z + side * (STAIR_HALF + 0.12)
		var pts := PackedVector3Array()
		var x0 := WALL_FROM
		var x1 := STAIR_X1 + 0.1
		var y0 := height_at_x(x0)
		var y1 := height_at_x(x1)
		for dz in [-0.12, 0.12]:
			pts.append(Vector3(x0, 0.0, z + dz))
			pts.append(Vector3(x1, 0.0, z + dz))
			pts.append(Vector3(x1, y1 + 1.5, z + dz))
			pts.append(Vector3(x0, y0 + 1.5, z + dz))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	# rails: a post every 2 m and two rails, along the slope
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sy := (DECK_Y) / (STAIR_X1 - STAIR_X0)
	for side in [-1.0, 1.0]:
		var z: float = STAIR_Z + side * (STAIR_HALF + 0.12)
		var x := WALL_FROM
		while x <= STAIR_X1:
			_box(st, Vector3(x, height_at_x(x) + 0.55, z), Vector3(0.08, 1.1, 0.08), Color(1, 1, 1))
			x += 2.0
		for hh in [0.55, 1.1]:
			var steps := 18
			var xa := WALL_FROM
			var xb := STAIR_X1
			for k in steps:
				var xm := lerpf(xa, xb, (k + 0.5) / steps)
				_box(st, Vector3(xm, height_at_x(xm) + hh, z), Vector3((xb - xa) / steps + 0.05, 0.07, 0.07), Color(1, 1, 1))
	st.generate_normals()
	var rails := MeshInstance3D.new()
	rails.name = "Rails"
	rails.mesh = st.commit()
	rails.material_override = _mat_yellow
	rails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rails)

## The deck: closed at both ends of the safe zone with concrete barriers (solid) and the zone painted on it.
func _build_deck() -> void:
	var body := StaticBody3D.new()
	body.name = "DeckBarriers"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zend in [ZONE_Z.x, ZONE_Z.y]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(ZONE_X.y - ZONE_X.x + 1.2, 3.0, 0.8)
		cs.shape = bs
		cs.position = Vector3((ZONE_X.x + ZONE_X.y) * 0.5, DECK_Y + 1.5, zend)
		body.add_child(cs)
		# visual: a row of barriers
		var x := ZONE_X.x + 0.5
		while x < ZONE_X.y:
			_box(st, Vector3(x, DECK_Y + 0.45, zend), Vector3(1.6, 0.9, 0.6), Color(0.85, 0.84, 0.8))
			_box(st, Vector3(x, DECK_Y + 0.95, zend), Vector3(0.9, 0.2, 0.4), Color(0.85, 0.84, 0.8))
			x += 1.7
	# the edges of the deck: the existing barrier meshes get a solid core
	for ex in [ZONE_X.x - 0.1, ZONE_X.y + 0.1]:
		var cs2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		bs2.size = Vector3(0.6, 3.0, ZONE_Z.y - ZONE_Z.x + 1.6)
		cs2.shape = bs2
		cs2.position = Vector3(ex + (-0.3 if ex < 61.0 else 0.3), DECK_Y + 1.5, (ZONE_Z.x + ZONE_Z.y) * 0.5)
		body.add_child(cs2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Barriers"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.71, 0.68)
	m.vertex_color_use_as_albedo = false
	m.roughness = 0.9
	mi.material_override = m
	add_child(mi)
	# the zone, painted: a dashed green outline and the words
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.8, 0.4)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zx0 := ZONE_X.x + 0.5
	var zx1 := ZONE_X.y - 0.5
	var zz0 := ZONE_Z.x + 1.1
	var zz1 := ZONE_Z.y - 1.1
	var xx := zx0
	while xx < zx1:
		_box(pst, Vector3(xx + 0.7, DECK_Y + 0.015, zz0), Vector3(1.4, 0.01, 0.22), Color.WHITE)
		_box(pst, Vector3(xx + 0.7, DECK_Y + 0.015, zz1), Vector3(1.4, 0.01, 0.22), Color.WHITE)
		xx += 2.4
	var zz := zz0
	while zz < zz1:
		_box(pst, Vector3(zx0, DECK_Y + 0.015, zz + 0.7), Vector3(0.22, 0.01, 1.4), Color.WHITE)
		_box(pst, Vector3(zx1, DECK_Y + 0.015, zz + 0.7), Vector3(0.22, 0.01, 1.4), Color.WHITE)
		zz += 2.4
	var paint := MeshInstance3D.new()
	paint.name = "ZonePaint"
	paint.mesh = pst.commit()
	paint.material_override = gm
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paint)
	var label := Label3D.new()
	label.text = "HIGH GROUND"
	label.font_size = 220
	label.pixel_size = 0.012
	label.modulate = Color(0.55, 1.0, 0.65, 0.9)
	label.outline_size = 0
	label.shaded = false
	label.rotation_degrees = Vector3(-90, 90, 0)
	label.position = Vector3(61.0, DECK_Y + 0.03, -29.5)
	label.double_sided = false
	add_child(label)

func _build_signs() -> void:
	# at the foot: a green board on posts, lit, pointing up the stair
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 1.6, 3.2)
	board.mesh = bm
	board.material_override = _mat_sign
	board.position = Vector3(STAIR_X0 + 0.4, 2.3, STAIR_Z - 4.2)
	add_child(board)
	for dz in [-1.4, 1.4]:
		var post := MeshInstance3D.new()
		var pmn := BoxMesh.new()
		pmn.size = Vector3(0.1, 2.3, 0.1)
		post.mesh = pmn
		post.material_override = _mat_steel
		post.position = Vector3(STAIR_X0 + 0.4, 1.15, STAIR_Z - 4.2 + dz)
		add_child(post)
	var l1 := Label3D.new()
	l1.text = "TSUNAMI EVACUATION\nHIGH GROUND  >"
	l1.font_size = 64
	l1.pixel_size = 0.0075
	l1.modulate = Color(0.75, 1.0, 0.8)
	l1.shaded = false
	l1.rotation_degrees = Vector3(0, 90, 0)
	l1.position = Vector3(STAIR_X0 + 0.5, 2.3, STAIR_Z - 4.2)
	add_child(l1)
	var l2 := Label3D.new()
	l2.text = "TSUNAMI EVACUATION\nHIGH GROUND  >"
	l2.font_size = 64
	l2.pixel_size = 0.0075
	l2.modulate = Color(0.75, 1.0, 0.8)
	l2.shaded = false
	l2.rotation_degrees = Vector3(0, -90, 0)
	l2.position = Vector3(STAIR_X0 + 0.3, 2.3, STAIR_Z - 4.2)
	add_child(l2)
	# lamps up the stair, low and green, so it reads from the lot
	for i in 5:
		var x := lerpf(STAIR_X0 + 3.0, STAIR_X1 - 2.0, i / 4.0)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.7, 1.0, 0.8)
		lamp.light_energy = 0.9
		lamp.omni_range = 7.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(x, height_at_x(x) + 2.4, STAIR_Z)
		add_child(lamp)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		bulb.mesh = sm
		bulb.material_override = _mat_glow
		bulb.position = lamp.position
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)

# --- Navigation ------------------------------------------------------------------------------------

func _build_navigation() -> void:
	var nm := NavigationMesh.new()
	var verts := PackedVector3Array()
	var segs := 19
	var zl := STAIR_Z - STAIR_HALF + 0.35
	var zr := STAIR_Z + STAIR_HALF - 0.35
	for i in segs + 1:
		var x := lerpf(STAIR_X0, STAIR_X1, float(i) / segs)
		var y := height_at_x(x) + NAV_LIFT
		verts.append(Vector3(x, y, zl))
		verts.append(Vector3(x, y, zr))
	# the deck's safe zone, and a neck from the stair's head to it
	var dy := DECK_Y + NAV_LIFT
	var r0 := verts.size()
	verts.append(Vector3(ZONE_X.x + 0.4, dy, ZONE_Z.x + 0.9))
	verts.append(Vector3(ZONE_X.x + 0.4, dy, ZONE_Z.y - 0.9))
	verts.append(Vector3(ZONE_X.y - 0.8, dy, ZONE_Z.y - 0.9))
	verts.append(Vector3(ZONE_X.y - 0.8, dy, ZONE_Z.x + 0.9))
	nm.vertices = verts
	var quads: Array = []
	for i in segs:
		var a := i * 2
		quads.append([a, a + 2, a + 3, a + 1])
	var h := segs * 2
	quads.append([h, h + 1, r0 + 1, r0])
	quads.append([r0, r0 + 1, r0 + 2, r0 + 3])
	for q in quads:
		var idx := PackedInt32Array(q)
		if WIND_REVERSED:
			idx.reverse()
		nm.add_polygon(idx)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "HighGroundNav"
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_link = NavigationLink3D.new()
	nav_link.name = "HighGroundLink"
	nav_link.bidirectional = true
	nav_link.start_position = Vector3(STAIR_X0 + 0.9, NAV_LIFT, STAIR_Z - STAIR_HALF - 1.6)
	nav_link.end_position = Vector3(STAIR_X0 + 0.9, height_at_x(STAIR_X0 + 0.9) + NAV_LIFT, STAIR_Z - STAIR_HALF + 0.5)
	nav_link.enter_cost = 0.0
	nav_link.travel_cost = 1.0
	add_child(nav_link)

# --- The warning's beacon ------------------------------------------------------------------------------

func _build_beacon() -> void:
	beacon_head = Node3D.new()
	beacon_head.name = "Beacon"
	beacon_head.position = Vector3(ZONE_X.x + 1.2, DECK_Y, STAIR_Z - 6.0)
	beacon_head.visible = false
	add_child(beacon_head)
	var mast := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.25, 6.0, 0.25)
	mast.mesh = mm
	mast.material_override = _mat_steel
	mast.position = Vector3(0, 3.0, 0)
	beacon_head.add_child(mast)
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	lens.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.55, 0.05)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.5, 0.05)
	lm.emission_energy_multiplier = 6.0
	lens.material_override = lm
	lens.position = Vector3(0, 6.3, 0)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon_head.add_child(lens)
	beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.55, 0.15)
	beacon_light.light_energy = 6.0
	beacon_light.omni_range = 60.0
	beacon_light.shadow_enabled = false
	beacon_light.position = Vector3(0, 6.3, 0)
	beacon_head.add_child(beacon_light)
	# the rotating beam: a spot and a thin glowing cone you can see
	beacon_spot = SpotLight3D.new()
	beacon_spot.light_color = Color(1.0, 0.5, 0.1)
	beacon_spot.light_energy = 8.0
	beacon_spot.spot_range = 120.0
	beacon_spot.spot_angle = 14.0
	beacon_spot.shadow_enabled = false
	beacon_spot.position = Vector3(0, 6.3, 0)
	beacon_head.add_child(beacon_spot)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 7.0
	cm.height = 60.0
	cm.radial_segments = 10
	cone.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cmat.albedo_color = Color(1.0, 0.45, 0.05, 0.1)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = cmat
	cone.rotation_degrees = Vector3(0, 0, 90)
	cone.position = Vector3(30.0, 0, 0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam := Node3D.new()
	beam.name = "Beam"
	beam.position = Vector3(0, 6.3, 0)
	beacon_head.add_child(beam)
	beam.add_child(cone)
	beacon_spot.reparent(beam)
	beacon_spot.position = Vector3.ZERO
	beacon_spot.rotation_degrees = Vector3(0, -90, 0)
	# two road flares, burning red, smoking
	for i in 2:
		var smoke := CPUParticles3D.new()
		smoke.name = "FlareSmoke%d" % i
		smoke.amount = 40
		smoke.lifetime = 7.0
		smoke.local_coords = false
		smoke.direction = Vector3.UP
		smoke.spread = 8.0
		smoke.initial_velocity_min = 2.0
		smoke.initial_velocity_max = 3.5
		smoke.gravity = Vector3(1.2, 0.5, 0.0)
		smoke.scale_amount_min = 2.0
		smoke.scale_amount_max = 5.0
		smoke.color = Color(0.9, 0.2, 0.15, 0.5)
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.billboard_keep_scale = true
		qm.vertex_color_use_as_albedo = true
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.albedo_texture = _soft()
		q.material = qm
		smoke.mesh = q
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.35, 0.25, 0.65))
		grad.add_point(0.4, Color(0.7, 0.12, 0.1, 0.4))
		grad.set_color(1, Color(0.2, 0.05, 0.05, 0.0))
		smoke.color_ramp = grad
		smoke.position = Vector3(1.2 + i * 1.6, 0.25, 1.5 - i * 3.0)
		smoke.emitting = false
		beacon_head.add_child(smoke)
		flare_smoke.append(smoke)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.15, 0.1)
		fl.light_energy = 2.5
		fl.omni_range = 12.0
		fl.shadow_enabled = false
		fl.position = smoke.position + Vector3(0, 0.4, 0)
		beacon_head.add_child(fl)

static var _soft_tex: Texture2D

static func _soft() -> Texture2D:
	if _soft_tex == null:
		var g := GradientTexture2D.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.width = 64
		g.height = 64
		_soft_tex = g
	return _soft_tex

## Lights the warning (or puts it out).
func beacon(on: bool) -> void:
	lit = on
	beacon_head.visible = on
	for s in flare_smoke:
		s.emitting = on

func _process(delta: float) -> void:
	if not lit:
		return
	_t += delta
	var beam := beacon_head.get_node("Beam") as Node3D
	beam.rotation.y = _t * 2.2
	beacon_light.light_energy = 4.0 + 3.0 * (0.5 + 0.5 * sin(_t * 8.0))

# --- Bodies on the stair and the deck ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var bodies: Array = get_tree().get_nodes_in_group("zombies")
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		bodies.append(player)
	for b in bodies:
		if b is CharacterBody3D and is_instance_valid(b):
			_place(b)
	# forget the gone
	for id in up.keys():
		if not is_instance_id_valid(id):
			up.erase(id)

func _place(b: CharacterBody3D) -> void:
	var p := b.global_position
	var id := b.get_instance_id()
	var in_stair := p.x >= STAIR_X0 and p.x <= STAIR_X1 + 0.05 and absf(p.z - STAIR_Z) <= STAIR_HALF + 0.05
	if in_stair and (p.y < DECK_Y - 0.4 or not up.get(id, false)):
		var y := height_at_x(p.x)
		var t := (p.x - STAIR_X0) / (STAIR_X1 - STAIR_X0)
		if t >= 0.97:
			up[id] = true
		elif t <= 0.04:
			up[id] = false
		b.global_position.y = y
		return
	if up.get(id, false):
		if p.x >= ZONE_X.x - 1.0 and p.x <= ZONE_X.y + 0.6 and p.z >= ZONE_Z.x - 0.6 and p.z <= ZONE_Z.y + 0.6:
			b.global_position.y = DECK_Y
		elif in_stair:
			b.global_position.y = height_at_x(p.x)
		else:
			# got out of the footprint somehow: back to the street
			up[id] = false
			b.global_position.y = 0.0
	elif p.y > 0.05 and p.y < 12.0 and not in_stair and _near_footprint(p):
		# walked off the low steps sideways
		b.global_position.y = 0.0

func _near_footprint(p: Vector3) -> bool:
	return p.x >= STAIR_X0 - 1.0 and p.x <= STAIR_X1 + 1.0 and absf(p.z - STAIR_Z) < STAIR_HALF + 2.0

# --- Questions -----------------------------------------------------------------------------------

func is_up(b: Node) -> bool:
	return up.get(b.get_instance_id(), false)

## Whether `p` is in the safe zone (on the deck inside the barriers).
func zone_contains(p: Vector3) -> bool:
	return p.x >= ZONE_X.x and p.x <= ZONE_X.y and p.z >= ZONE_Z.x and p.z <= ZONE_Z.y and p.y >= DECK_Y - 0.6

func zone_center() -> Vector3:
	return Vector3((ZONE_X.x + ZONE_X.y) * 0.5, DECK_Y, (ZONE_Z.x + ZONE_Z.y) * 0.5)

## Where the stair starts (on the street).
func stair_base() -> Vector3:
	return Vector3(STAIR_X0 + 1.0, 0.0, STAIR_Z)

## Puts a body on the deck (tests and captures).
func put_up(b: CharacterBody3D, at: Vector3) -> void:
	up[b.get_instance_id()] = true
	b.global_position = Vector3(at.x, DECK_Y, at.z)
