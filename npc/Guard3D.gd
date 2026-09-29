extends Node3D

signal spotted_theft
## Fires the moment this guard becomes suspicious enough to start watching
## you rather than the room. Used for feedback, not for the alarm.
signal suspicion_raised

@export var vision_range: float = 6.0
@export var vision_angle_deg: float = 50.0
@export var sweep_arc_deg: float = 70.0
@export var sweep_speed: float = 0.6
@export var base_facing_deg: float = 0.0
## Who this is when you talk to them (pushed onto the TalkZone child, so each
## store's clerk or guard can have their own name and lines).
@export var talk_name: String = ""
@export_multiline var talk_lines: String = ""
@export var talk_portrait_path: String = ""
## Not a person but an extra pair of eyes for someone else -- e.g. the liquor
## clerk watching the blind corner in a convex security mirror. No body, no
## conversation; the vision cone still shows what it covers.
@export var watcher_only: bool = false
## Which clerk/guard this is, from npc/CharacterCast.gd. Decides the body
## and its colours, so each store's staff look different.
@export var role: String = "clerk_convenience"
## Extra staff who only work part of the day, as [start, end) hours (e.g.
## [11, 19] for the midday rush). Empty means always on shift. Off shift
## they simply aren't there when you walk in.
@export var shift_hours: Array = []

const VISION_COLOR_CALM := Color(0.5, 0.95, 1.0, 0.35)
const VISION_COLOR_SUSPICIOUS := Color(1.0, 0.75, 0.15, 0.45)
const VISION_COLOR_ALERT := Color(1.0, 0.15, 0.15, 0.55)

## Suspicion, 0.0 to 1.0. The alarm goes up when it fills.
##
## This replaced a straight "seen mid-grab = busted" check. That made the
## whole stealth layer a coin flip on one 0.6 s window: nothing you did
## before or after the grab mattered, and there was no way to read how much
## trouble you were in or to back out of it. Suspicion gives the player
## something to manage -- break line of sight, stop sprinting, don't loiter
## in view with your arms full -- and the cone colour shows exactly where
## they stand.
##
## Rates are per second of being *in view*. Grabbing something in plain sight
## still fills the bar in well under a second, so a careless steal is caught
## about as fast as it used to be.
const SUSPICION_STEALING := 3.0
const SUSPICION_SPRINTING := 0.55
const SUSPICION_CARRYING := 0.35
const SUSPICION_LOITERING := 0.22
## Standing right next to a guard makes everything above worse.
const SUSPICION_CLOSE_RANGE := 2.5
const SUSPICION_CLOSE_MULTIPLIER := 1.6
## Out of sight, it drains -- but slowly enough that walking back into view
## repeatedly still adds up.
const SUSPICION_DECAY := 0.30
## Below this the guard is just doing their job; above it they're watching
## you, which shows in the cone and drains slower.
const SUSPICION_NOTICED := 0.35

@onready var vision_cone: MeshInstance3D = $VisionCone
@onready var body: Node3D = $Body

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

## How quickly the body swings round to follow the sweep. Slow enough to
## read as a person scanning the room rather than a turret.
const TURN_SPEED := 2.5

var anim: CharacterAnimator
@onready var cone_material := StandardMaterial3D.new()

var _sweep_t: float = 0.0
var can_see_player: bool = false
## 0.0 = going about their business, 1.0 = alarm.
var suspicion: float = 0.0
var _alarm_raised: bool = false
var _was_noticed: bool = false

func _ready() -> void:
	if not shift_hours.is_empty() and not GameState.hours_contain(shift_hours, GameState.hour()):
		# Off shift. Freed before the store connects to the "guards" group.
		set_physics_process(false)
		queue_free()
		return
	add_to_group("guards")
	# Start each visit at a random point in the sweep. Otherwise every guard
	# glances the same way at the same moment on every entry, which is both
	# unnatural and trivially learnable.
	_sweep_t = randf() * TAU
	if watcher_only:
		body.visible = false
		var zone := get_node_or_null("TalkZone")
		if zone:
			zone.queue_free()
	_build_body()
	anim = CharacterAnimator.new(body)
	var talk := get_node_or_null("TalkZone")
	if talk:
		if talk_name != "":
			talk.npc_name = talk_name
			talk.portrait_path = talk_portrait_path
		if talk_lines != "":
			talk.flavor_lines = talk_lines
		Voice.prewarm(talk.npc_name, Array(talk.flavor_lines.split("\n", false)))
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_material.albedo_color = VISION_COLOR_CALM
	vision_cone.material_override = cone_material
	# When a chase ends without an arrest the alarm latch has to come off,
	# or this guard is deaf to everything you do for the rest of the visit.
	GameState.wanted_changed.connect(_on_wanted_changed)

## Fills the empty Body mount with this role's model. Kept out of the scene
## file so one Guard3D.tscn covers every store's clerk and the door guard.
func _build_body() -> void:
	if watcher_only:
		return
	var model: Node = load(CharacterCast.model_for(role)).instantiate()
	body.add_child(model)
	CharacterCast.dress(model, role)

