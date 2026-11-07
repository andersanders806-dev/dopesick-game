extends "res://dev-tools/video_high_ground.gd"
## Dev helper: a recorded demo of Dead Block. A bot plays rounds 1..6 in full (until zm.round_ended(6)), then quits.
## It moves, aims, shoots and reloads like a player (real input actions, smooth aim, no teleports). If a quake +
## tsunami warning comes in any round it runs the route to the high ground, holds the stair, watches the wave and
## then fights on. Health is huge and the reserve is topped up (a demo, not a test). Safety limit: MAX_GAME_SECONDS.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --write-movie out.avi --fixed-fps 30 \
##     -s res://dev-tools/demo_deadblock_6.gd
const LAST_ROUND := 6
const MAX_GAME_SECONDS := 1500.0

var game_t := 0.0
var last_round_ended := 0
var strafe_dir := 1.0
var strafe_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var wander_yaw := 0.0
var turn_t := 0.0
var cleared: Array[int] = []

func _on_started(r: int) -> void:
	print("DEMO round %d start (t=%.0f s, alive=%d)" % [r, game_t, get_nodes_in_group("zombies").size()])

func _on_ended(r: int) -> void:
	print("DEMO round %d cleared (t=%.0f s, kills=%d)" % [r, game_t, zm.kills])
	cleared.append(r)
	last_round_ended = r

func _tick() -> void:
	await process_frame
	frames += 1
	game_t += maxf(root.get_process_delta_time(), 0.001)

