extends RefCounted
## Where the dead come in from, COD style, all round the player: climbing up out of the ground
## (a manhole or a burst in the street), dropping from a fire escape or a rooftop, smashing out of
## a shop front, or just rounding a corner out of sight. Built once from the block (its manholes,
## fire escapes and shop shutters are found in the scene), picked from at every spawn.
##
## An entrance is a Dictionary:
##   type   RISE (up out of the ground), DROP (falls in), SMASH (through a shop front), PLAIN (walks in)
##   pos    where it ends up standing, a point on the navmesh
##   start  where it begins (under the ground, up on the fire escape, at the shop front)
##   out    the way it faces / goes (away from the wall)
##   fall   DROP: seconds in the air
##   node   RISE: the manhole it comes out of, if there is one
##   roof   DROP: true when it comes off a rooftop
## The ones that show themselves (RISE, DROP, SMASH) may be in view from MIN_SHOW metres on: that
## is the spectacle. A PLAIN one never is, and stays MIN_HIDDEN away.
## Every pick leans to the part of the compass round the player that has had the fewest lately,
## so the dead arrive from all directions and not down one street.

const RISE := "rise"
const DROP := "drop"
const SMASH := "smash"
const PLAIN := "plain"

const MIN_SHOW := 8.0
const MAX_SHOW := 58.0
const MIN_HIDDEN := 20.0
const MAX_HIDDEN := 75.0
## The compass is cut into this many sectors round the player, relative to where they look.
const SECTORS := 8
const MEMORY := 14
## Gravity for a fall (m/s^2) and how far the platform of a fire escape is above the street.
const GRAVITY := 14.0
const ESCAPE_MIN_Y := 3.6
const ESCAPE_MAX_Y := 8.0
## A building must reach this high for a rooftop drop.
const ROOF_MIN := 7.5
const ROOF_MAX := 16.0
## The block's extent for random ground: |x| <= BOUNDS.x, BOUNDS.z <= z <= BOUNDS.y.
## The navmesh over the street sits this high (it also has levels on roofs and platforms).
const GROUND_Y := 0.3
const BOUNDS := Vector3(74.0, 4.0, -96.0)
## Landing spots must be on the navmesh within this much of where the site wants them.
const SNAP := 2.5

## Default odds of each kind per pick.
const WEIGHTS := {"rise": 0.34, "drop": 0.22, "smash": 0.2, "plain": 0.24}
## The surge: mostly out of the ground and off the buildings.
const SURGE_WEIGHTS := {"rise": 0.42, "drop": 0.28, "smash": 0.22, "plain": 0.08}

var map: RID
var world: World3D
var manholes: Array[Node3D] = []
## [{pos: Vector3 (the facade point), out: Vector3}]
var escapes: Array = []
var shops: Array = []
## Hidden-spawn points that were authored (ZombieBlock.SPAWN_POINTS).
var fixed_plain: Array[Vector3] = []
var rng := RandomNumberGenerator.new()
var _recent: Array[int] = []
## Counts per type picked, for the tests.
var picked := {"rise": 0, "drop": 0, "smash": 0, "plain": 0}

func _init() -> void:
	rng.randomize()

## Finds the block's manholes, fire escapes and shop fronts.
func build(city: Node3D, plain_points: Array = []) -> void:
	map = city.get_world_3d().navigation_map
	world = city.get_world_3d()
	manholes.clear()
	escapes.clear()
	shops.clear()
	for n in city.find_children("*anhole*", "Node3D", true, false):
		# (a manhole's placeholder and its mesh both match: one entry per spot)
		var at := Vector2(n.global_position.x, n.global_position.z)
		if manholes.all(func(m): return Vector2(m.global_position.x, m.global_position.z).distance_to(at) > 1.0):
			manholes.append(n as Node3D)
	for n in city.find_children("FireEscape*", "Node3D", true, false):
		var fe := n as Node3D
		var out := _out_of(fe)
		escapes.append({"pos": fe.global_position, "out": out})
	for n in city.find_children("*Shutter", "Node3D", true, false):
		var sh := n as Node3D
		shops.append({"pos": sh.global_position, "out": _out_of(sh)})
	fixed_plain.clear()
	for p in plain_points:
		fixed_plain.append(p)

## The way a facade's piece faces: its +Z turned by its yaw.
static func _out_of(n: Node3D) -> Vector3:
	var yaw := n.global_rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))

