extends RefCounted
## Cover for the crews, found in the block itself (Ghetto Wars): parked cars and wrecks, the buildings' walls and
## corners, dumpsters, anything solid in the world's physics that is waist high or taller, standing next to a
## spot on the navmesh. Nothing is hand-placed: build() walks a grid over the block, snaps each cell to the navmesh,
## and looks round it with short rays at knee, waist and head height.
##
## A cover point is {pos, dir (unit, from the spot towards the thing it hides behind), high (true: the thing
## stops a standing man's head, false: waist high, you crouch behind it and stand up to shoot), kind}.
## `hides(point, threat)` is the test that matters: does the thing stand between the spot and `threat`?

const WORLD_MASK := 1
const GRID := 2.5
## Rays round a spot, and how far they look for the thing it is hiding behind.
const RAYS := 8
const REACH := 1.1
const LOW_Y := 0.55
const MID_Y := 1.0
const HIGH_Y := 1.75
## A spot is dropped if another is nearer than this (so a long wall is not a hundred points).
const MIN_SEPARATION := 2.2
## How near the navmesh a candidate must be (m).
const NAV_SNAP := 0.6

var points: Array[Dictionary] = []
var bounds := Rect2(-76.0, -96.0, 152.0, 104.0)
## For tests: how long the last build took (ms), how many rays it cast.
var build_ms := 0
var rays := 0
## Spots that are claimed by a gangster right now (index -> instance id).
var claimed := {}

## Walks the grid. `world` is the 3D world the rays go into; `map` the navigation map.
func build(world: World3D, map: RID, rect := Rect2()) -> int:
	var t0 := Time.get_ticks_msec()
	points.clear()
	claimed.clear()
	rays = 0
	var area := rect if rect.size.x > 0.0 else bounds
	var space := world.direct_space_state
	var x := area.position.x
	var taken: Array[Vector3] = []
	var have_nav := NavigationServer3D.map_get_iteration_id(map) > 0
	while x <= area.end.x:
		var z := area.position.y
		while z <= area.end.y:
			var p := Vector3(x, 0.0, z)
			if have_nav:
				var snapped := NavigationServer3D.map_get_closest_point(map, p)
				if Vector2(snapped.x - p.x, snapped.z - p.z).length() > GRID * 0.7:
					z += GRID
					continue
				p = Vector3(snapped.x, 0.0, snapped.z)
			var pt := _probe(space, p)
			if not pt.is_empty():
				var near := false
				for q in taken:
					if q.distance_squared_to(p) < MIN_SEPARATION * MIN_SEPARATION:
						near = true
						break
				if not near:
					taken.append(p)
					pt["pos"] = p
					points.append(pt)
			z += GRID
		x += GRID
	build_ms = Time.get_ticks_msec() - t0
	return points.size()

## Looks round `p` for something to hide behind: the best (tallest, nearest) direction wins.
func _probe(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	var best := {}
	var best_score := -1.0
	for i in RAYS:
		var a := TAU * float(i) / float(RAYS)
		var d := Vector3(sin(a), 0.0, cos(a))
		var mid := _cast(space, p + Vector3(0, MID_Y, 0), d)
		if mid.is_empty():
			continue
		var low := _cast(space, p + Vector3(0, LOW_Y, 0), d)
		if low.is_empty():
			continue
		var high := not _cast(space, p + Vector3(0, HIGH_Y, 0), d).is_empty()
		# A thin thing (a lamp post, a sign) is not cover: needs width, so the neighbours along it hit too.
		var side := Vector3(d.z, 0.0, -d.x) * 0.5
		var wide := not _cast(space, p + side + Vector3(0, MID_Y, 0), d).is_empty() and not _cast(space, p - side + Vector3(0, MID_Y, 0), d).is_empty()
		if not wide:
			continue
		var dist: float = mid.distance
		var score := (2.0 if high else 1.0) - dist * 0.5
		if score > best_score:
			best_score = score
			var kind := "wall" if high else "car"
			if not high and low.has("collider") and String(low.collider.name).to_lower().contains("dumpster"):
				kind = "dumpster"
			best = {"dir": d, "high": high, "kind": kind, "normal": mid.normal, "dist": dist}
	return best

func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> Dictionary:
	rays += 1
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH)
	q.collision_mask = WORLD_MASK
	var r := space.intersect_ray(q)
	if r.is_empty():
		return {}
	return {"distance": from.distance_to(r.position), "normal": r.normal, "collider": r.collider}

# --- Queries ------------------------------------------------------------------------

## Whether the thing the spot hides behind stands between it and `threat` (a point in the world): the
## threat is on the far side, within ~65 degrees of the hide direction.
static func hides(point: Dictionary, threat: Vector3) -> bool:
	var pos: Vector3 = point["pos"]
	var to := Vector3(threat.x - pos.x, 0.0, threat.z - pos.z)
	if to.length() < 1.0:
		return false
	return to.normalized().dot(point["dir"]) > 0.42

## The spot's place to shoot from: `crouch` behind low cover stands up in place; behind high cover you lean out
## to whichever side is open, as far as `lean` metres. Returns the spot itself if there is no side.
static func fire_pos(point: Dictionary, lean := 0.85) -> Vector3:
	var pos: Vector3 = point["pos"]
	if not point["high"]:
		return pos
	var d: Vector3 = point["dir"]
	var side := Vector3(-d.z, 0.0, d.x)
	return pos + side * lean * float(point.get("lean_side", 1.0))

## Spots within `radius` of `around`, free, that hide from `threat`, nearest to `from` first.
func candidates(around: Vector3, radius: float, threat: Vector3, from: Vector3, limit := 6, min_threat := 4.0) -> Array[int]:
	var scored: Array = []
	var r2 := radius * radius
	for i in points.size():
		var p: Dictionary = points[i]
		var pos: Vector3 = p["pos"]
		if Vector2(pos.x - around.x, pos.z - around.z).length_squared() > r2:
			continue
		if claimed.has(i):
			continue
		if Vector2(pos.x - threat.x, pos.z - threat.z).length() < min_threat:
			continue
		if not hides(p, threat):
			continue
		scored.append([i, pos.distance_squared_to(from)])
	scored.sort_custom(func(a, b): return a[1] < b[1])
	var out: Array[int] = []
	for s in scored:
		out.append(s[0])
		if out.size() >= limit:
			break
	return out

func claim(i: int, who: int) -> void:
	claimed[i] = who

func release(who: int) -> void:
	for k in claimed.keys():
		if claimed[k] == who:
			claimed.erase(k)

func is_free(i: int) -> bool:
	return not claimed.has(i)
