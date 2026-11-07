extends Node
## Aim assist for the pad, the three things Call of Duty does (and never for the mouse):
##
##   friction     with the crosshair inside a bubble round a zombie's head or torso the look slows to
##                FRICTION of its speed, so the stick settles on it instead of skating past
##   rotation     a zombie that crosses the crosshair (it walks, or you strafe) drags the view along
##                with it by ROTATION of its own apparent movement, while you move or look
##   ADS pull     when you go down the sights with a zombie within SNAP_DEG of the crosshair the view
##                is pulled onto its head or torso, less the further away it is; once, as the sights
##                come up, never while they are up
##
## Ignored: dead zombies, anything beyond the gun's reach (REACH), anything with a wall between (a ray
## from the eye), and every input that is not the pad (the last thing touched must be a pad button or
## stick, not the mouse or a key). Off / Precision / Standard is Settings > Aim assist: Precision is
## the lighter set with no ADS pull.
##
## Child of the WeaponHolder (which adds it); Player3D.pad_look() hands each frame's look to adjust()
## as (right, up) in radians and gets it back. Zombies come from the group "zombies"; the hit zones sit
## where the animation has them only after sync_hitboxes(), which is called for the few zombies nearest
## the crosshair (the cheap prefilter uses their position), never for all of them.

## Per mode: look speed over a target, share of a target's apparent movement followed, the ADS pull's
## strength (0: none).
const MODES := {
	1: {"friction": 0.78, "rotation": 0.25, "snap": 0.0},
	2: {"friction": 0.6, "rotation": 0.4, "snap": 1.0},
}
## Metres a gun reaches for the assist, by family (default DEFAULT_REACH).
const REACH := {"pistol": 18.0, "smg": 20.0, "shotgun": 9.0, "ar": 34.0, "lmg": 30.0, "sniper": 60.0, "magnum": 26.0, "wonder": 24.0}
const DEFAULT_REACH := 20.0
## Bubble round a zone's centre, metres (zone + margin), and the least it is in degrees far away.
const BUBBLE_TORSO := 0.45
const BUBBLE_HEAD := 0.3
const BUBBLE_MIN_DEG := 1.4
## How far from the crosshair a zombie is worth looking at (degrees, plus its own width).
const CANDIDATE_DEG := 12.0
const MAX_CANDIDATES := 3
## The ADS pull: degrees from the crosshair it works within, seconds it takes to arrive, its share of
## the gap close to and at the gun's reach.
const SNAP_DEG := 6.0
const SNAP_TIME := 0.05
const SNAP_NEAR := 0.85
const SNAP_FAR := 0.35
## Rotation never turns the view faster than this (rad/s): a zombie swapped for another is not a jump.
const MAX_FOLLOW := 2.2

var holder: Node
var player: Node3D
## What the last frame did, for the tests and the debug eye: the bubble weight (0..1), the multiplier
## on the player's look, the radians added by rotation and by the pull.
var last_weight := 0.0
var last_friction := 1.0
var last_rotation := Vector2.ZERO
var last_pull := Vector2.ZERO
## The zombie the crosshair is in the bubble of, or null.
var target: Node3D
## Whether the pad was the last thing touched.
var source_pad := false

var _prev: Dictionary = {}
var _aiming_prev := false
var _snap := Vector2.ZERO
var _los_cache: Dictionary = {}

func _init() -> void:
	name = "AimAssist"

func _ready() -> void:
	holder = get_parent()
	player = holder.get("player") as Node3D
	if player != null:
		player.set("assist", self)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		source_pad = true
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.25:
			source_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		source_pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 0.0:
		source_pad = false

## Whether the assist is working: it is on, and the pad is what is being used.
func enabled() -> bool:
	return Graphics.aim_assist != Graphics.ASSIST_OFF and source_pad

func reach() -> float:
	var d = holder.get("current") if holder != null else null
	return float(REACH.get(d.family(), DEFAULT_REACH)) if d != null else DEFAULT_REACH