## The nearest navmesh point to `p` (on the ground), or Vector3.INF when it is farther than SNAP.
func snap(p: Vector3) -> Vector3:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return Vector3.INF
	var q := NavigationServer3D.map_get_closest_point(map, Vector3(p.x, 0.0, p.z))
	if Vector2(q.x - p.x, q.z - p.z).length() > SNAP or not is_clear(q):
		return Vector3.INF
	return Vector3(q.x, 0.0, q.z)

## Whether nothing solid stands at this spot (the navmesh and the buildings' solids overlap in
## a few places; a zombie put inside one sinks through the street).
func is_clear(p: Vector3) -> bool:
	if world == null:
		return true
	var space := world.direct_space_state
	for h in [0.4, 1.0, 1.6]:
		var q := PhysicsPointQueryParameters3D.new()
		q.position = Vector3(p.x, h, p.z)
		q.collision_mask = 1
		if not space.intersect_point(q, 1).is_empty():
			return false
	return true

## Whether a point on the ground is on the navmesh (closer than `tol`).
func on_navmesh(p: Vector3, tol := 0.35) -> bool:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return false
	var q := NavigationServer3D.map_get_closest_point(map, Vector3(p.x, 0.0, p.z))
	return Vector2(q.x - p.x, q.z - p.z).length() <= tol

# --- Picking ------------------------------------------------------------------------------------

## One entrance for the dead to use now. `cam` is the player's camera (for what is in sight),
## `weights` the odds by kind. Never an empty Dictionary: failing everything it falls back to
## the farthest hidden point there is.
func pick(player: Vector3, cam: Camera3D, weights: Dictionary = WEIGHTS) -> Dictionary:
	var order := _kind_order(weights)
	for kind in order:
		var options := _candidates(kind, player, cam)
		if options.is_empty():
			continue
		var best := _least_used(options, player, cam)
		_remember(best, player, cam)
		picked[best["type"]] += 1
		return best
	var far := fixed_plain[0] if not fixed_plain.is_empty() else player
	var e := {"type": PLAIN, "pos": far, "start": far, "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false}
	picked[PLAIN] += 1
	return e

## The kinds in the order to try: the first by a weighted draw, the rest by weight.
func _kind_order(weights: Dictionary) -> Array:
	var kinds: Array = weights.keys()
	var out: Array = []
	var pool := kinds.duplicate()
	while not pool.is_empty():
		var total := 0.0
		for k in pool:
			total += float(weights[k])
		var r := rng.randf() * total
		var chosen = pool[0]
		for k in pool:
			r -= float(weights[k])
			if r <= 0.0:
				chosen = k
				break
		out.append(chosen)
		pool.erase(chosen)
	return out

func _candidates(kind: String, player: Vector3, cam: Camera3D) -> Array:
	var out: Array = []
	match kind:
		RISE:
			for m in manholes:
				var p := Vector3(m.global_position.x, 0.0, m.global_position.z)
				if _in_show_ring(p, player) and on_navmesh(p, 1.2) and is_clear(p):
					# A real manhole is worth three of the street's bursts.
					for k in 3:
						out.append(_rise(p, m))
			for i in 8:
				var p := _random_ground()
				if p != Vector3.INF and _in_show_ring(p, player) and is_clear(p):
					out.append(_rise(p, null))
		DROP:
			for e in escapes:
				var landing := snap(e["pos"] + e["out"] * 2.6)
				if landing == Vector3.INF or not _in_show_ring(landing, player):
					continue
				out.append(_drop(e, landing))
		SMASH:
			for s in shops:
				var landing := snap(s["pos"] + s["out"] * 2.4)
				if landing == Vector3.INF or not _in_show_ring(landing, player):
					continue
				out.append({"type": SMASH, "pos": landing, "start": Vector3(s["pos"].x, 0.0, s["pos"].z) + s["out"] * 0.45,
					"out": s["out"], "fall": 0.0, "node": null, "roof": false, "facade": Vector3(s["pos"].x, 0.0, s["pos"].z)})
		PLAIN:
			for p in fixed_plain:
				if _hidden(p, player, cam) and is_clear(p):
					out.append(_plain(p))
			for i in 10:
				var p := _random_ground()
				if p != Vector3.INF and _hidden(p, player, cam) and is_clear(p):
					out.append(_plain(p))
	return out

func _plain(p: Vector3) -> Dictionary:
	return {"type": PLAIN, "pos": p, "start": p, "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false}

func _rise(p: Vector3, node: Node3D) -> Dictionary:
	return {"type": RISE, "pos": p, "start": p + Vector3(0, -2.1, 0), "out": Vector3.FORWARD, "fall": 0.0, "node": node, "roof": false}

## A fall off a fire escape, or off the roof above it when the building is tall enough.
func _drop(e: Dictionary, landing: Vector3) -> Dictionary:
	var fe: Vector3 = e["pos"]
	var out: Vector3 = e["out"]
	var wall := fe - out * 1.2
	var roof_y := _roof_height(Vector3(wall.x, 0.0, wall.z))
	var roof := roof_y >= ROOF_MIN and rng.randf() < 0.45
	var y := clampf(fe.y, ESCAPE_MIN_Y, ESCAPE_MAX_Y)
	var away := 0.5
	if roof:
		y = minf(roof_y + 0.1, ROOF_MAX)
		away = 0.7
	var start := Vector3(fe.x, 0.0, fe.z) + out * away
	start.y = y
	var fall := sqrt(2.0 * y / GRAVITY)
	return {"type": DROP, "pos": landing, "start": start, "out": out, "fall": fall, "node": null, "roof": roof}

## The height of whatever the world has at this spot (a roof), by a ray down from high up.
func _roof_height(at: Vector3) -> float:
	if world == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 40.0, at.z), Vector3(at.x, 0.5, at.z))
	q.collision_mask = 1
	var r := world.direct_space_state.intersect_ray(q)
	return float(r["position"].y) if not r.is_empty() else 0.0