func _release_all() -> void:
	for a in ["fire", "sprint", "move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(a)

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	zm = root.get_node("ZombieMode")
	root.get_node("GameState").no_sickness = true
	zm.round_started.connect(_on_started)
	zm.round_ended.connect(_on_ended)
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	p = get_first_node_in_group("player") as CharacterBody3D
	ts = block.tsunami
	hg = block.high_ground
	zm.health = 1e9
	var h: Node = p.get_node("WeaponHolder")
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	p.global_position = START
	p.set_look(PI / 2.0, 0.0)
	last_pos = p.global_position
	var was_warned := false
	var why := "unknown"
	while true:
		await _tick()
		if last_round_ended >= LAST_ROUND:
			why = "round %d cleared" % LAST_ROUND
			break
		if game_t > MAX_GAME_SECONDS:
			why = "safety limit %.0f s (round %d)" % [MAX_GAME_SECONDS, zm.round]
			break
		if zm.over:
			why = "game over (round %d)" % zm.round
			break
		var warn_now: bool = ts.warned and ts.phase == ts.Phase.COUNTDOWN
		if warn_now and not was_warned:
			was_warned = true
			await _tsunami(h)
			continue
		if not ts.warned:
			was_warned = false
		_play(h)
		if frames % 900 == 0:
			print("DEMO status real=%d fps=%d t=%.0f round=%d alive=%d reserve=%d mag=%d pos=%s kills=%d" % [Time.get_ticks_msec() / 1000, Engine.get_frames_per_second(), game_t, zm.round, get_nodes_in_group("zombies").size(), h.reserve, h.mag, str(p.global_position), zm.kills])
	_release_all()
	print("DEMO stopped: %s, cleared=%s, game time %.0f s, frames %d" % [why, str(cleared), game_t, frames])
	await _secs(3.0)
	zm.leave()
	quit()

## One frame of a player's fight: aim at the nearest, shoot in bursts, reload when low, keep moving.
func _play(h: Node) -> void:
	# reload like a player: a real reload when the mag runs low, the reserve topped up behind the scenes
	if h.reserve < 60:
		h.reserve = h.current.reserve_max
	var t_near := _nearest(30.0)
	if h.mag <= 2 and not h.reloading:
		Input.action_release("fire")
		h.reload()
	if h.mag <= 0 and not h.reloading and h.reserve <= 0:
		h.refill_all()
	var near_d: float = 999.0
	if t_near != null:
		near_d = t_near.global_position.distance_to(p.global_position)
	# aim + fire
	if t_near != null and not h.reloading:
		_aim_at(t_near, 0.18)
		Input.action_press("fire")
	else:
		Input.action_release("fire")
		if t_near != null:
			_aim_at(t_near, 0.18)
	# movement: back off when they are close, strafe, advance when nothing is near
	strafe_t -= DT
	if strafe_t <= 0.0:
		strafe_dir = -strafe_dir
		strafe_t = randf_range(1.2, 3.0)
	# stuck detection (walls, props)
	if p.global_position.distance_to(last_pos) < 0.02 * 1.0:
		stuck_t += DT
	else:
		stuck_t = 0.0
	last_pos = p.global_position
	if stuck_t > 0.8:
		strafe_dir = -strafe_dir
		strafe_t = 1.5
		turn_t = 1.0
		wander_yaw = float(p.get("_look_yaw")) + randf_range(1.2, 2.4) * (1.0 if randf() < 0.5 else -1.0)
		stuck_t = 0.0
	for a in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(a)
	if t_near == null:
		# nothing to shoot: look around, walk about the block
		Input.action_press("move_up")
		if turn_t > 0.0:
			turn_t -= DT
			p.set_look(lerp_angle(float(p.get("_look_yaw")), wander_yaw, 0.08), lerpf(float(p.get("_look_pitch")), 0.0, 0.1))
		else:
			p.set_look(float(p.get("_look_yaw")) + 0.012 * strafe_dir, lerpf(float(p.get("_look_pitch")), 0.0, 0.05))
		return
	if near_d < 6.0:
		Input.action_press("move_down")
	elif near_d > 16.0:
		Input.action_press("move_up")
	Input.action_press("move_right" if strafe_dir > 0.0 else "move_left")
	if stuck_t > 0.3 and near_d < 6.0:
		Input.action_press("move_up")
		Input.action_release("move_down")

func _nearest(reach: float) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	for z in get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or int(z.get("state")) >= 5 or float(z.get("body_scale")) > 1.6:
			continue
		var d: float = z.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = z
	return best

func _aim_at(z: Node3D, k: float) -> void:
	var eye := p.global_position + Vector3(0, 1.6, 0)
	var to := z.global_position + Vector3(0, 1.3, 0) - eye
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	p.set_look(lerp_angle(float(p.get("_look_yaw")), yaw, k), lerpf(float(p.get("_look_pitch")), pitch, k))

## The quake + tsunami: to the high ground on foot, hold the stair, watch the wave, then back to the fight.
func _tsunami(h: Node) -> void:
	print("DEMO quake + tsunami warning in round %d, clock %.0f s" % [zm.round, ts.remaining])
	_release_all()
	var ok := await _run_route(h)
	print("DEMO reached the high ground: %s, clock left %.0f s" % [ok, ts.remaining])
	Input.action_release("sprint")
	Input.action_release("move_up")
	while ts.phase == ts.Phase.COUNTDOWN and ts.remaining > 7.0 and game_t < MAX_GAME_SECONDS:
		_hold_stair(h)
		if h.mag <= 3:
			h.refill_all()
		await _tick()
	Input.action_release("fire")
	if ts.phase == ts.Phase.COUNTDOWN:
		await _face_west(7.0, h)
	var t := 0.0
	while t < 75.0 and ts.phase != ts.Phase.IDLE and ts.phase != ts.Phase.CANCELLED and game_t < MAX_GAME_SECONDS:
		await _tick()
		t += DT
		if _shoot_nearest(h, 7.0):
			continue
		Input.action_release("fire")
		p.set_look(lerp_angle(float(p.get("_look_yaw")), PI / 2.0 - 0.3, 0.04), lerpf(float(p.get("_look_pitch")), -0.45, 0.04))
	_release_all()
	print("DEMO after the flood: survived=%s swept=%d round=%d" % [ts.survived, ts.swept, zm.round])
	# the flood moved us / the dead: stand on the ground again for the fight
	last_pos = p.global_position
