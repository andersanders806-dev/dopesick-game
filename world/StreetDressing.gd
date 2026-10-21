extends Node3D
## Wear and tear on the block, as decals (textures from
## dev-tools/gen_street_decals.py): tags and flyers on the shop fronts
## between the doors, grime running down from the gutters, gum and coffee
## stains and cracks in the sidewalk, litter in the gutter, oil in the road,
## and puddles that go glossy and throw the neon back when it rains.
##
## Decals cost next to nothing -- no geometry, one projected texture each --
## so this is detail every preset gets. The layout is seeded, so the block
## looks the same every visit: the tag by the bar is always by the bar.

const DIR := "res://assets/decals/"
## The shop fronts' doors, west to east (build_rooms_3d.gd's city).
const DOORS_X := [-24.5, -17.5, -10.5, -3.5, 3.5, 10.5, 17.5, 24.5]
## The shop fronts step back in panels, from -4.7 to about -5.5; the
## projection box spans all of them and stops at -4.45, in front of the
## doors and short of anyone walking past.
const WALL_Z := -5.0
const WALL_DEPTH := 1.1
const SIDEWALK_Z := Vector2(-4.3, -1.7)
const ROAD_Z := Vector2(-1.2, 4.2)
const STREET_X := 28.5
const TAGS := ["tag_nofuture", "tag_dsk", "tag_block9", "tag_eattherich", "tag_circle_a"]
const FLYERS := ["flyer_lostdog", "flyer_gold", "flyer_gig", "flyer_help"]

var _puddles: Array[Decal] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1990
	# The walls: between each pair of doors, a tag, and flyers near the doors.
	for i in DOORS_X.size():
		var x: float = DOORS_X[i]
		for side: float in [-1.0, 1.0]:
			var wx: float = x + side * rng.randf_range(1.9, 2.7)
			if rng.randf() < 0.6:
				var t: String = TAGS[rng.randi() % TAGS.size()]
				var w := rng.randf_range(1.7, 2.5)
				_wall(t, Vector3(wx, rng.randf_range(0.7, 1.4), WALL_Z), Vector2(w, w * (0.4 if t != "tag_circle_a" else 1.0)))
			if rng.randf() < 0.45:
				var f: String = FLYERS[rng.randi() % FLYERS.size()]
				_wall(f, Vector3(x + side * rng.randf_range(1.1, 1.5), rng.randf_range(1.2, 1.6), WALL_Z), Vector2(0.34, 0.45), rng.randf_range(-8, 8))
			# Grime runs down from the gutters to the pavement.
			_wall("grime_streak", Vector3(x + side * rng.randf_range(1.2, 3.2), 1.1, WALL_Z), Vector2(rng.randf_range(0.6, 1.2), 2.2), 0.0, 0.8)
	# The sidewalk.
	for i in 34:
		var p := Vector3(rng.randf_range(-STREET_X, STREET_X), 0.0, rng.randf_range(SIDEWALK_Z.x, SIDEWALK_Z.y))
		match i % 4:
			0: _ground("stain_dark", p, rng.randf_range(0.6, 1.3), rng, 0.7)
			1: _ground("stain_coffee", p, rng.randf_range(0.25, 0.5), rng, 0.8)
			2: _ground("crack", p, rng.randf_range(1.0, 2.0), rng, 0.9)
			3: _ground("litter", Vector3(p.x, 0.0, rng.randf_range(-2.0, -1.6)), rng.randf_range(0.8, 1.4), rng, 1.0)
	# The road: oil where cars sit, puddles in the dips.
	for i in 12:
		_ground("stain_oil", Vector3(rng.randf_range(-STREET_X, STREET_X), 0.0, rng.randf_range(0.0, 0.8)), rng.randf_range(1.0, 2.2), rng, 0.8)
	for i in 10:
		var p := Vector3(rng.randf_range(-STREET_X, STREET_X), 0.0, rng.randf_range(ROAD_Z.x, ROAD_Z.y))
		_puddles.append(_ground("puddle", p, rng.randf_range(1.2, 2.6), rng, 1.0, true))
	_dress_block()
	GameState.weather_changed.connect(_on_weather)
	_on_weather(GameState.is_raining())

