extends RefCounted
## What a gun sounds like, read from its WeaponData: the recorded set in assets/sfx/guns/<sound_set>/
## (fire_N, fire_up_N, distant_N, tail_indoor, tail_outdoor, mech_N, dry), the reload and handling
## foley (WeaponData.foley), and where the player is (a room's tail or the street's).
##
## Everything is loaded once and kept: a shot only picks from arrays, it allocates nothing.

const WD := preload("res://weapons/WeaponData.gd")
const DIR := "res://assets/sfx/guns/"

## Tests: -1 decides from the scene, 0 forces the street's tail, 1 a room's.
static var force_indoors := -1
static var _sets := {}
static var _files := {}

## What a set must hold for a gun with recordings.
const REQUIRED := ["fire", "fire_up", "distant", "tail_indoor", "tail_outdoor", "mech", "dry"]
## The ids of the files of a set: the key, how many variants (0: a single file).
const LAYOUT := {
	"fire": ["fire_", 3], "fire_up": ["fire_up_", 3], "distant": ["distant_", 2], "mech": ["mech_", 2],
	"tail_indoor": ["tail_indoor", 0], "tail_outdoor": ["tail_outdoor", 0], "dry": ["dry", 0],
}

## One sound file under assets/sfx/guns/ by stem ("common/slide_rack", "mag_out"), kept; null if there is none.
static func file(stem: String) -> AudioStream:
	if not _files.has(stem):
		var path := DIR + stem + ".wav"
		_files[stem] = load(path) if ResourceLoader.exists(path) else null
	return _files[stem]

## The recordings of `d`'s sound set: {fire: [AudioStream], fire_up, distant, mech, tail_indoor, tail_outdoor, dry, real: bool}.
## A gun with no set (the wonder weapon) gets its synthesised shots, so every gun has something to say.
static func set_of(d: WD) -> Dictionary:
	var key := d.sound_set if d.sound_set != "" else "~" + d.handling_family()
	if _sets.has(key):
		return _sets[key]
	var out := {"fire": [], "fire_up": [], "distant": [], "mech": [], "tail_indoor": null, "tail_outdoor": null, "dry": null, "real": d.sound_set != ""}
	if d.sound_set != "":
		for k in LAYOUT:
			var lay: Array = LAYOUT[k]
			if int(lay[1]) == 0:
				out[k] = file("%s/%s" % [d.sound_set, lay[0]])
			else:
				for i in range(1, int(lay[1]) + 1):
					var s := file("%s/%s%d" % [d.sound_set, lay[0], i])
					if s != null:
						(out[k] as Array).append(s)
	else:
		var fam := d.handling_family()
		for v in ["a", "b"]:
			var s := file("fire_%s_%s" % [fam, v])
			if s != null:
				(out["fire"] as Array).append(s)
		out["fire_up"] = out["fire"]
		out["distant"] = out["fire"]
	if out["dry"] == null:
		out["dry"] = file("dry_click")
	_sets[key] = out
	return out

## The names of what is missing from the recorded set of `d` (empty: complete).
static func missing(d: WD) -> PackedStringArray:
	var gone := PackedStringArray()
	var s := set_of(d)
	for k in REQUIRED:
		var v = s[k]
		if v == null or (v is Array and (v as Array).is_empty()):
			gone.append(k)
	return gone

## A shot of `d` (the upgraded gun's own, with its ringing top), a different one each call.
static func shot(d: WD, n: int) -> AudioStream:
	var s := set_of(d)
	var pool: Array = s["fire_up"] if d.upgraded and not (s["fire_up"] as Array).is_empty() else s["fire"]
	return pool[n % pool.size()] if not pool.is_empty() else null

## The shot as heard from far away.
static func distant(d: WD, n: int) -> AudioStream:
	var pool: Array = set_of(d)["distant"]
	return pool[n % pool.size()] if not pool.is_empty() else null

static func tail(d: WD, indoors: bool) -> AudioStream:
	return set_of(d)["tail_indoor" if indoors else "tail_outdoor"]

static func mech(d: WD, n: int) -> AudioStream:
	var pool: Array = set_of(d)["mech"]
	return pool[n % pool.size()] if not pool.is_empty() else null

static func dry(d: WD) -> AudioStream:
	return set_of(d)["dry"]

## The sound of a handling cue ("mag_out", "pump") for `d`: the gun's own file (the nth of several), or the
## synthesised assets/sfx/guns/<cue>.wav.
static func foley(d: WD, cue: String, n := 0) -> AudioStream:
	if d != null and d.foley.has(cue):
		var stems: Array = d.foley[cue]
		if not stems.is_empty():
			var s := file(String(stems[n % stems.size()]))
			if s != null:
				return s
	return file(cue)

## Loads everything of a gun now (the title's warm-up and a swap call this, so the first shot does not).
static func warm(d: WD) -> void:
	if d == null:
		return
	set_of(d)
	for cue in d.foley:
		for stem in d.foley[cue]:
			file(String(stem))

## Whether the shot is heard in a room (the room's tail) or on the street: in a walk-in shop on the street's
## scene, or in any room scene; the street, the block and the backyard are outdoors.
static func indoors(node: Node) -> bool:
	if force_indoors >= 0:
		return force_indoors == 1
	var tree0 := Engine.get_main_loop() as SceneTree
	var gs: Node = tree0.root.get_node_or_null("GameState") if tree0 != null else null
	if gs != null and String(gs.get("indoors")) != "":
		return true
	var tree := node.get_tree() if node != null else null
	var scene := tree.current_scene if tree != null else null
	if scene == null or not (scene is Node3D):
		return false
	var n := String(scene.name)
	return n.ends_with("3D") and n != "City3D" and n != "Backyard3D"
