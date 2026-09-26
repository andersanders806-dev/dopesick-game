extends CharacterBody3D

const SPEED := 4.6
const LOSE_SIGHT_TIME := 4.0
const RETARGET_INTERVAL := 0.25
const TURN_SPEED := 10.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const Hitbox3D := preload("res://npc/Hitbox3D.gd")
const Effects := preload("res://fx/Effects.gd")

## --- Armed response ----------------------------------------------------------
## A theft gets you chased and cuffed, same as ever. Gunfire (see
## GameState.report_gunfire) changes the job: officers stop at range, take
## cover behind distance, and shoot. They don't try to cuff an armed suspect.
const MAX_HEALTH := 100.0
## Close enough to open fire, and the distance they hold while shooting.
const ENGAGE_RANGE := 16.0
const HOLD_RANGE := 7.0
const SHOT_INTERVAL := Vector2(0.38, 0.75)
## Rounds per burst before a short pause to "re-acquire".
const BURST := Vector2i(2, 4)
const BURST_PAUSE := Vector2(0.7, 1.4)
const DAMAGE := Vector2(7.0, 12.0)
## How long without seeing you before an armed officer gives up. Longer
## than a plain chase: nobody lets a shooter just walk away.
const LETHAL_LOSE_SIGHT_TIME := 9.0

# The Kenney sprint clip is 0.5 s per cycle, two footfalls.
const STEP_INTERVAL := 0.25

const BEACON_FLIP_TIME := 0.3
const BEACON_RED := Color(1, 0.15, 0.1, 1)
const BEACON_BLUE := Color(0.15, 0.35, 1, 1)

@onready var catch_zone: Area3D = $CatchZone
@onready var nav_agent: NavigationAgent3D = $NavAgent
@onready var model: Node3D = $Model
@onready var beacon: OmniLight3D = $Beacon
@onready var footsteps: AudioStreamPlayer3D = $Footsteps

var _lose_timer: float = 0.0
var _retarget_timer: float = 0.0
var _facing_angle: float = 0.0
var _beacon_timer: float = 0.0
var _beacon_red: bool = true
var anim: CharacterAnimator
var _step_timer: float = 0.0
var _left_foot: bool = true
var health: float = MAX_HEALTH
var dead: bool = false
var _shot_timer: float = 1.0
var _burst_left: int = 0
var _hitbox: StaticBody3D
var _gun_muzzle: Node3D