## The rest of the block (dev-tools/city/), its own seed so the middle
## above stays exactly as it was: the same wear on every street, walls
## facing every way. Sidewalks and walls as [x0, z0, x1, z1] and [from, to,
## line, outward normal]; along x for walls facing north or south.
const BLOCK_SIDEWALKS := [
	[-66.0, -4.3, -30.0, -1.7], [30.0, -4.3, 66.0, -1.7],      # Main past the shops
	[-67.8, -84.0, -65.2, -6.0], [-76.8, -94.0, -74.2, 3.0],   # West Ave
	[65.2, -84.0, 67.8, -6.0], [74.2, -94.0, 76.8, 3.0],       # East Ave
	[-76.0, -95.6, 76.0, -94.2], [-66.0, -87.8, 66.0, -85.2],  # Back Street
	[-8.8, -84.0, -6.2, -19.2], [-8.0, -18.8, 35.0, -16.2],    # the back alley, the lane
]
const BLOCK_ROADS := [[-66.0, -1.2, -30.0, 4.2], [30.0, -1.2, 66.0, 4.2], [-73.6, -87.0, -68.4, -2.0], [68.4, -87.0, 73.6, -2.0], [-73.0, -93.6, 73.0, -88.4]]
const BLOCK_WALLS := [
	[-64.0, -43.5, -4.5, Vector3.BACK], [38.0, 55.0, -4.5, Vector3.BACK],
	[-75.0, 54.0, -99.0, Vector3.BACK], [-5.0, 35.0, -19.0, Vector3.BACK],
	[-94.0, -8.0, -77.0, Vector3.RIGHT], [-94.0, -8.0, 77.0, Vector3.LEFT],
	[-83.0, -20.0, -9.0, Vector3.RIGHT], [-83.0, -20.0, -6.0, Vector3.LEFT],
]

## Open ground inside the block: [x0, z0, x1, z1, how many, what]. The
## park's grass worn through to earth, the lot's oil and puddles, the camp's
## litter.
const BLOCK_GROUNDS := [
	[-64.5, -69.5, -30.5, -16.5, 26, "park"], [-49.5, -84.5, -30.5, -70.5, 10, "park"],
	[36.6, -84.0, 55.4, -17.0, 40, "lot"], [56.6, -84.0, 64.8, -9.0, 36, "camp"],
]
## The overpass's pillars (inner.gd), tagged on the faces into the camp.
const PILLARS_Z := [-22.0, -36.0, -50.0, -64.0, -80.0]

