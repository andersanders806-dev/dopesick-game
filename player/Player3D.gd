extends CharacterBody3D
## First-person player: mouse look, walk/sprint/crouch/jump, a flashlight,
## look-to-interact, and the rifle (player/Weapon.gd) under the camera.
##
## Your own body is still here and still animated -- it just renders as a
## shadow only, so you see yourself on the floor under a streetlight but
## never the inside of your own head.

const BASE_SPEED := 4.2
## Sprinting is the risk/reward half of the stealth layer: it gets you out of
## a room fast, and it is the single loudest thing you can do in front of a
## guard (see Guard3D.SUSPICION_SPRINTING). Withdrawal takes it away -- when
## you are sick you cannot run, which is when you most need to.
const SPRINT_MULT := 1.55
const SICK_SPEED_MULT := 0.55
const SICK_THRESHOLD := 20.0
const CROUCH_MULT := 0.5
const ADS_MULT := 0.62
const ACCEL := 14.0
## Stopping is much sharper than starting, so letting go of the keys plants
## your feet instead of coasting.
const DECEL := 40.0
const STOP_SNAP := 0.25
const AIR_ACCEL := 2.5
const JUMP_VELOCITY := 4.3
const GRAVITY := 11.0
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05
const PITCH_LIMIT := 1.53

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

# One full walk cycle is two footfalls.
const STEP_INTERVAL := 0.333

## How long the player is rooted in place for a grab. Long enough to read
## as deliberate rather than a twitch; the animation is stretched to fit,
## whatever its authored length.
const PICKUP_DURATION := 0.6

@onready var interact_zone: Area3D = $InteractZone
@onready var model: Node3D = $Model
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var listener: AudioListener3D = $Listener

var nearby: Array = []
var dialogue_active: bool = false
var is_stealing: bool = false
var anim: CharacterAnimator
var _step_timer: float = 0.0
var _left_foot: bool = true
var _sprinting: bool = false
var _crouching: bool = false
var _grounded: bool = true
var _busy_timer: float = 0.0
var _theft_serial: int = 0
var dead: bool = false

## Off for the screenshot tool, so a capture never grabs the desktop's mouse.
var capture_mouse: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
## The part of the recoil that springs back on its own; the rest stays, and
## it's on the player to pull the muzzle down.
var _recoil_pitch: float = 0.0
var _shake: float = 0.0
var _bob_t: float = 0.0
var _eye: float = EYE_HEIGHT

func _ready() -> void:
	add_to_group("player")
	CharacterCast.dress(model, "player")
	anim = CharacterAnimator.new(model)
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	listener.make_current()
	camera.make_current()
	weapon.player = self
	interact_zone.area_entered.connect(_on_area_entered)
	interact_zone.area_exited.connect(_on_area_exited)
	GameState.player_damaged.connect(_on_damaged)
	GameState.player_died.connect(_on_died)
	camera.fov = Settings.fov
	_apply_look()

## Points the view. Rooms call this on spawn to face you into the room; the
## headless tests call it with 0 so "move_right" is still world +X.
func set_look(new_yaw: float, new_pitch := 0.0) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_apply_look()

func _apply_look() -> void:
	head.rotation.y = yaw
	camera.rotation.x = clampf(pitch + _recoil_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	listener.rotation.y = yaw
	# The body faces where you look (its forward is +Z, the camera's is -Z).
	model.rotation.y = yaw + PI

func _process(delta: float) -> void:
	_update_mouse_mode()
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-9.0 * delta))
	_shake = move_toward(_shake, 0.0, delta * 2.5)

	# Crouching lowers the eye; dying drops it to the floor.
	var target_eye := CROUCH_EYE_HEIGHT if _crouching else EYE_HEIGHT
	if dead:
		target_eye = 0.35
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-(4.0 if dead else 12.0) * delta))
	head.position.y = _eye

	var cam_offset := Vector3.ZERO
	var speed := horizontal_speed()
	if Settings.head_bob and _grounded and speed > 0.3 and not dead:
		_bob_t += delta * speed * 2.1
		var amt: float = clampf(speed / BASE_SPEED, 0.0, 1.5) * (1.0 - weapon.ads * 0.8)
		cam_offset = Vector3(sin(_bob_t) * 0.025, absf(cos(_bob_t)) * 0.035, 0.0) * amt
	if _shake > 0.0:
		cam_offset += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.03
	camera.position = camera.position.lerp(cam_offset, 1.0 - exp(-18.0 * delta))
	camera.rotation.z = lerpf(camera.rotation.z, 1.1 if dead else 0.0, 1.0 - exp(-3.0 * delta))
	_apply_look()

	var fov := Settings.fov
	fov *= lerpf(1.0, 0.72, weapon.ads)
	if _sprinting:
		fov *= 1.07
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-12.0 * delta))

