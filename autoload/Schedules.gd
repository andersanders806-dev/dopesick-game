extends Node
## Everyone who has somewhere to be, as data. A person is a list of
## entries, each "from this minute of the day, be at this place doing this"
## -- the last one before the clock holds, and the day wraps, so the entry
## in force just after midnight is the one that began the evening before.
## The places are the Place_* markers the block's builder puts down
## (group "places"); nothing here knows a coordinate.
##
## Activities:
##   idle      stands about.
##   sit       sits (the bench).
##   walk_loop shuffles round their spot, a few steps at a time.
##   work      stands at their post; shopkeepers behind their counter.
##   smoke     leans on the wall.
##   sleep     isn't out: indoors, on the bus, home. The body is put away
##             where the door is, and comes out of it again.
##
## npc/ScheduledPerson.gd plays the entries on the block, in three tiers
## (near the player it walks and animates; far off in an awake cell it
## steps along its path every 15th tick without animating; in a sleeping
## cell it isn't processed at all and is put at position_at() when the cell
## wakes). The pusher and the beat cop read their posts and loop from here;
## the postman is an errand, not a timetable (City3D sends him to the mailbox
## when a parcel is due), so he isn't listed.
##
## One rule for everybody: nobody appears, vanishes, teleports or changes
## pose while the player could see it (is_seen(): within SEEN_RANGE, or in
## the camera's view). A change that is due is put off until it is unseen;
## people who have to go in at a door walk to it first.

const DAY := 1440
const ACTIVITIES := ["idle", "sit", "walk_loop", "work", "smoke", "sleep"]

