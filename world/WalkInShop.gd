extends "res://world/Store3D.gd"
## A shop on Main Street you walk into from the sidewalk (built by dev-tools/
## city/walk_in.gd inside its building; world/Facades.WALK_INS). It's a node
## of the street's scene, not a scene of its own, and does what the old
## rooms did:
##   - theft, guards, the police: world/Store3D.gd's, unchanged. The clerks
##     only look at you while you're inside (outside, a clerk's cone would
##     catch you through the doorway), and the police are called to the door.
##   - closing time: with you inside, staff tell you to go and, a few
##     seconds later, you're shown out onto the sidewalk.
##   - the roof of the building comes off while you're inside, so the camera
##     sees in; the lamps are on, and the window's painted glow off, only
##     while you're within WALK_IN_NEAR of it.
## Tells the street's root (entered_shop / left_shop) when you cross in or out.

const Facades := preload("res://world/Facades.gd")
const TapeCounter := preload("res://world/TapeCounter.gd")
## Past this the shop is a lit window again (a bit more than it took to wake
## it, so it doesn't flicker on the line).
const FAR := Facades.WALK_IN_NEAR + 1.5
## The room is built when you come this near its door.
const BUILD_RANGE := 30.0
## ...and this near, its scene is wanted now, walking or not.
const URGENT_RANGE := 20.0
## What one frame spends on building it (microseconds).
const BUILD_BUDGET_USEC := 3000

var place := ""
var player_inside := false
var near := false
## The room (world/walkin/<Front>.tscn) is in.
var loaded := false
var _front := ""
var _guard_range := {}
var _poll := 0.0
var _inert := false
var _room: Node = null
## Which shop is being built right now: one at a time.
static var _building: Node = null

func _ready() -> void:
	place = String(get_meta("place", ""))
	for front in Facades.WALK_INS:
		if Facades.WALK_INS[front]["node"] == String(name):
			_front = front
	if GameState.mode == "zombies":
		# Dead Block: furnished and empty. The room is built like any other
		# (the lazy path), then stripped of its people (_dress_inert).
		_go_inert()
		return
	# The street's scene holds the doorway only: the Inside area, the
	# markers, the gate. The room is built into it later (_process).
	var inside := get_node("Inside") as Area3D
	inside.body_entered.connect(_on_body_entered)
	inside.body_exited.connect(_on_body_exited)
	GameState.clock_changed.connect(func(_m): _refresh_gate())
	_refresh_gate()

## The room's scene, in the background since the title screen (SceneLoader);
## null until it is.
func _packed(urgent := false) -> PackedScene:
	var loader := get_node_or_null("/root/SceneLoader")
	var path := Facades.walk_in_scene(_front)
	if loader != null:
		return loader.packed(path, urgent)
	return load(path) as PackedScene

## Builds the whole room at once -- for a player who is already inside (a
## Continue, a teleport), behind the fade, not for walking up to the door.
func ensure_loaded() -> void:
	if loaded:
		return
	if _room == null:
		var packed := _packed(true)
		if packed == null:
			packed = load(Facades.walk_in_scene(_front)) as PackedScene
		_start_room(packed)
	while _room.get_child_count() > 0:
		_adopt_one()
	_finish_room()

func _start_room(packed: PackedScene) -> void:
	_room = packed.instantiate()

func _adopt_one() -> void:
	var c := _room.get_child(0)
	_room.remove_child(c)
	c.owner = null
	add_child(c)

func _finish_room() -> void:
	_room.free()
	_room = null
	if _building == self:
		_building = null
	# Inside, the lamps are on a layer of their own, so a lamp in the shop
	# never lights the street: everything here is on it as well as layer 1.
	for n in find_children("*", "VisualInstance3D", true, false):
		if not (n is Light3D):
			(n as VisualInstance3D).layers = 3
	if _inert:
		_dress_inert()
		loaded = true
		return
	_setup_store()
	_wire_guards()
	_shuffle_items()
	if store_id == "music":
		TapeCounter.wire_zones(self)
	for guard in get_tree().get_nodes_in_group("guards"):
		if is_ancestor_of(guard):
			_guard_range[guard] = guard.vision_range
			guard.vision_range = 0.0
	loaded = true
	_set_near(false)

## A frame of building: the room is instanced one frame, then handed over a
## few nodes at a time (a clerk is the slow part), within a small budget.
func _build_step(urgent := false) -> void:
	if _room == null:
		var packed := _packed(urgent)
		if packed == null or (_building != null and _building != self):
			return
		_building = self
		_start_room(packed)
		return
	var t0 := Time.get_ticks_usec()
	while _room.get_child_count() > 0 and Time.get_ticks_usec() - t0 < BUILD_BUDGET_USEC:
		_adopt_one()
	if _room.get_child_count() == 0:
		_finish_room()

