extends Node
## The block is all loaded at once (loading while walking is what made
## the street stutter); what's far from you just sleeps: nothing in it
## processes (people, signs, buzzing lamps, anything with a script), its
## after-dark lights are off, and its small props thin out with distance.
## One cell changes state per frame.
##
## Sleeping does NOT hide the buildings: a cell's masses, fronts, ground,
## cars, landmarks and the like stay drawn (static and occluded, cheap),
## so the far end of an avenue is there and nothing pops in at the edge
## of a margin. What is hidden is hidden by distance and not by the cell:
## the small props get a visibility range with a fade (PROP_RANGE_END),
## so they fade out whether their cell sleeps or not -- and at wake or
## sleep nothing changes on screen. City3D fades the cell's lamps in and
## out (cell_changed) for the same reason.
##
## A cell is its root under City3D (Cell_Main...), with its `bounds`, plus
## the buildings world/Facades.gd raises for it at load (the Facades
## children with meta "cell"; they have nothing to put to sleep).
##
## Lights City3D switches with the day (night_lights, sign glows,
## streetlights) are City3D's; any other light in a cell (a fire barrel's)
## is switched off here while it sleeps.
##
## Anything in group "cell_sleepers" that isn't inside a cell root (people
## walking the block) is frozen while every cell its position lies in
## sleeps.

const WAKE_MARGIN := 25.0
## A cell that's awake sleeps again only past this: a few metres more than
## it took to wake it, so walking back and forth over the line is one
## switch (and not the lights, buzzes and processing toggling every frame).
const SLEEP_MARGIN := WAKE_MARGIN + 8.0
## How often loose cell_sleepers are looked at again (they move).
const SLEEPER_PERIOD := 0.25

## A small prop (nothing over PROP_SIZE wide or PROP_HEIGHT tall) fades out
## between PROP_RANGE_END - PROP_RANGE_MARGIN and PROP_RANGE_END metres from
## the camera (or the margin beyond it; either way gone by 24 m, under the
## 25 m a cell wakes at).
const PROP_RANGE_END := 18.0
const PROP_RANGE_MARGIN := 6.0
const PROP_SIZE := 3.5
const PROP_HEIGHT := 3.0
## A light of the cell's own, not City3D's: it dims with distance too.
const LIGHT_FADE_BEGIN := 9.0
const LIGHT_FADE_LENGTH := 8.0
## Parts of a building (shop doors, signs) and what isn't drawn: never props.
const NOT_PROPS := ["Door", "Sign", "Hours", "Building", "Bounds", "Number", "Streetlight", "Lamp"]

signal cell_changed(cell: Node3D, awake: bool)

var _awake := {}
var _cells: Array[Node3D] = []
var _props := {}
var _lights := {}
var _gathered := false
var _sleeper_t := 0.0
## For the perf probe: how long the last switch took, in frames.
var last_switch_usec := 0
var last_switch_frames := 1

func _ready() -> void:
	add_to_group("block_cells")
	for c in get_parent().get_children():
		if c is Node3D and String(c.name).begins_with("Cell_"):
			_cells.append(c)
			_awake[c] = true

func is_awake(cell: Node3D) -> bool:
	return _awake.get(cell, true)

## The cell roots, for City3D.
func cells() -> Array[Node3D]:
	return _cells

## The small props of a cell: what thins out with distance.
func props(cell: Node3D) -> Array[Node3D]:
	return _props.get(cell, [] as Array[Node3D])

## The cell a node belongs to: the cell root it's under, or its "cell" meta.
func cell_of(node: Node) -> Node3D:
	var n := node
	while n != null and n != get_parent():
		if n is Node3D and n in _awake:
			return n
		if n.has_meta("cell"):
			return get_parent().get_node_or_null(String(n.get_meta("cell"))) as Node3D
		n = n.get_parent()
	return null

