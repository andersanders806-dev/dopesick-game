extends Node3D

const NAV_OBSTACLE_GROUP := "nav_obstacles"
const PoliceScene := preload("res://npc/Police3D.tscn")

## Rooms were built for a camera 9 m overhead: south walls cut down to
## knee height so they never hid the player, and no ceilings. Seen from
## eye level those read as a missing wall and an open sky, so they're
## restored here at load rather than by rebuilding every scene.
const WALL_HEIGHT := 2.4
const CEILING_COLOR := Color(0.16, 0.15, 0.14)
## An officer arrives this long after the first shot.
const ARMED_RESPONSE_TIME := 3.0
## Backup after a cop goes down, and how many can be on scene at once.
const REINFORCEMENT_TIME := 6.0
const MAX_POLICE := 4
## Lethal heat with nobody left hunting you burns off after this long.
const HEAT_COOLDOWN := 25.0

var _heat_timer: float = 0.0
var _response_pending: bool = false

func _ready() -> void:
	_adapt_for_first_person()
	_bake_navigation()
	var spawn_marker := _place_player_at_spawn()
	_face_player_into_room()
	_maybe_continue_chase(spawn_marker)
	GameState.lethal_changed.connect(_on_lethal_changed)
	GameState.police_killed.connect(_on_police_killed)
	# The main menu borrows the street as a backdrop, with no player in it.
	if get_tree().get_first_node_in_group("player") != null:
		GameState.run_active = true
		GameState.run_started = true

func _physics_process(delta: float) -> void:
	if not GameState.lethal or GameState.in_custody:
		_heat_timer = 0.0
		return
	if get_tree().get_first_node_in_group("police") != null or _response_pending:
		_heat_timer = 0.0
		return
	_heat_timer += delta
	if _heat_timer >= HEAT_COOLDOWN:
		_heat_timer = 0.0
		GameState.set_wanted(false)

func _adapt_for_first_person() -> void:
	if not has_node("WallNorth"):
		return  # the street has no walls or roof to fix
	for body in find_children("*South*", "StaticBody3D", true, false):
		var mesh_node := body.get_node_or_null("Mesh") as MeshInstance3D
		var shape_node: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_node = c
		if mesh_node == null or shape_node == null or not (mesh_node.mesh is BoxMesh) or not (shape_node.shape is BoxShape3D):
			continue
		var full: Vector3 = (shape_node.shape as BoxShape3D).size
		var box := (mesh_node.mesh as BoxMesh).duplicate() as BoxMesh
		box.size = full
		mesh_node.mesh = box
		mesh_node.position = shape_node.position
	var floor_body := get_node_or_null("Floor")
	if floor_body == null:
		return
	for c in floor_body.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var size: Vector3 = c.shape.size
			var ceiling := MeshInstance3D.new()
			ceiling.name = "Ceiling"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(size.x + 0.4, 0.1, size.z + 0.4)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = CEILING_COLOR
			mat.roughness = 1.0
			mesh.material = mat
			ceiling.mesh = mesh
			# Lights mounted up near the ceiling still have to reach the room.
			ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ceiling)
			ceiling.global_position = Vector3(floor_body.global_position.x, WALL_HEIGHT + 0.05, floor_body.global_position.z)
			break

## Walking through a door you should be looking into the room, not at the
## back of it. Rooms are centred on their origin; the street faces along its
## length.
func _face_player_into_room() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("set_look"):
		return
	var to_center: Vector3 = global_position - player.global_position
	to_center.y = 0.0
	if to_center.length() < 0.5:
		return
	player.set_look(atan2(-to_center.x, -to_center.z))

func _on_lethal_changed(is_lethal: bool) -> void:
	if is_lethal and get_tree().get_first_node_in_group("police") == null:
		_call_police(ARMED_RESPONSE_TIME)

func _on_police_killed() -> void:
	_call_police(REINFORCEMENT_TIME)

func _call_police(delay: float) -> void:
	if _response_pending:
		return
	_response_pending = true
	var tree := get_tree()
	var room := self
	tree.create_timer(delay).timeout.connect(func():
		if not is_instance_valid(room):
			return
		room._response_pending = false
		if tree.current_scene != room or not GameState.wanted or GameState.in_custody:
			return
		if tree.get_nodes_in_group("police").size() >= MAX_POLICE:
			return
		var police := PoliceScene.instantiate()
		room.add_child(police)
		police.global_position = room._police_entry_point())

## Where backup comes in: the room's own police marker if it has one, the
## station steps out on the street, or else the way you came in.
func _police_entry_point() -> Vector3:
	for marker_name in ["PoliceSpawn", "SpawnFromJail"]:
		var m := find_child(marker_name, true, false) as Node3D
		if m:
			return m.global_position
	for door in get_tree().get_nodes_in_group("interactable"):
		if "target_scene" in door and is_ancestor_of(door):
			return door.global_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player.global_position + Vector3(4, 0, 4) if player else global_position

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