func _random_ground() -> Vector3:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return Vector3.INF
	var p := NavigationServer3D.map_get_random_point(map, 1, true)
	# Only the flat ground inside the block (the street, the lots, the park): not a platform or the
	# navmesh's rim.
	if absf(p.y - GROUND_Y) > 0.15 or absf(p.x) > BOUNDS.x or p.z > BOUNDS.y or p.z < BOUNDS.z:
		return Vector3.INF
	return Vector3(p.x, 0.0, p.z)

func _in_show_ring(p: Vector3, player: Vector3) -> bool:
	var d := Vector2(p.x - player.x, p.z - player.z).length()
	return d >= MIN_SHOW and d <= MAX_SHOW

## Out of the player's sight, far enough off: behind them, outside the frustum, or behind a wall.
func _hidden(p: Vector3, player: Vector3, cam: Camera3D) -> bool:
	var d := Vector2(p.x - player.x, p.z - player.z).length()
	if d < MIN_HIDDEN or d > MAX_HIDDEN:
		return false
	var head := p + Vector3.UP * 1.0
	if cam == null or not cam.is_inside_tree():
		return true
	if cam.is_position_behind(head) or not cam.is_position_in_frustum(head):
		return true
	if world != null:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
		q.collision_mask = 1
		return not world.direct_space_state.intersect_ray(q).is_empty()
	return false

# --- Compass ---------------------------------------------------------------------------------

## Which eighth of the compass round the player `p` is in, counted from where they look.
func sector_of(p: Vector3, player: Vector3, cam: Camera3D) -> int:
	var fwd := Vector2(0, -1)
	if cam != null and cam.is_inside_tree():
		var f := -cam.global_transform.basis.z
		var f2 := Vector2(f.x, f.z)
		if f2.length() > 0.01:
			fwd = f2.normalized()
	var to := Vector2(p.x - player.x, p.z - player.z)
	if to.length() < 0.01:
		return 0
	var ang := fwd.angle_to(to.normalized())
	return int(floor(fposmod(ang + PI / SECTORS, TAU) / (TAU / SECTORS))) % SECTORS

func _least_used(options: Array, player: Vector3, cam: Camera3D) -> Dictionary:
	var counts: Array[int] = []
	counts.resize(SECTORS)
	counts.fill(0)
	for s in _recent:
		counts[s] += 1
	var best_n := 9999
	var pool: Array = []
	for o in options:
		var n := counts[sector_of(o["pos"], player, cam)]
		if n < best_n:
			best_n = n
			pool = [o]
		elif n == best_n:
			pool.append(o)
	return pool[rng.randi() % pool.size()]

func _remember(e: Dictionary, player: Vector3, cam: Camera3D) -> void:
	_recent.append(sector_of(e["pos"], player, cam))
	while _recent.size() > MEMORY:
		_recent.pop_front()
