extends StaticBody3D
## Something a bullet can hit. A capsule on its own physics layer, so it
## stops rounds without getting in the way of anything else: the player and
## police collide on layers 1/2/8 and the guards' line-of-sight rays use
## mask 1, none of which see layer 32.
##
## The owner (a cop, a clerk, a patron) implements
##     take_damage(amount: float, hit_pos: Vector3, from: Vector3) -> bool
## returning true when that hit killed them.

const LAYER := 32
## Anything struck above this height (from the owner's feet) is the head.
## The cast stands 1.68-1.75 m tall.
const HEAD_HEIGHT := 1.45
const HEADSHOT_MULTIPLIER := 2.5

var target: Node3D

## Adds a hitbox to `parent`, forwarding hits to `target` (usually the same
## node). `height` is how tall the capsule stands; a seated patron is shorter.
static func attach(parent: Node3D, target_node: Node3D, height := 1.8, radius := 0.3) -> StaticBody3D:
	var box: StaticBody3D = load("res://npc/Hitbox3D.gd").new()
	box.name = "Hitbox"
	box.collision_layer = LAYER
	box.collision_mask = 0
	box.target = target_node
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position = Vector3(0, height * 0.5, 0)
	box.add_child(shape)
	parent.add_child(box)
	return box

## Returns {"killed": bool, "headshot": bool} for the shooter's hitmarker.
func hit(damage: float, hit_pos: Vector3, from: Vector3) -> Dictionary:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return {"killed": false, "headshot": false}
	var headshot := hit_pos.y - global_position.y >= HEAD_HEIGHT
	var amount := damage * (HEADSHOT_MULTIPLIER if headshot else 1.0)
	var killed: bool = target.take_damage(amount, hit_pos, from)
	return {"killed": killed, "headshot": headshot}

func disable() -> void:
	collision_layer = 0
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
