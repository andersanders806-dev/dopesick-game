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

func _ready() -> void:
	_bake_navigation()
	var spawn_marker := _place_player_at_spawn()
	_restore_saved_position()
	_maybe_continue_chase(spawn_marker)
	Jobs.decorate(self)
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

	# Floors live on layer 5 (value 16) so the player/police bodies and the
	# line-of-sight rays (mask 1) ignore them, but the bake still needs them
	# as the walkable surface.
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1 | 16
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = NAV_OBSTACLE_GROUP
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.6
	nav_mesh.agent_max_climb = 0.1
	nav_mesh.cell_size = 0.1
	nav_mesh.cell_height = 0.1

	nav_region.navigation_mesh = nav_mesh
	nav_region.bake_navigation_mesh(false)
	_frame_camera(nav_mesh)

## Tell the player's camera how big the walkable room is.
func _frame_camera(nav_mesh: NavigationMesh) -> void:
	var verts := nav_mesh.get_vertices()
	var player := get_tree().get_first_node_in_group("player")
	if verts.is_empty() or player == null or not player.has_method("set_room_bounds"):
		return
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	player.set_room_bounds(box.grow(0.6))

func _place_player_at_spawn() -> Marker3D:
	if GameState.pending_spawn == "":
		return null
	var marker := find_child(GameState.pending_spawn, true, false) as Marker3D
	var player := get_tree().get_first_node_in_group("player")
	if marker and player:
		player.global_position = marker.global_position
		# A spawn is a teleport, not movement: don't smear it across a tick.
		player.reset_physics_interpolation()
	GameState.pending_spawn = ""
	return marker

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
	if not GameState.wanted or GameState.in_custody:
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
