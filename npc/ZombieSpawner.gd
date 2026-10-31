extends Node
## Deals each round's dead onto the block. On ZombieMode.round_started(r) it
## owes ZombieMode.zombies_in_round(r) zombies, lets them out one at a time
## from spawn points the player can't see, never more than ZombieMode.MAX_ALIVE
## on the block at once (the rest wait in reserve), and when the last is down
## and none are left it ends the round after a breath.
##
## Runners are mixed in from round 6: a tenth of the round's dead then, a tenth
## more each round, all of them from round 15.
##
## It also keeps the corpses: no more than CORPSE_LIMIT lie about (the oldest
## are removed first), and counts each kill for the run's stats (points are
## the weapon's: Zombie3D.died says which part and whether it was melee).

signal spawned(zombie: Node)
signal round_cleared(r: int)
## A stuck one was put back on a spawn point.
signal relocated(zombie: Node)

const ZombieScript := preload("res://npc/Zombie3D.gd")
const CORPSE_LIMIT := 12
## Seconds before the first of a round, between two, and the quiet after the
## last one dies.
const FIRST_DELAY := 2.5
const GAP_BASE := 1.8
const GAP_PER_ROUND := 0.08
const GAP_MIN := 0.35
const ROUND_BREAK := 5.0
## A spawn point has to be this far from the player and out of their view.
const MIN_SPAWN_DISTANCE := 22.0

## Scales every wait (tests run it near zero).
var time_scale := 1.0
## Where the dead come from: world positions on the navmesh.
var spawn_points: Array[Vector3] = []
## Where they go into the world.
var holder: Node3D
var round_no := 0
## How many the round owes, how many are out so far, and their kinds.
var total := 0
var released := 0
var _kinds: Array[String] = []
var _timer := 0.0
var _break := -1.0
var _corpses: Array[Node] = []
var _rng := RandomNumberGenerator.new()
## Highest count of the dead alive at once this round (the tests read it).
var peak_alive := 0
## What has been let out, by kind, this round.
var kind_counts := {"walker": 0, "runner": 0}
var enabled := true
## What the last spawn cost (building the zombie and adding it to the tree), and
## the worst so far: the hitch a spawn adds to its frame (the tests and the
## perf probe read these).
var last_spawn_usec := 0
var worst_spawn_usec := 0

func _ready() -> void:
	name = "ZombieSpawner"
	_rng.randomize()
	add_to_group("zombie_spawner")
	ZombieMode.round_started.connect(_on_round_started)
	if holder == null:
		holder = get_parent() as Node3D

## How many of the dead are alive on the block.
func alive() -> int:
	return get_tree().get_nodes_in_group("zombies").size()

## How many are still waiting to come out this round.
func reserve() -> int:
	return maxi(total - released, 0)

func _on_round_started(r: int) -> void:
	round_no = r
	total = ZombieMode.zombies_in_round(r)
	released = 0
	peak_alive = 0
	kind_counts = {"walker": 0, "runner": 0}
	_break = -1.0
	_timer = FIRST_DELAY * time_scale
	_kinds = _plan_kinds(r, total)

## A shuffled list of the round's kinds: round(total * runner share) runners.
func _plan_kinds(r: int, n: int) -> Array[String]:
	var out: Array[String] = []
	var share := clampf((r - 5) / 10.0, 0.0, 1.0)
	var runners := int(ceil(n * share - 0.0001)) if r >= 6 else 0
	for i in n:
		out.append("runner" if i < runners else "walker")
	# Fisher-Yates with our own rng.
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out

func _process(delta: float) -> void:
	if not enabled or not ZombieMode.active or ZombieMode.over or round_no == 0:
		return
	if released < total:
		_timer -= delta
		if _timer <= 0.0 and alive() < ZombieMode.MAX_ALIVE:
			_release()
			_timer = _gap() * time_scale
	elif alive() == 0:
		if _break < 0.0:
			_break = ROUND_BREAK * time_scale
		else:
			_break -= delta
			if _break <= 0.0:
				_break = -1.0
				var done := round_no
				round_cleared.emit(done)
				ZombieMode.advance_round()

func _gap() -> float:
	return maxf(GAP_BASE - round_no * GAP_PER_ROUND, GAP_MIN) * _rng.randf_range(0.7, 1.3)

func _release() -> void:
	var z := spawn_one(_kinds[released])
	released += 1
	if z:
		kind_counts[z.get("kind")] += 1

## One zombie of `kind` at a fresh spawn point, now. (The round's budget is
## `released`; tests and the horde probe call this directly.)
func spawn_one(kind: String, at := Vector3.INF, body := "") -> CharacterBody3D:
	if holder == null:
		return null
	var t0 := Time.get_ticks_usec()
	var z = ZombieScript.new()
	z.configure(kind, maxi(round_no, 1), _rng)
	if body != "":
		z.set_meta("body", body)
	z.position = at if at != Vector3.INF else _pick_point()
	z.died.connect(_on_died)
	holder.add_child(z)
	z.reset_physics_interpolation()
	last_spawn_usec = Time.get_ticks_usec() - t0
	worst_spawn_usec = maxi(worst_spawn_usec, last_spawn_usec)
	peak_alive = maxi(peak_alive, alive())
	spawned.emit(z)
	return z

## A spawn point away from the player and out of their view; failing that,
## the farthest one.
func _pick_point(strict := false) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.INF if strict else holder.global_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var good: Array[Vector3] = []
	var farthest := spawn_points[0]
	var far_d := -1.0
	for p in spawn_points:
		var d := p.distance_to(player.global_position) if player else 999.0
		if d > far_d:
			far_d = d
			farthest = p
		if d < MIN_SPAWN_DISTANCE:
			continue
		if cam and not cam.is_position_behind(p) and cam.is_position_in_frustum(p + Vector3.UP):
			continue
		good.append(p)
	if good.is_empty():
		# (strict: nowhere that doesn't pop in front of the player)
		return Vector3.INF if strict else farthest
	return good[_rng.randi() % good.size()]

## Puts a stuck zombie back on a spawn point out of the player's sight.
## False if there is none right now (it asks again later).
func relocate(z: Node3D) -> bool:
	var p := _pick_point(true)
	if p == Vector3.INF:
		return false
	var map := z.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var snapped := NavigationServer3D.map_get_closest_point(map, p)
		if snapped.distance_to(p) < 3.0:
			p = Vector3(snapped.x, p.y, snapped.z)
	z.global_position = p
	z.reset_physics_interpolation()
	if z.has_method("relocated"):
		z.relocated()
	relocated.emit(z)
	return true

func _on_died(zombie: Node, part: String, _melee: bool) -> void:
	ZombieMode.record_kill(part == "head")
	_corpses.append(zombie)
	while _corpses.size() > CORPSE_LIMIT:
		var old = _corpses.pop_front()
		if is_instance_valid(old):
			old.remove_corpse()
	_corpses = _corpses.filter(func(c): return is_instance_valid(c))

## How many corpses lie about.
func corpse_count() -> int:
	_corpses = _corpses.filter(func(c): return is_instance_valid(c) and not c.is_queued_for_deletion())
	return _corpses.size()
