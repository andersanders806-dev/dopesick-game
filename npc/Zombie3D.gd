extends CharacterBody3D
## One of the dead. A Rocketbox body in the rot shader (npc/zombie_rot.gdshader)
## wearing the zombie clips (CharacterAnimator), hit zones on its bones
## (npc/ZombieHitboxes.gd), a capsule for the world, and a brain that is only
## "walk the navmesh to the player; tear down the boards in the way; claw".
##
## Built in code by npc/ZombieSpawner.gd. Group "zombies" while it can still
## hurt you; "corpses" once it can't.
##
## Hits come in as take_hit(part, damage, dir, weapon): `damage` is already
## what the weapon does to that part (the weapon scales it); this only
## subtracts it, reacts, and dies. Points are the weapon's business: the
## `died` signal says which part killed it and whether it was a melee kill.

signal died(zombie: Node, part: String, melee: bool)
## Every hit that lands (the weapon's hitmarker listens).
signal hit(zombie: Node, part: String, damage: float, killed: bool)
## It clawed at its target for `damage`. The target's `take_zombie_hit(damage,
## zombie)`, if it has one, is called too.
signal attacked(zombie: Node, damage: float)

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const ZombieHitboxes := preload("res://npc/ZombieHitboxes.gd")
const ZombieFlinch := preload("res://npc/ZombieFlinch.gd")
const ImpactFX := preload("res://fx/ImpactFX.gd")
const EntranceFX := preload("res://fx/EntranceFX.gd")
const Gore := preload("res://fx/gore/Gore.gd")
const ZombieVoice := preload("res://npc/ZombieVoice.gd")
const ROT_SHADER := preload("res://npc/zombie_rot.gdshader")

enum State { CHASE, TEAR, ATTACK, KNEEL, STANDUP, ENTER, DYING, DEAD }

## Bodies the dead wear.
const BODIES := [
	"Male_Adult_01", "Male_Adult_02", "Male_Adult_03", "Male_Adult_04", "Male_Adult_05",
	"Male_Adult_06", "Male_Adult_08", "Male_Adult_09", "Male_Adult_10", "Male_Adult_11",
	"Female_Adult_01", "Female_Adult_02", "Female_Adult_03", "Female_Adult_04", "Female_Adult_05",
	"Female_Adult_07", "Female_Adult_08", "Female_Adult_09", "Business_Male_02", "Construction_Male_08",
]
const MODEL_DIR := "res://assets/rocketbox/"

## The gaits a healthy walker gets (weights by repeats): a plain shamble, a human walk leaned over,
## a foot-dragging one and a lurching, swaying one.
const WALK_CLIPS := ["z_walk", "z_walk", "z_walk2", "z_walk3", "z_walk4", "z_walk4"]
const ATTACK_CLIPS := ["z_attack", "z_attack2", "z_attack3", "z_bite", "z_smash"]
## Where in each attack the blow lands (share of the clip); the others use ATTACK_HIT_AT.
const ATTACK_HIT := {"z_bite": 0.4, "z_smash": 0.6, "z_attack3": 0.5}
## Share of its pace a hurt walker keeps: a bad leg, a bad arm.
const LIMP_PACE := 0.75
const HURT_ARM_PACE := 0.9
## The lunge: a walker within LUNGE_FROM metres of its prey (and further than LUNGE_MIN) may throw
## itself forward for LUNGE_TIME seconds at LUNGE_BOOST times its pace, then it is in reach.
const LUNGE_FROM := 4.2
const LUNGE_MIN := 2.1
const LUNGE_TIME := 0.7
const LUNGE_BOOST := 2.7
## Facing off by more than this (radians) while standing: it shuffles its feet round.
const TURN_STEP := 0.5
const WALK_SPEED := Vector2(0.9, 1.45)
const RUN_SPEED := Vector2(3.0, 3.7)
## Legless, it drags itself along.
const CRAWL_SPEED := 0.55
const TURN_SPEED := 7.0
## Reach of a claw, and when in the swing it lands (fraction of the clip).
const ATTACK_RANGE := 1.35
const ATTACK_HIT_AT := 0.45
const ATTACK_COOLDOWN := 0.5
const ATTACK_DAMAGE := 35.0
const RUNNER_DAMAGE := 40.0
## Seconds between a zombie's board-tearing swings.
const TEAR_PERIOD := 2.2
## Beyond this from the player its pose steps less often (LOD_MID) ...
const FAR_DISTANCE := LOD_MID
## ... and beyond this it casts no shadow.
const SHADOW_DISTANCE := 12.0
## Beyond this from the player it thinks and steps every second physics tick,
## beyond FAR_THINK_2 every fourth (on owed time, so it covers the same ground).
const FAR_THINK := 28.0
const FAR_THINK_2 := 50.0
## Animation LOD (see "Far away: cheaper"): from LOD_MID its pose is updated every 2nd
## rendered frame, from LOD_FAR every 4th, from LOD_VFAR every 8th; from LOD_FAR the rot
## shader skips its finest layer too. Rings of 2 m hysteresis keep one at a tier.
const LOD_MID := 15.0
const LOD_FAR := 32.0
const LOD_VFAR := 55.0
const LOD_HYST := 2.0
const REPATH := Vector2(0.5, 1.0)
const CORPSE_LIFE := 30.0
## A hit to the leg drops it to a knee for this long (the clip ends mid-fall,
## so it holds that pose), then it gets up, or drags on if legless.
const KNEEL_TIME := 1.3
const BODY_LAYER := 128
## Attack slots round the target: three rings of eight, so a crowd stands
## round it (each slot 0.7 m or more from the next) instead of in one pile.
## The outer ring is out of claw reach and waits its turn.
const RING_RADII := [1.0, 1.5, 2.0]
const RING_SLOTS := 8
## A zombie this close to its target takes a slot; it lets go beyond RELEASE.
const SLOT_ENGAGE := 7.0
const SLOT_RELEASE := 10.0
## Closer than this to another of the dead and it is pushed off.
const PERSONAL_SPACE := 0.62
## Seconds without getting nearer (and out of the player's sight) before it
## is put back on a spawn point.
const STUCK_TIME := 8.0
const STUCK_PROGRESS := 0.5

static var _noise: Texture2D
static var _materials := {}
## The clip library, held so the cache never drops it between two zombies
## (reloading it from disk cost 14-20 ms on the next spawn).
static var _clip_library: Resource
## Attack slot -> the zombie holding it.
static var _slots := {}
static var _horde_frame := -1
static var _horde_cache: Array = []
static var _horde_pos := PackedVector3Array()
static var _gates_frame := -1
static var _gates_cache: Array = []

var kind := "walker"
## How big the body is drawn and its capsule and hit zones are (1.5 for the dead; npc/Drowned.gd is bigger).
var body_scale := 1.5
var max_health := 150.0
var health := 150.0
## Both legs gone: it crawls and its capsule and leg zones shrink with it
## (set_legless does that; assigning the property does the same).
var legless := false: set = set_legless
var state: State = State.CHASE
var target: Node3D
var speed := 1.1
var damage := ATTACK_DAMAGE
## Where the last hit came from and what part, for the death.
var last_part := ""

