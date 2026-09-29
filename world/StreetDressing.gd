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
	GameState.weather_changed.connect(_on_weather)
	_on_weather(GameState.raining)

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
