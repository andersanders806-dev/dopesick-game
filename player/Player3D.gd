extends CharacterBody3D

const PauseMenuScript := preload("res://ui/PauseMenu.gd")
const FirstPersonRoom := preload("res://world/FirstPersonRoom.gd")
const NotebookScript := preload("res://ui/Notebook.gd")
## A walk: the clip plants its feet up to 1.8x its own pace (0.98 m/s on
## this body), so this is as fast as walking goes without skating. It was
## 4.2, a jog the walk cycle could never keep up with.
const BASE_SPEED := 1.75
## Sprinting is the risk/reward half of the stealth layer: it gets you out of
## a room fast, and it is the single loudest thing you can do in front of a
## guard (see Guard3D.SUSPICION_SPRINTING). Withdrawal takes it away -- when
## you are sick you cannot run, which is when you most need to.
## 5.25 m/s: the run clip's planted limit (2.95 m/s x 1.8), and still clear
## of the police (4.6) and the mugger (3.9).
const SPRINT_MULT := 3.0
const SICK_SPEED_MULT := 0.55
const SICK_THRESHOLD := 20.0
## Limping for a few hours after the collector's been at you.
const HURT_SPEED_MULT := 0.75
const TURN_SPEED := 10.0
## Getting up to speed and pulling up: about a tenth of a second -- eased,
## but quick enough that moving answers the stick (a fifth felt laggy).
const ACCEL := 42.0
const DECEL := 50.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

# One full walk cycle is two footfalls; before the body is loaded.
const STEP_INTERVAL := 0.615

## How long the player is rooted in place for a grab. Long enough to read
## as deliberate rather than a twitch; the animation is stretched to fit,
## whatever its authored length.
const PICKUP_DURATION := 0.6
## In withdrawal your hands shake: a grab takes up to this much longer at
## the bottom of the meter, which is more time rooted in a guard's view.
const TREMOR_GRAB_MULT := 0.6
## Above this sickness a grab can be fumbled: the hands won't hold still, the thing slips and hits
## the floor (loudly, see items/StealableItem3D.gd) and has to be picked up again. The chance
## climbs from zero here to FUMBLE_MAX at the bottom of the meter.
const FUMBLE_FROM := 0.6
const FUMBLE_MAX := 0.5
## Running feet in a shop carry this far (m) to a guard's ear, a footfall at a time.
const SPRINT_NOISE_M := 4.5
## Stomach cramps: every so often in withdrawal you double over and can't
## move for a moment. Seconds between cramps, and how long one holds you.
const CRAMP_INTERVAL := Vector2(9.0, 18.0)
const CRAMP_DURATION := 0.9
## Camera shake at full sickness: metres of drift and degrees of roll.
const SHAKE_OFFSET := 0.08
const SHAKE_ROLL_DEG := 1.6

@onready var interact_zone: Area3D = $InteractZone
@onready var model: Node3D = $Model
@onready var camera: Camera3D = $CameraMount/Camera3D

var nearby: Array = []
var dialogue_active: bool = false
var is_stealing: bool = false
## Crouched in a hiding spot (Backyard3D). Nobody can see you -- see
## Police3D/Guard3D._has_line_of_sight -- and moving gets you up again.
var hiding: bool = false
var _facing_angle: float = 0.0
var anim: CharacterAnimator
var _step_timer: float = 0.0
var _left_foot: bool = true
var _sprinting: bool = false
var _busy_timer: float = 0.0
var _theft_serial: int = 0
var _camera_base: Transform3D

# --- Camera framing ---------------------------------------------------------
## The rig floats free of the player (top_level) and eases after them, so
## the character stays in the middle of the screen wherever they walk. It
## is the same distance in every room, so a room's size reads as its size:
## the old rig zoomed in on small rooms and pinned itself to the walls,
## which made rooms jump in scale and left you walking off-centre. The
## scroll wheel moves it in and out.
const CAM_FOLLOW := 15.0
## Of the scene file's 9 m-high rig: close enough to read faces and hands.
const CAM_ZOOM := 0.75
const CAM_USER_ZOOM := Vector2(0.7, 1.4)
var _cam_offset: Vector3
var _cam_focus: Vector3
## Where the camera's line to you is cut short by a building behind it
## (Facades.camera_clip), 0..1, how far of the line it keeps.
var _cam_clip := 1.0
const Facades := preload("res://world/Facades.gd")
## Chest height the camera's line to you starts at, and how far off a wall
## it stays (its near plane stays clear), and how fast it eases back out.
const CAM_CHEST := 1.2
const CAM_WALL_PAD := 0.6
const CAM_CLIP_OUT := 3.0
## Of its height, at least, the camera keeps when a wall has pulled it in.
const CAM_CLIPPED_HEIGHT := 0.55
var _user_zoom: float = 1.0
## Zoom per second at full right-stick tilt.
const PAD_ZOOM_RATE := 0.8
var _sprint_latched: bool = false
## The weapon holds it while the trigger is down: a gun fired on the run ends the sprint.
var sprint_blocked: bool = false
var _cam_ready: bool = false

