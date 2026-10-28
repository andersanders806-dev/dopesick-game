extends Node
## The block is all loaded at once (loading while walking is what made
## the street stutter); what's far from you just sleeps: no processing,
## nothing drawn but the landmarks. One cell changes state per frame.
##
## A cell is its root under City3D (Cell_Main...), with its `bounds`, plus
## the buildings world/Facades.gd raises for it at load (the Facades
## children with meta "cell"). Hiding a few thousand meshes in one frame
## costs milliseconds, so a switch is spread over as many frames as it
## takes at SWITCH_BUDGET_USEC each; the next cell waits for it.
##
## Lights City3D switches with the day (night_lights, sign glows,
## streetlights) aren't turned back on here: City3D hears cell_changed and
## puts them back to what the hour says, so waking a cell at noon doesn't
## light its lamps.
##
## Anything in group "cell_sleepers" that isn't inside a cell root (people
## walking the block) is frozen while every cell its position lies in
## sleeps.

const WAKE_MARGIN := 25.0
## Per physics frame, for a cell's switch.
const SWITCH_BUDGET_USEC := 1500
## How often loose cell_sleepers are looked at again (they move).
const SLEEPER_PERIOD := 0.25

signal cell_changed(cell: Node3D, awake: bool)

var _awake := {}
var _cells: Array[Node3D] = []
var _members := {}
var _gathered := false
## The switch in progress: [cell, on, next member index], or empty.
var _job: Array = []
var _sleeper_t := 0.0
## For the perf probe: how long the last finished switch took, its frames.
var last_switch_usec := 0
var last_switch_frames := 0
var _job_usec := 0
var _job_frames := 0

func _ready() -> void:
	for c in get_parent().get_children():
		if c is Node3D and String(c.name).begins_with("Cell_"):
			_cells.append(c)
			_awake[c] = true

func is_awake(cell: Node3D) -> bool:
	return _awake.get(cell, true)

## Whether a point lies in cells that all sleep (a point in none is awake).
func asleep_at(p: Vector3) -> bool:
	var inside := false
	for c in _cells:
		if (c.get_meta("bounds") as AABB).has_point(Vector3(p.x, 1.0, p.z)):
			inside = true
			if _awake[c]:
				return false
	return inside

## The cell roots, for City3D.
func cells() -> Array[Node3D]:
	return _cells

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
			if n is Node3D and not n.is_in_group("landmark"):
				list.append(n)
		_members[c] = list
		# A sleeping cell keeps its walls: physics bodies stay in the world
		# (a far policeman's line of sight, the navmesh's agents) and only
		# the drawing and processing stop.
		for body in c.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	for holder in get_parent().get_children():
		if holder in _awake or not (holder is Node3D):
			continue
		for n in holder.get_children():
			if n is Node3D and n.has_meta("cell"):
				var c := get_parent().get_node_or_null(String(n.get_meta("cell"))) as Node3D
				if c and _members.has(c) and not n.is_in_group("landmark"):
					(_members[c] as Array[Node3D]).append(n)

func _physics_process(delta: float) -> void:
	if not _gathered:
		_gather()
	_sleeper_t -= delta
	if _sleeper_t <= 0.0:
		_sleeper_t = SLEEPER_PERIOD
		_update_sleepers()
	if not _job.is_empty():
		_run_job()
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var at := Vector3(player.global_position.x, 1.0, player.global_position.z)
	for c in _cells:
		var want := (c.get_meta("bounds") as AABB).grow(WAKE_MARGIN).has_point(at)
		if want != _awake[c]:
			_set_awake(c, want)
			return  # one per frame

func _set_awake(c: Node3D, on: bool) -> void:
	_awake[c] = on
	c.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_job = [c, on, 0]
	_job_usec = 0
	_job_frames = 0
	_run_job()

func _run_job() -> void:
	var t0 := Time.get_ticks_usec()
	var c: Node3D = _job[0]
	var on: bool = _job[1]
	var list: Array[Node3D] = _members.get(c, [] as Array[Node3D])
	var i: int = _job[2]
	while i < list.size():
		var n := list[i]
		i += 1
		if is_instance_valid(n) and not (on and _day_managed(n)):
			n.visible = on
		if Time.get_ticks_usec() - t0 > SWITCH_BUDGET_USEC:
			break
	_job_usec += Time.get_ticks_usec() - t0
	_job_frames += 1
	if i < list.size():
		_job[2] = i
		return
	_job = []
	last_switch_usec = _job_usec
	last_switch_frames = _job_frames
	if OS.is_stdout_verbose() or Engine.has_meta("cell_log"):
		print("BlockCells: %s %s in %.1f ms over %d frames (%d members)" % [c.name, "woke" if on else "slept", _job_usec / 1000.0, _job_frames, list.size()])
	_update_sleepers()
	cell_changed.emit(c, on)

## City3D puts these back by the hour (_on_cell_changed).
func _day_managed(n: Node) -> bool:
	return n is Light3D and (n.is_in_group("night_lights") or String(n.name).ends_with("SignGlow"))

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
