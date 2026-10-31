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
const Gore := preload("res://fx/gore/Gore.gd")
const ROT_SHADER := preload("res://npc/zombie_rot.gdshader")

enum State { CHASE, TEAR, ATTACK, KNEEL, STANDUP, DYING, DEAD }

## Bodies the dead wear.
const BODIES := [
	"Male_Adult_01", "Male_Adult_02", "Male_Adult_03", "Male_Adult_04", "Male_Adult_05",
	"Male_Adult_06", "Male_Adult_08", "Male_Adult_09", "Male_Adult_10", "Male_Adult_11",
	"Female_Adult_01", "Female_Adult_02", "Female_Adult_03", "Female_Adult_04", "Female_Adult_05",
	"Female_Adult_07", "Female_Adult_08", "Female_Adult_09", "Business_Male_02", "Construction_Male_08",
]
const MODEL_DIR := "res://assets/rocketbox/"

const WALK_CLIPS := ["z_walk", "z_walk2", "z_walk3"]
const ATTACK_CLIPS := ["z_attack", "z_attack2", "z_attack3"]
const WALK_SPEED := Vector2(0.9, 1.45)
const RUN_SPEED := Vector2(3.0, 3.7)
## Legless, it drags itself along.
const CRAWL_SPEED := 0.75
const TURN_SPEED := 7.0
## Reach of a claw, and when in the swing it lands (fraction of the clip).
const ATTACK_RANGE := 1.35
const ATTACK_HIT_AT := 0.45
const ATTACK_COOLDOWN := 0.5
const ATTACK_DAMAGE := 35.0
const RUNNER_DAMAGE := 40.0
## Seconds between a zombie's board-tearing swings.
const TEAR_PERIOD := 2.2
## Beyond this from the player its animation runs on every second frame and
## it casts no shadow.
const FAR_DISTANCE := 15.0
const SHADOW_DISTANCE := 12.0
## Beyond this from the player it thinks and steps every second physics tick.
const FAR_THINK := 28.0
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
	collision_layer = BODY_LAYER
	collision_mask = 1
	# The block is flat and its floors sit on another layer: like the player,
	# it walks the plane and never falls.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	_shape.shape = cap
	_shape.position = Vector3(0, 0.85, 0)
	add_child(_shape)
	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_model_root.scale = Vector3.ONE * 1.5
	add_child(_model_root)
	var body: String = get_meta("body", BODIES[0])
	model = CharacterCast.scene_for(MODEL_DIR + body + ".glb").instantiate()
	_model_root.add_child(model)
	CharacterAnimator.install_zombie_library(model)
	anim = CharacterAnimator.new(model, _move_clip)
	anim.set_clips(_move_clip, "z_idle")
	_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton and ZombieMode.gore_enabled:
		# Limb ids on the body's vertices, so a lost limb can be clipped away (once per body;
		# before the rot materials, since a new mesh drops the surface overrides).
		Gore.GoreRig.prepare(self)
	_apply_rot(float(get_meta("seed", 0.0)))
	if _skeleton:
		hitboxes = ZombieHitboxes.build(_skeleton, self)

	_facing = randf() * TAU
	_model_root.rotation.y = _facing
	_repath_in = randf_range(0.0, REPATH.y)
	_frame = randi() % 2
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	# Starts into its walk at a random point, so a crowd isn't in step.
	anim.play(_move_clip, 1.0)
	if _anim_player:
		_anim_player.seek(randf() * 0.8, true)