# --- First person ------------------------------------------------------------
## Graphics.first_person: the camera at your eyes, the mouse or right stick
## to look, and walking goes where you're facing. Your body still casts its
## shadow, but you don't see the inside of your own head.
const EYE_HEIGHT := 1.62
const FP_FOV := 70.0
## Radians per second at full right-stick tilt, and per pixel of mouse.
const LOOK_SPEED := 2.6
const MOUSE_SENS := 0.0025
const PITCH_LIMIT := deg_to_rad(80.0)
var _first_person: bool = false
## Dead Block's first-person feel (player/FPFeel.gd), if the mode made one: ADS, recoil, slide.
var feel: Node
var _look_yaw: float = 0.0
var _look_set: bool = false
var _look_pitch: float = 0.0
## The pad's look: deadzone, curve, turn acceleration (player/PadLook.gd), and the aim assist the
## weapon holder makes in zombie mode (player/AimAssist.gd; null elsewhere).
const PadLook := preload("res://player/PadLook.gd")
const StoryHandsScript := preload("res://player/StoryHands.gd")
const SickBurstsScript := preload("res://player/SickBursts.gd")
var pad_look_state := PadLook.new()
var assist: Node
var _tp_camera_base: Transform3D
var _tp_fov: float
var _shake_t: float = 0.0
## A jolt that dies away fast: a punch, a fall, a knife (kick()).
var _kick: float = 0.0
## The head bowed, in radians, added to the pitch (StoryHands: taking a dose, looking down at your hands).
var fp_dip: float = 0.0
## Your own hands (player/StoryHands.gd): story first person only.
var story_hands: Node
var _cramp_timer: float = 0.0
## Withdrawal's coughs and sniffs, and holding them in (player/SickBursts.gd).
var sick_bursts: Node
## A hitch of the head, in radians, added to the pitch (a breath caught, a cough): SickBursts.
var fp_hitch: float = 0.0
## Test hook: a fixed roll for the fumble check (-1 leaves it to chance).
var fumble_roll_override: float = -1.0

func _ready() -> void:
	add_to_group("player")
	CharacterCast.dress(model, "player")
	anim = CharacterAnimator.new(model)
	# Hear the world from the character, not the camera hanging 9 m above.
	$Listener.make_current()
	_camera_base = camera.transform
	_tp_camera_base = _camera_base
	_tp_fov = camera.fov
	_cam_offset = $CameraMount.position
	$CameraMount.top_level = true
	_cramp_timer = randf_range(CRAMP_INTERVAL.x, CRAMP_INTERVAL.y)
	sick_bursts = SickBurstsScript.new()
	add_child(sick_bursts)
	sick_bursts.setup(self)
	interact_zone.area_entered.connect(_on_area_entered)
	interact_zone.area_exited.connect(_on_area_exited)
	Graphics.view_changed.connect(_apply_view)
	# Deferred: the room around us is still being built.
	_apply_view.call_deferred(Graphics.first_person)

func _apply_view(on: bool) -> void:
	_first_person = on
	for m in model.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# First person: drawn every frame from where the body is drawn and the
	# latest mouse look (_process), not stepped on the physics tick -- the
	# fix Godot's jitter/stutter guide gives for first-person cameras.
	$CameraMount.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if on else Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if on:
		# Look the way you were facing, unless a room has already turned you (world/WorldRoot3D.gd).
		if not _look_set:
			set_look(_facing_angle + PI, 0.0)
		_camera_base = Transform3D()
		camera.fov = FP_FOV
		camera.near = 0.05
	else:
		_camera_base = _tp_camera_base
		camera.fov = _tp_fov
		$CameraMount.rotation = Vector3.ZERO
		_cam_ready = false
	FirstPersonRoom.apply(get_tree().current_scene, on)
	_sync_story_hands(on)
	_update_camera_rig(0.0)

## Story first person gets its own hands (the gun modes bring theirs with the weapon).
func _sync_story_hands(on: bool) -> void:
	# DOPESICK_NO_HANDS=1 leaves them out, for the perf probes' before/after.
	if on and story_hands == null and GameState.mode == "story" and OS.get_environment("DOPESICK_NO_HANDS") == "":
		story_hands = StoryHandsScript.new()
		add_child(story_hands)
		story_hands.setup(self, camera)
	elif not on and story_hands != null:
		story_hands.queue_free()
		story_hands = null
		fp_dip = 0.0

## Where you're looking, in radians: yaw round from -Z, pitch up from level.
func set_look(yaw: float, pitch: float) -> void:
	_look_set = true
	_look_yaw = wrapf(yaw, -PI, PI)
	_look_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)

## Something you talk to (not a counter, a door or a sign): anyone with a name, the dealer, the collector, a guard
## or a shopkeeper's talk zone, a hustler, a pedestrian.
const PERSON_SCRIPTS := ["Pusher3D.gd", "Collector3D.gd", "Guard3D.gd", "PatrolCop3D.gd", "TalkZone3D.gd", "Pedestrian3D.gd",
	"Lookout3D.gd", "Homeless3D.gd", "KartHustler3D.gd", "Outreach3D.gd", "NPC3D.gd", "Police3D.gd", "Postman3D.gd"]

func _is_person(n: Node) -> bool:
	if "npc_name" in n:
		return true
	var sc: Script = n.get_script()
	while sc != null:
		if sc.resource_path.get_file() in PERSON_SCRIPTS:
			return true
		sc = sc.get_base_script()
	return false

