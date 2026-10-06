extends CharacterBody3D

const PauseMenuScript := preload("res://ui/PauseMenu.gd")
const FirstPersonRoom := preload("res://world/FirstPersonRoom.gd")
const NotebookScript := preload("res://ui/Notebook.gd")
const BASE_SPEED := 4.2
## Sprinting is the risk/reward half of the stealth layer: it gets you out of
## a room fast, and it is the single loudest thing you can do in front of a
## guard (see Guard3D.SUSPICION_SPRINTING). Withdrawal takes it away -- when
## you are sick you cannot run, which is when you most need to.
const SPRINT_MULT := 1.55
const SICK_SPEED_MULT := 0.55
const SICK_THRESHOLD := 20.0
## Limping for a few hours after the collector's been at you.
const HURT_SPEED_MULT := 0.75
const TURN_SPEED := 10.0
## Getting up to speed and pulling up: about a fifth of a second either
## way, so starts and stops ease instead of snapping.
const ACCEL := 24.0
const DECEL := 30.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

# One full walk cycle is two footfalls.
const STEP_INTERVAL := 0.333

## How long the player is rooted in place for a grab. Long enough to read
## as deliberate rather than a twitch; the animation is stretched to fit,
## whatever its authored length.
const PICKUP_DURATION := 0.6
## In withdrawal your hands shake: a grab takes up to this much longer at
## the bottom of the meter, which is more time rooted in a guard's view.
const TREMOR_GRAB_MULT := 0.6
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
const CAM_FOLLOW := 8.0
## Of the scene file's 9 m-high rig: close enough to read faces and hands.
const CAM_ZOOM := 0.75
const CAM_USER_ZOOM := Vector2(0.7, 1.4)
var _cam_offset: Vector3
var _cam_focus: Vector3
var _user_zoom: float = 1.0
## Zoom per second at full right-stick tilt.
const PAD_ZOOM_RATE := 0.8
var _sprint_latched: bool = false
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
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _tp_camera_base: Transform3D
var _tp_fov: float
var _shake_t: float = 0.0
var _cramp_timer: float = 0.0

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
	interact_zone.area_entered.connect(_on_area_entered)
	interact_zone.area_exited.connect(_on_area_exited)
	Graphics.view_changed.connect(_apply_view)
	# Deferred: the room around us is still being built.
	_apply_view.call_deferred(Graphics.first_person)

func _apply_view(on: bool) -> void:
	_first_person = on
	for m in model.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if on:
		# Look the way you were facing.
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
	_update_camera_rig(0.0)

## Where you're looking, in radians: yaw round from -Z, pitch up from level.
func set_look(yaw: float, pitch: float) -> void:
	_look_yaw = wrapf(yaw, -PI, PI)
	_look_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)

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
		$CameraMount.global_position = global_position + Vector3(0, EYE_HEIGHT, 0)
		$CameraMount.rotation = Vector3(_look_pitch, _look_yaw, 0.0)
		return
	var target := global_position
	# Snap after a spawn or a door; ease otherwise.
	if not _cam_ready or _cam_focus.distance_to(target) > 8.0:
		_cam_focus = target
		_cam_ready = true
	else:
		_cam_focus = _cam_focus.lerp(target, 1.0 - exp(-CAM_FOLLOW * delta))
	$CameraMount.global_position = _cam_focus + _cam_offset * CAM_ZOOM * _user_zoom

## The view trembles and lists in withdrawal: two sine waves at unrelated
## rates, so it never settles into a rhythm you can tune out.
func _update_camera_shake(delta: float) -> void:
	var s := GameState.sickness()
	_shake_t += delta
	var offset := Vector3(sin(_shake_t * 1.7) + 0.5 * sin(_shake_t * 5.3), cos(_shake_t * 1.3) * 0.6, 0.0) * SHAKE_OFFSET * s
	var roll := deg_to_rad(sin(_shake_t * 0.8) * SHAKE_ROLL_DEG * s)
	camera.transform = _camera_base.translated_local(offset).rotated_local(Vector3.FORWARD, roll)

## Doubled over by a cramp: rooted for a moment, with a groan.
func _update_cramps(delta: float) -> void:
	if GameState.craving > SICK_THRESHOLD:
		_cramp_timer = randf_range(CRAMP_INTERVAL.x, CRAMP_INTERVAL.y)
		return
	_cramp_timer -= delta
	if _cramp_timer > 0.0:
		return
	_cramp_timer = randf_range(CRAMP_INTERVAL.x, CRAMP_INTERVAL.y)
	_busy_timer = anim.play_once_timed("pick-up", CRAMP_DURATION)
	SFX.play("groan", -6.0, randf_range(0.9, 1.0))