## The mouse is the camera during play, and a pointer whenever anything
## wants clicking: dialogue, the drug menu, the run-end screen, pause.
func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless" or not capture_mouse:
		return
	var want := Input.MOUSE_MODE_CAPTURED
	if dialogue_active or dead or get_tree().paused or not get_tree().get_nodes_in_group("modal_ui").is_empty():
		want = Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

func can_use_weapon() -> bool:
	return not dialogue_active and not dead and _busy_timer <= 0.0 and not get_tree().paused \
		and get_tree().get_nodes_in_group("modal_ui").is_empty()

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func is_grounded() -> bool:
	return _grounded

func is_crouching() -> bool:
	return _crouching

func add_recoil(pitch_kick: float, yaw_kick: float) -> void:
	pitch = clampf(pitch + pitch_kick * 0.55, -PITCH_LIMIT, PITCH_LIMIT)
	_recoil_pitch += pitch_kick * 0.45
	yaw += yaw_kick

func _physics_process(delta: float) -> void:
	if not _grounded:
		velocity.y -= GRAVITY * delta

	if dialogue_active or dead or _busy_timer > 0.0:
		# Rooted in place while talking, dead, or while an action animation
		# (e.g. grabbing an item) plays.
		if _busy_timer > 0.0:
			_busy_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_sprinting = false
		_move(delta)
		if _busy_timer <= 0.0:
			anim.update(0.0)
		_update_footsteps(delta, false, 1.0)
		return

	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var speed := BASE_SPEED
	var sick := GameState.craving <= SICK_THRESHOLD
	_crouching = Input.is_action_pressed("crouch")
	_sprinting = (not sick) and (not _crouching) and dir.length() > 0.1 and Input.is_action_pressed("sprint") \
		and not Input.is_action_pressed("aim") and not Input.is_action_pressed("fire")
	if sick:
		speed *= SICK_SPEED_MULT
	elif _sprinting:
		speed *= SPRINT_MULT
	if _crouching:
		speed *= CROUCH_MULT
	speed *= lerpf(1.0, ADS_MULT, weapon.ads)

	var accel := AIR_ACCEL
	if _grounded:
		accel = ACCEL if dir.length() > 0.1 else DECEL
	var t := 1.0 - exp(-accel * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, t)
	velocity.z = lerpf(velocity.z, dir.z * speed, t)
	if _grounded and dir.length() <= 0.1 and horizontal_speed() < STOP_SNAP:
		velocity.x = 0.0
		velocity.z = 0.0
	if _grounded and Input.is_action_just_pressed("jump") and not _crouching:
		velocity.y = JUMP_VELOCITY
		_grounded = false
	_move(delta)

	# Withdrawal slows the stride along with the movement, so it reads as a
	# shuffle rather than the feet sliding.
	var anim_speed := SICK_SPEED_MULT if sick else 1.0
	if _sprinting:
		anim.play("sprint", anim_speed)
	else:
		anim.update(horizontal_speed(), anim_speed)
	_update_footsteps(delta, _grounded and dir.length() > 0.1, anim_speed * (SPRINT_MULT if _sprinting else 1.0) * (0.6 if _crouching else 1.0))

