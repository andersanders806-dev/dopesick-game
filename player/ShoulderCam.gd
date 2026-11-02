class_name ShoulderCam
extends Node3D
## The story's third-person camera: over the right shoulder, like Resident
## Evil 4. It hangs close behind you (OFFSET: right, up, back), a little above
## level, and the mouse or right stick swings it all the way round you; walking
## goes where it looks (forward_flat) and the character turns to his own
## heading, he does not strafe.
##
## It is the CameraMount node itself, top_level, driven by Player3D from
## _process: it follows the body's *interpolated* position (so the physics
## tick never shows as judder), lags a hair behind the orbit, and when
## geometry comes between the head and the lens it comes in at once and eases
## back out slowly. Player3D lays shake, kick and the sprint FOV push on the
## Camera3D below it, so the rig and the feel never fight over one transform.
##
const Facades := preload("res://world/Facades.gd")

## Axes: yaw 0 looks along -Z (north), positive turns left (Godot's own
## rotation.y); pitch is the camera's rotation.x, negative looks down.

## Where the camera sits relative to the player's feet, in the camera's own
## turned frame: right, up, back. The orbit pivots on the head (OFFSET.y).
const OFFSET := Vector3(0.55, 1.55, 2.4)
const PITCH_MIN := deg_to_rad(-35.0)
const PITCH_MAX := deg_to_rad(55.0)
## A slight look down over the shoulder when nothing is steering it.
const REST_PITCH := deg_to_rad(-12.0)
## How far off a wall the lens is kept (on top of the cast sphere's own radius).
const PULL_IN_MARGIN := 0.2
const PROBE_RADIUS := 0.2
## Never closer to the head than this: one inside the head sees its inside.
const MIN_ARM := 0.45
## The follow, the orbit's lag and the pull-in's way back out, in 1/s.
const FOLLOW := 15.0
const ORBIT_LAG := 16.0
const ARM_OUT := 2.5
## Shoulder swap: the offset slides across in about a third of a second.
const SWAP_RATE := 6.0
## The mouse wheel moves it in and out a little (story only).
const USER_ZOOM := Vector2(0.75, 1.4)
## Floors (16) and walls/furniture (1); people and interactables are not in it.
const SOLID_MASK := 1 | 16

## Where it is asked to look (the input); it follows with a short lag.
var yaw: float = 0.0
var pitch: float = REST_PITCH
## +1 right shoulder, -1 left.
var shoulder: int = 1
var user_zoom: float = 1.0
## The body whose collider the probe ignores.
var ignore: RID = RID()

var _yaw_r: float = 0.0
var _pitch_r: float = REST_PITCH
var _side: float = 1.0
var _focus := Vector3.ZERO
var _placed := false
## How much of the head-to-lens arm is free, 0..1 (what pull-in moved).
var arm_free: float = 1.0
var _probe: SphereShape3D

func _ready() -> void:
	top_level = true
	_probe = SphereShape3D.new()
	_probe.radius = PROBE_RADIUS

## Looking: radians, wrapped and clamped. (The pad's stick and the mouse.)
func orbit(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, PITCH_MIN, PITCH_MAX)

func swap_shoulder() -> void:
	shoulder = -shoulder

## Straight ahead of the camera on the ground: what forward means for walking.
func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

## A door or a spawn: the camera swings in behind a player who faces
## `player_yaw` (the model's own heading: 0 faces +Z) at once, no lag, and
## settles at its resting pitch.
func snap_behind(player_yaw: float) -> void:
	yaw = wrapf(player_yaw + PI, -PI, PI)
	pitch = REST_PITCH
	_yaw_r = yaw
	_pitch_r = pitch
	_placed = false

## Where it wants to hang with nothing in the way, for a focus on the floor.
func ideal_position(feet: Vector3) -> Vector3:
	return feet + Vector3(0, OFFSET.y, 0) + Basis.from_euler(Vector3(pitch, yaw, 0.0)) * _arm(float(shoulder))

func _arm(side: float) -> Vector3:
	return Vector3(OFFSET.x * side, 0.0, OFFSET.z * user_zoom)

## Place the rig for this frame. `feet` is the body's drawn position. A delta
## of 0 puts everything where it is going, with no easing (a spawn, a test).
func follow(delta: float, feet: Vector3) -> void:
	if not _placed or _focus.distance_to(feet) > 8.0 or delta <= 0.0:
		_focus = feet
		_placed = true
		if delta <= 0.0:
			_yaw_r = yaw
			_pitch_r = pitch
			_side = float(shoulder)
	else:
		_focus = _focus.lerp(feet, 1.0 - exp(-FOLLOW * delta))
		var k := 1.0 - exp(-ORBIT_LAG * delta)
		_yaw_r = lerp_angle(_yaw_r, yaw, k)
		_pitch_r = lerpf(_pitch_r, pitch, k)
		_side = move_toward(_side, float(shoulder), SWAP_RATE * delta)
	var basis := Basis.from_euler(Vector3(_pitch_r, _yaw_r, 0.0))
	var pivot := _focus + Vector3(0, OFFSET.y, 0)
	var arm := basis * _arm(_side)
	var free := _free_arm(pivot, arm)
	# In at once, out slowly.
	if free < arm_free or delta <= 0.0:
		arm_free = free
	else:
		arm_free = lerpf(arm_free, free, 1.0 - exp(-ARM_OUT * delta))
	global_transform = Transform3D(basis, pivot + arm * arm_free)

## How far the lens is from your head now.
func arm_length() -> float:
	return (global_position - (_focus + Vector3(0, OFFSET.y, 0))).length()

## How much of the arm from the head to the lens is clear, 0..1: the first
## wall, floor or fixture the probe sphere meets, less a margin; and, on the
## block with you out in the street, the building masses (Facades.camera_clip)
## as a second opinion. (Inside a walk-in shop you are inside a mass: the
## room's own walls are colliders, and they are all that counts there.)
func _free_arm(pivot: Vector3, arm: Vector3) -> float:
	var length := arm.length()
	if length < 0.001 or not is_inside_tree():
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, pivot)
	q.motion = arm
	q.collision_mask = SOLID_MASK
	if ignore.is_valid():
		q.exclude = [ignore]
	var space := get_world_3d().direct_space_state
	var r: PackedFloat32Array = space.cast_motion(q)
	var t := 1.0
	if r.size() == 2:
		t = r[0]
	var dist := length * t
	if t < 1.0:
		dist = maxf(dist - PULL_IN_MARGIN, MIN_ARM)
	if get_tree().get_first_node_in_group("block_cells") != null and not Facades.in_building(pivot, 0.0):
		var c := Facades.camera_clip(pivot, pivot + arm, PULL_IN_MARGIN * 2.0)
		dist = minf(dist, maxf(length * c, MIN_ARM))
	return clampf(dist / length, 0.0, 1.0)