## The look this frame (right, up in radians) with the assist in it. `active` is whether the player is
## moving or looking at all; `delta` the frame's seconds.
func adjust(look: Vector2, delta: float, active: bool) -> Vector2:
	last_weight = 0.0
	last_friction = 1.0
	last_rotation = Vector2.ZERO
	last_pull = Vector2.ZERO
	target = null
	var aiming: bool = holder != null and holder.get("aiming") == true
	var was_aiming := _aiming_prev
	_aiming_prev = aiming
	if not enabled() or player == null or delta <= 0.0:
		_prev.clear()
		_snap = Vector2.ZERO
		return look
	var cam := player.get("camera") as Camera3D
	if cam == null:
		return look
	var mode: Dictionary = MODES[Graphics.aim_assist]
	var eye := cam.global_position
	var yaw: float = player.get("_look_yaw")
	var pitch: float = player.get("_look_pitch")
	var cands := _candidates(eye, yaw, pitch)
	_los_cache.clear()
	var seen := {}
	var best: Dictionary = {}
	var best_angle := INF
	for c in cands:
		var z: Node3D = c.zombie
		var pts := _points(z)
		var dist := eye.distance_to(pts.torso)
		if dist > reach() or not _visible(eye, pts, z):
			continue
		var id := z.get_instance_id()
		var tor := _angles(eye, pts.torso)
		var cur := Vector2(tor.x, tor.y)
		seen[id] = cur
		# The crosshair's distance to each zone, against its bubble.
		for part in ["head", "torso"]:
			var p: Vector3 = pts[part]
			var off := _offset(eye, p, yaw, pitch)
			var ang := rad_to_deg(off.length())
			var r := maxf(rad_to_deg(atan(((BUBBLE_HEAD if part == "head" else BUBBLE_TORSO)) / maxf(dist, 0.5))), BUBBLE_MIN_DEG)
			var w := 1.0 - smoothstep(r * 0.55, r, ang)
			if w > 0.0 and ang < best_angle:
				best_angle = ang
				best = {"zombie": z, "weight": w, "id": id, "dist": dist, "cur": cur, "bubble": r}
	# Friction: slows what the player put in, never what the assist adds.
	var out := look
	if not best.is_empty():
		target = best.zombie
		last_weight = best.weight
		last_friction = lerpf(1.0, float(mode.friction), best.weight)
		out = look * last_friction
		# Rotation: the target's own apparent movement since last frame, while the player is at it.
		if active and _prev.has(best.id):
			var d: Vector2 = best.cur - (_prev[best.id] as Vector2)
			var follow := Vector2(-wrapf(d.x, -PI, PI), d.y) * float(mode.rotation)
			var cap := MAX_FOLLOW * delta
			follow = Vector2(clampf(follow.x, -cap, cap), clampf(follow.y, -cap, cap))
			last_rotation = follow
			out += follow
	_prev = seen
	# The pull as the sights come up.
	if aiming and not was_aiming and float(mode.snap) > 0.0:
		_snap = _pull_for(eye, yaw, pitch, cands) * float(mode.snap)
	elif not aiming:
		_snap = Vector2.ZERO
	if _snap.length_squared() > 0.0:
		var step := _snap * (1.0 - exp(-delta / SNAP_TIME))
		_snap -= step
		if _snap.length() < 0.0002:
			_snap = Vector2.ZERO
		last_pull = step
		out += step
	return out