## Moves, then lands on y = 0 if there's nothing higher underneath. Floors
## sit on physics layer 5, which the player's body doesn't collide with (so
## the guards' and police's rays keep working as they always have); the
## ground plane stands in for them, and furniture on layer 1 can still be
## stood on.
func _move(_delta: float) -> void:
	move_and_slide()
	if global_position.y <= 0.0:
		global_position.y = 0.0
		velocity.y = maxf(velocity.y, 0.0)
		_grounded = true
	else:
		_grounded = is_on_floor()
		if _grounded:
			velocity.y = 0.0

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
	SFX.play("footstep_a" if _left_foot else "footstep_b", -8.0 - (6.0 if _crouching else 0.0), randf_range(0.92, 1.05))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not dead:
		var sens := Settings.look_radians_per_pixel() * lerpf(1.0, 0.6, weapon.ads)
		var rel: Vector2 = event.relative
		yaw -= rel.x * sens
		pitch -= rel.y * sens * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
		weapon.add_sway(rel)
		_apply_look()
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("flashlight") and not dead:
		flashlight.visible = not flashlight.visible
		SFX.play("blip", -10.0, 1.6)

## Holds the player still while the grab animation plays. Returns how long
## that takes. (The body you can't see turns to face it; the view doesn't.)
func play_pickup(target_pos: Vector3) -> float:
	var to_target := target_pos - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		model.rotation.y = atan2(to_target.x, to_target.z)
	_busy_timer = anim.play_once_timed("pick-up", MetaProgress.pickup_duration(PICKUP_DURATION))
	return _busy_timer

## True while actually running, for the guards' suspicion check.
func is_sprinting() -> bool:
	return _sprinting

func is_busy() -> bool:
	return _busy_timer > 0.0

func _try_interact() -> void:
	if _busy_timer > 0.0 or dead:
		return
	if dialogue_active:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.advance_or_close_dialogue()
		return
	var target := interact_target()
	if target:
		target.interact(self)

## What pressing E would use right now. Among the things in reach, the one
## you're looking at wins; distance only breaks ties. (Interaction areas
## overlap -- the Apartment's mattress reaches almost to the door -- so
## "first in" or "nearest" alone keeps picking the wrong one.)
func interact_target() -> Node3D:
	nearby = nearby.filter(func(a): return is_instance_valid(a) and a.is_in_group("interactable"))
	var forward := -camera.global_basis.z
	var eye := camera.global_position
	var best: Node3D = null
	var best_score := INF
	for area in nearby:
		if not area.has_method("interact"):
			continue
		var to: Vector3 = area.global_position - eye
		var flat := Vector2(area.global_position.x - global_position.x, area.global_position.z - global_position.z).length()
		var facing := Vector2(forward.x, forward.z).normalized().dot(Vector2(to.x, to.z).normalized()) if flat > 0.05 else 1.0
		var score := flat - facing * 1.5
		if score < best_score:
			best_score = score
			best = area
	return best

## Plain nearest-in-reach, ignoring where you're looking. The headless tests
## steer by this; E itself uses interact_target().
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

## The "[E] ..." line under the crosshair.
func interact_prompt() -> String:
	if dialogue_active or dead or _busy_timer > 0.0:
		return ""
	var t := interact_target()
	if t == null:
		return ""
	if t.has_method("prompt_text"):
		return t.prompt_text()
	if "item_id" in t:
		return "Steal %s" % GameState.item_name_for(t.item_id)
	if t.is_in_group("pusher"):
		return "Talk to the pusher"
	if "npc_name" in t:
		return "Talk to %s" % t.npc_name
	return "Use"

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

func _on_damaged(amount: float, _from: Vector3) -> void:
	_shake = minf(1.0, _shake + amount / 25.0)
	SFX.play("player_hurt", -4.0, randf_range(0.9, 1.1))

## Shot down. The view drops to the floor, then you come round in custody --
## a strike, like any other arrest.
func _on_died() -> void:
	if dead:
		return
	dead = true
	flashlight.visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("flash_wasted"):
		hud.flash_wasted()
	var tree := get_tree()
	tree.create_timer(2.6).timeout.connect(func():
		GameState.get_busted()
		GameState.pending_spawn = "SpawnCell"
		tree.change_scene_to_file("res://world/Jail3D.tscn"))