var anim: CharacterAnimator
var hitboxes := {}
var model: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _model_root: Node3D
var _shape: CollisionShape3D
var _move_clip := "z_walk"
var _path := PackedVector3Array()
var _path_i := 0
var _repath_in := 0.0
var _attack_time := 0.0
var _attack_len := 1.0
var _attack_hit_done := false
var _attack_cooldown := 0.0
var _barricade: Node3D
var _tear_timer := 0.0
var _tear_hit_done := false
var _stagger := 0.0
var _kneel_t := 0.0
var _slow := 0.0
## Z5 body language. The gait it was dealt, the pace its wounds leave it, the lunge, the
## shuffle-turn, the throat.
var _base_clip := "z_walk"
var _gait_mult := 1.0
var gait := ""
var _lunger := false
var _lunge_t := 0.0
var _lunge_ready := true
var _lunge_cd := 0.0
var lunges := 0
var _turn_err := 0.0
var _hit_dir := Vector3.ZERO
var _kneel_left := false
var _attack_clip := ""
var _voice_pitch := 1.0
var _voice_t := 4.0
var _breath_t := 0.0
var _breath_out := false
var _pain_cd := 0.0
var _react_cd := 0.0
var _dist_player := 99.0
var voice_kinds := {}
## A shove from a shotgun at close range (m/s on the ground, dying away).
var _knock := Vector3.ZERO
## Gore (fx/gore/Gore.gd): damage taken per hit zone, the limbs gone (limb -> true), the
## skeleton modifier that holds them at nothing, wounds painted, whether the head is off.
var limb_damage := {}
var severed := {}
var sever_bits := 0
var wounds_placed := 0
var head_gone := false
var _flinch: SkeletonModifier3D
var _frame := 0
var _far := false
## Animation LOD tier: 0 near (the AnimationPlayer runs itself), 1..3 stepped by hand in _process.
var _lod := 0
var _lod_phase := 0
var _lod_acc := 0.0
var _lod_ticks := 0
## The body's meshes that wear the rot shader (they get the far_lod instance uniform).
var _lod_meshes: Array = []
## Time of a skipped tick, paid on the next (far zombies think every second tick).
var _owed := 0.0
var _shadows := true
var _corpse_age := 0.0
var _facing := 0.0
## Whether the leg-hit clip was still playing when the zombie left the knee
## (true means the next clip blended out of it; the smoke test reads it).
var kneel_handoff_live := false
var _rot_amount := 0.6
## Playback speed of its board-tearing swings (tests squeeze them).
var swing_speed := 1.0
var _tear_swung := false
var _slot := -1
var _holding := false
var _slot_check := 0.0
## How long it may go without getting any nearer to its target.
var stuck_limit := STUCK_TIME
var _stuck_t := 0.0
var _best_remaining := INF
## Set when it is put back on the map (the spawner's relocate); the tests read it.
var relocations := 0