## The view turns to look at `point` over `duration` s, the shorter way round
## (a conversation starting, a beat that wants your eyes somewhere). Level
## enough that the horizon stays put: pitch is held to +-0.35 rad.
var _look_tween: Tween

func ease_look_to(point: Vector3, duration := 0.4) -> void:
	var to := point - camera.global_position
	if to.length() < 0.1:
		return
	var yaw := atan2(-to.x, -to.z)
	var pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.35, 0.35)
	if absf(angle_difference(_look_yaw, yaw)) < deg_to_rad(4.0) and absf(pitch - _look_pitch) < 0.06:
		return
	if _look_tween != null and _look_tween.is_valid():
		_look_tween.kill()
	var y0 := _look_yaw
	var p0 := _look_pitch
	_look_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_method(func(t: float): set_look(lerp_angle(y0, yaw, t), lerpf(p0, pitch, t)), 0.0, 1.0, duration)

## Graphics asks, each frame: should the mouse be steering the view?
func wants_mouse_captured() -> bool:
	if not _first_person or dialogue_active or get_tree().paused:
		return false
	for c in get_tree().root.get_children():
		if c is CanvasLayer and (c.has_method("open") or c.has_method("open_with") or c.has_method("start")):
			return false
	return true


func _update_camera_rig(delta: float) -> void:
	if _first_person:
		_update_fp_camera()
		return
	var target := global_position
	# Snap after a spawn or a door; ease otherwise.
	if not _cam_ready or _cam_focus.distance_to(target) > 8.0:
		_cam_focus = target
		_cam_ready = true
	else:
		_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-CAM_FOLLOW * delta))
	var want := _cam_focus + _cam_offset * CAM_ZOOM * _user_zoom
	# On the block the camera never goes into a building: it comes in along
	# its line to you at once, and eases back out.
	var chest := _cam_focus + Vector3(0, CAM_CHEST, 0)
	var clip := 1.0
	if get_tree().get_first_node_in_group("block_cells") != null:
		clip = Facades.camera_clip(chest, want, CAM_WALL_PAD)
	if clip < _cam_clip or delta <= 0.0:
		_cam_clip = clip
	else:
		_cam_clip = lerpf(_cam_clip, clip, 1.0 - exp(-CAM_CLIP_OUT * delta))
	var pos := chest.lerp(want, _cam_clip)
	var tilt := 0.0
	if _cam_clip < 0.999:
		# Not straight in: it keeps most of its height (looking down on
		# you from just off the wall) when that's clear, and tilts to keep
		# you in the middle.
		var off := want - chest
		var lifted := chest + Vector3(off.x * _cam_clip, off.y * maxf(_cam_clip, CAM_CLIPPED_HEIGHT), off.z * _cam_clip)
		if not Facades.in_building(lifted, CAM_WALL_PAD * 0.5):
			pos = lifted
		var to_you := chest - pos
		var down := atan2(-to_you.y, Vector2(to_you.x, to_you.z).length())
		tilt = (-down - _tp_camera_base.basis.get_euler().x) * (1.0 - _cam_clip)
	$CameraMount.global_position = pos
	$CameraMount.rotation = Vector3(tilt, 0.0, 0.0)

## The block's walls between the camera and you dither out
## (world/Cutaway.gd): its shader reads where you are, every drawn frame,
## and how wide a hole to open -- none in first person, where the wall in
## front of your face is meant to be a wall.
const Cutaway := preload("res://world/Cutaway.gd")
## What was last set: [player_world_pos, cutaway_radius] (the smoke test).
var cutaway_globals := [Vector3.ZERO, 0.0]

func _process(delta: float) -> void:
	cutaway_globals = [get_global_transform_interpolated().origin, 0.0 if _first_person else Cutaway.RADIUS]
	RenderingServer.global_shader_parameter_set("player_world_pos", cutaway_globals[0])
	RenderingServer.global_shader_parameter_set("cutaway_radius", cutaway_globals[1])
	if _first_person:
		pad_look(delta)
		_update_camera_shake(delta)
		_update_fp_camera()

## The right stick looks round every drawn frame, as the mouse does: PadLook shapes it, the aim assist
## (pad only, never the mouse, which has its own path in _unhandled_input) adds to it.
func pad_look(delta: float) -> void:
	if dialogue_active or get_tree().paused:
		pad_look_state.reset()
		return
	var ads: float = feel.ads if feel != null else 0.0
	var scale := _look_scale() * lerpf(1.0, Graphics.pad_ads_mult, ads)
	var look := pad_look_state.step(PadLook.raw_stick(), delta, scale, Graphics.invert_look)
	if assist != null:
		var moving := Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.1
		look = assist.adjust(look, delta, moving or pad_look_state.tilt > 0.0)
	if look != Vector2.ZERO:
		set_look(_look_yaw - look.x, _look_pitch + look.y)

## Look speed scale: aimed down the sights the zoomed view turns by the same
## picture distance (FPFeel.sens_scale), otherwise 1.
func _look_scale() -> float:
	return feel.sens_scale() if (_first_person and feel != null) else 1.0

## Hiding is a crouch (the body sits 0.35 lower): the eyes go down with it.
const HIDE_EYE_DROP := 0.55
var _eye_drop := 0.0

