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

var place := ""
var player_inside := false
var near := false
var _front := ""
var _guard_range := {}
var _poll := 0.0
var _inert := false

func _ready() -> void:
	place = String(get_meta("place", ""))
	for front in Facades.WALK_INS:
		if Facades.WALK_INS[front]["node"] == String(name):
			_front = front
	if GameState.mode == "zombies":
		_go_inert()
		return
	_setup_store()
	_wire_guards()
	_shuffle_items()
	if store_id == "music":
		TapeCounter.wire_zones(self)
	# Inside, the lamps are on a layer of their own, so a lamp in the shop
	# never lights the street: everything here is on it as well as layer 1.
	for n in find_children("*", "VisualInstance3D", true, false):
		if not (n is Light3D):
			(n as VisualInstance3D).layers = 3
	for guard in get_tree().get_nodes_in_group("guards"):
		if is_ancestor_of(guard):
			_guard_range[guard] = guard.vision_range
			guard.vision_range = 0.0
	var inside := get_node("Inside") as Area3D
	inside.body_entered.connect(_on_body_entered)
	inside.body_exited.connect(_on_body_exited)
	GameState.clock_changed.connect(func(_m): _refresh_gate())
	_refresh_gate()
	_set_near(false)

## Dead Block has no shopkeepers: the rooms stand empty and open.
func _go_inert() -> void:
	_inert = true
	for n in get_children():
		if n.is_in_group("guards") or n is Area3D and n.name != "Inside" or n.name.begins_with("Pawnbroker"):
			n.queue_free()
	for n in ["Gate"]:
		if has_node(n):
			(get_node(n) as CollisionObject3D).collision_layer = 0
	set_process(false)

## Frames cost nothing here: the roof, the lamps and the guards change on the
## step, not every frame.
func _process(delta: float) -> void:
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
	player.global_position = (get_node("OutsideSpawn") as Marker3D).global_position
	player.reset_physics_interpolation()

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