func _physics_process(delta: float) -> void:
	if _first_person:
		# The right stick looks round, as the mouse does.
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.0 and not dialogue_active:
			set_look(_look_yaw - look.x * LOOK_SPEED * delta, _look_pitch - look.y * LOOK_SPEED * delta)
	else:
		# The right stick pulls the camera in and out, as the wheel does.
		var zoom := Input.get_axis("look_up", "look_down")
		if absf(zoom) > 0.0:
			_user_zoom = clampf(_user_zoom + zoom * PAD_ZOOM_RATE * delta, CAM_USER_ZOOM.x, CAM_USER_ZOOM.y)
	# On the physics tick, so interpolation smooths the shake with the rest.
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
	var sick := GameState.craving <= SICK_THRESHOLD
	var hurt := GameState.is_hurt()
	# Hold Shift, or click L3 once and keep going, like COD: a pad sprint
	# lasts until you let the stick go.
	if dir.length() <= 0.1:
		_sprint_latched = false
	_sprinting = (not sick) and (not hurt) and dir.length() > 0.1 and (Input.is_action_pressed("sprint") or _sprint_latched)
	if sick:
		speed *= SICK_SPEED_MULT
	elif _sprinting:
		speed *= SPRINT_MULT
	if hurt:
		speed *= HURT_SPEED_MULT
	if Jobs.carrying_box():
		speed *= Jobs.CARRY_SPEED

	var target := dir * speed
	velocity = velocity.move_toward(target, (ACCEL if dir.length() > 0.1 else DECEL) * delta)
	move_and_slide()
	# Withdrawal slows the stride along with the movement, so it reads as a
	# shuffle rather than the feet sliding; so does easing in and out.
	var moved := Vector2(velocity.x, velocity.z).length()
	# Sick, you walk like it: a hunched, bruised shuffle and a fidget when
	# you stand, on the bodies that have those clips. The shuffle is already
	# slow, so it isn't slowed again.
	var sick_clips: bool = sick and anim.has_clip("walk_sick")
	if not hiding:
		anim.set_clips("walk_sick" if sick_clips else "walk", "idle_sick" if sick and anim.has_clip("idle_sick") else "idle")
	var anim_speed := (SICK_SPEED_MULT if sick and not sick_clips else 1.0) * clampf(moved / maxf(speed, 0.01), 0.35, 1.0)
	if _sprinting:
		anim.play("sprint", anim_speed)
	else:
		anim.update(moved, anim_speed)
	_update_footsteps(delta, dir.length() > 0.1, anim_speed * (SPRINT_MULT if _sprinting else 1.0))

	if dir.length() > 0.1:
		var target_angle := atan2(dir.x, dir.z)
		_facing_angle = lerp_angle(_facing_angle, target_angle, TURN_SPEED * delta)
		model.rotation.y = _facing_angle

## Footfalls stay in step with the walk animation: same cycle length, and
## slowed by the same factor when the stride slows in withdrawal.
func _update_footsteps(delta: float, moving: bool, anim_speed: float) -> void:
	if not moving:
		# Next step lands soon after starting to walk again, not instantly.
		_step_timer = STEP_INTERVAL * 0.5
		return
	_step_timer -= delta * anim_speed
	if _step_timer > 0.0:
		return
	_step_timer += STEP_INTERVAL
	_left_foot = not _left_foot
	SFX.play_footstep(-8.0, randf_range(0.92, 1.05))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _first_person:
		set_look(_look_yaw - event.relative.x * MOUSE_SENS, _look_pitch - event.relative.y * MOUSE_SENS)
		return
	if event is InputEventJoypadButton and event.is_action_pressed("sprint"):
		_sprint_latched = true
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("notebook") and not event.is_echo():
		if not dialogue_active and not get_tree().paused:
			get_viewport().set_input_as_handled()
			var book := NotebookScript.new()
			get_tree().root.add_child(book)
			book.open()
	elif event is InputEventMouseButton and event.pressed and not _first_person and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
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
	var duration := MetaProgress.pickup_duration(PICKUP_DURATION)
	if GameState.craving <= SICK_THRESHOLD:
		duration *= 1.0 + TREMOR_GRAB_MULT * GameState.sickness()
	_busy_timer = anim.play_once_timed("pick-up", duration)
	return _busy_timer

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
		target.interact(self)

## The closest thing in reach, not the first one that came into range:
## interaction areas can overlap (the Apartment's phone reaches almost to the
## door), and "first in" would keep picking the phone long after you'd
## walked over to the door.
func _nearest_interactable() -> Node3D:
	nearby = nearby.filter(func(a): return is_instance_valid(a) and a.is_in_group("interactable"))
	var best: Node3D = null
	var best_dist := INF
	for area in nearby:
		if not area.has_method("interact"):
			continue
		var d := Vector2(area.global_position.x - global_position.x, area.global_position.z - global_position.z).length()
		if d < best_dist:
			best_dist = d
			best = area
	return best

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("interactable"):
		nearby.append(area)

func _on_area_exited(area: Area3D) -> void:
	nearby.erase(area)

func begin_theft_window(duration: float) -> void:
	is_stealing = true
	# Only the latest theft's timer may end the window, so a quick second grab
	# isn't cut short by the first one's timer.
	_theft_serial += 1
	var serial := _theft_serial
	get_tree().create_timer(duration).timeout.connect(func():
		if serial == _theft_serial:
			is_stealing = false)
