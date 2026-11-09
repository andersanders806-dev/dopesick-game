extends Node3D

signal spotted_theft
## Fires the moment this guard becomes suspicious enough to start watching
## you rather than the room. Used for feedback, not for the alarm.
signal suspicion_raised
## Heard something (a cough, a dropped item, running feet) and turned to look. `kind` is the
## noise's, `strength` 0..1 how much of its loudness reached this guard.
signal heard_noise(kind: String, strength: float)

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
## Listens for noises (GameState.noise_made). The beat cop, who has his own business, doesn't.
@export var hears_noise: bool = true

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

## --- Hearing --------------------------------------------------------------
## A noise carries `loudness_m` metres in the open and half that through a wall (a raycast, like
## sight). Inside it, how far the guard's suspicion jumps depends on how close it was -- the full
## bump at their feet, none at the edge -- and on what it was; the guard also turns to face it for
## a couple of seconds, then the sweep takes over again. A sound never fills the bar on its own:
## it makes them look, and what they see does the rest.
const NOISE_BUMP := {"drop": 0.6, "retch": 0.5, "cough": 0.45, "cough_fit": 0.5, "sniff": 0.25, "sprint": 0.14}
const NOISE_BUMP_DEFAULT := 0.35
const NOISE_CAP := 0.8
const NOISE_WALL_FACTOR := 0.5
## How long they stay turned to it, and how fast the facing swings there and back.
const HEAR_TURN_TIME := 3.4
const HEAR_SWING_IN := 12.0
const HEAR_SWING_OUT := 1.6
## The faster body swing while looking at a noise (TURN_SPEED is the sweep's).
const HEAR_BODY_TURN := 16.0
## After the first look they scan: the last SCAN_TIME seconds of it sweep +-SCAN_DEG about the sound.
const SCAN_TIME := 1.6
const SCAN_DEG := 40.0
## The startle: a quick lean and hop as the head snaps round.
const FLINCH_TIME := 0.4
const BARK_COOLDOWN := 4.0
## Said at a small bump, and at a big one.
const BARKS_MILD := ["Hm?", "Huh?"]
const BARKS_ALERT := ["Who's there?", "What was that?"]

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
## Turned toward a noise: the direction (cone degrees), seconds left, and how far the facing has
## swung from the sweep to it (0..1).
var _hear_deg: float = 0.0
var _hear_t: float = 0.0
var _hear_blend: float = 0.0
var _bark_cd: float = 0.0
var _flinch_t: float = 0.0
## What the guard last said (the smoke test reads it).
var last_bark: String = ""
var last_heard: String = ""

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
	if hears_noise and not watcher_only:
		GameState.noise_made.connect(_on_noise)

## Fills the empty Body mount with this role's model. Kept out of the scene
## file so one Guard3D.tscn covers every store's clerk and the door guard.
func _build_body() -> void:
	if watcher_only:
		return
	var model: Node = CharacterCast.scene_for(CharacterCast.model_for(role)).instantiate()
	body.add_child(model)
	CharacterCast.dress(model, role)

func _physics_process(delta: float) -> void:
	_sweep_t += delta * sweep_speed
	var facing_deg := base_facing_deg + sin(_sweep_t) * (sweep_arc_deg * 0.5)
	# Turned to a noise: the sweep is overridden, then eases back to wherever it has got to.
	_bark_cd = maxf(0.0, _bark_cd - delta)
	if _hear_t > 0.0:
		_hear_t -= delta
		_hear_blend = move_toward(_hear_blend, 1.0, HEAR_SWING_IN * delta)
	else:
		_hear_blend = move_toward(_hear_blend, 0.0, HEAR_SWING_OUT * delta)
	if _hear_blend > 0.0:
		var look_deg := _hear_deg
		if _hear_t > 0.0 and _hear_t < SCAN_TIME:
			# The look-around: left, right, back to the noise.
			look_deg += sin((SCAN_TIME - _hear_t) / SCAN_TIME * TAU) * SCAN_DEG
		facing_deg = rad_to_deg(lerp_angle(deg_to_rad(facing_deg), deg_to_rad(look_deg), smoothstep(0.0, 1.0, _hear_blend)))
	if _flinch_t > 0.0 and not watcher_only:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		var k := sin((1.0 - _flinch_t / FLINCH_TIME) * PI)
		body.rotation.x = -0.22 * k
		body.position.y = 0.06 * k
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
		# The cone's 0 deg points +X and the characters (CharacterCast) face
		# +Z, hence the 90 deg offset. It was -90 for Kenney's models, which
		# faced -Z -- kept after the cast changed, it turned every guard and
		# the beat cop round, so he walked the block backwards.
		var want := deg_to_rad(90.0 - facing_deg)
		var turn := HEAR_BODY_TURN if _hear_blend > 0.0 else TURN_SPEED
		body.rotation.y = lerp_angle(body.rotation.y, want, min(1.0, turn * delta))

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
			if GameState.carrying_stolen():
				rate += SUSPICION_CARRYING + SUSPICION_LOITERING
			if player.has_method("is_sprinting") and player.is_sprinting():
				rate += SUSPICION_SPRINTING
		if rate > 0.0 and global_position.distance_to(player.global_position) <= SUSPICION_CLOSE_RANGE:
			rate *= SUSPICION_CLOSE_MULTIPLIER

	if rate > 0.0:
		suspicion = min(1.0, suspicion + rate * MetaProgress.suspicion_scale() * _alertness() * delta)
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