## Sets the kind ("walker" or "runner") and the round's health before it is
## added to the tree (npc/ZombieSpawner.gd does this).
func configure(zkind: String, round_no: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	kind = zkind
	max_health = float(ZombieMode.zombie_health(round_no))
	health = max_health
	if kind == "runner":
		speed = rng.randf_range(RUN_SPEED.x, RUN_SPEED.y)
		damage = RUNNER_DAMAGE
		_move_clip = "z_run"
	else:
		# A little faster each round, like the rest of the horde.
		speed = rng.randf_range(WALK_SPEED.x, WALK_SPEED.y) * (1.0 + minf(round_no, 15) * 0.02)
		_move_clip = WALK_CLIPS[rng.randi() % WALK_CLIPS.size()]
	_base_clip = _move_clip
	gait = _move_clip
	_lunger = kind == "walker" and rng.randf() < 0.6
	_voice_pitch = rng.randf_range(0.82, 1.18) * (1.12 if kind == "runner" else 1.0)
	_voice_t = rng.randf_range(1.0, 7.0)
	_rot_amount = rng.randf_range(0.45, 1.0)
	set_meta("body", BODIES[rng.randi() % BODIES.size()])
	set_meta("seed", rng.randf())

func _ready() -> void:
	# A prewarm dummy (world/ZombieBlock.gd draws every body once, out of sight)
	# is not one of the dead: no group, no brain.
	var dummy: bool = get_meta("prewarm", false)
	if not dummy:
		add_to_group("zombies")
	set_physics_process(not dummy)
	# Only a far zombie steps its pose by hand (set_lod turns this on).
	set_process(false)
	collision_layer = BODY_LAYER
	collision_mask = 1
	# The block is flat and its floors sit on another layer: like the player,
	# it walks the plane and never falls.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var grow := body_scale / 1.5
	cap.radius = 0.3 * grow
	cap.height = 1.7 * grow
	_shape.shape = cap
	_shape.position = Vector3(0, 0.85 * grow, 0)
	add_child(_shape)
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.scale = Vector3.ONE * body_scale
	add_child(_model_root)
	var body: String = get_meta("body", BODIES[0])
	model = CharacterCast.scene_for(MODEL_DIR + body + ".glb").instantiate()
	_model_root.add_child(model)
	_make_anim()
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton and ZombieMode.gore_enabled:
		# Limb ids on the body's vertices, so a lost limb can be clipped away (once per body;
		# before the rot materials, since a new mesh drops the surface overrides).
		Gore.GoreRig.prepare(self)
	_apply_look()
	if _skeleton:
		hitboxes = ZombieHitboxes.build(_skeleton, self, body_scale / 1.5)

	_facing = randf() * TAU
	_model_root.rotation.y = _facing
	_repath_in = randf_range(0.0, REPATH.y)
	_frame = randi() % 4
	_lod_phase = randi() % 8
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	# Starts into its walk at a random point, so a crowd isn't in step.
	anim.play(_move_clip, 1.0)
	if _anim_player:
		_anim_player.seek(randf() * 0.8, true)

# --- The look ------------------------------------------------------------------

## Hooks for npc/Gangster3D.gd (the armed humans of Ghetto Wars wear the same body pipeline).
func _make_anim() -> void:
	CharacterAnimator.install_zombie_library(model)
	anim = CharacterAnimator.new(model, _move_clip)
	anim.set_clips(_move_clip, "z_idle")

func _apply_look() -> void:
	_apply_rot(float(get_meta("seed", 0.0)))

## Loads and keeps what every zombie shares (the rot noise, the clip library);
## ZombieBlock calls it before the first round.
static func warm_shared() -> void:
	noise_texture()
	if ResourceLoader.exists(CharacterAnimator.ZOMBIE_LIBRARY):
		_clip_library = load(CharacterAnimator.ZOMBIE_LIBRARY)

## The noise the rot shader reads: four independent channels, tiling.
static func noise_texture() -> Texture2D:
	if _noise != null:
		return _noise
	var chans: Array[Image] = []
	for i in 4:
		var n := FastNoiseLite.new()
		n.seed = 11 + i * 17
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012 + i * 0.004
		n.fractal_octaves = 3
		chans.append(n.get_seamless_image(128, 128, false, false, 0.1))
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			img.set_pixel(x, y, Color(chans[0].get_pixel(x, y).r, chans[1].get_pixel(x, y).r,
				chans[2].get_pixel(x, y).r, chans[3].get_pixel(x, y).r))
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise

## Every surface of the body swapped for the rot shader's material (one per
## source material, shared); per-zombie rot and seed ride the instance.
func _apply_rot(seed_value: float) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var src := inst.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			inst.set_surface_override_material(i, _rot_material(src))
		inst.set_instance_shader_parameter("rot", _rot_amount)
		_lod_meshes.append(inst)
		inst.set_instance_shader_parameter("seed", seed_value)

static func _rot_material(src: BaseMaterial3D) -> Material:
	if _materials.has(src):
		return _materials[src]
	var rname := src.resource_name
	if rname.ends_with("opacity"):
		# Hair and lashes: the model's own cut-out, greyed.
		var hair := src.duplicate() as BaseMaterial3D
		hair.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		hair.alpha_scissor_threshold = 0.45
		hair.cull_mode = BaseMaterial3D.CULL_DISABLED
		hair.albedo_color = src.albedo_color * Color(0.62, 0.64, 0.58)
		_materials[src] = hair
		return hair
	var m := ShaderMaterial.new()
	m.shader = ROT_SHADER
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("albedo_color", src.albedo_color)
	m.set_shader_parameter("noise_tex", noise_texture())
	m.set_shader_parameter("kind", 1 if rname.ends_with("head") else 0)
	m.set_shader_parameter("roughness_base", src.roughness)
	_materials[src] = m
	return m

# --- Brain ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.DEAD:
			_corpse_age += delta
			if _corpse_age > CORPSE_LIFE:
				remove_corpse()
			return
		State.DYING:
			return
		State.ENTER:
			_enter_tick(delta)
			return
	_frame += 1
	# Far down the street it thinks and steps every second tick (every fourth beyond
	# FAR_THINK_2), on owed time: nobody can see the difference at 30 m, and it
	# thins out the far half of the horde.
	if state == State.CHASE and target != null and is_instance_valid(target):
		var away := target.global_position - global_position
		if not _think_now(away.x * away.x + away.z * away.z):
			_owed += delta
			return
	delta += _owed
	_owed = 0.0
	_stagger = maxf(_stagger - delta, 0.0)
	_slow = maxf(_slow - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_lunge_t = maxf(_lunge_t - delta, 0.0)
	_lunge_cd = maxf(_lunge_cd - delta, 0.0)
	_pain_cd = maxf(_pain_cd - delta, 0.0)
	_react_cd = maxf(_react_cd - delta, 0.0)
	_update_lod(delta)
	_voice_tick(delta)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	var want := Vector3.ZERO
	match state:
		State.CHASE:
			want = _chase(delta)
		State.TEAR:
			want = _tear(delta)
		State.ATTACK:
			_attack(delta)
		State.KNEEL:
			_kneel(delta)
		State.STANDUP:
			_kneel_t -= delta
			if _kneel_t <= 0.0:
				state = State.CHASE
				_repath_in = 0.0
	if state == State.CHASE:
		_watch(delta)
	else:
		_stuck_t = 0.0
		_best_remaining = INF
	_move(want, delta)

## Puts the hit zones on the bones as the animation has them now. Weapons call
## this for the zombies near a shot just before they cast; nothing keeps them
## on the bones between shots (npc/ZombieHitboxes.gd says why).
func sync_hitboxes() -> void:
	if _skeleton != null and not hitboxes.is_empty():
		ZombieHitboxes.sync(_skeleton, hitboxes)

## Where it wants to go this tick (a direction on the ground, zero to hold).
func _chase(delta: float) -> Vector3:
	if target == null:
		anim.update(0.0)
		return Vector3.ZERO
	var to := target.global_position - global_position
	var height_gap := absf(to.y)
	to.y = 0.0
	var dist := to.length()
	# Not on its level (the player up on the high ground): no clawing through the floor, it has to find the way.
	if height_gap > 2.4:
		dist = maxf(dist, 99.0)
	_dist_player = dist
	if dist < ATTACK_RANGE and _attack_cooldown <= 0.0 and _stagger <= 0.0:
		_lunge_t = 0.0
		_begin_attack(to)
		return Vector3.ZERO
	if _stagger > 0.0:
		return Vector3.ZERO
	var dir := to.normalized() if to.length() > 0.001 else Vector3.FORWARD
	_holding = false
	dist = _lunge_check(dist, dir, height_gap)
	if _lunge_t > 0.0:
		return dir
	# Near the target it takes a slot on the ring round it and goes to that.
	var slot_goal := _slot_goal(dist, delta)
	if slot_goal != Vector3.INF:
		var to_slot := slot_goal - global_position
		to_slot.y = 0.0
		if to_slot.length() < 0.3:
			_holding = true
			_face(to, delta)
			if dist < ATTACK_RANGE + 0.35 and _attack_cooldown <= 0.0 and _stagger <= 0.0:
				_begin_attack(to)
			return Vector3.ZERO
		var steer := _around(slot_goal)
		dir = Vector3(steer.x - global_position.x, 0.0, steer.z - global_position.z).normalized()
	# Close in, straight at it; further out (or when the straight line is
	# blocked) along the navmesh.
	if dist > 3.0 or (slot_goal == Vector3.INF and _blocked(dir)):
		_repath_in -= delta
		if _repath_in <= 0.0:
			_repath_in = randf_range(REPATH.x, REPATH.y)
			_repath()
		dir = _follow_path(dir)
	var gate := _gate_ahead(dir)
	if gate != null:
		_begin_tear(gate)
		return Vector3.ZERO
	return dir

func _repath() -> void:
	var map := get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, global_position, target.global_position, true)
	_path_i = 1 if _path.size() > 1 else 0

func _follow_path(fallback: Vector3) -> Vector3:
	while _path_i < _path.size():
		var p := _path[_path_i]
		var d := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
		if d.length() < 0.45:
			_path_i += 1
			continue
		return d.normalized()
	return fallback

## A barricade with boards left that it is walking into.
func _gate_ahead(dir: Vector3) -> Node3D:
	for b in _gates():
		if (b as Node).has_method("blocks") and b.blocks(global_position, dir):
			return b
	return null

func _begin_tear(b: Node3D) -> void:
	state = State.TEAR
	_barricade = b
	_tear_timer = randf_range(0.2, 0.8)
	_tear_hit_done = false
	_tear_swung = false

func _tear(delta: float) -> Vector3:
	if _barricade == null or not is_instance_valid(_barricade) or not _barricade.intact():
		_barricade = null
		state = State.CHASE
		_repath_in = 0.0
		return Vector3.ZERO
	# The player in reach comes first.
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() < ATTACK_RANGE * 0.9 and _attack_cooldown <= 0.0:
			_begin_attack(to)
			return Vector3.ZERO
	var look: Vector3 = _barricade.global_position - global_position
	look.y = 0.0
	_face(look, delta)
	_tear_timer -= delta
	if _tear_timer <= 0.0 and _stagger <= 0.0:
		_tear_timer = TEAR_PERIOD
		_tear_hit_done = false
		_tear_swung = true
		_swing(ATTACK_CLIPS[randi() % ATTACK_CLIPS.size()], swing_speed)
	# The swing lands a little way in. (On the timer alone: a short clip, or
	# one that was cut off, must not keep the board up.)
	if _tear_swung and not _tear_hit_done and _tear_timer < TEAR_PERIOD - 0.55:
		_tear_hit_done = true
		if _barricade.has_method("tear_board"):
			_barricade.tear_board(self)
	anim.update(0.0)
	return Vector3.ZERO

## A walker that closes to within a few metres of its prey may throw itself at it: a short
## burst of speed with the lunge clip, then the swing. Once per approach (it is armed again
## when the prey gets 9 m away); returns the distance for the caller to carry on with.
func _lunge_check(dist: float, dir: Vector3, height_gap: float) -> float:
	if dist > 9.0:
		_lunge_ready = true
	if not (_lunger and _lunge_ready and _lunge_cd <= 0.0 and _lunge_t <= 0.0 and not legless):
		return dist
	if dist > LUNGE_FROM or dist < LUNGE_MIN or height_gap > 0.8 or _blocked(dir) or _move_clip != _base_clip:
		return dist
	_lunge_ready = false
	_lunge_cd = 6.0
	_lunge_t = LUNGE_TIME
	lunges += 1
	anim.play_once_timed("z_lunge", LUNGE_TIME)
	_say("lunge")
	return dist

func _begin_attack(to: Vector3) -> void:
	state = State.ATTACK
	_attack_hit_done = false
	_attack_time = 0.0
	_face(to, 1.0)
	# A runner goes for the bite and the claws, a walker may smash or hug as well.
	var clip: String = ATTACK_CLIPS[randi() % ATTACK_CLIPS.size()]
	if kind == "runner" and (clip == "z_smash" or clip == "z_attack3"):
		clip = "z_bite" if randf() < 0.6 else "z_attack"
	_attack_clip = clip
	_attack_len = _swing(clip)
	_say("snarl")

func _swing(clip: String, rate := 1.0) -> float:
	var dur := anim.play_once(clip, rate)
	return maxf(dur, 0.4)

func _attack(delta: float) -> void:
	_attack_time += delta
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		_face(to, delta * 0.5)
		if not _attack_hit_done and _attack_time >= _attack_len * float(ATTACK_HIT.get(_attack_clip, ATTACK_HIT_AT)):
			_attack_hit_done = true
			if to.length() <= ATTACK_RANGE + 0.35:
				attacked.emit(self, damage)
				if target.is_in_group("player") and ZombieMode.gore_enabled:
					var gore := Gore.of(self)
					if gore != null:
						gore.screen_blood(clampf(damage / 35.0, 0.6, 1.6))
				if target.has_method("take_zombie_hit"):
					target.take_zombie_hit(damage, self)
	if _attack_time >= _attack_len:
		state = State.CHASE
		_attack_cooldown = ATTACK_COOLDOWN
		_repath_in = 0.0

func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	_turn_err = absf(angle_difference(_facing, want))
	_facing = lerp_angle(_facing, want, clampf(TURN_SPEED * delta, 0.0, 1.0))
	_model_root.rotation.y = _facing

func _move(want: Vector3, delta: float) -> void:
	var v := Vector3.ZERO
	if want.length() > 0.01:
		var pace := CRAWL_SPEED if legless else speed * _gait_mult
		if _slow > 0.0:
			pace *= 0.5
		if _lunge_t > 0.0:
			pace *= LUNGE_BOOST
		v = want * pace
		_face(want, delta)
	if state == State.CHASE or state == State.ATTACK:
		v += _separation()
	velocity.x = move_toward(velocity.x, v.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, v.z, 14.0 * delta)
	velocity.y = 0.0
	if _knock.length_squared() > 0.0001:
		velocity += _knock
		_knock = _knock.move_toward(Vector3.ZERO, 11.0 * delta)
	# A tick that carries a skipped one steps twice as far.
	var steps := delta / maxf(get_physics_process_delta_time(), 0.0001)
	if steps > 1.5:
		var keep := velocity
		velocity *= steps
		move_and_slide()
		velocity = keep
	else:
		move_and_slide()
	if state == State.CHASE and _stagger <= 0.0 and _lunge_t <= 0.0:
		# A reaction clip that handed over to the walk while still running never reports back.
		anim.end_once()
		var moved := Vector2(velocity.x, velocity.z).length()
		var clip := "z_crawl" if legless else _move_clip
		if moved > 0.15:
			# Steps as long as the ground it covers: the clip's pace follows the velocity.
			var rate := anim.stride_rate(clip, moved)
			if legless:
				# A crawl's strokes are slow for the ground they cover: let it pull faster than a walk may.
				rate = clampf(moved / maxf(anim.natural_speed(clip), 0.05), 0.5, 2.9)
			anim.play(clip, rate)
		elif _turn_err > TURN_STEP and not legless:
			# Standing but swinging round to face its prey: shuffles its feet instead of spinning on the spot.
			anim.play(_move_clip, clampf(_turn_err * 0.5, 0.45, 0.9))
		else:
			anim.play("z_idle", 1.0)
		_turn_err = 0.0

## A shove off its neighbours so a horde spreads instead of stacking (also
## when standing still: a pile unpicks itself). Reads one snapshot of the living
## dead's places per physics frame (_horde()), not twenty zombies asked twenty
## times: this was a quarter of the horde's script time.
func _separation() -> Vector3:
	_horde()
	var push := Vector3.ZERO
	var me := global_position
	var space2 := PERSONAL_SPACE * PERSONAL_SPACE
	var spots := _horde_pos
	for i in spots.size():
		var o := spots[i]
		var dx := me.x - o.x
		var dz := me.z - o.z
		var l2 := dx * dx + dz * dz
		if l2 >= space2 or _horde_cache[i] == self:
			continue
		var l := sqrt(l2)
		var d := Vector3(dx, 0.0, dz)
		if l < 0.001:
			d = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			l = 0.001
		push += d / maxf(l, 0.001) * (PERSONAL_SPACE - l) / PERSONAL_SPACE * 2.2
	return push.limit_length(2.5)

## The living dead, listed once per physics frame for everyone (with where each
## stood when the frame began; only the living are in it).
static func _horde() -> Array:
	var f := Engine.get_physics_frames()
	if f != _horde_frame:
		_horde_frame = f
		var all: Array = (Engine.get_main_loop() as SceneTree).get_nodes_in_group("zombies")
		_horde_cache = []
		_horde_pos = PackedVector3Array()
		for o in all:
			if is_instance_valid(o) and o.is_alive():
				_horde_cache.append(o)
				_horde_pos.append((o as Node3D).global_position)
	return _horde_cache

static func _gates() -> Array:
	var f := Engine.get_physics_frames()
	if f != _gates_frame:
		_gates_frame = f
		_gates_cache = (Engine.get_main_loop() as SceneTree).get_nodes_in_group("barricades")
	return _gates_cache

## Whether something solid is right in front of it on its way to `dir`.
func _blocked(dir: Vector3) -> bool:
	return test_move(global_transform, dir.normalized() * 0.4)

# --- Slots round the target ------------------------------------------------------

static func slot_offset(i: int) -> Vector3:
	var ring := i / RING_SLOTS
	var k := i % RING_SLOTS
	var ang := (float(k) + 0.5 * float(ring % 2)) * TAU / RING_SLOTS
	return Vector3(cos(ang), 0.0, sin(ang)) * float(RING_RADII[ring])

func _slot_free(i: int) -> bool:
	if not _slots.has(i):
		return true
	var o = _slots[i]
	return o == self or not is_instance_valid(o) or not o.is_alive() or o._slot != i

func _slot_cost(i: int) -> float:
	var at: Vector3 = target.global_position + slot_offset(i)
	return Vector2(at.x - global_position.x, at.z - global_position.z).length() + float(i / RING_SLOTS) * 0.9

## The point it should stand at to claw its target (Vector3.INF: not near
## enough to need one yet).
func _slot_goal(dist: float, delta: float) -> Vector3:
	if target == null:
		return Vector3.INF
	if dist > SLOT_RELEASE or (_slot < 0 and dist > SLOT_ENGAGE):
		_release_slot()
		return Vector3.INF
	_slot_check -= delta
	if _slot < 0 or _slot_check <= 0.0:
		_slot_check = randf_range(0.4, 0.8)
		var best := -1
		var best_cost := INF
		for i in RING_SLOTS * RING_RADII.size():
			if not _slot_free(i):
				continue
			var c := _slot_cost(i)
			if c < best_cost:
				best_cost = c
				best = i
		# A better slot has to be clearly better to be worth the walk.
		if best >= 0 and (_slot < 0 or best_cost < _slot_cost(_slot) - 0.6):
			_release_slot()
			_slot = best
			_slots[best] = self
	if _slot < 0:
		return Vector3.INF
	return target.global_position + slot_offset(_slot)

## A slot on the far side of the target is reached by going round it, outside
## the ones already standing there, not through them.
func _around(goal: Vector3) -> Vector3:
	var c := target.global_position
	var rel := Vector2(global_position.x - c.x, global_position.z - c.z)
	var want := Vector2(goal.x - c.x, goal.z - c.z)
	var r := rel.length()
	if r > 3.4 or r < 0.01:
		return goal
	var diff := angle_difference(rel.angle(), want.angle())
	if absf(diff) < 0.6:
		return goal
	var ang := rel.angle() + signf(diff) * 0.5
	var rr := maxf(r, float(RING_RADII[RING_RADII.size() - 1]) + 0.45)
	return Vector3(c.x + cos(ang) * rr, goal.y, c.z + sin(ang) * rr)

func _release_slot() -> void:
	if _slot >= 0 and _slots.get(_slot) == self:
		_slots.erase(_slot)
	_slot = -1

func _exit_tree() -> void:
	_release_slot()

# --- Stuck ----------------------------------------------------------------------

## How far it still has to go: along its path out in the street, straight
## when it is close.
func _remaining() -> float:
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= 3.0 or _path_i >= _path.size():
		return dist
	var total := 0.0
	var at := global_position
	for i in range(_path_i, _path.size()):
		total += Vector2(_path[i].x - at.x, _path[i].z - at.z).length()
		at = _path[i]
	return total

## The watchdog: no nearer to its target for `stuck_limit` seconds (boxed in
## by a wreck, a pillar, a pile of the dead...) and out of the player's view,
## and the spawner puts it back on a spawn point. Tearing a board, clawing,
## kneeling and queueing at the target's ring all count as getting on.
func _watch(delta: float) -> void:
	if target == null or _holding or _stagger > 0.0:
		_stuck_t = 0.0
		return
	var rem := _remaining()
	if rem < ATTACK_RANGE + 0.8:
		# At its target.
		_stuck_t = 0.0
		_best_remaining = INF
		return
	if rem < _best_remaining - STUCK_PROGRESS:
		_best_remaining = rem
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t < stuck_limit:
		return
	# Never in sight: wait until the player looks away.
	var cam := get_viewport().get_camera_3d()
	if cam != null and not cam.is_position_behind(global_position + Vector3.UP) and cam.is_position_in_frustum(global_position + Vector3.UP):
		_stuck_t = stuck_limit - 0.5
		return
	var spawner := get_tree().get_first_node_in_group("zombie_spawner")
	if spawner != null and spawner.has_method("relocate") and spawner.relocate(self):
		return
	_stuck_t = stuck_limit - 1.0

## Called by the spawner after it moved this one: forget the old route.
func relocated() -> void:
	relocations += 1
	_stuck_t = 0.0
	_best_remaining = INF
	_path = PackedVector3Array()
	_path_i = 0
	_repath_in = 0.0
	_release_slot()
	velocity = Vector3.ZERO

# --- Entrances (npc/Entrances.gd) ---------------------------------------------------------------

## Seconds for a zombie to climb out of the ground, and how deep it starts.
const RISE_TIME := 3.0
const RISE_DEPTH := 2.1
## How far under the street the body is when the hands first reach the surface.
const RISE_HANDS := 0.3
## Out through a shop front: the shove it comes out with (m/s along the ground).
const SMASH_SHOVE := 6.5
## How it came in ("", "rise", "drop", "smash", "plain"); the tests read it.
var entrance := ""
var _enter := {}
var _enter_t := 0.0
var _rise_len := RISE_TIME
var _groaned := false

## Lets it come in the way `e` says (an Entrances.pick() result); call it right after adding the
## zombie to the tree. A rise starts under the street and climbs out, a drop falls from a fire
## escape or roof and lands, a smash is shoved out through a shop front; a plain one just walks in.
func begin_entrance(e: Dictionary) -> void:
	entrance = String(e.get("type", "plain"))
	_enter = e
	_enter_t = 0.0
	var fx := EntranceFX.of(self) if entrance != "plain" else null
	match entrance:
		"rise":
			state = State.ENTER
			global_position = e["pos"]
			_ghost(true)
			_model_root.position.y = -RISE_DEPTH
			# The climb out is a clip of its own (hand first, the body dragged after it, a push up
			# onto the knees, then to its feet), a little quicker or slower for each of them. It ends
			# 0.15 s early: the blend into the walk needs a clip that is still running.
			var dur := anim.play_once("z_rise", randf_range(1.1, 1.35))
			_rise_len = maxf(dur - 0.15, 1.0)
			_groaned = false
			if fx != null:
				fx.ground_burst(e["pos"], e.get("node"))
		"drop":
			state = State.ENTER
			global_position = e["start"]
			_ghost(true)
			anim.play("z_idle", 1.0)
			_face_dir(e["out"])
		"smash":
			global_position = e["start"]
			_face_dir(e["out"])
			_knock = (e["out"] as Vector3).normalized() * SMASH_SHOVE
			_stagger = 0.15
			if fx != null:
				fx.smash(e["facade"], e["out"])

func _face_dir(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_facing = atan2(dir.x, dir.z)
		_model_root.rotation.y = _facing

## Climbing out of the ground, or falling in; hands over to the chase when it is done.
func _enter_tick(delta: float) -> void:
	_enter_t += delta
	match entrance:
		"rise":
			var k := clampf(_enter_t / _rise_len, 0.0, 1.0)
			# A pause while the dirt flies, then the hands come up through it; the rest of the climb
			# is the clip's own (the body is lying on the street as it drags itself out).
			var y := -RISE_DEPTH + (RISE_DEPTH - RISE_HANDS) * smoothstep(0.03, 0.13, k)
			y += RISE_HANDS * smoothstep(0.14, 0.42, k)
			_model_root.position.y = minf(y, 0.0)
			if k > 0.45 and not _groaned:
				_groaned = true
				_say("groan", -2.0)
			if k >= 1.0:
				anim.end_once()
				_finish_entrance(0.0)
		"drop":
			var fall := maxf(float(_enter.get("fall", 0.5)), 0.2)
			var k := clampf(_enter_t / fall, 0.0, 1.0)
			var start: Vector3 = _enter["start"]
			var land: Vector3 = _enter["pos"]
			var at := start.lerp(land, k)
			at.y = start.y * (1.0 - k * k)
			global_position = at
			if k >= 1.0:
				global_position = land
				var fx := EntranceFX.of(self)
				if fx != null:
					fx.landing(land, bool(_enter.get("roof", false)))
				# Down in a crouch (the clip), the trunk driven forward by the impact; a runner is up and
				# off almost at once, a walker takes its time to find its feet.
				_land_kick()
				_say("pain", -3.0)
				_finish_entrance(0.0, "z_land", 1.7 if kind == "runner" else 1.0)
		_:
			_finish_entrance(0.0)

## Hands over to the chase. With a `clip` the body lands in it first (held as a stagger, less the
## blend into the walk); without, it walks off at once.
func _finish_entrance(stagger: float, clip := "", rate := 1.0) -> void:
	_end_entrance()
	state = State.CHASE
	_stagger = stagger
	_repath_in = 0.0
	if clip != "":
		var dur := anim.play_once(clip, rate)
		_stagger = maxf(dur - 0.18, 0.2)
	else:
		anim.play(_move_clip, 1.0)

## The impact of a landing drives the trunk forward and the head down, and it settles back.
func _land_kick() -> void:
	if _skeleton == null:
		return
	if _flinch == null:
		_flinch = ZombieFlinch.new()
		_skeleton.add_child(_flinch)
	var inv := _skeleton.global_transform.basis.orthonormalized().inverse()
	var fwd := Vector3(sin(_facing), 0.0, cos(_facing))
	var bend := inv * Vector3.UP.cross(fwd).normalized()
	var f: Variant = _flinch
	f.kick(_skeleton.find_bone("Bip01 Spine"), bend, deg_to_rad(16.0), 0.6)
	f.kick(_skeleton.find_bone("Bip01 Spine1"), bend, deg_to_rad(22.0), 0.55)
	f.kick(_skeleton.find_bone("Bip01 Neck"), bend, deg_to_rad(12.0), 0.5)

## Back to a body in the world: the capsule on, the model at its feet.
func _end_entrance() -> void:
	if state != State.ENTER:
		return
	_model_root.position.y = 0.0
	_ghost(false)
	velocity = Vector3.ZERO

## No body for the world while it climbs out or falls in (the player walks through it; hit
## zones stay): the layers off rather than the shape, which would make it a new body to push out.
func _ghost(on: bool) -> void:
	collision_layer = 0 if on else BODY_LAYER
	collision_mask = 0 if on else 1

# --- Far away: cheaper ---------------------------------------------------------
# Distance tiers, all of them invisible within the fog and the size on screen:
#   shadow   beyond SHADOW_DISTANCE no shadow caster;
#   think    beyond FAR_THINK / FAR_THINK_2 the brain and the step run every 2nd / 4th tick;
#   pose     beyond LOD_MID / LOD_FAR / LOD_VFAR the AnimationPlayer is stepped by hand every
#            2nd / 4th / 8th rendered frame (the skeleton, its skinning and the shadow pass
#            only get new work then), with the elapsed time, so the walk keeps its pace;
#   shader   beyond LOD_FAR the rot shader leaves out its finest veins (instance uniform).
# The hit zones are not part of this: sync_hitboxes() reads the pose on screen at any distance.

## Whether this physics tick is one the brain runs, for a squared ground distance.
func _think_now(d2: float) -> bool:
	if d2 > FAR_THINK_2 * FAR_THINK_2:
		return _frame % 4 == 0
	if d2 > FAR_THINK * FAR_THINK:
		return _frame % 2 == 1
	_owed = 0.0
	return true

## The tier (0..3) for a distance, with hysteresis round the one it is in.
static func lod_for(d: float, current: int) -> int:
	var edges := [LOD_MID, LOD_FAR, LOD_VFAR]
	var tier := 0
	for i in 3:
		var e: float = edges[i] - (LOD_HYST if current > i else 0.0)
		if d > e:
			tier = i + 1
	return tier

## Pose update period in rendered frames for a tier.
static func lod_period(tier: int) -> int:
	return 1 << tier if tier > 0 else 1

## Called from the physics tick: sets the tier, the hand-stepped mode, the shadow and the shader.
func _update_lod(_delta: float) -> void:
	if _anim_player == null or target == null:
		return
	var d := global_position.distance_to(target.global_position)
	var tier := lod_for(d, _lod)
	if tier != _lod:
		set_lod(tier)
	var shadows := d < SHADOW_DISTANCE if _shadows else d < SHADOW_DISTANCE - 2.0
	if shadows != _shadows:
		_shadows = shadows
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Puts the zombie on a tier (tests may force one; the next physics tick sets it by distance again).
func set_lod(tier: int) -> void:
	if _anim_player == null:
		return
	var was_far := _lod > 0
	_lod = tier
	_far = tier > 0
	_lod_ticks = 0
	if _far != was_far:
		_lod_acc = 0.0
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if _far else AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	for mi in _lod_meshes:
		(mi as MeshInstance3D).set_instance_shader_parameter("far_lod", 1.0 if tier >= 2 else 0.0)
	set_process(_far and state < State.DYING)

## Rendered frames: a far zombie's pose is stepped here, by the time owed since its last step.
func _process(delta: float) -> void:
	if _lod == 0 or _anim_player == null:
		return
	_lod_acc += delta
	_lod_ticks += 1
	if (_lod_ticks + _lod_phase) % lod_period(_lod) != 0:
		return
	_anim_player.advance(_lod_acc)
	_lod_acc = 0.0

## Back to the AnimationPlayer running itself (a death plays out in full).
func _lod_release() -> void:
	set_process(false)
	if _anim_player != null and _lod > 0:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		for mi in _lod_meshes:
			(mi as MeshInstance3D).set_instance_shader_parameter("far_lod", 0.0)
	_lod = 0
	_far = false

# --- Hits ----------------------------------------------------------------------

## `damage` is final (the weapon already scaled it for `part`). `melee` marks
## a knife/kick kill for the points.
func take_hit(part: String, dmg: float, dir: Vector3, weapon: Resource = null, melee := false, at := Vector3.INF) -> void:
	if state >= State.DYING:
		return
	if weapon != null and weapon.get("melee") == true:
		melee = true
	last_part = part
	if ZombieMode.insta_kill:
		dmg = maxf(dmg, health)
	health -= dmg
	var killed := health <= 0.0
	hit.emit(self, part, dmg, killed)
	_hit_fx(part, dmg, dir, at, killed, melee)
	if ZombieMode.gore_enabled and is_inside_tree() and not bool(get_meta("prewarm", false)):
		var gore := Gore.of(self)
		if gore != null:
			gore.on_hit(self, part, dmg, dir, at, killed, weapon)
	if killed:
		_die(part, melee, dir)
		var power := _ragdoll_power(dmg, weapon, melee)
		if power > 0.0 and ZombieMode.gore_enabled and is_inside_tree() and not bool(get_meta("prewarm", false)):
			var gore := Gore.of(self)
			if gore != null:
				gore.ragdoll(self, dir, power, at)
		return
	_hit_dir = Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.ZERO
	_react(part, dmg)
	_refresh_gait()
	_flinch_part(part, dir, dmg)

## Blood, the sound of it, a floating number: where the bullet went in (or where the part is).
func _hit_fx(part: String, dmg: float, dir: Vector3, at: Vector3, killed: bool, melee: bool) -> void:
	if not is_inside_tree() or bool(get_meta("prewarm", false)):
		return
	var pos := at
	if pos == Vector3.INF:
		sync_hitboxes()
		var zone := hitboxes.get(part) as Node3D
		pos = zone.global_position if zone != null else global_position + Vector3(0, 1.1, 0)
	var fx := ImpactFX.of(self)
	if fx == null:
		return
	fx.blood_hit(pos, dir if dir.length() > 0.01 else Vector3.BACK, part, killed, dmg / maxf(max_health * 0.3, 1.0))
	fx.damage_number(pos, dmg, part, killed)

## How hard a kill throws the body (m/s), 0 for one that just plays its death clip: a real hit
## (15 % of its health or more), a headless one, or a shotgun close up (thrown hard).
func _ragdoll_power(dmg: float, weapon: Resource, melee: bool) -> float:
	if weapon == null or melee:
		return 0.0
	var close := -1.0
	if int(weapon.get("pellets")) > 1 and target != null and is_instance_valid(target):
		close = (target as Node3D).global_position.distance_to(global_position)
	if close >= 0.0 and close < 6.0:
		return 3.5 + 3.5 * (1.0 - close / 6.0)
	if head_gone:
		return 3.0
	if dmg >= max_health * 0.15:
		return 1.8 + minf(dmg / maxf(max_health, 1.0), 1.0) * 2.2
	return 0.0

## Which way it gives: the head snaps back, a shoulder twists, the body bends, a leg buckles.
func _flinch_part(part: String, dir: Vector3, dmg: float) -> void:
	if _skeleton == null or state >= State.DYING:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		return
	d = d.normalized()
	var inv := _skeleton.global_transform.basis.orthonormalized().inverse()
	var bend := inv * Vector3.UP.cross(d).normalized()
	var spin := inv * Vector3.UP
	var k := clampf(0.5 + dmg / maxf(max_health * 0.25, 1.0), 0.5, 1.6)
	if _flinch == null:
		_flinch = ZombieFlinch.new()
		_skeleton.add_child(_flinch)
	var f: Variant = _flinch
	match part:
		"head":
			f.kick(_skeleton.find_bone("Bip01 Head"), bend, deg_to_rad(34.0) * k)
			f.kick(_skeleton.find_bone("Bip01 Neck"), bend, deg_to_rad(14.0) * k)
			f.kick(_skeleton.find_bone("Bip01 Spine1"), bend, deg_to_rad(6.0) * k)
		"neck":
			f.kick(_skeleton.find_bone("Bip01 Neck"), bend, deg_to_rad(24.0) * k)
			f.kick(_skeleton.find_bone("Bip01 Head"), bend, deg_to_rad(16.0) * k)
		"torso":
			f.kick(_skeleton.find_bone("Bip01 Spine1"), bend, deg_to_rad(14.0) * k)
			f.kick(_skeleton.find_bone("Bip01 Spine"), bend, deg_to_rad(8.0) * k)
		_:
			if part.contains("arm"):
				var sgn := 1.0 if part.ends_with("_l") else -1.0
				f.kick(_skeleton.find_bone("Bip01 Spine1"), spin, deg_to_rad(18.0) * k * sgn)
				f.kick(_skeleton.find_bone("Bip01 " + ("L" if sgn > 0.0 else "R") + " UpperArm"), bend, deg_to_rad(30.0) * k)
			elif part.contains("leg"):
				f.kick(_skeleton.find_bone("Bip01 Pelvis"), -bend, deg_to_rad(13.0) * k)
				f.kick(_skeleton.find_bone("Bip01 Spine"), -bend, deg_to_rad(10.0) * k)

## Which gait its wounds leave it. A leg that is gone or has taken a beating (a fifth of its
## health) puts it on the foot-dragging limp for that side at a bit over half pace; an arm that
## is gone or ruined leans the whole body to that side with the arm hanging. Only the plain
## walkers and runners: the special ones set their own clip.
func _refresh_gait() -> void:
	if legless or _skeleton == null or not (kind == "walker" or kind == "runner"):
		return
	var leg_l := severed.has("leg_l") or severed.has("shin_l") or float(limb_damage.get("upper_leg_l", 0.0)) + float(limb_damage.get("lower_leg_l", 0.0)) >= max_health * 0.2
	var leg_r := severed.has("leg_r") or severed.has("shin_r") or float(limb_damage.get("upper_leg_r", 0.0)) + float(limb_damage.get("lower_leg_r", 0.0)) >= max_health * 0.2
	var arm_l := severed.has("arm_l") or severed.has("forearm_l") or float(limb_damage.get("upper_arm_l", 0.0)) + float(limb_damage.get("lower_arm_l", 0.0)) >= max_health * 0.25
	var arm_r := severed.has("arm_r") or severed.has("forearm_r") or float(limb_damage.get("upper_arm_r", 0.0)) + float(limb_damage.get("lower_arm_r", 0.0)) >= max_health * 0.25
	var clip := _base_clip
	var mult := 1.0
	if leg_l or leg_r:
		clip = "z_limp_l" if (leg_l and not leg_r) else "z_walk3"
		mult = LIMP_PACE
	elif (arm_l or arm_r) and kind == "walker":
		clip = "z_walk_hurt_l" if arm_l and not arm_r else "z_walk_hurt_r"
		mult = HURT_ARM_PACE
	if clip != _move_clip or not is_equal_approx(mult, _gait_mult):
		_move_clip = clip
		gait = clip
		_gait_mult = mult

# --- The throat (npc/ZombieVoice.gd) ------------------------------------------------

## Says something (a kind of ZombieVoice.SOUNDS) from where its head is; the pool decides
## whether anyone hears it. A head blown off has no more to say.
func _say(kind_: String, gain_db := 0.0, variant := -1) -> void:
	if head_gone or not is_inside_tree() or bool(get_meta("prewarm", false)) or not (kind == "walker" or kind == "runner"):
		return
	var v := ZombieVoice.of(self)
	if v == null:
		return
	var up := 0.5 if (legless or state == State.KNEEL) else 1.55
	if entrance == "rise" and state == State.ENTER:
		gain_db -= 10.0
		up = 0.2
	var pitch := _voice_pitch * (0.86 if legless else 1.0)
	if v.say(global_position + Vector3.UP * up * body_scale / 1.5, kind_, pitch, gain_db, variant):
		voice_kinds[kind_] = int(voice_kinds.get(kind_, 0)) + 1

## The voice follows what the body does: a groan every few seconds while it comes on (a crawler
## and a runner more often), and, within earshot, the breath: in on one step, out on the next, so
## the rasp keeps the gait's time. Nothing while it is far, dying or attacking (the snarl covers that).
func _voice_tick(delta: float) -> void:
	if head_gone or state == State.DEAD or state >= State.DYING or _lod > 0 or not (kind == "walker" or kind == "runner"):
		return
	_voice_t -= delta
	if _voice_t <= 0.0:
		_voice_t = randf_range(3.5, 9.0) * (0.6 if (kind == "runner" or legless) else 1.0)
		if state == State.CHASE or state == State.TEAR or state == State.KNEEL:
			_say("groan")
	if state == State.CHASE and _dist_player < 9.0 and Vector2(velocity.x, velocity.z).length() > 0.3:
		var clip := "z_crawl" if legless else _move_clip
		_breath_t -= delta * maxf(anim.stride_rate(clip, Vector2(velocity.x, velocity.z).length()), 0.4)
		if _breath_t <= 0.0:
			_breath_t = anim.step_time(clip) * (0.9 if kind == "runner" else 1.0)
			_breath_out = not _breath_out
			_say("rasp", 0.0, 1 if _breath_out else 0)

## A shove along the ground (a shotgun at close range).
func knock(v: Vector3) -> void:
	if state >= State.DYING:
		return
	v.y = 0.0
	_knock += v
	if _knock.length() > 7.0:
		_knock = _knock.normalized() * 7.0

## What it does with a hit: nothing for a graze (the bone kicks in _flinch_part still play), a
## grunt and a clip for one that matters. The clip says where it landed: the head snaps, a
## shoulder takes the upper body round (the side that was hit), the chest rocks it, a leg
## buckles into a stumble or, when the leg has taken enough, down onto a knee. A big hit also
## shoves it along the shot. The clip hands over to the walk 0.18 s before it ends so the
## stagger blends into the gait (a stopped player cannot crossfade).
func _react(part: String, dmg: float) -> void:
	if state == State.ENTER or state >= State.DYING:
		return
	var big := dmg >= max_health * 0.12
	if big and not head_gone and _pain_cd <= 0.0:
		_pain_cd = 0.7
		_say("pain")
	# A graze doesn't make it flinch.
	if not big or state == State.ATTACK or state == State.KNEEL or state == State.STANDUP:
		return
	var heavy := dmg >= max_health * 0.25
	# Quick hits in a row only keep the bones kicking (_flinch_part): a zombie under an SMG is
	# rocked, not held still. A heavy one always lands.
	if _react_cd > 0.0 and not heavy:
		return
	_lunge_t = 0.0
	if part.contains("leg") and not legless:
		var hurt := 0.0
		for p in ["upper_leg_l", "lower_leg_l", "upper_leg_r", "lower_leg_r"]:
			hurt += float(limb_damage.get(p, 0.0))
		if dmg >= max_health * 0.18 or hurt >= max_health * 0.4 or _gait_mult < 1.0:
			_kneel_left = part.ends_with("_l")
			_begin_kneel()
			return
		_knock_along(1.6)
		_hit_clip("z_stumble", 0.9)
		return
	var clip := "z_hit_chest"
	var secs := 0.0
	if part == "head" or part == "neck":
		clip = "z_stumble" if heavy else "z_hit_head"
		secs = 0.9 if heavy else 0.0
	elif part.contains("arm"):
		clip = "z_hit_arm_l" if part.ends_with("_l") else "z_hit_arm_r"
		secs = 0.75
	elif heavy:
		# (z_hit_knockback is a knock-down onto the back: for the brute, not for a bullet.)
		clip = "z_stumble"
		secs = 0.9
	if heavy:
		_knock_along(2.2)
	_hit_clip(clip, secs)

## Plays a reaction clip and holds the chase for it, less the blend into the walk. `seconds` > 0
## squeezes the clip into that time (the longer takes are slow for a bullet's worth of hurt).
func _hit_clip(clip: String, seconds := 0.0) -> void:
	if state != State.CHASE:
		_stagger = 0.35
		return
	var dur := anim.play_once_timed(clip, seconds) if seconds > 0.0 else anim.play_once(clip, 1.0)
	_stagger = clampf(dur - 0.18, 0.25, 1.2)
	_react_cd = _stagger + 0.4

## A shove along the shot (the way the bullet travelled).
func _knock_along(power: float) -> void:
	if _hit_dir != Vector3.ZERO:
		_knock += _hit_dir * power
		if _knock.length() > 7.0:
			_knock = _knock.normalized() * 7.0

## Down on a knee: the leg clip plays once and its last frame is held.
func _begin_kneel() -> void:
	state = State.KNEEL
	_barricade = null
	_lunge_t = 0.0
	_kneel_t = KNEEL_TIME
	var left := _kneel_left or ((severed.has("leg_l") or severed.has("shin_l")) and not (severed.has("leg_r") or severed.has("shin_r")))
	_kneel_left = false
	var dur := anim.play_once("z_hit_leg_l" if left else "z_hit_leg", 1.0)
	# The clip ends on the knee and a stopped player can't crossfade: hand
	# over to the stand-up / crawl while it is still running, so there is a
	# real blend out of the kneel and no pop.
	if dur > 0.0:
		_kneel_t = minf(KNEEL_TIME, maxf(dur - 0.12, 0.2))
	_say("pain")

func _kneel(delta: float) -> void:
	_kneel_t -= delta
	if _kneel_t > 0.0:
		return
	kneel_handoff_live = _anim_player != null and _anim_player.is_playing()
	if legless:
		# No legs to get up on: drag on from where it knelt.
		state = State.CHASE
		_repath_in = 0.0
		return
	state = State.STANDUP
	_kneel_t = maxf(anim.play_once("z_standup", 1.0), 0.4)

func is_kneeling() -> bool:
	return state == State.KNEEL

func _die(part: String, melee: bool, _dir: Vector3) -> void:
	_end_entrance()
	state = State.DYING
	_release_slot()
	remove_from_group("zombies")
	add_to_group("corpses")
	# Nothing of it can be shot or bumped into any more.
	collision_layer = 0
	for p in hitboxes:
		var area := hitboxes[p] as Area3D
		area.set_deferred("monitorable", false)
		area.collision_layer = 0
	# Shot from the front it goes over backwards, from behind onto its face (a fifth of them the other way).
	var fwd := Vector3(sin(_facing), 0.0, cos(_facing))
	var d_flat := Vector3(_dir.x, 0.0, _dir.z)
	var forward := randf() < 0.4
	if d_flat.length() > 0.01:
		forward = d_flat.normalized().dot(fwd) > 0.0
		if randf() < 0.2:
			forward = not forward
	_lunge_t = 0.0
	var dur := anim.play_once("z_death2" if (forward and not legless) else "z_death", 1.0)
	if not head_gone and not melee:
		_say("pain", 0.0)
	_lod_release()
	died.emit(self, part, melee)
	get_tree().create_timer(maxf(dur, 0.5) + 0.1).timeout.connect(_settle)

func _settle() -> void:
	if state != State.DYING:
		return
	state = State.DEAD
	_shape.set_deferred("disabled", true)
	if ZombieMode.gore_enabled and not bool(get_meta("prewarm", false)):
		var gore := Gore.of(self)
		if gore != null:
			gore.pool_under(self)

## Both legs gone (gore, Z6): it crawls from now on. `false` gives the legs back.
func set_legless(on := true) -> void:
	if legless == on:
		return
	legless = on
	if _shape == null:
		return
	var cap := _shape.shape as CapsuleShape3D
	cap.height = 0.7 if on else 1.7
	_shape.position.y = 0.35 if on else 0.85
	if on and state == State.STANDUP:
		state = State.CHASE
	for p in ["upper_leg_l", "upper_leg_r", "lower_leg_l", "lower_leg_r"]:
		if hitboxes.has(p) and state < State.DYING:
			(hitboxes[p] as Area3D).collision_layer = 0 if on else ZombieHitboxes.HITBOX_LAYER

func is_alive() -> bool:
	return state < State.DYING

## Removes a corpse (the spawner keeps no more than a dozen).
func remove_corpse() -> void:
	if is_inside_tree():
		queue_free()