# --- The look ------------------------------------------------------------------

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
	_frame += 1
	# Far down the street it thinks and steps every second tick, on double time:
	# nobody can see the difference at 30 m, and it halves the far half of the horde.
	if state == State.CHASE and target != null and is_instance_valid(target):
		var away := target.global_position - global_position
		if away.x * away.x + away.z * away.z > FAR_THINK * FAR_THINK:
			if _frame % 2 == 0:
				_owed += delta
				return
		else:
			_owed = 0.0
	delta += _owed
	_owed = 0.0
	_stagger = maxf(_stagger - delta, 0.0)
	_slow = maxf(_slow - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_update_lod(delta)
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
	to.y = 0.0
	var dist := to.length()
	if dist < ATTACK_RANGE and _attack_cooldown <= 0.0 and _stagger <= 0.0:
		_begin_attack(to)
		return Vector3.ZERO
	if _stagger > 0.0:
		return Vector3.ZERO
	var dir := to.normalized()
	_holding = false
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

func _begin_attack(to: Vector3) -> void:
	state = State.ATTACK
	_attack_hit_done = false
	_attack_time = 0.0
	_face(to, 1.0)
	var clip: String = ATTACK_CLIPS[randi() % ATTACK_CLIPS.size()]
	_attack_len = _swing(clip)

func _swing(clip: String, rate := 1.0) -> float:
	var dur := anim.play_once(clip, rate)
	return maxf(dur, 0.4)

func _attack(delta: float) -> void:
	_attack_time += delta
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		_face(to, delta * 0.5)
		if not _attack_hit_done and _attack_time >= _attack_len * ATTACK_HIT_AT:
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
	_facing = lerp_angle(_facing, atan2(dir.x, dir.z), clampf(TURN_SPEED * delta, 0.0, 1.0))
	_model_root.rotation.y = _facing

func _move(want: Vector3, delta: float) -> void:
	var v := Vector3.ZERO
	if want.length() > 0.01:
		var pace := CRAWL_SPEED if legless else speed
		if _slow > 0.0:
			pace *= 0.5
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
	if state == State.CHASE and _stagger <= 0.0:
		var moved := Vector2(velocity.x, velocity.z).length()
		var clip := "z_crawl" if legless else _move_clip
		if moved > 0.15:
			anim.play(clip, anim.stride_rate(clip, moved))
		else:
			anim.play("z_idle", 1.0)

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

# --- Far away: cheaper ---------------------------------------------------------

## Beyond FAR_DISTANCE of the player its animation advances every other
## frame (twice as far each time) and it stops casting a shadow.
func _update_lod(delta: float) -> void:
	if _anim_player == null or target == null:
		return
	var d := global_position.distance_to(target.global_position)
	var far := d > FAR_DISTANCE if not _far else d > FAR_DISTANCE - 2.0
	if far != _far:
		_far = far
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if far else AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if _far and _frame % 2 == 0:
		_anim_player.advance(delta * 2.0)
	var shadows := d < SHADOW_DISTANCE if _shadows else d < SHADOW_DISTANCE - 2.0
	if shadows != _shadows:
		_shadows = shadows
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
		return
	_react(part, dmg)
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

## A shove along the ground (a shotgun at close range).
func knock(v: Vector3) -> void:
	if state >= State.DYING:
		return
	v.y = 0.0
	_knock += v
	if _knock.length() > 7.0:
		_knock = _knock.normalized() * 7.0

func _react(part: String, dmg: float) -> void:
	# A hit that matters makes it flinch; a graze doesn't.
	if dmg < max_health * 0.12 or state == State.ATTACK or state == State.KNEEL or state == State.STANDUP:
		return
	if part.contains("leg") and not legless:
		_begin_kneel()
		return
	var clip := "z_hit_chest"
	if part == "head" or part == "neck":
		clip = "z_hit_head"
	_stagger = 0.35
	if state == State.CHASE:
		anim.play_once(clip, 1.0)

## Down on a knee: the leg clip plays once and its last frame is held.
func _begin_kneel() -> void:
	state = State.KNEEL
	_barricade = null
	_kneel_t = KNEEL_TIME
	var dur := anim.play_once("z_hit_leg", 1.0)
	# The clip ends on the knee and a stopped player can't crossfade: hand
	# over to the stand-up / crawl while it is still running, so there is a
	# real blend out of the kneel and no pop.
	if dur > 0.0:
		_kneel_t = minf(KNEEL_TIME, maxf(dur - 0.12, 0.2))

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
	var dur := anim.play_once("z_death2" if (randf() < 0.4 and not legless) else "z_death", 1.0)
	if _anim_player and _far:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
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