func _ready() -> void:
	add_to_group("police")
	CharacterCast.dress(model, "police")
	anim = CharacterAnimator.new(model, "sprint")
	GameState.set_wanted(true)
	catch_zone.body_entered.connect(_on_catch_body_entered)
	_hitbox = Hitbox3D.attach(self, self)
	_arm()
	# First shot comes after a beat, not the instant they round the corner.
	_shot_timer = randf_range(0.8, 1.4)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		nav_agent.target_position = player.global_position

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return

	if dead:
		return
	var sees := _has_line_of_sight(player)
	if sees:
		_lose_timer = 0.0
		_retarget_timer -= delta
		if _retarget_timer <= 0.0:
			_retarget_timer = RETARGET_INTERVAL
			nav_agent.target_position = player.global_position
	else:
		_lose_timer += delta
		if _lose_timer >= (LETHAL_LOSE_SIGHT_TIME if GameState.lethal else LOSE_SIGHT_TIME):
			_give_up()
			return

	var dist := global_position.distance_to(player.global_position)
	var shooting := GameState.lethal and sees and dist <= ENGAGE_RANGE and GameState.health > 0.0
	if shooting and dist <= HOLD_RANGE:
		# In range with a clear shot: plant your feet and fire.
		velocity = Vector3.ZERO
	elif nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
	else:
		var next_point: Vector3 = nav_agent.get_next_path_position()
		var to_next: Vector3 = next_point - global_position
		to_next.y = 0.0
		# Advancing while shooting is a walk, not a sprint.
		velocity = to_next.normalized() * SPEED * (0.45 if shooting else 1.0)
	move_and_slide()
	if shooting:
		_face_toward(player.global_position, delta)
		_update_shooting(player, dist, delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	anim.update(speed)
	_update_footsteps(delta, speed > 0.1)

	if Vector2(velocity.x, velocity.z).length() > 0.1 and not shooting:
		var target_angle := atan2(velocity.x, velocity.z)
		_facing_angle = lerp_angle(_facing_angle, target_angle, TURN_SPEED * delta)
		model.rotation.y = _facing_angle

	_update_beacon(delta)

## Positional, so you can hear an officer coming round a shelf before you
## see them.
func _update_footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer += STEP_INTERVAL
	_left_foot = not _left_foot
	footsteps.stream = SFX.SOUNDS["footstep_a" if _left_foot else "footstep_b"]
	footsteps.pitch_scale = randf_range(0.85, 0.95)
	footsteps.play()

func _update_beacon(delta: float) -> void:
	_beacon_timer += delta
	if _beacon_timer >= BEACON_FLIP_TIME:
		_beacon_timer = 0.0
		_beacon_red = not _beacon_red
		beacon.light_color = BEACON_RED if _beacon_red else BEACON_BLUE

func _has_line_of_sight(player: Node) -> bool:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 0.8, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

func _face_toward(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	_facing_angle = lerp_angle(_facing_angle, atan2(to.x, to.z), TURN_SPEED * delta)
	model.rotation.y = _facing_angle

## Hit chance falls with distance and with how hard you are to track --
## moving, crouched, or in the air all help. Misses still crack past you.
func _update_shooting(player: Node, dist: float, delta: float) -> void:
	_shot_timer -= delta
	if _shot_timer > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = randi_range(BURST.x, BURST.y)
	_burst_left -= 1
	_shot_timer = randf_range(SHOT_INTERVAL.x, SHOT_INTERVAL.y)
	if _burst_left <= 0:
		_shot_timer += randf_range(BURST_PAUSE.x, BURST_PAUSE.y)

	var chance := 0.62 - dist * 0.022
	if player.has_method("horizontal_speed"):
		chance -= clampf(player.horizontal_speed() / 6.0, 0.0, 1.0) * 0.18
	if player.has_method("is_crouching") and player.is_crouching():
		chance -= 0.1
	if player.has_method("is_grounded") and not player.is_grounded():
		chance -= 0.12
	chance = clampf(chance, 0.08, 0.65)

	var muzzle_pos := _gun_muzzle.global_position if _gun_muzzle else global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	var hit := randf() < chance
	if hit:
		GameState.damage_player(randf_range(DAMAGE.x, DAMAGE.y), global_position)
	else:
		target += Vector3(randf_range(-1, 1), randf_range(-0.4, 0.8), randf_range(-1, 1)).normalized() * randf_range(0.6, 1.4)
		# The miss lands somewhere: sparks where it strikes.
		var dir := (target - muzzle_pos).normalized()
		var q := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + dir * 60.0, 1 | 16)
		q.exclude = [get_rid()]
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			target = r.position
			Effects.impact(self, r.position, r.normal)
	if _gun_muzzle:
		Effects.muzzle_flash(_gun_muzzle, 0.7)
	Effects.tracer(self, muzzle_pos, target)
	Effects.sound_at(self, "pistol_shot", muzzle_pos, 2.0, randf_range(0.92, 1.05), 60.0)

## A service pistol in the right hand. Held in the palm bone so it follows
## the run cycle.
func _arm() -> void:
	var skeleton: Node = null
	for found in model.find_children("*", "Skeleton3D", true, false):
		skeleton = found
	if not (skeleton is Skeleton3D):
		return
	var bone := (skeleton as Skeleton3D).find_bone("Palm.R")
	if bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_idx = bone
	skeleton.add_child(attach)
	var gun := Node3D.new()
	attach.add_child(gun)
	# The skeleton is scaled by the import and the scene; undo that so the
	# pistol is a real-world size.
	var s: Vector3 = attach.global_basis.get_scale()
	if s.x > 0.0001:
		gun.scale = Vector3.ONE / s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.07)
	mat.metallic = 0.7
	mat.roughness = 0.4
	for part in [[Vector3(0.03, 0.035, 0.19), Vector3(0, 0.03, 0.07)], [Vector3(0.028, 0.1, 0.035), Vector3(0, -0.02, 0.0)]]:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		bm.material = mat
		m.mesh = bm
		m.position = part[1]
		gun.add_child(m)
	_gun_muzzle = Node3D.new()
	_gun_muzzle.position = Vector3(0, 0.03, 0.17)
	gun.add_child(_gun_muzzle)

## Bullets land here via the Hitbox. Returns true when this one killed them.
func take_damage(amount: float, _hit_pos: Vector3, _from: Vector3) -> bool:
	if dead:
		return false
	health -= amount
	# Getting shot is gunfire too, whoever started it.
	GameState.report_gunfire()
	if health > 0.0:
		_shot_timer = minf(_shot_timer, 0.3)
		return false
	_die()
	return true

func _die() -> void:
	dead = true
	remove_from_group("police")
	velocity = Vector3.ZERO
	_hitbox.disable()
	collision_layer = 0
	catch_zone.set_deferred("monitoring", false)
	beacon.visible = false
	footsteps.stop()
	anim.play_once("death")
	set_physics_process(false)
	GameState.register_kill(true)
	Effects.drop_pickup(self, global_position + Vector3(0.4, 0, 0.2), randi_range(30, 60), randi_range(8, 30))

func _give_up() -> void:
	remove_from_group("police")
	# With backup on scene, one officer losing you doesn't end the hunt.
	if get_tree().get_first_node_in_group("police") == null:
		GameState.set_wanted(false)
	queue_free()

func _on_catch_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or GameState.in_custody or dead:
		return
	# Nobody tries to cuff somebody who's shooting at them.
	if GameState.lethal:
		return
	GameState.get_busted()
	body.dialogue_active = true  # hold still while being cuffed
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash_busted()
	set_physics_process(false)
	GameState.pending_spawn = "SpawnCell"
	# Hold the tree ourselves: this officer is freed below, and a timer
	# callback that calls *its* get_tree() would never fire.
	var tree := get_tree()
	tree.create_timer(0.9).timeout.connect(
		func(): tree.change_scene_to_file("res://world/Jail3D.tscn")
	)
	queue_free()
