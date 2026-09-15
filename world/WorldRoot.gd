extends Node2D

const NAV_OBSTACLE_GROUP := "nav_obstacles"

func _ready() -> void:
	_bake_navigation()
	_place_player_at_spawn()

func _bake_navigation() -> void:
	var nav_region := get_node_or_null("NavRegion") as NavigationRegion2D
	if nav_region == null:
		return

	var top_left := Vector2(4, 4)
	var bottom_right := Vector2(476, 316)
	var floor_rect := get_node_or_null("Floor") as ColorRect
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

func _place_player_at_spawn() -> void:
	if GameState.pending_spawn == "":
		return
	var marker := find_child(GameState.pending_spawn, true, false)
	var player := get_tree().get_first_node_in_group("player")
	if marker and player:
		player.global_position = marker.global_position
	GameState.pending_spawn = ""
