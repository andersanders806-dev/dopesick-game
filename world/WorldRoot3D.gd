extends Node3D

const NAV_OBSTACLE_GROUP := "nav_obstacles"
const PoliceScene := preload("res://npc/Police3D.tscn")

func _ready() -> void:
	_bake_navigation()
	var spawn_marker := _place_player_at_spawn()
	_maybe_continue_chase(spawn_marker)

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

func _place_player_at_spawn() -> Marker3D:
	if GameState.pending_spawn == "":
		return null
	var marker := find_child(GameState.pending_spawn, true, false) as Marker3D
	var player := get_tree().get_first_node_in_group("player")
	if marker and player:
		player.global_position = marker.global_position
	GameState.pending_spawn = ""
	return marker

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