## Entries are [from minute of day, place, activity], in order of time.
## `offset` is where they stand from the place (x, z); `lift` raises a sitter
## to a seat taller than the clip's (the bench); `partner`, if any, is who they face. A person who is only data (`spawn` false) isn't put on the
## block: the postman and Ray have their own scenes and scripts, and the
## shopkeepers are inside shops that aren't on the block.
const PEOPLE := {
	# The park bench regulars, 09:00 to 17:00; a chess game that runs all day.
	"chess_a": {"role": "chess_a", "lift": 0.1, "offset": Vector2(-0.45, -1.0),
		"entries": [[0, "ParkBench", "sleep"], [9 * 60, "ParkBench", "sit"], [17 * 60, "ParkBench", "sleep"]]},
	"chess_b": {"role": "chess_b", "lift": 0.1, "offset": Vector2(0.45, -1.0),
		"entries": [[0, "ParkBench", "sleep"], [9 * 60 + 30, "ParkBench", "sit"], [16 * 60 + 30, "ParkBench", "sleep"]]},
	# The court, daylight only; one of them stays on after the others.
	"court_a": {"role": "court_a", "offset": Vector2(-1.5, 0.5),
		"entries": [[0, "Court", "sleep"], [10 * 60, "Court", "walk_loop"], [18 * 60, "Court", "sleep"]]},
	"court_b": {"role": "court_b", "offset": Vector2(1.5, -0.5),
		"entries": [[0, "Court", "sleep"], [11 * 60, "Court", "walk_loop"], [20 * 60, "Court", "sleep"]]},
	# The 14 and the 22 stop here: out for the morning and the evening rush.
	"commuter_a": {"role": "commuter_a", "offset": Vector2(-0.8, 0.0),
		"entries": [[0, "BusStop", "sleep"], [7 * 60 + 20, "BusStop", "idle"], [9 * 60, "BusStop", "sleep"],
			[17 * 60, "BusStop", "idle"], [19 * 60, "BusStop", "sleep"]]},
	"commuter_b": {"role": "commuter_b", "offset": Vector2(0.8, 0.2),
		"entries": [[0, "BusStop", "sleep"], [7 * 60 + 40, "BusStop", "idle"], [9 * 60, "BusStop", "sleep"],
			[17 * 60 + 20, "BusStop", "idle"], [19 * 60, "BusStop", "sleep"]]},
	# The stoops, in the evening: out for a cigarette, then in. The 0:00
	# entry is the one that takes them in across midnight.
	"stoop_a": {"role": "stoop_a", "offset": Vector2(0.0, 0.9),
		"entries": [[0, "Stoop1", "sleep"], [18 * 60 + 30, "Stoop1", "smoke"]]},
	"stoop_b": {"role": "stoop_b", "offset": Vector2(0.4, 1.0),
		"entries": [[0 * 60 + 40, "Stoop2", "sleep"], [19 * 60, "Stoop2", "idle"], [22 * 60, "Stoop2", "smoke"]]},
	"stoop_c": {"role": "stoop_c", "offset": Vector2(-0.4, 1.0),
		"entries": [[0, "Stoop3", "sleep"], [20 * 60, "Stoop3", "idle"], [23 * 60 + 30, "Stoop3", "sleep"]]},
	# The camp's residents, from dusk to the morning; one of them works the
	# dumpsters while the others sleep it off.
	"camp_a": {"role": "camp_a", "offset": Vector2(-0.6, -0.6),
		"entries": [[0, "UnderpassCamp", "sit"], [7 * 60, "UnderpassCamp", "sleep"], [19 * 60, "UnderpassCamp", "sit"]]},
	"camp_b": {"role": "camp_b", "offset": Vector2(1.0, -0.4),
		"entries": [[0, "UnderpassCamp", "idle"], [6 * 60 + 30, "UnderpassCamp", "sleep"], [20 * 60, "UnderpassCamp", "idle"]]},
	"camp_c": {"role": "camp_c", "offset": Vector2(0.0, 0.3),
		"entries": [[0, "UnderpassCamp", "sit"], [8 * 60, "AlleyDumpsters", "work"], [18 * 60, "UnderpassCamp", "sit"]]},
	# The corner, 10:00 to 20:00; the underpass after that, until 03:00
	# (GameState.PUSHER_HOURS). npc/Pusher3D.gd works the post it's given.
	"pusher": {"role": "pusher", "spawn": false,
		"entries": [[0, "PusherNight", "idle"], [3 * 60, "PusherCorner", "sleep"], [10 * 60, "PusherCorner", "idle"], [20 * 60, "PusherNight", "idle"]]},
	# Ray never leaves his crate.
	"ray": {"role": "homeless", "spawn": false,
		"entries": [[0, "RayCrate", "sit"]]},
	# The beat cop's loop is PATROL_ROUTE; he starts it at the station.
	"beat_cop": {"role": "police", "spawn": false,
		"entries": [[0, "PoliceStation", "walk_loop"]]},
}

## The shopkeepers keep their shop's hours (GameState.OPENING_HOURS): at the
## counter while it's open, gone while it's shut. The shops are walk-in
## ones (open-world Task 3); until the block has their Place_Shop*
## markers they are only data.
const SHOPKEEPERS := {
	"shop_convenience": {"role": "clerk_convenience", "shop": "convenience"},
	"shop_liquor": {"role": "clerk_liquor", "shop": "liquor"},
	"shop_pawn": {"role": "pawnbroker", "shop": "pawn"},
	"shop_music": {"role": "clerk_music", "shop": "music"},
}

## The beat cop's loop round the block: the sidewalk beside the road on
## every street, clockwise from the station. Waypoints, not a path: he
## finds his way between them on the navmesh. About 430 m.
const PATROL_ROUTE: Array[Vector3] = [
	Vector3(-24.5, 0, -2.6), Vector3(0.0, 0, -2.6), Vector3(12.9, 0, -2.6), Vector3(40.0, 0, -2.6), Vector3(66.6, 0, -2.6),
	Vector3(66.6, 0, -30.0), Vector3(66.6, 0, -60.0), Vector3(66.6, 0, -85.6),
	Vector3(40.0, 0, -85.6), Vector3(20.0, 0, -85.6), Vector3(0.0, 0, -85.6), Vector3(-30.0, 0, -85.6), Vector3(-66.6, 0, -85.6),
	Vector3(-66.6, 0, -60.0), Vector3(-66.6, 0, -30.0), Vector3(-66.6, 0, -2.6),
	Vector3(-50.0, 0, -2.6),
]