func _update_fp_camera() -> void:
	_eye_drop = lerpf(_eye_drop, HIDE_EYE_DROP if hiding else 0.0, 1.0 - exp(-8.0 * get_process_delta_time()))
	$CameraMount.global_position = get_global_transform_interpolated().origin + Vector3(0, EYE_HEIGHT - _eye_drop, 0)
	$CameraMount.rotation = Vector3(clampf(_look_pitch - fp_dip - fp_hitch, -PITCH_LIMIT, PITCH_LIMIT), _look_yaw, 0.0)

## The view trembles and lists in withdrawal: two sine waves at unrelated
## rates, so it never settles into a rhythm you can tune out.
## Jolts the view (HUD calls it when you take a hit).
func kick(strength := 1.0) -> void:
	_kick = maxf(_kick, strength)

## Walking moves the view a little, the way a head does: a sway per stride
## and a dip per footfall in first person, and a push of the field of view
## when you break into a run (either view). Settings > Camera motion.
const BOB := Vector2(0.024, 0.028)
## Radians of bob phase per metre walked: one sway each way per two steps.
const BOB_PER_METRE := 4.2
const SPRINT_FOV := 7.0
var _bob_phase := 0.0
var _bob_weight := 0.0

func _update_camera_feel(delta: float) -> Vector3:
	var speed := Vector2(velocity.x, velocity.z).length()
	var on := Graphics.camera_motion and not dialogue_active
	var base := FP_FOV if _first_person else _tp_fov
	var want := base + (SPRINT_FOV if on and _sprinting and speed > 1.0 else 0.0)
	camera.fov = lerpf(camera.fov, want, 1.0 - exp(-5.0 * delta))
	if not _first_person:
		return Vector3.ZERO
	_bob_weight = move_toward(_bob_weight, clampf(speed / 3.0, 0.0, 1.3) if on else 0.0, delta * 4.0)
	_bob_phase = fmod(_bob_phase + speed * delta * BOB_PER_METRE, TAU * 2.0)
	return Vector3(sin(_bob_phase) * BOB.x, -absf(sin(_bob_phase)) * BOB.y, 0.0) * _bob_weight

func _update_camera_shake(delta: float) -> void:
	var s := GameState.sickness()
	_shake_t += delta
	var offset := Vector3(sin(_shake_t * 1.7) + 0.5 * sin(_shake_t * 5.3), cos(_shake_t * 1.3) * 0.6, 0.0) * SHAKE_OFFSET * s
	offset += _update_camera_feel(delta)
	if _kick > 0.0:
		offset += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.12 * _kick
		_kick = maxf(0.0, _kick - delta * 4.0)
	var roll := deg_to_rad(sin(_shake_t * 0.8) * SHAKE_ROLL_DEG * s)
	camera.transform = _camera_base.translated_local(offset).rotated_local(Vector3.FORWARD, roll)

## Doubled over by a cramp: rooted for a moment, with a groan.
func _update_cramps(delta: float) -> void:
	if not GameState.withdrawn(SICK_THRESHOLD):
		_cramp_timer = randf_range(CRAMP_INTERVAL.x, CRAMP_INTERVAL.y)
		return
	_cramp_timer -= delta
	if _cramp_timer > 0.0:
		return
	_cramp_timer = randf_range(CRAMP_INTERVAL.x, CRAMP_INTERVAL.y)
	_busy_timer = anim.play_once_timed("pick-up", CRAMP_DURATION)
	SFX.play("groan", -6.0, randf_range(0.9, 1.0))

## Zombie mode: a claw from the dead (npc/Zombie3D.gd calls this).
func take_zombie_hit(dmg: float, _from: Node) -> void:
	ZombieMode.player_hit(dmg)

## Ghetto Wars: a round from a gun (npc/Gangster3D.gd). `from` is the muzzle, for the red arc.
func take_gun_hit(dmg: float, from: Vector3, _by: Node) -> void:
	ZombieMode.player_hit(dmg, from)

func is_sliding() -> bool:
	return feel != null and bool(feel.get("sliding"))

## First person: nobody comes closer to your eyes than this (m, along the floor). The story's
## people mostly have no body to bump into (areas, or nodes with no collider at all), so the player
## keeps out of them instead, or a head fills the whole view (hair at the near plane).
## Two parts: the player's own movement slides round the ring at any speed (a sprint included), and
## someone walking into the player eases him back out (never through a wall).
const PERSONAL_SPACE := 0.95
## Every kind of person in the story that can be walked into. (The police and muggers have bodies and
## are meant to be touched; Dead Block's dead and the gangs are not in the story.)
const PERSONAL_GROUPS := ["pedestrians", "scheduled_people", "guards", "patrol", "pusher", "collector", "postman"]
## Only people this close (m) are looked at each physics tick.
const PEOPLE_RANGE := 3.0
const PEOPLE_PUSH_SPEED := 6.0
var _people_frame := -1
var _people: Array[Node3D] = []

