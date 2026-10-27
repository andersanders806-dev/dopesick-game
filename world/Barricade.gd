extends StaticBody3D
## Boards across a gap in the block (the alleys' mouths onto Main Street).
## While any board is up it blocks the way, for you and for the dead; the dead
## tear the boards off one at a time (Zombie3D's tearing state), and once the
## last is gone they come through. You nail them back, one board a press, for
## ZombieMode.POINTS_BOARD each.
##
## The gap stays open in the navmesh (a runtime carve isn't possible), so the
## dead path straight at it and meet the boards: `blocks()` is how a zombie
## knows it has.
##
## Built in code; face the gap along local Z (the boards stand on the XY
## plane, `width` wide).

signal board_torn(barricade: Node3D, boards_left: int)
signal board_repaired(barricade: Node3D, boards_left: int)
## The last board came off.
signal cleared(barricade: Node3D)

const BOARD_COUNT := 6
const REPAIR_GAP := 0.45
## How far from the boards a zombie starts on them.
const TEAR_REACH := 1.15
const InteractableScript := preload("res://interactables/Interactable3D.gd")

@export var width: float = 2.2
var boards: int = BOARD_COUNT
var _planks: Array[MeshInstance3D] = []
var _home: Array[Transform3D] = []
var _shape: CollisionShape3D
var _repair_ready := 0.0

func _ready() -> void:
	add_to_group("barricades")
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.3, 0.3)
	_shape.shape = box
	_shape.position = Vector3(0, 1.15, 0)
	add_child(_shape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.19)
	wood.roughness = 0.92
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in BOARD_COUNT:
		var plank := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width * rng.randf_range(0.9, 1.02), 0.17, 0.05)
		plank.mesh = mesh
		plank.material_override = wood
		plank.name = "Board%d" % i
		var xf := Transform3D(Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-4.0, 4.0))),
			Vector3(rng.randf_range(-0.04, 0.04), 0.3 + i * 0.35, 0.05 if i % 2 == 0 else -0.05))
		add_child(plank)
		plank.transform = xf
		_planks.append(plank)
		_home.append(xf)
	var zone := Area3D.new()
	zone.name = "RepairZone"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	zone.set_meta("prompt", "Rebuild the barricade")
	add_child(zone)
	var zshape := CollisionShape3D.new()
	var zbox := BoxShape3D.new()
	zbox.size = Vector3(width + 0.6, 1.6, 3.2)
	zshape.shape = zbox
	zshape.position = Vector3(0, 0.8, 0)
	zone.add_child(zshape)
	zone.interacted.connect(func(_z: Area3D, player: Node) -> void: repair_board(player as Node3D))

func intact() -> bool:
	return boards > 0

func is_full() -> bool:
	return boards >= BOARD_COUNT

## Whether a body at `pos` moving along `dir` is up against the boards: on
## either side, near, and heading for them.
func blocks(pos: Vector3, dir: Vector3) -> bool:
	if boards <= 0:
		return false
	var local := to_local(pos)
	if absf(local.x) > width * 0.5 + 0.15 or absf(local.z) > TEAR_REACH:
		return false
	var ldir := global_transform.basis.inverse() * dir
	return local.z * ldir.z < 0.0

## Where a zombie stands to work on the boards from `pos`'s side.
func stand_point(pos: Vector3) -> Vector3:
	var local := to_local(pos)
	return to_global(Vector3(clampf(local.x, -width * 0.5 + 0.3, width * 0.5 - 0.3), 0.0, signf(local.z) * 0.85 if local.z != 0.0 else 0.85))

## A zombie rips the top board off. Returns whether there was one.
func tear_board(_by: Node = null) -> bool:
	if boards <= 0:
		return false
	boards -= 1
	var plank := _planks[boards]
	# It drops and lies on the ground in front of the gap.
	var side := signf(plank.position.x + randf_range(-0.3, 0.3))
	var rest := Transform3D(Basis(Vector3.UP, randf_range(-0.6, 0.6)) * Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(side * randf_range(0.0, 0.6), 0.04, randf_range(0.5, 0.9) * (1.0 if randf() < 0.5 else -1.0)))
	if is_inside_tree() and plank.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(plank, "transform", rest, 0.3)
	else:
		plank.transform = rest
	if boards == 0:
		_shape.set_deferred("disabled", true)
		cleared.emit(self)
	board_torn.emit(self, boards)
	return true

## Nails one board back (the lowest gap) and pays for it. False if it's
## whole, you're standing in the gap, or you just did one.
func repair_board(by: Node3D = null, pay := true) -> bool:
	if boards >= BOARD_COUNT:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now < _repair_ready:
		return false
	if by != null:
		var local := to_local(by.global_position)
		if absf(local.z) < 0.45 and absf(local.x) < width * 0.5 + 0.2:
			return false
	_repair_ready = now + REPAIR_GAP
	var plank := _planks[boards]
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(plank, "transform", _home[boards], 0.12)
	else:
		plank.transform = _home[boards]
	boards += 1
	_shape.set_deferred("disabled", false)
	if pay:
		ZombieMode.add_points(ZombieMode.POINTS_BOARD, "board")
	board_repaired.emit(self, boards)
	return true

## All the boards back (the Carpenter power-up pays its own flat bonus).
func repair_all() -> void:
	while boards < BOARD_COUNT:
		_repair_ready = 0.0
		if not repair_board(null, false):
			break
