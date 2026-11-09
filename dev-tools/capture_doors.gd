extends "res://dev-tools/pilot.gd"
## The pilot plus what the door captures need (see .pilot/proto_doors/):
##   clearpeople                 no pedestrians, scheduled people or cops in the street
##   customer <x> <z0> <z1>      a customer (Rocketbox, walking clip) walks from z0 to z1 at x, through whatever door is there
##   tpl <x> <z> <yaw>           stand there looking that way (yaw deg, 0 = -Z)
##   doorinfo                    log every hinged door's state
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_doors.gd -- "clock 17:00" "scene City3D" ...

const CastScript := preload("res://npc/CharacterCast.gd")
const LookScript := preload("res://npc/CharacterLook.gd")
const AnimScript := preload("res://npc/CharacterAnimator.gd")

func _do(step: String) -> bool:
	var parts := step.split(" ", false)
	var cmd := parts[0].to_lower() if not parts.is_empty() else ""
	match cmd:
		"clearpeople":
			for grp in ["pedestrians", "scheduled_people", "patrol", "police"]:
				for n in get_nodes_in_group(grp):
					n.queue_free()
			if current_scene.has_method("set"):
				current_scene.set("_patrol_timer", 99999.0)
			await _wait(0.3)
			return true
		"tpl":
			if player():
				player().global_position = Vector3(float(parts[1]), player().global_position.y, float(parts[2]))
				player().set_look(deg_to_rad(float(parts[3])), 0.0)
			await _wait(0.5)
			return true
		"customer":
			await _customer(float(parts[1]), float(parts[2]), float(parts[3]))
			return true
		"doorinfo":
			for d in get_nodes_in_group("hinged_doors"):
				log_line("door %s kind=%s at=%s angle=%.1f locked=%s closed=%s" % [d.get_path(), d.kind, d.global_position.snapped(Vector3.ONE * 0.1), rad_to_deg(d.angle), d.locked, d.is_closed()])
			return true
	return await super._do(step)

func _customer(x: float, z0: float, z1: float) -> void:
	var npc := CharacterBody3D.new()
	npc.collision_layer = 8
	npc.collision_mask = 1
	npc.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.1
	cs.shape = cap
	cs.position.y = 0.55
	npc.add_child(cs)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 1.5
	npc.add_child(holder)
	var model: Node = CastScript.scene_for(CastScript.model_for("pedestrian")).instantiate()
	holder.add_child(model)
	LookScript.apply(model, CastScript.look_for("pedestrian"))
	var anim = AnimScript.new(model)
	anim.play("walk", 1.0)
	current_scene.add_child(npc)
	npc.global_position = Vector3(x, 0.0, z0)
	var dir := -1.0 if z1 < z0 else 1.0
	holder.rotation.y = 0.0 if dir < 0 else PI
	var t0 := Time.get_ticks_msec()
	while (npc.global_position.z - z1) * dir < 0.0 and Time.get_ticks_msec() - t0 < 20000:
		await physics_frame
		npc.velocity = Vector3(0, 0, dir * 1.2)
		npc.move_and_slide()
		await process_frame
	npc.queue_free()
