extends SkeletonModifier3D
## The left hand of an armed man on the gun's foregrip (Ghetto Wars). The aim pose holds a pistol with both
## hands; a rifle's foregrip is a forearm further out, so after the animation this reaches the left arm there with a
## two-bone solve (law of cosines, elbow pole down and out), and closes the fingers round it. Everything is in the
## skeleton's own units; the gun's pose is derived from the right hand's bone, not read off the node (which would
## trail a frame behind).

const GRIP_CURL := [48.0, 60.0, 40.0]
const THUMB_CURL := [8.0, 12.0]

## Foregrip in the gun's space (metres) and how the gun sits in the right hand (see npc/Gangster3D.gd).
var fore_m := Vector3(0, -0.04, -0.2)
var gun_pos := Vector3.ZERO
var gun_quat := Quaternion.IDENTITY
var unit := 0.015
## 0 off, 1 fully on the grip.
var weight := 1.0

var _bones := {}
var _lens := Vector2.ZERO
var _ready_bones := false

func _bind() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_bones = {"rh": sk.find_bone("Bip01 R Hand"), "up": sk.find_bone("Bip01 L UpperArm"), "fo": sk.find_bone("Bip01 L Forearm"),
		"ha": sk.find_bone("Bip01 L Hand")}
	var ou := sk.get_bone_global_rest(_bones["up"]).origin
	var of := sk.get_bone_global_rest(_bones["fo"]).origin
	var oh := sk.get_bone_global_rest(_bones["ha"]).origin
	_lens = Vector2(ou.distance_to(of), of.distance_to(oh))
	_ready_bones = true

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or weight <= 0.0:
		return
	if not _ready_bones:
		_bind()
	var rh: Transform3D = sk.get_bone_global_pose(_bones["rh"])
	var target: Vector3 = rh * (gun_pos / unit + Basis(gun_quat) * (fore_m / unit))
	var up_t: Transform3D = sk.get_bone_global_pose(_bones["up"])
	var sh := up_t.origin
	var cur_hand: Vector3 = sk.get_bone_global_pose(_bones["ha"]).origin
	target = cur_hand.lerp(target, weight)
	var l1 := _lens.x
	var l2 := _lens.y
	var to_t := target - sh
	var reach := (l1 + l2) * 0.985
	if to_t.length() > reach:
		to_t = to_t.normalized() * reach
		target = sh + to_t
	var d := maxf(to_t.length(), absf(l1 - l2) + 0.5)
	var dir := to_t / maxf(to_t.length(), 0.0001)
	# The elbow drops and goes out to the left of the body (skeleton space: the pose's own elbow side).
	var cur_elbow: Vector3 = sk.get_bone_global_pose(_bones["fo"]).origin
	var pole := cur_elbow - (sh + dir * (cur_elbow - sh).dot(dir))
	if pole.length() < 0.001:
		pole = Vector3.UP
	pole = pole.normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var elbow := sh + dir * along + pole * h
	var up_rest := sk.get_bone_global_rest(_bones["up"])
	var fo_rest := sk.get_bone_global_rest(_bones["fo"])
	var ha_rest := sk.get_bone_global_rest(_bones["ha"])
	sk.set_bone_global_pose(_bones["up"], Transform3D(_aim(up_rest.basis, (elbow - sh).normalized()), sh))
	sk.set_bone_global_pose(_bones["fo"], Transform3D(_aim(fo_rest.basis, (target - elbow).normalized()), elbow))
	sk.set_bone_global_pose(_bones["ha"], Transform3D(_aim(ha_rest.basis, (target - elbow).normalized()), target))
	_curl(sk)

static func _aim(rest: Basis, dir: Vector3) -> Basis:
	var x := rest.x.normalized()
	var q := Quaternion(x, dir) if x.dot(dir) > -0.9999 else Quaternion(rest.y.normalized(), PI)
	return Basis(q) * rest

func _curl(sk: Skeleton3D) -> void:
	for f in 5:
		var base := "Bip01 L Finger%d" % f
		for k in 3:
			var idx := sk.find_bone(base + ("" if k == 0 else str(k)))
			if idx < 0:
				continue
			var ang: float = (THUMB_CURL[mini(k, 1)] if f == 0 else GRIP_CURL[k]) * weight
			var rest_local := sk.get_bone_rest(idx)
			sk.set_bone_pose_rotation(idx, (rest_local.basis * Basis(Vector3.BACK, deg_to_rad(ang))).get_rotation_quaternion())