## Dead Block has no shopkeepers: the rooms stand empty and open.
func _go_inert() -> void:
	_inert = true
	if has_node("Gate"):
		(get_node("Gate") as CollisionObject3D).collision_layer = 0

## What an inert room loses once it is built: its clerks, the pawnbroker and
## every trigger (nobody to talk to, nothing to lift).
func _dress_inert() -> void:
	for n in get_children():
		if n.is_in_group("guards") or n is Area3D and n.name != "Inside" or n.name.begins_with("Pawnbroker"):
			n.queue_free()

## Frames cost nothing here: the roof, the lamps and the guards change on the
## step, not every frame.
func _process(delta: float) -> void:
	if not loaded:
		if _room != null:
			_build_step()
		else:
			_poll -= delta
			if _poll <= 0.0:
				_poll = 0.25
				var player := get_tree().get_first_node_in_group("player") as Node3D
				var d := 1e9
				if player != null:
					d = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z - -5.5).length()
				if d < BUILD_RANGE:
					# Close to the door the load doesn't wait for you to stand
					# still (SceneLoader): you'd reach it with a blocking one.
					_build_step(d < URGENT_RANGE)
		return
	if _inert:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		_update_near()
	if player_inside:
		_check_closing()

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or player_inside:
		return
	player_inside = true
	ensure_loaded()
	_inside_changed()
	_city_signal("entered_shop")

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player") or not player_inside:
		return
	player_inside = false
	_inside_changed()
	_city_signal("left_shop")

func _city_signal(sig: String) -> void:
	var city: Node = owner if owner != null and owner.has_signal(sig) else get_tree().current_scene
	if city != null and city.has_signal(sig):
		city.emit_signal(sig, place)

func _inside_changed() -> void:
	var roof := roof_node()
	if roof != null:
		roof.visible = not player_inside
	for guard in _guard_range:
		if not is_instance_valid(guard):
			continue
		guard.vision_range = _guard_range[guard] if player_inside else 0.0
		if not player_inside:
			guard.reset_suspicion()
	if player_inside:
		_update_near()
	_refresh_gate()

## The building's roof (a node of world/Facades.gd's), or null before the
## street's buildings are up.
func roof_node() -> Node3D:
	var facades := owner.get_node_or_null("Facades") if owner != null else null
	return facades.get_node_or_null("Roof" + _front) as Node3D if facades != null else null

func _update_near() -> void:
	if not loaded:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var centre := global_position + Vector3(0, 0, -5.5)
	var d := Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length()
	var want := player_inside or (d < Facades.WALK_IN_NEAR if not near else d < FAR)
	if want != near:
		_set_near(want)

func _set_near(on: bool) -> void:
	near = on
	for l in get_tree().get_nodes_in_group("walk_in_lights"):
		if is_ancestor_of(l):
			(l as Light3D).visible = on
	var facades := owner.get_node_or_null("Facades") if owner != null else null
	if facades != null:
		facades.set_near(_front, on)
	# The building's occluder would hide the room from the street.
	var occ := owner.get_node_or_null("Cell_Main/Building" + _front + "/Occluder") if owner != null else null
	if occ != null:
		occ.visible = not on

## Shut doorway at closing time -- but never on you: if you're inside when
## it closes, you leave by the door, or are shown out.
func _refresh_gate() -> void:
	var shut := not GameState.is_open(place) and not player_inside
	(get_node("Gate") as CollisionObject3D).collision_layer = 1 if shut else 0
	(get_node("Locked") as CollisionObject3D).collision_layer = 4 if shut else 0


func _check_closing() -> void:
	if _closing or GameState.wanted or GameState.in_custody or GameState.is_open(place):
		return
	_closing = true
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", CLOSING_LINES.pick_random())
	get_tree().create_timer(CLOSING_GRACE).timeout.connect(_show_out)

func _show_out() -> void:
	_closing = false
	if not is_inside_tree() or not player_inside or GameState.wanted or GameState.in_custody:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.dialogue_panel.visible:
		hud.advance_or_close_dialogue()
	player.dialogue_active = false
	var out := get_node("OutsideSpawn") as Marker3D
	player.global_position = out.global_position
	player.reset_physics_interpolation()
	if player.has_method("arrive"):
		player.arrive(out.global_rotation.y + PI)

## Racks of tapes aren't the catalogue's: whatever you haven't got.
func _shuffle_items() -> void:
	if store_id == "music":
		TapeCounter.stock_racks(item_slots)
	else:
		super._shuffle_items()

## The city's the scene you're in, whichever shop the alarm went up in.
func _still_here() -> bool:
	return is_inside_tree()

func _police_parent() -> Node:
	return owner if owner != null else self