## Done on the first tick, after City3D's _ready has raised the buildings.
func _gather() -> void:
	_gathered = true
	for c in _cells:
		var list: Array[Node3D] = []
		for n in c.get_children():
			if n is Node3D and is_prop(n):
				list.append(n)
				_fade_with_distance(n)
		_props[c] = list
		# A sleeping cell keeps its walls: physics bodies stay in the world
		# (a far policeman's line of sight, the navmesh's agents) and only
		# the drawing and processing stop.
		for body in c.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		var lights: Array[Light3D] = []
		for l in c.find_children("*", "Light3D", true, false):
			if not _day_managed(l):
				lights.append(l)
				(l as Light3D).distance_fade_enabled = true
				(l as Light3D).distance_fade_begin = LIGHT_FADE_BEGIN
				(l as Light3D).distance_fade_length = LIGHT_FADE_LENGTH
		_lights[c] = lights

## A small loose thing (a hydrant, a bench, a pile of tyres) as against a
## building part, the ground, a car or a tree: those stay drawn.
static func is_prop(n: Node3D) -> bool:
	if n.is_in_group("landmark") or n is Light3D or n is Label3D or n is Decal or n is MultiMeshInstance3D:
		return false
	for part in NOT_PROPS:
		if String(n.name).contains(part):
			return false
	var box := AABB()
	var first := true
	var parts: Array = n.find_children("*", "GeometryInstance3D", true, false)
	if n is GeometryInstance3D:
		parts.append(n)
	for g in parts:
		var b: AABB = (n.global_transform.affine_inverse() * (g as GeometryInstance3D).global_transform) * (g as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return false
	return maxf(box.size.x, box.size.z) < PROP_SIZE and box.size.y < PROP_HEIGHT

static func _fade_with_distance(n: Node3D) -> void:
	var parts: Array = n.find_children("*", "GeometryInstance3D", true, false)
	if n is GeometryInstance3D:
		parts.append(n)
	for g in parts:
		var gi := g as GeometryInstance3D
		gi.visibility_range_end = PROP_RANGE_END
		gi.visibility_range_end_margin = PROP_RANGE_MARGIN
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _physics_process(delta: float) -> void:
	if not _gathered:
		_gather()
	_sleeper_t -= delta
	if _sleeper_t <= 0.0:
		_sleeper_t = SLEEPER_PERIOD
		_update_sleepers()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var at := Vector3(player.global_position.x, 1.0, player.global_position.z)
	for c in _cells:
		var want := (c.get_meta("bounds") as AABB).grow(SLEEP_MARGIN if _awake[c] else WAKE_MARGIN).has_point(at)
		if want != _awake[c]:
			_set_awake(c, want)
			return  # one per frame

func _set_awake(c: Node3D, on: bool) -> void:
	var t0 := Time.get_ticks_usec()
	_awake[c] = on
	c.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for l in _lights.get(c, []):
		if is_instance_valid(l):
			l.visible = on
	_update_sleepers()
	last_switch_usec = Time.get_ticks_usec() - t0
	if OS.is_stdout_verbose() or Engine.has_meta("cell_log"):
		print("BlockCells: %s %s in %.1f ms" % [c.name, "woke" if on else "slept", last_switch_usec / 1000.0])
	cell_changed.emit(c, on)

## City3D puts these back by the hour (_fade_lights).
func _day_managed(n: Node) -> bool:
	return n is Light3D and (n.is_in_group("night_lights") or String(n.name).ends_with("SignGlow") or String(n.get_parent().name).begins_with("Streetlight"))

func _update_sleepers() -> void:
	for n in get_tree().get_nodes_in_group("cell_sleepers"):
		if not (n is Node3D) or not get_parent().is_ancestor_of(n) or cell_of(n) != null:
			continue
		var p: Vector3 = (n as Node3D).global_position
		var inside := false
		var awake := false
		for c in _cells:
			if (c.get_meta("bounds") as AABB).has_point(Vector3(p.x, 1.0, p.z)):
				inside = true
				awake = awake or _awake[c]
		var want := Node.PROCESS_MODE_INHERIT if (awake or not inside) else Node.PROCESS_MODE_DISABLED
		if n.process_mode != want:
			n.process_mode = want
