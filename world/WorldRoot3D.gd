extends Node3D

const NAV_OBSTACLE_GROUP := "nav_obstacles"
const PoliceScene := preload("res://npc/Police3D.tscn")
## How long staff give you to leave once the place closes around you.
const CLOSING_GRACE := 5.0
const CLOSING_LINES := [
	"The lights over the back half go out. \"We're closed. Let's go.\"",
	"\"Closing up. Whatever you're doing, do it outside.\"",
	"Keys rattle at the door. \"We're closed, pal. Out.\"",
]

var _closing: bool = false
## How long the last navmesh bake took (City3D's is the one that matters:
## it's behind the door's fade).
var nav_bake_ms := 0

func _ready() -> void:
	_bake_navigation()
	var spawn_marker := _place_player_at_spawn()
	_restore_saved_position()
	_face_player(spawn_marker)
	_maybe_continue_chase(spawn_marker)
	if GameState.mode == "story":
		Jobs.decorate(self)
	preload("res://world/PlaceAmbience.gd").apply(self)
	# Autosave on arrival, once the room has settled.
	SaveGame.save.call_deferred()

func _process(_delta: float) -> void:
	_check_closing_time()

## A store or the bar closing with you still inside: staff tell you to go,
## and a few seconds later you're shown out onto the street. Not during a
## chase -- the cops take precedence over closing time.
func _check_closing_time() -> void:
	if _closing or GameState.wanted or GameState.in_custody:
		return
	var place := GameState.place_for_scene(scene_file_path)
	if place == "" or GameState.is_open(place):
		return
	_closing = true
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", CLOSING_LINES.pick_random())
	get_tree().create_timer(CLOSING_GRACE).timeout.connect(_show_out)

func _show_out() -> void:
	if not is_inside_tree() or get_tree().current_scene != self or GameState.wanted or GameState.in_custody:
		return
	var player := get_tree().get_first_node_in_group("player")
	for door in find_children("*", "Area3D", true, false):
		if door.get("target_scene") and String(door.target_scene).ends_with("City3D.tscn"):
			if player:
				player.dialogue_active = false
			door.interact(player)
			return

func _bake_navigation() -> void:
	var nav_region := get_node_or_null("NavRegion") as NavigationRegion3D
	if nav_region == null:
		return

	for body in find_children("*", "StaticBody3D", true, false):
		body.add_to_group(NAV_OBSTACLE_GROUP)

	var nav_mesh := new_nav_mesh()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = NAV_OBSTACLE_GROUP

	nav_region.navigation_mesh = nav_mesh
	var t0 := Time.get_ticks_msec()
	nav_region.bake_navigation_mesh(false)
	nav_bake_ms = Time.get_ticks_msec() - t0

## The agent and cell settings every room bakes with (and the City, which
## is baked ahead by build_rooms_3d.gd).
static func new_nav_mesh() -> NavigationMesh:
	# Floors live on layer 5 (value 16) so the player/police bodies and the
	# line-of-sight rays (mask 1) ignore them, but the bake still needs them
	# as the walkable surface.
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_collision_mask = 1 | 16
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.6
	nav_mesh.agent_max_climb = 0.1
	nav_mesh.cell_size = 0.1
	nav_mesh.cell_height = 0.1
	return nav_mesh

func _place_player_at_spawn() -> Marker3D:
	if GameState.pending_spawn == "":
		return null
	var marker := find_child(GameState.pending_spawn, true, false) as Marker3D
	# A walk-in shop's name is a spawn too: just inside its door.
	if marker == null:
		var shop := find_child(GameState.pending_spawn, true, false)
		if shop != null:
			marker = shop.get_node_or_null("SpawnInside") as Marker3D
	var player := get_tree().get_first_node_in_group("player")
	if marker and player:
		player.global_position = marker.global_position
		# A spawn is a teleport, not movement: don't smear it across a tick.
		player.reset_physics_interpolation()
	GameState.pending_spawn = ""
	return marker

## First person: you arrive looking into the room, not at the wall behind the
## door. A spawn marker that is turned says which way; otherwise it is away
## from the door you came through (the nearest one), and with no door near
## (the apartment's bed, the jail cell) towards the middle of what there is to
## use. The story only: Dead Block and Ghetto Wars keep their own start.
func _face_player(marker: Marker3D) -> void:
	if GameState.mode != "story":
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("set_look"):
		return
	var at := player.global_position
	var fwd := Vector3.ZERO
	if marker != null and absf(marker.global_transform.basis.get_euler().y) > 0.01:
		fwd = -marker.global_transform.basis.z
	else:
		var door: Node3D = null
		var best := 5.0
		for d in get_tree().get_nodes_in_group("doors"):
			if d is Node3D and is_ancestor_of(d):
				var dist := Vector2(d.global_position.x - at.x, d.global_position.z - at.z).length()
				if dist < best:
					best = dist
					door = d
		if door != null:
			fwd = at - door.global_position
		else:
			var sum := Vector3.ZERO
			var n := 0
			for i in get_tree().get_nodes_in_group("interactable"):
				if i is Node3D and is_ancestor_of(i) and not i.is_in_group("doors"):
					sum += (i as Node3D).global_position
					n += 1
			if n > 0:
				fwd = sum / n - at
	fwd.y = 0.0
	if fwd.length() > 0.2:
		player.call("set_look", atan2(-fwd.x, -fwd.z), 0.0)

## Continue from the title screen: stand where the save left you.
func _restore_saved_position() -> void:
	if SaveGame.pending_position == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.global_position = SaveGame.pending_position
		player.reset_physics_interpolation()
	SaveGame.pending_position = null

## Mirrors WorldRoot.gd's 2D chase-persistence fix: a room is a fully
## separate scene, so a pursuing officer doesn't survive a door crossing on
## its own. Spawn a fresh one beside wherever the player just walked in, as
## long as they're still wanted, so the chase follows them room to room.
func _maybe_continue_chase(spawn_marker: Marker3D) -> void:
	if GameState.mode != "story" or not GameState.wanted or GameState.in_custody:
		return
	if get_tree().get_first_node_in_group("police") != null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var police := PoliceScene.instantiate()
	add_child(police)
	var base_pos: Vector3 = spawn_marker.global_position if spawn_marker else player.global_position
	police.global_position = base_pos + Vector3(1.2, 0, -1.2)
	police.reset_physics_interpolation()