var _people: Dictionary = {}
var _places: Dictionary = {}

func _ready() -> void:
	_people = PEOPLE.duplicate(true)
	for id in SHOPKEEPERS:
		var shop: String = SHOPKEEPERS[id]["shop"]
		var hours: Array = GameState.OPENING_HOURS.get(shop, [0, 24])
		var place := "Shop_" + shop.capitalize()
		var entries: Array
		if hours[0] == 0 and hours[1] == 24:
			entries = [[0, place, "work"]]
		else:
			# [open, close) wraps past midnight when close < open; the
			# entry list is in order of time either way.
			var open_m: int = int(hours[0]) * 60
			var close_m: int = (int(hours[1]) % 24) * 60
			entries = [[open_m, place, "work"], [close_m, place, "sleep"]] if close_m > open_m \
				else [[close_m, place, "sleep"], [open_m, place, "work"]]
			entries.sort_custom(func(a, b): return a[0] < b[0])
		_people[id] = {"role": SHOPKEEPERS[id]["role"], "spawn": false, "shop": shop, "entries": entries}

func people() -> PackedStringArray:
	return PackedStringArray(_people.keys())

## Those that are put on the block as ScheduledPersons.
func walkers() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _people:
		if _people[id].get("spawn", true):
			out.append(id)
	return out

func info(person: String) -> Dictionary:
	return _people.get(person, {})

func role_of(person: String) -> String:
	return String(info(person).get("role", "player"))

func _entries(person: String) -> Array:
	return info(person).get("entries", [])

## The entry in force at `minute_of_day` (0..1439, wraps): {"from": int,
## "place": String, "activity": String}. Before a person's first entry of
## the day the last one holds still -- it began yesterday.
func entry_at(person: String, minute_of_day: int) -> Dictionary:
	var entries := _entries(person)
	if entries.is_empty():
		return {}
	var m := posmod(minute_of_day, DAY)
	var pick: Array = entries[entries.size() - 1]
	for e in entries:
		if e[0] <= m:
			pick = e
		else:
			break
	return {"from": pick[0], "place": pick[1], "activity": pick[2]}

## The entry after the one in force, and how many minutes until it starts
## (across midnight if need be). The same entry again for a person with only one.
func next_entry(person: String, minute_of_day: int) -> Dictionary:
	var entries := _entries(person)
	if entries.is_empty():
		return {}
	var m := posmod(minute_of_day, DAY)
	var nxt: Array = entries[0]
	for e in entries:
		if e[0] > m:
			nxt = e
			break
	return {"from": nxt[0], "place": nxt[1], "activity": nxt[2], "in": posmod(nxt[0] - m - 1, DAY) + 1}

## Whether they are out on the block at `minute_of_day` (not indoors).
func is_out(person: String, minute_of_day: int) -> bool:
	var e := entry_at(person, minute_of_day)
	return not e.is_empty() and e["activity"] != "sleep"

## Where the Place_<name> marker stands; Vector3.INF if the block has none.
func place_position(place: String) -> Vector3:
	var m = _places.get(place)
	if m != null and is_instance_valid(m) and m.is_inside_tree():
		return m.global_position
	if not is_inside_tree():
		return Vector3.INF
	_places.clear()
	for n in get_tree().get_nodes_in_group("places"):
		if n is Node3D and String(n.name).begins_with("Place_"):
			_places[String(n.name).substr(6)] = n
	m = _places.get(place)
	return (m as Node3D).global_position if m != null else Vector3.INF

## Where a person is (to the metre) at `minute_of_day`: their place's marker
## plus their own offset from it.
func position_at(person: String, minute_of_day: int) -> Vector3:
	var e := entry_at(person, minute_of_day)
	if e.is_empty():
		return Vector3.INF
	return position_for(person, e["place"])

func position_for(person: String, place: String) -> Vector3:
	var p := place_position(place)
	if p == Vector3.INF:
		return p
	var off: Vector2 = info(person).get("offset", Vector2.ZERO)
	return p + Vector3(off.x, 0.0, off.y)