## The people within PEOPLE_RANGE, worked out once per physics tick: squared distances first, visibility
## only for those that are close.
func _people_close() -> Array[Node3D]:
	var f := Engine.get_physics_frames()
	if f == _people_frame:
		return _people
	_people_frame = f
	_people.clear()
	if GameState.mode != "story" or not _first_person:
		return _people
	var tree := get_tree()
	var r2 := PEOPLE_RANGE * PEOPLE_RANGE
	var here := global_position
	var seen := {}
	var all: Array = []
	for g in PERSONAL_GROUPS:
		all.append_array(tree.get_nodes_in_group(g))
	for a in nearby:
		if is_instance_valid(a) and "npc_name" in a:
			all.append(a)
	for n in all:
		var n3 := n as Node3D
		if n3 == null or seen.has(n3):
			continue
		var dx: float = n3.global_position.x - here.x
		var dz: float = n3.global_position.z - here.z
		if dx * dx + dz * dz > r2 or not n3.is_visible_in_tree():
			continue
		seen[n3] = true
		_people.append(n3)
	return _people

## Walking (or sprinting) at someone: the part of the velocity that would take the eyes inside the ring
## this tick is taken off, so the player slides round them instead of through them. Wall-safe: it only
## ever removes velocity.
func _slide_round_people(delta: float) -> void:
	var people := _people_close()
	if people.is_empty() or delta <= 0.0:
		return
	var here := Vector2(global_position.x, global_position.z)
	var v := Vector2(velocity.x, velocity.z)
	for _pass in 2:
		for n in people:
			var to := Vector2(n.global_position.x, n.global_position.z) - here
			var d := to.length()
			if d < 0.01:
				continue
			var dir := to / d
			var closing := v.dot(dir)
			var room := maxf(d - PERSONAL_SPACE, 0.0)
			if closing * delta > room:
				v -= dir * (closing - room / delta)
	velocity.x = v.x
	velocity.z = v.y

func _keep_people_out(delta: float) -> void:
	var people := _people_close()
	if people.is_empty():
		return
	var here := Vector2(global_position.x, global_position.z)
	var push := Vector2.ZERO
	for n in people:
		var off := here - Vector2(n.global_position.x, n.global_position.z)
		var d := off.length()
		if d >= PERSONAL_SPACE:
			continue
		if d < 0.01:
			var back := camera.global_transform.basis.z
			off = Vector2(back.x, back.z)
			d = 0.0
		push += off.normalized() * (PERSONAL_SPACE - d)
	if push.length() > 0.001:
		# Eased: never a shove, and a wall stops it (then the person is the one in the ring).
		var step := push.limit_length(maxf(PEOPLE_PUSH_SPEED * delta, 0.02))
		move_and_collide(Vector3(step.x, 0.0, step.y))

func _physics_process(delta: float) -> void:
	_keep_people_out(delta)
	if not _first_person:
		# (First person: the right stick looks round in pad_look(), every drawn frame.)
		# The right stick pulls the camera in and out, as the wheel does.
		var zoom := Input.get_axis("look_up", "look_down")
		if absf(zoom) > 0.0:
			_user_zoom = clampf(_user_zoom + zoom * PAD_ZOOM_RATE * delta, CAM_USER_ZOOM.x, CAM_USER_ZOOM.y)
	# Third person on the physics tick, so interpolation smooths the shake
	# with the rest; first person every frame (_process).
	if not _first_person:
		_update_camera_shake(delta)
		_update_camera_rig(delta)
	if dialogue_active:
		velocity = Vector3.ZERO
		move_and_slide()
		anim.update(0.0)
		return

	# Rooted in place while an action animation (e.g. grabbing an item) plays.
	if _busy_timer > 0.0:
		_busy_timer -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		_update_footsteps(delta, false, 1.0)
		return

	_update_cramps(delta)
	if _busy_timer > 0.0:
		return
	if hiding:
		var wants_move := Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.1
		if not wants_move:
			velocity = Vector3.ZERO
			move_and_slide()
			return
		set_hiding(false)

	if _first_person and feel != null and feel.sliding:
		# Dead Block's slide: carried along, steering locked, for a moment.
		velocity = feel.slide_velocity(delta)
		move_and_slide()
		return

	var dir := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	dir = dir.normalized()
	if _first_person:
		# Forward is where you're looking.
		dir = dir.rotated(Vector3.UP, _look_yaw)

	var speed := BASE_SPEED
	var sick := GameState.withdrawn(SICK_THRESHOLD)
	var hurt := GameState.is_hurt()
	# Hold Shift, or click L3 once and keep going, like COD: a pad sprint
	# lasts until you let the stick go.
	if dir.length() <= 0.1:
		_sprint_latched = false
	_sprinting = (not sick) and (not hurt) and dir.length() > 0.1 and not sprint_blocked and (Input.is_action_pressed("sprint") or _sprint_latched)
	if sick:
		speed *= SICK_SPEED_MULT
	elif _sprinting:
		speed *= SPRINT_MULT
	if hurt:
		speed *= HURT_SPEED_MULT
	if Jobs.carrying_box():
		speed *= Jobs.CARRY_SPEED
	if _first_person and feel != null:
		speed *= feel.speed_mult()
	if sick_bursts != null:
		speed *= sick_bursts.speed_mult()

	var target := dir * speed
	velocity = velocity.move_toward(target, (ACCEL if dir.length() > 0.1 else DECEL) * delta)
	_slide_round_people(delta)
	move_and_slide()
	GameState.stat("walked", Vector2(velocity.x, velocity.z).length() * delta)
	# Withdrawal slows the stride along with the movement, so it reads as a
	# shuffle rather than the feet sliding; so does easing in and out.
	var moved := Vector2(velocity.x, velocity.z).length()
	# Sick, you walk like it: a hunched, bruised shuffle and a fidget when
	# you stand, on the bodies that have those clips. The shuffle is already
	# slow, so it isn't slowed again.
	var sick_clips: bool = sick and anim.has_clip("walk_sick")
	if not hiding:
		anim.set_clips("walk_sick" if sick_clips else "walk", "idle_sick" if sick and anim.has_clip("idle_sick") else "idle")
	# Feet planted: the stride plays at the rate the pace needs (it used to
	# run at 1.0 whatever the speed, the feet sliding under you), slowed
	# while you're high -- heavy, a half-beat behind.
	var clip := "sprint" if _sprinting else ("walk_sick" if sick_clips else "walk")
	var anim_speed := anim.stride_rate(clip, moved) if moved > 0.1 else 1.0
	if sick and not sick_clips:
		anim_speed *= SICK_SPEED_MULT
	if is_high():
		anim_speed *= HIGH_ANIM_MULT
	if _sprinting:
		anim.play("sprint", anim_speed)
	else:
		anim.update(moved, anim_speed)
	_update_footsteps(delta, dir.length() > 0.1, anim_speed, anim.step_time(clip))

	if dir.length() > 0.1:
		var target_angle := atan2(dir.x, dir.z)
		_facing_angle = lerp_angle(_facing_angle, target_angle, TURN_SPEED * delta)
		model.rotation.y = _facing_angle

