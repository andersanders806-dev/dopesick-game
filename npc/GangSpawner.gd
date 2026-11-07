extends "res://npc/ZombieSpawner.gd"
## Deals each wave of Ghetto Wars onto the block. On round_started(r) it owes ZombieMode.gangsters_in_wave(r)
## crewmen (the round machinery is the zombies': FIRST_DELAY, the break between rounds, the corpse limit), lets
## them out in pairs at spawn points out of the player's sight (never more than 12 alive: they think and shoot),
## and ends the wave when the last is down. Every fifth wave opens with a heavy in plates.
##
## The pairs are squads: one holds, one flanks (npc/Gangster3D.gd: role, buddy). `spawn_wave(def)` is the
## hook the story and set-dressing layers call to put a crowd on the street right now.

const GangsterScript := preload("res://npc/Gangster3D.gd")
const PAIR_GAP := 2.6
const PAIR_GAP_MIN := 1.2
const LastStandScript := preload("res://npc/LastStand.gd")

## Spawned by spawn_wave() or by the pairs, for the tests.
var squads := 0
var bosses := 0
var gun_counts := {}
var crew_name := "Dock Boys"

func _ready() -> void:
	super._ready()
	name = "GangSpawner"
	add_to_group("gang_spawner")
	ZombieMode.max_alive = ZombieMode.GANG_MAX_ALIVE
	adaptive = false
	var ls := LastStandScript.new()
	ls.spawner = self
	add_child(ls)

func alive() -> int:
	return get_tree().get_nodes_in_group("gangsters").size()

func _on_round_started(r: int) -> void:
	round_no = r
	total = ZombieMode.gangsters_in_wave(r)
	released = 0
	peak_alive = 0
	kind_counts = {"grunt": 0, "vest": 0, "heavy": 0}
	_break = -1.0
	_timer = FIRST_DELAY * time_scale
	_kinds = _plan_gang_kinds(r, total)
	ZombieMode.max_alive = ZombieMode.GANG_MAX_ALIVE

func _plan_gang_kinds(r: int, n: int) -> Array[String]:
	var out: Array[String] = []
	var vests := 0 if r < 4 else int(round(n * clampf(0.15 + (r - 4) * 0.05, 0.0, 0.4)))
	for i in n:
		out.append("vest" if i < vests else "grunt")
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	if ZombieMode.is_boss_wave(r):
		out[0] = "heavy"
	return out

func _process(delta: float) -> void:
	if not enabled or not ZombieMode.active or ZombieMode.over or round_no == 0:
		return
	if released < total:
		_timer -= delta
		var room := ZombieMode.max_alive - alive()
		if _timer <= 0.0 and room >= 1:
			var n := 1
			if room >= 2 and total - released >= 2 and _kinds[released] != "heavy":
				n = 2
			_release_squad(n)
			_timer = maxf(PAIR_GAP - round_no * 0.12, PAIR_GAP_MIN) * time_scale * _rng.randf_range(0.8, 1.25)
	elif alive() <= LAST_HURRY and alive() > 0:
		for g in get_tree().get_nodes_in_group("gangsters"):
			if is_instance_valid(g) and g.has_method("rush"):
				g.rush()
	if released >= total and alive() == 0:
		if _break < 0.0:
			_break = ROUND_BREAK * time_scale
		else:
			_break -= delta
			if _break <= 0.0:
				_break = -1.0
				var done := round_no
				round_cleared.emit(done)
				ZombieMode.advance_round()

## Spawn points out of the player's view, no nearer than MIN_SPAWN_DISTANCE: one of the four nearest, so the
## crew arrives within a few seconds and not across the whole block.
func _pick_point(strict := false, nearest := false) -> Vector3:
	if spawn_points.is_empty():
		return super._pick_point(strict, nearest)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var good: Array = []
	for p in spawn_points:
		var d := p.distance_to(player.global_position) if player else 999.0
		if d < MIN_SPAWN_DISTANCE:
			continue
		if cam and not cam.is_position_behind(p) and cam.is_position_in_frustum(p + Vector3.UP):
			continue
		good.append([d, p])
	if good.is_empty():
		return super._pick_point(strict, nearest)
	good.sort_custom(func(a, b): return a[0] < b[0])
	var k := mini(4, good.size())
	return good[_rng.randi() % k][1]

## Whether the navmesh has a way from where the player stands to `to` (not an island inside a fence).
func reachable(map: RID, to: Vector3) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return true
	var path := NavigationServer3D.map_get_path(map, player.global_position, to, true)
	return path.size() >= 2 and Vector2(path[path.size() - 1].x - to.x, path[path.size() - 1].z - to.z).length() < 1.2

