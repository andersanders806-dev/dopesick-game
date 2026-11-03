extends "res://dev-tools/smoke_test_3d.gd"
## Zombie body language (task Z5): the climb out and the landing, hit reactions by where it hurt, hurt
## gaits, the lunge, the turn shuffle, the attack variety, the voices, crawlers and corpses.
## Bare stage, no city: zombies on a floor-less plane hunting a stand-in for the player.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_body.gd
var Zed: GDScript   # loaded at run time: it names the ZombieMode autoload
const Voice := preload("res://npc/ZombieVoice.gd")

var _stage: Node3D
var _prey: Node3D

func _run() -> void:
	Zed = load("res://npc/Zombie3D.gd")
	await _zombie_body_checks()

func _make(kind := "walker", at := Vector3.ZERO, seed_ := 5, clip := "z_walk") -> Node3D:
	var z: Node3D = Zed.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	z.configure(kind, 2, rng)
	if clip != "":
		z._move_clip = clip
		z._base_clip = clip
	z.target = _prey
	z.max_health = 200.0
	z.health = 200.0
	_stage.add_child(z)
	z.global_position = at
	return z

func _zombie_body_checks() -> void:
	await _section("Zombie bodies: entrances, hit reactions, gaits, the lunge, the voices")
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	zm.gore_enabled = false
	_stage = Node3D.new()
	root.add_child(_stage)
	_prey = Node3D.new()
	_prey.add_to_group("player")
	_stage.add_child(_prey)
	_prey.global_position = Vector3(60, 0, 0)
	var CA := preload("res://npc/CharacterAnimator.gd")

	# --- The clips ---
	var lib := load("res://assets/zombie_anims/zombie_clips.res") as AnimationLibrary
	for c in ["z_rise", "z_land", "z_hit_leg_l", "z_hit_arm_l", "z_hit_arm_r", "z_stumble", "z_walk4", "z_limp_l", "z_walk_hurt_l", "z_walk_hurt_r", "z_lunge", "z_bite", "z_smash"]:
		_check(lib.has_animation(c), "  the library has a real %s" % c)
	_check(lib.has_animation("z_walk4") and lib.has_animation("z_limp_l") and lib.get_animation("z_walk4").loop_mode == Animation.LOOP_LINEAR and lib.get_animation("z_limp_l").loop_mode == Animation.LOOP_LINEAR
		and lib.get_animation("z_rise").loop_mode == Animation.LOOP_NONE, "  gaits loop, the climb does not")

	# --- Gaits dealt out ---
	var seen := {}
	var runner_ok := true
	for i in 120:
		var rz: Node3D = Zed.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = i + 1
		rz.configure("walker", 3, rng)
		seen[rz._move_clip] = true
		rz.free()
		var rr: Node3D = Zed.new()
		rr.configure("runner", 7, rng)
		runner_ok = runner_ok and rr._move_clip == "z_run" and rr._gait_mult == 1.0
		rr.free()
	_check(seen.has("z_walk") and seen.has("z_walk2") and seen.has("z_walk3") and seen.has("z_walk4") and runner_ok,
		"  walkers get all four gaits (%s), runners run" % [seen.keys()])

	# --- Hurt gaits ---
	var z := _make("walker", Vector3(0, 0, 0))
	await _frames(3)
	z.limb_damage["upper_leg_l"] = 50.0
	z._refresh_gait()
	_check(z._move_clip == "z_limp_l" and z._gait_mult < 0.8, "  a beaten left leg: the left limp at %.0f %% pace" % (z._gait_mult * 100.0))
	z.limb_damage["upper_leg_l"] = 0.0
	z.limb_damage["lower_leg_r"] = 50.0
	z._refresh_gait()
	_check(z._move_clip == "z_walk3", "  a beaten right leg: the right-foot drag")
	z.limb_damage.clear()
	z.severed["arm_r"] = true
	z._refresh_gait()
	_check(z._move_clip == "z_walk_hurt_r" and z._gait_mult > 0.8, "  a lost right arm: leaning to the right, arm hanging")
	z.severed.clear()
	z.severed["forearm_l"] = true
	z._refresh_gait()
	_check(z._move_clip == "z_walk_hurt_l", "  a lost left forearm: leaning to the left")
	z.severed.clear()
	z._refresh_gait()
	_check(z._move_clip == z._base_clip and z._gait_mult == 1.0, "  healed (a test only) it has its own gait back")
	var rn := _make("runner", Vector3(5, 0, 5), 5, "z_run")
	rn.severed["arm_l"] = true
	rn._refresh_gait()
	_check(rn._move_clip == "z_run", "  a runner with one arm still runs")
	rn.free()

	# --- Reactions by where it hurt ---
	var cases := [
		["head", 0.2, "z_hit_head", "a head hit snaps the head"],
		["head", 0.35, "z_stumble", "a big head hit throws it back a step"],
		["upper_arm_l", 0.2, "z_hit_arm_l", "a left shoulder hit spins it left"],
		["upper_arm_r", 0.2, "z_hit_arm_r", "a right shoulder hit spins it right"],
		["torso", 0.2, "z_hit_chest", "a chest hit rocks it"],
		["torso", 0.35, "z_stumble", "a heavy chest hit staggers it back"],
		["upper_leg_r", 0.15, "z_stumble", "a light leg hit makes it stumble"],
	]
	for c in cases:
		z.state = z.State.CHASE
		z._stagger = 0.0
		z._react_cd = 0.0
		z._knock = Vector3.ZERO
		z.limb_damage.clear()
		z.health = z.max_health
		z.take_hit(c[0], z.max_health * float(c[1]), Vector3.RIGHT)
		var clip: String = z.anim.resolved_clip(c[2])
		_check(z._anim_player.current_animation == clip and z._stagger > 0.2, "  %s (%s, stagger %.2f)" % [c[3], z._anim_player.current_animation, z._stagger])
		await _frames(2)
	z.state = z.State.CHASE
	z._stagger = 0.0
	z._react_cd = 0.0
	z.health = z.max_health
	z.take_hit("torso", z.max_health * 0.35, Vector3.RIGHT)
	_check(z._knock.x > 1.5 and absf(z._knock.z) < 0.01, "  and a heavy hit shoves it along the shot (%.1f m/s)" % z._knock.x)
	z.state = z.State.CHASE
	z._stagger = 0.0
	z.take_hit("torso", z.max_health * 0.05, Vector3.RIGHT)
	_check(z._stagger == 0.0, "  a graze leaves it walking")
	z.state = z.State.CHASE
	z.limb_damage.clear()
	z.take_hit("upper_leg_l", z.max_health * 0.3, Vector3.RIGHT)
	_check(z.state == z.State.KNEEL and z._anim_player.current_animation == z.anim.resolved_clip("z_hit_leg_l"), "  a leg hit that matters: down on the left knee")
	z.free()

	# --- Stagger blends into the walk ---
	var w := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	_prey.global_position = Vector3(20, 0, 0)
	await _frames(20)
	w.take_hit("torso", 30.0, Vector3.RIGHT)
	var hit_clip: String = w._anim_player.current_animation
	await _frames(int(w._stagger * 60.0) + 14)
	_check(w._anim_player.current_animation == w.anim.resolved_clip("z_walk") and not w.anim.is_playing_once() and w.state == w.State.CHASE,
		"  the stagger hands over to the walk while the reaction clip is still running (%s -> %s)" % [hit_clip, w._anim_player.current_animation])
	# --- Feet match ground speed ---
	await _frames(40)
	var ground := Vector2(w.velocity.x, w.velocity.z).length()
	var want_rate: float = w.anim.stride_rate("z_walk", ground)
	_check(ground > 0.5 and absf(w._anim_player.speed_scale - want_rate) < 0.05,
		"  the walk's playback follows the ground speed (%.2f m/s -> x%.2f)" % [ground, w._anim_player.speed_scale])
	w.free()

	# --- Lunge ---
	_prey.global_position = Vector3(6.0, 0, 0)
	var lz := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	lz._lunger = true
	lz._facing = PI / 2.0
	var base_speed: float = lz.speed
	var peak := 0.0
	var started := false
	for i in 300:
		await physics_frame
		peak = maxf(peak, Vector2(lz.velocity.x, lz.velocity.z).length())
		if lz.state == lz.State.ATTACK:
			break
	_check(lz.lunges == 1 and peak > base_speed * 2.0 and lz.state == lz.State.ATTACK,
		"  a walker closing in lunges once (%d, peak %.1f m/s against %.1f), then swings" % [lz.lunges, peak, base_speed])
	lz.free()
	var nl := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	nl._lunger = false
	for i in 200:
		await physics_frame
		if nl.state == nl.State.ATTACK:
			break
	_check(nl.lunges == 0, "  one that is not a lunger shambles all the way in")
	nl.free()

	# --- Turn shuffle: standing, facing off from where it should look ---
	_prey.global_position = Vector3(40, 0, 0)
	var tz := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	tz.state = tz.State.CHASE
	tz._stagger = 0.0
	tz.velocity = Vector3.ZERO
	tz._turn_err = 1.2
	tz._move(Vector3.ZERO, 0.016)
	var shuffle: String = tz._anim_player.current_animation
	var shuffle_rate: float = tz._anim_player.speed_scale
	tz._turn_err = 0.1
	tz._move(Vector3.ZERO, 0.016)
	_check(shuffle == tz.anim.resolved_clip("z_walk") and shuffle_rate < 1.0 and tz._anim_player.current_animation == tz.anim.resolved_clip("z_idle"),
		"  turning on the spot it shuffles its feet (%s at x%.2f); squared up it stands" % [shuffle, shuffle_rate])
	tz.free()

	# --- Attack variety ---
	var picks := {}
	var runner_picks := {}
	var az := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	var ar := _make("runner", Vector3(0, 9, 0), 5, "z_run")
	for i in 160:
		az.state = az.State.CHASE
		az._begin_attack(Vector3.RIGHT)
		picks[az._attack_clip] = true
		ar.state = ar.State.CHASE
		ar._begin_attack(Vector3.RIGHT)
		runner_picks[ar._attack_clip] = true
	_check(picks.size() == 5 and picks.has("z_bite") and picks.has("z_smash"), "  five different attacks (%s)" % [picks.keys()])
	_check(not runner_picks.has("z_smash") and not runner_picks.has("z_attack3") and runner_picks.has("z_bite"), "  a runner claws and bites, no hug or smash (%s)" % [runner_picks.keys()])
	az.free()
	ar.free()

	# --- Voices ---
	var v: Node3D = Voice.of(_stage)
	_prey.global_position = Vector3(0, 0, 0)
	var s0: int = v.spoken
	var ok_near: bool = v.say(Vector3(5, 1.5, 0), "groan")
	var ok_far: bool = v.say(Vector3(80, 1.5, 0), "groan")
	_check(ok_near and not ok_far and v.spoken == s0 + 1, "  a groan 5 m away is spoken, one 80 m away is not (%s %s %d/%d)" % [ok_near, ok_far, v.spoken, s0])
	await physics_frame
	var rasp_far: bool = v.say(Vector3(14, 1.5, 0), "rasp", 1.0, 0.0, 0)
	_check(not rasp_far, "  a rasp is only for the ones within 9 m")
	var started_now := 0
	for i in 5:
		if v.say(Vector3(3, 1.5, 0), "snarl"):
			started_now += 1
	_check(started_now <= 2, "  at most two new voices start in a frame (%d)" % started_now)
	for i in 6:
		await physics_frame
		for k in 2:
			v.say(Vector3(4, 1.5, 0), "rasp", 1.0, 0.0, 0)
	var loud: bool = false
	for i in 6:
		await physics_frame
		loud = v.say(Vector3(2, 1.5, 0), "lunge") or loud
	_check(loud and v.speaking() <= v.VOICES, "  a roar takes a voice off a rasp when the pool is full (%d speaking)" % v.speaking())
	var hz := _make("walker", Vector3(3, 0, 0), 5, "z_walk")
	var n0: int = v.spoken
	hz.head_gone = true
	hz._say("pain")
	_check(v.spoken == n0, "  a head blown off says nothing more")
	hz.free()
	# The throat follows the body: a walker near prey breathes with its steps, groans now and then.
	var bz := _make("walker", Vector3(4, 0, 0), 5, "z_walk")
	bz._facing = -PI / 2.0
	_prey.global_position = Vector3(0, 0, 0)
	bz._voice_t = 0.5
	for i in 300:
		await physics_frame
	_check(int(bz.voice_kinds.get("groan", 0)) >= 1 and int(bz.voice_kinds.get("rasp", 0)) >= 2,
		"  a walking zombie groans and breathes in time with its steps (%s)" % [bz.voice_kinds])
	bz.free()

	# --- Crawler ---
	_prey.global_position = Vector3(40, 0, 0)
	var cz := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	cz.set_legless(true)
	await _frames(50)
	var cg := Vector2(cz.velocity.x, cz.velocity.z).length()
	var rate: float = cz._anim_player.speed_scale
	var natural: float = cz.anim.natural_speed("z_crawl")
	_check(cg > 0.3 and absf(rate * natural - cg) < 0.15 and cz._anim_player.current_animation == cz.anim.resolved_clip("z_crawl"),
		"  a crawler drags itself at the pace its strokes cover (%.2f m/s, strokes cover %.2f)" % [cg, rate * natural])
	cz.free()

	# --- Entrances: the climb out and the landing ---
	_prey.global_position = Vector3(30, 0, 0)
	var rz := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	rz.begin_entrance({"type": "rise", "pos": Vector3.ZERO, "start": Vector3(0, -2.1, 0), "out": Vector3.RIGHT, "fall": 0.0, "node": null, "roof": false})
	await _frames(3)
	var rise_clip: String = rz.anim.resolved_clip("z_rise")
	_check(rz.state == rz.State.ENTER and rz._anim_player.current_animation == rise_clip and rise_clip.begins_with("zombie/"), "  a rise plays the climb-out clip (%s)" % rz._anim_player.current_animation)
	var ys := []
	for i in 6:
		await _frames(30)
		ys.append(rz._model_root.position.y)
	_check(ys[0] < ys[3] + 0.001 and ys[1] <= ys[4] + 0.001 and rz._rise_len > 2.0, "  it comes up through the street (%s) over %.1f s" % [ys, rz._rise_len])
	for i in 400:
		if rz.state != rz.State.ENTER:
			break
		await physics_frame
	_check(rz.state == rz.State.CHASE and absf(rz._model_root.position.y) < 0.001, "  and ends on its feet on the street")
	await _frames(20)
	_check(not rz.anim.is_playing_once(), "  the climb hands over to the walk (no one-shot left over)")
	rz.free()
	var dz := _make("walker", Vector3(0, 3, 0), 5, "z_walk")
	dz.begin_entrance({"type": "drop", "pos": Vector3.ZERO, "start": Vector3(0, 3.2, 0), "out": Vector3.RIGHT, "fall": 0.5, "node": null, "roof": false})
	for i in 50:
		await physics_frame
	_check(dz.state == dz.State.CHASE and dz._stagger > 0.3 and dz._anim_player.current_animation == dz.anim.resolved_clip("z_land"),
		"  after the fall it lands in a crouch and staggers (%.2f s, %s)" % [dz._stagger, dz._anim_player.current_animation])
	dz.free()

	# --- Dying: direction, and the body settles ---
	var fz := _make("walker", Vector3(0, 0, 0), 5, "z_walk")
	fz._facing = PI / 2.0
	fz._model_root.rotation.y = fz._facing
	var back := 0
	var fwd := 0
	for i in 40:
		fz._facing = PI / 2.0
		# Shot from the front (travelling -x against a zombie facing +x)
		var f2 := _make("walker", Vector3(0, 0, 3), i + 20, "z_walk")
		f2._facing = PI / 2.0
		f2.take_hit("torso", 1.0e6, Vector3.LEFT)
		if f2._anim_player.current_animation == f2.anim.resolved_clip("z_death"):
			back += 1
		var b2 := _make("walker", Vector3(0, 0, 6), i + 70, "z_walk")
		b2._facing = PI / 2.0
		b2.take_hit("torso", 1.0e6, Vector3.RIGHT)
		if b2._anim_player.current_animation == b2.anim.resolved_clip("z_death2"):
			fwd += 1
		f2.free()
		b2.free()
	_check(back >= 28 and fwd >= 28, "  shot from the front it goes over backwards (%d of 40), from behind onto its face (%d of 40)" % [back, fwd])
	fz.take_hit("torso", 1.0e6, Vector3.LEFT)
	await _frames(200)
	var sk: Skeleton3D = fz._skeleton
	var thigh := sk.find_bone("Bip01 L Thigh")
	var q0: Quaternion = sk.get_bone_pose_rotation(thigh)
	await _frames(30)
	var q1: Quaternion = sk.get_bone_pose_rotation(thigh)
	_check(fz.state == fz.State.DEAD and q0.angle_to(q1) < 0.001 and not fz._anim_player.is_playing(),
		"  the corpse has settled and does not twitch (state %d, drift %.4f rad)" % [fz.state, q0.angle_to(q1)])
	var rest_q: Quaternion = sk.get_bone_rest(thigh).basis.get_rotation_quaternion()
	var spine := sk.find_bone("Bip01 Spine1")
	_check(q1.angle_to(rest_q) > 0.05 or sk.get_bone_pose_rotation(spine).angle_to(sk.get_bone_rest(spine).basis.get_rotation_quaternion()) > 0.05, "  and it lies in its death pose, not the T-pose")
	fz.free()
	_stage.queue_free()