## Footfalls stay in step with the walk animation: same cycle length, and
## slowed by the same factor when the stride slows in withdrawal.
## C: what you can make from what you're carrying (autoload/Crafting.gd).
func open_craft_menu() -> CanvasLayer:
	dialogue_active = true
	var have := Crafting.MATERIALS.map(func(m): return "%s %d" % [m, Crafting.count(m)])
	var options: Array = Crafting.RECIPES.map(func(r):
		var parts := []
		for id in r["needs"]:
			parts.append("%d %s" % [r["needs"][id], id])
		return "%s  (%s)" % [r["label"], ", ".join(parts)])
	var disabled := []
	for i in Crafting.RECIPES.size():
		if not Crafting.can_make(Crafting.RECIPES[i]):
			disabled.append(i)
	var menu: CanvasLayer = preload("res://ui/ChoiceMenu.gd").new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		dialogue_active = false
		if Crafting.make(i):
			Graphics._show_toast("Made: %s" % Crafting.RECIPES[i]["label"]))
	menu.cancelled.connect(func(): dialogue_active = false)
	menu.open("Make something", "Carrying: %s. Search trash bags and parked cars for more." % ", ".join(have), options, disabled)
	return menu

func _update_footsteps(delta: float, moving: bool, anim_speed: float, interval := STEP_INTERVAL) -> void:
	if not moving:
		# Next step lands soon after starting to walk again, not instantly.
		_step_timer = interval * 0.5
		return
	_step_timer -= delta * anim_speed
	if _step_timer > 0.0:
		return
	_step_timer = maxf(_step_timer + interval, 0.0)
	_left_foot = not _left_foot
	SFX.play_footstep(-8.0, randf_range(0.92, 1.05))
	if _sprinting:
		GameState.emit_noise(global_position, SPRINT_NOISE_M, "sprint")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _first_person:
		var m := MOUSE_SENS * Graphics.look_sensitivity * _look_scale()
		set_look(_look_yaw - event.relative.x * m, _look_pitch - event.relative.y * m * (-1.0 if Graphics.invert_look else 1.0))
		return
	if event is InputEventJoypadButton and event.is_action_pressed("sprint"):
		_sprint_latched = true
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("craft") and not event.is_echo():
		# Crafting and the notebook are the story's (its inventory and
		# objectives); Dead Block has neither.
		if GameState.mode == "story" and not dialogue_active and not get_tree().paused:
			get_viewport().set_input_as_handled()
			open_craft_menu()
	elif event.is_action_pressed("notebook") and not event.is_echo():
		if GameState.mode == "story" and not dialogue_active and not get_tree().paused:
			get_viewport().set_input_as_handled()
			var book := NotebookScript.new()
			get_tree().root.add_child(book)
			book.open()
	elif event is InputEventMouseButton and event.pressed and not _first_person and GameState.mode != "zombies" and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := -0.06 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.06
		_user_zoom = clampf(_user_zoom + step, CAM_USER_ZOOM.x, CAM_USER_ZOOM.y)
	elif event.is_action_pressed("cancel_ui") or event.is_action_pressed("pause"):
		# Menus parented to the root (the shoebox, the pusher, pool) get Esc
		# before this does; anything reaching here means the world has it.
		get_viewport().set_input_as_handled()
		if dialogue_active:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.dialogue_panel.visible:
				hud.advance_or_close_dialogue()
			return
		# Circle backs out of things; only Options (or Esc) pauses.
		if get_tree().paused or _busy_timer > 0.0 or not event.is_action_pressed("pause"):
			return
		var menu := PauseMenuScript.new()
		get_tree().root.add_child(menu)
		menu.open()