func _dress_block() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for g in BLOCK_GROUNDS:
		for i in int(g[4]):
			var p := Vector3(rng.randf_range(g[0], g[2]), 0.0, rng.randf_range(g[1], g[3]))
			match [g[5], i % 4]:
				["park", 0], ["park", 1]:
					# Bare earth where the grass gave up.
					var d := _ground("stain_dark", p, rng.randf_range(2.0, 4.5), rng, 0.55)
					d.modulate = Color(0.55, 0.42, 0.3, 0.55)
				["park", 2], ["lot", 2], ["camp", 2]:
					_ground("litter", p, rng.randf_range(0.8, 1.4), rng, 1.0)
				["lot", 0]:
					_puddles.append(_ground("puddle", p, rng.randf_range(1.2, 2.8), rng, 1.0, true))
				["lot", 1], ["camp", 1]:
					_ground("stain_oil", p, rng.randf_range(1.0, 2.4), rng, 0.8)
				_:
					_ground("stain_dark", p, rng.randf_range(0.8, 1.8), rng, 0.7)
	for z: float in PILLARS_Z:
		for face in [[58.0, Vector3.RIGHT], [63.4, Vector3.LEFT]]:
			if rng.randf() < 0.75:
				var tex: String = TAGS[rng.randi() % TAGS.size()]
				var tw := rng.randf_range(1.0, 1.15)
				_wall_facing(tex, face[1], face[0], z + rng.randf_range(-0.05, 0.05), rng.randf_range(1.2, 1.8), Vector2(tw, tw * (0.4 if tex != "tag_circle_a" else 1.0)), 0.0, 1.0)
	for r in BLOCK_SIDEWALKS:
		var area: float = (r[2] - r[0]) * (r[3] - r[1])
		for i in int(area / 9.0):
			var p := Vector3(rng.randf_range(r[0], r[2]), 0.0, rng.randf_range(r[1], r[3]))
			match i % 4:
				0: _ground("stain_dark", p, rng.randf_range(0.6, 1.3), rng, 0.7)
				1: _ground("stain_coffee", p, rng.randf_range(0.25, 0.5), rng, 0.8)
				2: _ground("crack", p, rng.randf_range(1.0, 2.0), rng, 0.9)
				3: _ground("litter", p, rng.randf_range(0.8, 1.4), rng, 1.0)
	for r in BLOCK_ROADS:
		var area: float = (r[2] - r[0]) * (r[3] - r[1])
		for i in int(area / 40.0):
			var p := Vector3(rng.randf_range(r[0], r[2]), 0.0, rng.randf_range(r[1], r[3]))
			if i % 3 == 0:
				_puddles.append(_ground("puddle", p, rng.randf_range(1.2, 2.6), rng, 1.0, true))
			else:
				_ground("stain_oil", p, rng.randf_range(1.0, 2.2), rng, 0.8)
	for w in BLOCK_WALLS:
		var a: float = w[0]
		while a < w[1]:
			a += rng.randf_range(3.0, 6.5)
			var roll := 0.0
			var tex := "grime_streak"
			var size := Vector2(rng.randf_range(0.6, 1.2), 2.2)
			var y := 1.1
			var pick := rng.randf()
			if pick < 0.35:
				tex = TAGS[rng.randi() % TAGS.size()]
				var tw := rng.randf_range(1.7, 2.5)
				size = Vector2(tw, tw * (0.4 if tex != "tag_circle_a" else 1.0))
				y = rng.randf_range(0.7, 1.4)
			elif pick < 0.55:
				tex = FLYERS[rng.randi() % FLYERS.size()]
				size = Vector2(0.34, 0.45)
				y = rng.randf_range(1.2, 1.6)
				roll = rng.randf_range(-8, 8)
			_wall_facing(tex, w[3], w[2], a, y, size, roll, 0.8 if tex == "grime_streak" else 1.0)

## A wall decal on a wall along its side's line, facing `normal`; `at` is
## the position along the wall (x for walls facing north or south, z else).
func _wall_facing(tex: String, normal: Vector3, line: float, at: float, y: float, size: Vector2, roll_deg: float, alpha: float) -> void:
	var d := _decal(tex)
	d.size = Vector3(size.x, WALL_DEPTH, size.y)
	# Project into the wall: local -Y along -normal, the texture's top up.
	var down := Vector3.DOWN.rotated(normal, deg_to_rad(roll_deg))
	d.basis = Basis(normal.cross(down), normal, down)
	var on_wall := Vector3(at, y, line) if absf(normal.z) > 0.5 else Vector3(line, y, at)
	d.position = on_wall - normal * (WALL_DEPTH / 2.0 - 0.05)
	d.modulate.a = alpha

## Wall decals project straight back into the shop fronts.
func _wall(tex: String, pos: Vector3, size: Vector2, roll_deg := 0.0, alpha := 1.0) -> Decal:
	var d := _decal(tex)
	d.size = Vector3(size.x, WALL_DEPTH, size.y)
	d.rotation_degrees = Vector3(90.0, 0.0, roll_deg)
	d.position = pos
	d.modulate.a = alpha
	return d

func _ground(tex: String, pos: Vector3, size: float, rng: RandomNumberGenerator, alpha := 1.0, glossy := false) -> Decal:
	var d := _decal(tex)
	d.size = Vector3(size, 0.3, size * rng.randf_range(0.6, 1.0))
	d.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	d.position = pos
	d.modulate.a = alpha
	if glossy:
		d.texture_orm = load(DIR + tex + "_orm.png")
	return d

func _decal(tex: String) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load(DIR + tex + ".png")
	d.albedo_mix = 1.0
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.distance_fade_enabled = false
	add_child(d)
	return d

## Dry, the puddles are dull damp patches; in the rain they spread and
## shine.
func _on_weather(raining: bool) -> void:
	for p in _puddles:
		p.modulate.a = 1.0 if raining else 0.35