## `p` on the navmesh, on the player's side of it: a man is never put down where the player cannot get at him
## (inside the roadworks' fence, say). Tries a ring of spots round `p`, then the nearest spawn point that has a way.
func _walkable(p: Vector3, map: RID) -> Vector3:
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	var s := NavigationServer3D.map_get_closest_point(map, p)
	if s.distance_to(p) < 6.0 and reachable(map, s):
		return Vector3(s.x, p.y, s.z)
	for r in [1.6, 3.2, 4.8]:
		for k in 8:
			var c := p + Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * float(r)
			var n := NavigationServer3D.map_get_closest_point(map, c)
			if Vector2(n.x - c.x, n.z - c.z).length() < 0.8 and reachable(map, n):
				return Vector3(n.x, p.y, n.z)
	var near: Array = spawn_points.duplicate()
	near.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(p) < b.distance_squared_to(p))
	for sp in near:
		var n := NavigationServer3D.map_get_closest_point(map, sp)
		if n.distance_to(sp) < 3.0 and reachable(map, n):
			return Vector3(n.x, sp.y, n.z)
	return p

## Puts a stuck one back on a spawn point out of the player's sight, on a way the player can walk.
func relocate(z: Node3D) -> bool:
	var p := _pick_point(true, true)
	if p == Vector3.INF:
		return false
	z.global_position = _walkable(p, z.get_world_3d().navigation_map)
	z.reset_physics_interpolation()
	if z.has_method("relocated"):
		z.relocated()
	relocated.emit(z)
	return true

func _release_squad(n: int) -> void:
	var made: Array = []
	var at := _pick_point()
	for i in n:
		var kind := _kinds[released]
		released += 1
		var g := spawn_one(kind, at + Vector3(i * 1.4, 0, 0))
		if g:
			kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
			made.append(g)
	if made.size() == 2:
		squads += 1
		made[0].buddy = made[1]
		made[1].buddy = made[0]
		made[0].role = "support"
		made[1].role = "flank"

func spawn_one(kind: String, at := Vector3.INF, body := "", gun := "") -> CharacterBody3D:
	if holder == null:
		return null
	var t0 := Time.get_ticks_usec()
	var g = GangsterScript.new()
	g.crew = crew_name
	g.configure(kind, maxi(round_no, 1), _rng)
	if gun != "" and gun in GangsterScript.GUNS:
		g.gun_id = gun
		g.gun = GangsterScript.GUNS[gun]
		g.mag = int(g.gun["mag"])
	if body != "":
		g.set_meta("body", body)
	var p := at if at != Vector3.INF else _pick_point()
	p = _walkable(p, holder.get_world_3d().navigation_map)
	g.position = p
	g.died.connect(_on_died)
	holder.add_child(g)
	g.reset_physics_interpolation()
	g.bark_ready()
	gun_counts[g.gun_id] = int(gun_counts.get(g.gun_id, 0)) + 1
	if g.boss:
		bosses += 1
	last_spawn_usec = Time.get_ticks_usec() - t0
	worst_spawn_usec = maxi(worst_spawn_usec, last_spawn_usec)
	peak_alive = maxi(peak_alive, alive())
	spawned.emit(g)
	return g

## The story and set layers: put `def.count` crew on the street now. def = {count, weapons: [gun ids], crew,
## from_points: [Vector3], drive_by: bool}. Returns the men made. They count as alive (for the wave to wait for)
## but not against the wave's own tally.
func spawn_wave(def: Dictionary) -> Array:
	var count := int(def.get("count", 4))
	var weapons: Array = def.get("weapons", [])
	var points: Array = def.get("from_points", [])
	var old_crew := crew_name
	if def.has("crew"):
		crew_name = String(def["crew"])
	var out: Array = []
	for i in count:
		var at := Vector3.INF
		if not points.is_empty():
			at = points[i % points.size()] + Vector3((i / maxi(points.size(), 1)) * 1.3, 0, 0)
		var gun := String(weapons[i % weapons.size()]) if not weapons.is_empty() else ""
		var kind := "grunt"
		if def.get("heavy", false) and i == 0:
			kind = "heavy"
		var g := spawn_one(kind, at, "", gun)
		if g != null:
			if bool(def.get("drive_by", false)):
				g.drive_by()
			out.append(g)
	crew_name = old_crew
	return out

func _on_died(zombie: Node, part: String, melee: bool) -> void:
	super._on_died(zombie, part, melee)
	var gm := get_node_or_null("/root/GhettoMode")
	if gm != null:
		gm.enemy_killed.emit(zombie, "melee" if melee else ("head" if part == "head" else "body"))