## Turns to face `target_pos` and plays the pick-up animation, holding the
## player still until it's done. Returns how long that takes.
func play_pickup(target_pos: Vector3) -> float:
	var to_target := target_pos - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		_facing_angle = atan2(to_target.x, to_target.z)
		model.rotation.y = _facing_angle
	var duration := MetaProgress.pickup_duration(PICKUP_DURATION) * grab_time_mult()
	_busy_timer = anim.play_once_timed("pick-up", duration)
	return _busy_timer

## How much longer a grab takes with shaking hands: nothing when well, +TREMOR_GRAB_MULT at the
## bottom of the meter, smoothly in between.
func grab_time_mult() -> float:
	return 1.0 + TREMOR_GRAB_MULT * GameState.sickness()

## The chance a grab goes wrong right now (see FUMBLE_FROM).
func fumble_chance() -> float:
	return FUMBLE_MAX * clampf((GameState.sickness() - FUMBLE_FROM) / (1.0 - FUMBLE_FROM), 0.0, 1.0)

## Rolled once per grab, before anything is taken (items/StealableItem3D.gd).
func roll_fumble() -> bool:
	var roll := fumble_roll_override if fumble_roll_override >= 0.0 else randf()
	return roll < fumble_chance()

## Walking among passersby (not running, not crouched): a cop more than a
## few metres off loses you in the crowd (npc/Police3D.gd).
const CROWD_RADIUS := 2.0
func in_crowd() -> bool:
	if hiding or is_sprinting():
		return false
	for p in get_tree().get_nodes_in_group("pedestrians"):
		if (p as Node3D).global_position.distance_to(global_position) <= CROWD_RADIUS:
			return true
	return false

func set_hiding(value: bool) -> void:
	hiding = value
	anim.set_rest_clip("sit" if hiding else "idle")
	model.position.y = -0.35 if hiding else 0.0

## True while actually running, for the guards' suspicion check.
func is_sprinting() -> bool:
	return _sprinting

## High: a dose of an opioid in the last HIGH_SECONDS (real), and not sick.
const HIGH_SECONDS := 150.0
const HIGH_ANIM_MULT := 0.8

func is_high() -> bool:
	var since := GameState.run_time - float(GameState.last_dose_at.get(Drugs.OPIOID, -99999.0))
	return since < HIGH_SECONDS and GameState.sickness() < 0.3

func is_busy() -> bool:
	return _busy_timer > 0.0

func _try_interact() -> void:
	if _busy_timer > 0.0:
		return
	if dialogue_active:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.advance_or_close_dialogue()
		return
	var target := _nearest_interactable()
	if target:
		# Talking to someone: the view settles on them, as your head would.
		if _first_person and _is_person(target):
			ease_look_to(target.global_position + Vector3(0, 1.45, 0))
		if story_hands != null:
			story_hands.reach(target.global_position, target.get("item_id") != null)
		target.interact(self)

## What E would use, and what the prompt names: the thing the crosshair is on,
## else the closest thing in reach. Both ask here, so the prompt and E agree.
##
## The closest is not the first one that came into range: interaction areas
## overlap (the Apartment's phone reaches almost to the door), and "first in"
## would keep picking the phone long after you'd walked over to the door.
## But in first person the nearest alone is wrong too -- the pool zone under
## your feet is nearer than the bar door you are looking at -- so the view ray
## decides, and distance only breaks the tie when nothing is aimed at.
func _nearest_interactable() -> Node3D:
	nearby = nearby.filter(func(a): return is_instance_valid(a) and a.is_in_group("interactable"))
	var best: Node3D = null
	if _first_person and camera != null and camera.is_inside_tree():
		best = _aimed_interactable()
		if best != null:
			return best
	# Nothing aimed at: the closest, preferring what is in front of you (a door behind your back is
	# only offered when there is nothing else).
	var fwd := -camera.global_transform.basis.z if camera != null and camera.is_inside_tree() else Vector3.ZERO
	var best_dist := INF
	var best_behind: Node3D = null
	var best_behind_dist := INF
	for area in nearby:
		if not area.has_method("interact"):
			continue
		var d := Vector2(area.global_position.x - global_position.x, area.global_position.z - global_position.z).length()
		var to := Vector3(area.global_position.x - global_position.x, 0.0, area.global_position.z - global_position.z)
		if _first_person and d > 0.5 and Vector3(fwd.x, 0.0, fwd.z).dot(to) < 0.0:
			if d < best_behind_dist:
				best_behind_dist = d
				best_behind = area
			continue
		if d < best_dist:
			best_dist = d
			best = area
	return best if best != null else best_behind

## A thing counts as aimed at when the view ray enters one of its shapes, or
## the centre of one is within this many degrees of the crosshair.
const AIM_CONE_DEG := 9.0
## Inside a thing's own area, the crosshair this close to its centre is a hit.
const INSIDE_AIM_COS := 0.996
## An aimed thing behind a wall is not aimed at: the ray must reach it
## within this much (m) of its centre.
const AIM_OCCLUDE_SLACK := 0.6
var _shape_aabbs := {}

