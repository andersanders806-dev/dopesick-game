extends Node2D

const NAV_OBSTACLE_GROUP := "nav_obstacles"
const PoliceScene := preload("res://npc/Police.tscn")

func _ready() -> void:
	_bake_navigation()
	var spawn_marker := _place_player_at_spawn()
	_maybe_continue_chase(spawn_marker)

func _bake_navigation() -> void:
	var nav_region := get_node_or_null("NavRegion") as NavigationRegion2D
	if nav_region == null:
		return

	var top_left := Vector2(4, 4)
	var bottom_right := Vector2(476, 316)
	var floor_rect := get_node_or_null("Floor") as Control
	if floor_rect:
		top_left = Vector2(floor_rect.offset_left, floor_rect.offset_top) + Vector2(4, 4)
		bottom_right = Vector2(floor_rect.offset_right, floor_rect.offset_bottom) - Vector2(4, 4)

	# Obstacles (walls, shelves) live as siblings of NavRegion, not children of
	# it, so the default root-node-children scan finds nothing to carve out.
	# Group them explicitly so baking can find their colliders anywhere in
	# the room.
	for body in find_children("*", "StaticBody2D", true, false):
		body.add_to_group(NAV_OBSTACLE_GROUP)

	var nav_poly := NavigationPolygon.new()
	nav_poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_poly.parsed_collision_mask = 1
	nav_poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_poly.source_geometry_group_name = NAV_OBSTACLE_GROUP
	nav_poly.agent_radius = 12.0
	nav_poly.add_outline(PackedVector2Array([
		top_left,
		Vector2(bottom_right.x, top_left.y),
		bottom_right,
		Vector2(top_left.x, bottom_right.y),
	]))

	nav_region.navigation_polygon = nav_poly
	nav_region.bake_navigation_polygon(false)

func _place_player_at_spawn() -> Marker2D:
	if GameState.pending_spawn == "":
		return null
	var marker := find_child(GameState.pending_spawn, true, false) as Marker2D
	var player := get_tree().get_first_node_in_group("player")
	if marker and player:
		player.global_position = marker.global_position
	GameState.pending_spawn = ""
	return marker

## A police chase doesn't end just because you ducked through a door: the
## room the officer was in gets torn down along with the rest of the scene,
## so without this, escaping mid-chase (before the 4s line-of-sight give-up)
## would strand `GameState.wanted` true forever with nobody left to clear it
## -- silently locking the player out of sleeping in the Apartment for the
## rest of the run. Spawning a fresh pursuer next to wherever the player
## just walked in keeps the chase alive room to room until they actually
## lose it or get caught.
func _maybe_continue_chase(spawn_marker: Marker2D) -> void:
	if not GameState.wanted:
		return
	if get_tree().get_first_node_in_group("police") != null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var police := PoliceScene.instantiate()
	add_child(police)
	var base_pos: Vector2 = spawn_marker.global_position if spawn_marker else player.global_position
	police.global_position = base_pos + Vector2(40, -40)
