extends RefCounted
## The rooms were built to be seen from up over them (build_rooms_3d.gd's
## _room_shell): no ceiling, and a front wall cut down to LOW_WALL_H so it
## never hides you. From your own eyes that's a room with the lid off and
## a hole along one side, so in first person each room gets a ceiling and
## its front wall back at full height. Rooms without that shell -- the
## street, the lot out back -- are left open to the sky.

const WALL_H := 2.4
const CEILING_NAME := "FPCeiling"

static func apply(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var south := scene.get_node_or_null("WallSouth") as StaticBody3D
	var floor_body := scene.get_node_or_null("Floor") as StaticBody3D
	if south == null or floor_body == null:
		return
	var mesh := south.get_node_or_null("Mesh") as MeshInstance3D
	if mesh and mesh.mesh is BoxMesh:
		var box := mesh.mesh as BoxMesh
		if not mesh.has_meta("fp_low_size"):
			mesh.set_meta("fp_low_size", box.size)
			mesh.set_meta("fp_low_pos", mesh.position)
		var shape := _box_size(south)
		if on and shape != Vector3.ZERO:
			# Its own copy: the mesh resource may be shared with other walls.
			mesh.mesh = box.duplicate()
			(mesh.mesh as BoxMesh).size = shape
			mesh.position = Vector3.ZERO
		elif not on:
			(mesh.mesh as BoxMesh).size = mesh.get_meta("fp_low_size")
			mesh.position = mesh.get_meta("fp_low_pos")
	var lid := scene.get_node_or_null(CEILING_NAME)
	if on and lid == null:
		var size := _box_size(floor_body)
		if size == Vector3.ZERO:
			return
		lid = MeshInstance3D.new()
		lid.name = CEILING_NAME
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x + 0.4, 0.1, size.z + 0.4)
		var plaster := StandardMaterial3D.new()
		plaster.albedo_color = Color(0.32, 0.30, 0.28)
		plaster.roughness = 0.95
		slab.material = plaster
		lid.mesh = slab
		# The rooms are lit from inside; a lid that cast shadows would black
		# out whatever light the scene brings in from above.
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(lid)
		lid.global_position = Vector3(floor_body.global_position.x, WALL_H + 0.05, floor_body.global_position.z)
	elif not on and lid != null:
		lid.queue_free()
		scene.remove_child(lid)

static func _box_size(body: StaticBody3D) -> Vector3:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			return (c.shape as BoxShape3D).size
	return Vector3.ZERO