func _physics_process(delta: float) -> void:
	_sweep_t += delta * sweep_speed
	var facing_deg := base_facing_deg + sin(_sweep_t) * (sweep_arc_deg * 0.5)
	var facing := Vector2.RIGHT.rotated(deg_to_rad(facing_deg))

	var player := get_tree().get_first_node_in_group("player")
	can_see_player = false

	if player and is_instance_valid(player):
		var to_player_3d: Vector3 = player.global_position - global_position
		var to_player := Vector2(to_player_3d.x, to_player_3d.z)
		var dist := to_player.length()
		if dist <= vision_range:
			var angle_diff := rad_to_deg(abs(facing.angle_to(to_player.normalized())))
			if angle_diff <= vision_angle_deg * 0.5:
				can_see_player = _has_line_of_sight(player)

	_update_suspicion(player, delta)

	if not watcher_only:
		# The cone's 0 deg points +X, the model's forward is -Z, hence the
		# 90 deg offset.
		var want := deg_to_rad(-facing_deg - 90.0)
		body.rotation.y = lerp_angle(body.rotation.y, want, min(1.0, TURN_SPEED * delta))

	_redraw_cone(facing_deg)

## Builds or drains suspicion and raises the alarm when it fills. The rates
## stack, so sprinting through an aisle with your arms full right past the
## clerk is much worse than any one of those on its own.
func _update_suspicion(player: Node, delta: float) -> void:
	if GameState.in_custody or _alarm_raised:
		return
	var rate := 0.0
	if can_see_player and player != null and is_instance_valid(player):
		if player.is_stealing:
			rate += SUSPICION_STEALING
		else:
			# Loitering in view is only suspicious once you're actually
			# holding something you shouldn't be; otherwise browsing a shop
			# would be impossible.
			if not GameState.inventory.is_empty():
				rate += SUSPICION_CARRYING + SUSPICION_LOITERING
			if player.has_method("is_sprinting") and player.is_sprinting():
				rate += SUSPICION_SPRINTING
		if rate > 0.0 and global_position.distance_to(player.global_position) <= SUSPICION_CLOSE_RANGE:
			rate *= SUSPICION_CLOSE_MULTIPLIER

	if rate > 0.0:
		suspicion = min(1.0, suspicion + rate * MetaProgress.suspicion_scale() * GameState.staff_alertness() * delta)
	else:
		# Once they've clocked you they stay wary a while longer.
		var decay := SUSPICION_DECAY * (0.5 if suspicion > SUSPICION_NOTICED else 1.0)
		suspicion = max(0.0, suspicion - decay * delta)

	if suspicion >= SUSPICION_NOTICED and not _was_noticed:
		_was_noticed = true
		suspicion_raised.emit()
	elif suspicion < SUSPICION_NOTICED:
		_was_noticed = false

	if suspicion >= 1.0:
		_alarm_raised = true
		spotted_theft.emit()

func _on_wanted_changed(is_wanted: bool) -> void:
	if not is_wanted:
		reset_suspicion()

## Clears the alarm latch so this guard can catch you again -- called when a
## chase ends without an arrest. Without it a guard who once raised the alarm
## would never raise another for the rest of the visit.
func reset_suspicion() -> void:
	suspicion = 0.0
	_alarm_raised = false
	_was_noticed = false

func _has_line_of_sight(player: Node) -> bool:
	if player.get("hiding"):
		return false
	var space_state := get_world_3d().direct_space_state
	# Eye height sits above the shop counter so the counter itself doesn't
	# blind the shopkeeper; the tall shelves still break line of sight.
	var from: Vector3 = global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

func _redraw_cone(facing_deg: float) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	uvs.append(Vector2(0.5, 0.5))
	var steps := 10
	var half := vision_angle_deg * 0.5
	for i in range(steps + 1):
		var a := deg_to_rad(facing_deg - half + (vision_angle_deg * i / float(steps)))
		var dir := Vector2.RIGHT.rotated(a) * vision_range
		verts.append(Vector3(dir.x, 0.03, dir.y))
		uvs.append(Vector2(0.5, 0.5))
	for i in range(1, steps + 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	vision_cone.mesh = mesh
	# The cone is the player's only read on how much trouble they're in, so it
	# tracks suspicion continuously: calm blue -> amber as the guard starts
	# paying attention -> red as the alarm approaches.
	var t := suspicion / SUSPICION_NOTICED
	if suspicion <= SUSPICION_NOTICED:
		cone_material.albedo_color = VISION_COLOR_CALM.lerp(VISION_COLOR_SUSPICIOUS, clampf(t, 0.0, 1.0))
	else:
		var u := (suspicion - SUSPICION_NOTICED) / (1.0 - SUSPICION_NOTICED)
		cone_material.albedo_color = VISION_COLOR_SUSPICIOUS.lerp(VISION_COLOR_ALERT, clampf(u, 0.0, 1.0))