## Where the sights-up pull would take the view from here: the gap to the nearest head or torso
## within SNAP_DEG, as a share by distance. (right, up) radians; zero when there is nothing to pull to.
func _pull_for(eye: Vector3, yaw: float, pitch: float, cands: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_ang := INF
	var best_k := 0.0
	for c in cands:
		var z: Node3D = c.zombie
		var pts := _points(z)
		var dist := eye.distance_to(pts.torso)
		if dist > reach() or not _visible(eye, pts, z):
			continue
		for part in ["head", "torso"]:
			var off := _offset(eye, pts[part], yaw, pitch)
			var ang := rad_to_deg(off.length())
			if ang <= SNAP_DEG and ang < best_ang:
				best_ang = ang
				best = off
				best_k = lerpf(SNAP_NEAR, SNAP_FAR, clampf(dist / reach(), 0.0, 1.0))
	return best * best_k

## [{zombie, angle}] of the living zombies roughly in front, the MAX_CANDIDATES nearest the crosshair.
func _candidates(eye: Vector3, yaw: float, pitch: float) -> Array:
	var fwd := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var out: Array = []
	var far := reach()
	for z in get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D) or (z.has_method("is_alive") and not z.is_alive()):
			continue
		var c: Vector3 = (z as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		var to := c - eye
		var dist := to.length()
		if dist > far + 1.0 or dist < 0.3:
			continue
		var ang := rad_to_deg(acos(clampf(fwd.dot(to / dist), -1.0, 1.0)))
		if ang <= CANDIDATE_DEG + rad_to_deg(atan(1.0 / dist)):
			out.append({"zombie": z, "angle": ang})
	out.sort_custom(func(a, b): return a.angle < b.angle)
	return out.slice(0, MAX_CANDIDATES)

## {head, torso}: where those zones are now (synced first), or a stand-in on the body.
func _points(z: Node3D) -> Dictionary:
	if z.has_method("sync_hitboxes"):
		z.sync_hitboxes()
	var hb = z.get("hitboxes")
	var base := z.global_position
	var torso := base + Vector3(0, 1.0, 0)
	var head := base + Vector3(0, 1.65, 0)
	if hb is Dictionary:
		if hb.has("torso") and is_instance_valid(hb["torso"]):
			torso = _centre(hb["torso"])
		if hb.has("head") and is_instance_valid(hb["head"]):
			head = _centre(hb["head"])
	return {"head": head, "torso": torso}

## The middle of a hit zone: its shape (the Area3D itself sits on the bone).
func _centre(area: Node3D) -> Vector3:
	if area.get_child_count() > 0 and area.get_child(0) is Node3D:
		return (area.get_child(0) as Node3D).global_position
	return area.global_position

## (yaw, pitch) of the direction from the eye to `p`, in the player's own look convention.
func _angles(eye: Vector3, p: Vector3) -> Vector2:
	var d := (p - eye).normalized()
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))

## The gap from where the player looks to `p`: (right, up) in radians.
func _offset(eye: Vector3, p: Vector3, yaw: float, pitch: float) -> Vector2:
	var a := _angles(eye, p)
	return Vector2(wrapf(yaw - a.x, -PI, PI), a.y - pitch)

## Nothing solid between the eye and the zombie's torso or head: a ray that passes through zombies
## (and the dead's ragdolls) and stops at a wall, a car, a board.
func _visible(eye: Vector3, pts: Dictionary, z: Node3D) -> bool:
	var id := z.get_instance_id()
	if _los_cache.has(id):
		return _los_cache[id]
	var ok := _clear(eye, pts.torso) or _clear(eye, pts.head)
	_los_cache[id] = ok
	return ok

func _clear(eye: Vector3, to: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var skip: Array[RID] = [(player as CollisionObject3D).get_rid()]
	var dist := eye.distance_to(to)
	for n in 8:
		var q := PhysicsRayQueryParameters3D.create(eye, to)
		q.exclude = skip
		q.collision_mask = 0xFFFFFFFF & ~(512 | 64)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var r := space.intersect_ray(q)
		if r.is_empty():
			return true
		var c := r.collider as CollisionObject3D
		if c == null or eye.distance_to(r.position) >= dist - 0.35:
			return true
		if c.is_in_group("zombies") or c.is_in_group("corpses") or c.is_in_group("see_through") or c.has_method("take_hit"):
			skip.append(c.get_rid())
			continue
		return false
	return false