## Whether `pos` is behind a wall from here: a ray to it that something solid -- not a shelf, a
## counter or a person -- stops. Sound goes round the stock.
func _wall_between(pos: Vector3) -> bool:
	var from := global_position + Vector3(0, 1.4, 0)
	var to := pos + Vector3(0, 1.0, 0)
	var exclude: Array[RID] = []
	var space := get_world_3d().direct_space_state
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var c: Object = hit.collider
		if c is CharacterBody3D or (c is Node and (c as Node).get_parent() != null and String((c as Node).name).begins_with("Fixture")):
			exclude.append(hit.rid)
			continue
		return true
	return false

## GameState.noise_made: close enough to hear it? A bump of suspicion by how near, a turn to look,
## and a bark -- what the player sees of it is the cone going amber and the head swinging round.
func _on_noise(pos: Vector3, loudness_m: float, kind: String) -> void:
	# A shop that isn't the one you're in has its vision switched off (WalkInShop): it's off for hearing, too.
	if vision_range <= 0.0 or GameState.in_custody or _alarm_raised or not is_inside_tree():
		return
	var reach := loudness_m
	var d := global_position.distance_to(pos)
	if d > reach:
		return
	if _wall_between(pos):
		reach *= NOISE_WALL_FACTOR
		if d > reach:
			return
	var strength := 1.0 - d / maxf(reach, 0.01)
	var bump: float = float(NOISE_BUMP.get(kind, NOISE_BUMP_DEFAULT)) * strength
	bump *= MetaProgress.suspicion_scale() * _alertness()
	# Never to the alarm: a noise makes them look; seeing is what fills the bar.
	suspicion = maxf(suspicion, minf(suspicion + bump, NOISE_CAP))
	var to := pos - global_position
	_hear_deg = rad_to_deg(atan2(to.z, to.x))
	if _hear_t <= 0.0 and not watcher_only:
		# The head and shoulders snap most of the way at once: something just made them jump.
		body.rotation.y = lerp_angle(body.rotation.y, deg_to_rad(90.0 - _hear_deg), 0.7)
		_flinch_t = FLINCH_TIME
	_hear_t = HEAR_TURN_TIME
	last_heard = kind
	heard_noise.emit(kind, strength)
	if bump > 0.02 and _bark_cd <= 0.0:
		_bark(bump >= 0.3)

## "Hm?" at a small one, "Who's there?" at a big one: said from where they stand.
func _bark(alert: bool) -> void:
	_bark_cd = BARK_COOLDOWN
	var line: String = (BARKS_ALERT if alert else BARKS_MILD).pick_random()
	last_bark = line
	if watcher_only:
		return
	var speaker := "Security" if role in ["security_guard", "police"] else "Clerk"
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_subtitle"):
		var who := "Clerk"
		var talk := get_node_or_null("TalkZone")
		if talk != null and String(talk.npc_name) != "":
			who = String(talk.npc_name)
		hud.show_subtitle(line, 2.2, "bark", who)
	var stream: AudioStream = Voice.bark_stream(speaker, line)
	if stream != null:
		var voice := SFX.play_at("", global_position + Vector3(0, 1.6, 0), 1.0, randf_range(0.97, 1.03), stream)
		if voice != null:
			voice.bus = "Voice"

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

## How hard this clerk is watching: the hour, today's headline, and any tip
## or grudge a regular left about this store (GameState.store_alertness).
func _alertness() -> float:
	var store_id := _store_id()
	if store_id != "":
		return GameState.store_alertness(store_id)
	return GameState.staff_alertness()

## Which store this clerk works in: the nearest ancestor that says so -- the
## old rooms' root, or a walk-in shop on the street (whose scene is the City).
func _store_id() -> String:
	var n: Node = get_parent()
	while n != null:
		var id = n.get("store_id")
		if id is String and id != "":
			return id
		n = n.get_parent()
	return ""
