extends RefCounted
## The goods on the corner shop's shelves: the room's stock boxes are plain coloured cubes in the scene, so
## each gets one of the shop's products' packaging instead (assets/items/labels/<name>_box.png, drawn by
## dev-tools/gen_product_labels.py -- invented brands). Nothing else about them changes.

const DIR := "res://assets/items/labels/"
const CONVENIENCE := ["northstar", "crunchies", "fizz", "peak", "volt", "minty", "noodle", "cocoa", "dairy", "oats"]
static var _mats := {}

## The ten box labels start loading on a thread, so that dressing the shelves (a frame of the room's build) finds them in
## and doesn't read ten PNGs off the disk in one frame (~20 ms cold).
static func warm() -> void:
	for name in CONVENIENCE:
		var path: String = DIR + name + "_box.png"
		if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)

static func _material(name: String) -> StandardMaterial3D:
	if not _mats.has(name):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DIR + name + "_box.png")
		m.roughness = 0.6
		_mats[name] = m
	return _mats[name]

## Packages every Stock* mesh under the store's Fixture* nodes, a product per shelf row so a shelf reads as
## a row of one thing. `rng` makes the pick repeatable for the tests.
static func apply(store: Node, rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var done := 0
	for fixture in store.get_children():
		if not String(fixture.name).begins_with("Fixture"):
			continue
		var rows := {}
		for stock in fixture.get_children():
			if not (stock is MeshInstance3D) or not String(stock.name).begins_with("Stock"):
				continue
			var row := String(stock.name).get_slice("_", 0)
			if not rows.has(row):
				rows[row] = CONVENIENCE[rng.randi() % CONVENIENCE.size()]
			(stock as MeshInstance3D).material_override = _material(rows[row])
			done += 1
	return done
