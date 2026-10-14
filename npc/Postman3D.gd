extends "res://npc/Collector3D.gd"
## The postman on his round (world/City3D.gd sends him when a Silk Lane
## order is due): down the block to the mailbox by your door, a package in
## the slot, and on his way. He doesn't stop for you.

const WALK := 2.2
var target := Vector3.ZERO
var exit := Vector3.ZERO
var _posted := false

func _ready() -> void:
	add_to_group("postman")
	CharacterCast.dress(model, "postman")
	anim = CharacterAnimator.new(model)
	# The uniform's two tells: a blue cap and a mailbag on the hip.
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color(0.12, 0.2, 0.42)
	navy.roughness = 0.7
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.11
	cm.bottom_radius = 0.12
	cm.height = 0.07
	cap.mesh = cm
	cap.material_override = navy
	model.add_child(cap)
	cap.position = Vector3(0, 1.8, 0.0)
	var brim := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.015, 0.1)
	brim.mesh = bm
	brim.material_override = navy
	cap.add_child(brim)
	brim.position = Vector3(0, -0.025, 0.12)
	var bag := MeshInstance3D.new()
	var bag_mesh := BoxMesh.new()
	bag_mesh.size = Vector3(0.12, 0.32, 0.38)
	bag.mesh = bag_mesh
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.4, 0.27, 0.15)
	leather.roughness = 0.8
	bag.material_override = leather
	model.add_child(bag)
	bag.position = Vector3(0.24, 0.95, 0.0)

func _physics_process(delta: float) -> void:
	var goal := exit if _posted else target
	nav_agent.target_position = goal
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 0.6:
		if not _posted:
			_posted = true
			GameState.parcel["posted"] = true
			SFX.play("door", -14.0, 1.6)
		else:
			queue_free()
			return
	var next: Vector3 = nav_agent.get_next_path_position() - global_position
	next.y = 0.0
	velocity = (next if next.length() > 0.05 else to).normalized() * WALK
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	anim.update(speed)
	if speed > 0.1:
		_facing_angle = lerp_angle(_facing_angle, atan2(velocity.x, velocity.z), TURN_SPEED * delta)
		model.rotation.y = _facing_angle

func _on_catch_body_entered(_body: Node) -> void:
	pass