## The interactable (in reach) under the crosshair, or null. Ray entry beats
## the cone; among ray hits the nearer entry wins, among cone hits the smaller angle.
func _aimed_interactable() -> Node3D:
	# The prompt, the HUD, the weapon holder and E all ask, several times a frame: one answer per drawn
	# frame for the same view, place and set of things in reach.
	var frame := Engine.get_process_frames()
	var xf := camera.global_transform
	if frame == _aim_frame and xf == _aim_xf and global_position == _aim_pos and nearby.size() == _aim_n and (_aim_result == null or is_instance_valid(_aim_result)):
		return _aim_result
	_aim_result = _aimed_uncached()
	_aim_frame = frame
	_aim_xf = xf
	_aim_pos = global_position
	_aim_n = nearby.size()
	return _aim_result

var _aim_frame := -1
var _aim_xf := Transform3D()
var _aim_pos := Vector3.ZERO
var _aim_n := -1
var _aim_result: Node3D
## Each reachable area's collision shapes, found once (find_children on an NPC walks its whole model).
var _shape_cache := {}

func _shapes_of(area: Node) -> Array:
	var id := area.get_instance_id()
	var shapes: Array = _shape_cache.get(id, [])
	if shapes.is_empty() or not is_instance_valid(shapes[0]):
		shapes = area.find_children("*", "CollisionShape3D", true, false)
		_shape_cache[id] = shapes
	return shapes

func _aimed_uncached() -> Node3D:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var cone_cos := cos(deg_to_rad(AIM_CONE_DEG))
	var best: Node3D = null
	var best_score := INF
	var best_point := Vector3.ZERO
	for area in nearby:
		if not area.has_method("interact"):
			continue
		for sh in _shapes_of(area):
			var cs := sh as CollisionShape3D
			if cs.disabled or cs.shape == null:
				continue
			var box := _shape_aabb(cs.shape)
			var xf := cs.global_transform
			var inv := xf.affine_inverse()
			var centre := xf * box.get_center()
			var score := INF
			var point := centre
			var t := _ray_box(inv * from, inv.basis * dir, box)
			if t > 0.0:
				# Entered from outside: nearer entries first, ahead of every cone hit.
				# (Equal entries, as overlapping boxes have looking down at them: the one the crosshair is
				# nearer the middle of.)
				var to_c := centre - from
				score = -1.0 + t * 0.001 + (1.0 - dir.dot(to_c.normalized())) * 0.01
				point = from + dir * t
			else:
				var to := centre - from
				var dist := to.length()
				if dist > 0.05 and dir.dot(to / dist) >= cone_cos:
					score = 1.0 - dir.dot(to / dist)
					# Standing in someone's reach and looking straight at them beats a zone you only graze.
					if dir.dot(to / dist) >= INSIDE_AIM_COS and box.has_point(inv * from):
						score = -1.0 + dist * 0.001
			if score < best_score:
				best_score = score
				best = area
				best_point = point
	if best == null:
		return null
	# A wall between the eye and it: not what you are looking at.
	var q := PhysicsRayQueryParameters3D.create(from, best_point, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and from.distance_to(hit["position"]) < from.distance_to(best_point) - AIM_OCCLUDE_SLACK:
		return null
	return best

func _shape_aabb(shape: Shape3D) -> AABB:
	if _shape_aabbs.has(shape):
		return _shape_aabbs[shape]
	var box: AABB
	if shape is BoxShape3D:
		box = AABB(-shape.size * 0.5, shape.size)
	elif shape is SphereShape3D:
		box = AABB(Vector3.ONE * -shape.radius, Vector3.ONE * shape.radius * 2.0)
	elif shape is CapsuleShape3D:
		box = AABB(Vector3(-shape.radius, -shape.height * 0.5, -shape.radius), Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0))
	elif shape is CylinderShape3D:
		box = AABB(Vector3(-shape.radius, -shape.height * 0.5, -shape.radius), Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0))
	else:
		box = shape.get_debug_mesh().get_aabb()
	_shape_aabbs[shape] = box
	return box

## Distance along a ray (local space; `dir` need not be unit) to where it
## enters `box` from outside, or -1 when it misses, starts inside, or points away.
static func _ray_box(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t_near := -INF
	var t_far := INF
	var lo := box.position
	var hi := box.end
	for i in 3:
		if absf(dir[i]) < 1e-8:
			if from[i] < lo[i] or from[i] > hi[i]:
				return -1.0
		else:
			var t1 := (lo[i] - from[i]) / dir[i]
			var t2 := (hi[i] - from[i]) / dir[i]
			t_near = maxf(t_near, minf(t1, t2))
			t_far = minf(t_far, maxf(t1, t2))
	if t_near > t_far or t_far < 0.0 or t_near <= 0.0:
		return -1.0
	return t_near

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("interactable"):
		nearby.append(area)

func _on_area_exited(area: Area3D) -> void:
	nearby.erase(area)
	_shape_cache.erase(area.get_instance_id())

func begin_theft_window(duration: float) -> void:
	# The shaking hands that make the grab longer keep you looking like a thief for as long.
	duration *= grab_time_mult()
	is_stealing = true
	# Only the latest theft's timer may end the window, so a quick second grab
	# isn't cut short by the first one's timer.
	_theft_serial += 1
	var serial := _theft_serial
	get_tree().create_timer(duration).timeout.connect(func():
		if serial == _theft_serial:
			is_stealing = false)
