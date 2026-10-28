extends CharacterBody3D
## A stand-in for npc/Zombie3D.gd in the weapon tests: the same take_hit /
## hit / died / is_alive surface and the same kind of hit zones (Area3Ds on
## layer 64 carrying meta "part" and "zombie"), but no model, nav or brain.
## It has a capsule round it on the world layer like the real one, which a
## shot must look through to reach the hit zones.

signal died(zombie: Node, part: String, melee: bool)
signal hit(zombie: Node, part: String, damage: float, killed: bool)

var health := 150.0
var max_health := 150.0
var alive := true
var last_part := ""
var last_weapon: Resource
var hits: Array = []
var hitboxes := {}

## A zombie with a round's health (ZombieMode.zombie_health(round)).
static func make(parent: Node, at: Vector3, round_no := 1) -> CharacterBody3D:
	var z := CharacterBody3D.new()
	z.set_script(load("res://dev-tools/test_zombie_double.gd"))
	z.health = float(ZombieMode.zombie_health(round_no))
	z.max_health = z.health
	parent.add_child(z)
	z.global_position = at
	return z

func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	_box("head", 1.68, 0.12, 0.3)
	_box("neck", 1.52, 0.07, 0.2)
	_box("torso", 1.1, 0.2, 0.7)
	_box("upper_leg_l", 0.6, 0.1, 0.5)
	_box("lower_leg_l", 0.2, 0.08, 0.4)
	_box("upper_arm_r", 1.2, 0.06, 0.4, 0.3)

func _box(part: String, y: float, radius: float, height: float, x := 0.0) -> void:
	var area := Area3D.new()
	area.name = "Hit_" + part
	area.collision_layer = 64
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("part", part)
	area.set_meta("zombie", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.01)
	cs.shape = cap
	area.add_child(cs)
	add_child(area)
	area.position = Vector3(x, y, 0)
	hitboxes[part] = area

func take_hit(part: String, dmg: float, _dir: Vector3, weapon: Resource = null, melee := false) -> void:
	if not alive:
		return
	if weapon != null and weapon.get("melee") == true:
		melee = true
	last_part = part
	last_weapon = weapon
	if ZombieMode.insta_kill:
		dmg = maxf(dmg, health)
	health -= dmg
	var killed := health <= 0.0
	hits.append([part, dmg])
	hit.emit(self, part, dmg, killed)
	if killed:
		alive = false
		remove_from_group("zombies")
		collision_layer = 0
		for p in hitboxes:
			(hitboxes[p] as Area3D).collision_layer = 0
		died.emit(self, part, melee)

func is_alive() -> bool:
	return alive
