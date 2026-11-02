extends SkeletonModifier3D
## Short hit reactions on top of whatever the animation is playing: the head snaps
## back, a shoulder twists, the spine bends, the pelvis dips when a leg is hit. Each kick
## is a rotation about an axis (skeleton space) on one bone that decays in about a third
## of a second. The modifier switches itself off when nothing is left to play.

const MAX_KICKS := 12

## Each: {bone, axis, angle, t, dur}
var _kicks: Array = []

func _ready() -> void:
	active = false

## Turns `bone` by `angle` radians about `axis` (skeleton space), easing back over `dur`.
func kick(bone: int, axis: Vector3, angle: float, dur := 0.38) -> void:
	if bone < 0 or axis.length() < 0.001:
		return
	if _kicks.size() >= MAX_KICKS:
		_kicks.pop_front()
	_kicks.append({"bone": bone, "axis": axis.normalized(), "angle": angle, "t": 0.0, "dur": dur})
	active = true

func busy() -> bool:
	return not _kicks.is_empty()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var dt := get_process_delta_time()
	var keep: Array = []
	for k in _kicks:
		k["t"] += dt
		var u: float = k["t"] / k["dur"]
		if u >= 1.0:
			continue
		keep.append(k)
		# Snap on fast, ease back slowly.
		var a: float = k["angle"] * (1.0 - u) * (1.0 - u) * minf(u * 9.0, 1.0) * (1.0 + 0.25 * (1.0 - u))
		var b: int = k["bone"]
		var g := sk.get_bone_global_pose(b)
		var pb := sk.get_bone_parent(b)
		var pbasis := sk.get_bone_global_pose(pb).basis if pb >= 0 else Basis()
		var nb := Basis(k["axis"], a) * g.basis
		sk.set_bone_pose_rotation(b, (pbasis.inverse() * nb).orthonormalized().get_rotation_quaternion())
	_kicks = keep
	if _kicks.is_empty():
		active = false