## Who faces whom, for the pair on the bench.
func partner_of(person: String) -> String:
	return String(info(person).get("partner", ""))

## Where the pusher works at `minute_of_day`: "PusherCorner" or
## "PusherNight". Off shift he's still wherever his last hours were.
func pusher_post(minute_of_day: int) -> String:
	return String(entry_at("pusher", minute_of_day).get("place", "PusherCorner"))

func patrol_route() -> Array[Vector3]:
	return PATROL_ROUTE

## Where the beat cop would be on his loop at `abs_minute` (GameState.now_minutes())
## walking at his pace, `dir` +1 or -1: {"pos": Vector3, "index": the
## waypoint he is heading for}. Used to put him back on the beat after he has
## been frozen in a sleeping cell, or after a load.
func patrol_point(abs_minute: float, dir := 1, extra_m := 0.0) -> Dictionary:
	var n := PATROL_ROUTE.size()
	var total := 0.0
	for i in n:
		total += PATROL_ROUTE[i].distance_to(PATROL_ROUTE[(i + 1) % n])
	# 1.25 m/s on a clock that runs MINUTES_PER_SEC game minutes a second;
	# `extra_m` is that many metres further on in his heading.
	var along := fposmod(abs_minute * 1.25 / GameState.MINUTES_PER_SEC + extra_m, total)
	if dir < 0:
		along = total - along
	for i in n:
		var a: Vector3 = PATROL_ROUTE[i]
		var b: Vector3 = PATROL_ROUTE[(i + 1) % n]
		var len := a.distance_to(b)
		if along <= len or i == n - 1:
			var pos := a.lerp(b, clampf(along / maxf(len, 0.001), 0.0, 1.0))
			return {"pos": pos, "index": (i + 1) % n if dir > 0 else i}
		along -= len
	return {"pos": PATROL_ROUTE[0], "index": 0}

## --- Who can see what ---------------------------------------------------------------

## Within this many metres of the player anything can be seen (round the
## corner of a wall included: the player moves, the camera swings).
const SEEN_RANGE := 30.0
## For tests: 1 = everything is seen, 0 = nothing is, -1 (the default) = ask
## the player and the camera.
var seen_override := -1

## Whether the player could see something standing at `pos`: it is within
## SEEN_RANGE of them or inside the active camera's view (the real camera,
## which can swing anywhere). With `behind_cover`, something standing behind
## a wall or a pillar from the camera doesn't count -- for those who slip
## away round a corner.
func is_seen(pos: Vector3, behind_cover := false) -> bool:
	if seen_override >= 0:
		return seen_override == 1
	if not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length() < SEEN_RANGE
	if not near and not _framed(cam, pos):
		return false
	if behind_cover and cam != null and _covered(cam, pos):
		return false
	return true

## Whether `pos` (a person standing there) is inside the camera's view.
func in_view(pos: Vector3) -> bool:
	if seen_override >= 0:
		return seen_override == 1
	return is_inside_tree() and _framed(get_viewport().get_camera_3d(), pos)

## Feet, waist, head and a hand's breadth either side: any of them in view.
func _framed(cam: Camera3D, pos: Vector3) -> bool:
	if cam == null:
		return false
	for off in [Vector3(0, 0.1, 0), Vector3(0, 0.9, 0), Vector3(0, 1.8, 0), Vector3(0.4, 0.9, 0), Vector3(-0.4, 0.9, 0), Vector3(0, 0.9, 0.4), Vector3(0, 0.9, -0.4)]:
		if cam.is_position_in_frustum(pos + off):
			return true
	return false

## All of feet, waist and head hidden from the camera by something solid.
func _covered(cam: Camera3D, pos: Vector3) -> bool:
	var space := cam.get_world_3d().direct_space_state
	for h in [0.2, 0.9, 1.7]:
		var to := pos + Vector3(0, h, 0)
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, to + (from - to).normalized() * 0.3, 1)
		if space.intersect_ray(q).is_empty():
			return false
	return true
