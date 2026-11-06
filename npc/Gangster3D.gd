extends "res://npc/Zombie3D.gd"
## A man of the rival crew, armed. Same body pipeline as the dead (a Rocketbox body, hit zones on the bones, gore,
## ragdoll, LOD, group "zombies" so every weapon, aim assist and rumble sees it), but a different head: it moves
## between cover points (npc/CoverMap.gd, found in the block's own geometry), crouches behind a car or a wall, leans
## out or stands up to shoot in bursts, flanks in pairs, pushes when you reload, falls back when hurt, and now and
## then throws a bottle of fire or a grenade. It shoots back with hitscan: tracers, flashes, a crack and a whizz if the
## round passes you, damage that falls off with distance, and an aim that earns its accuracy (see hit_chance()).
##
## Built in code by npc/GangSpawner.gd. Group "gangsters" while it can hurt you.

signal fired(who: Node, from: Vector3, hit: bool)
signal barked(who: Node, text: String)

const GunModelScript := preload("res://weapons/GunModel.gd")
const CoverMapScript := preload("res://npc/CoverMap.gd")
const Barks := preload("res://npc/Barks.gd")
const GangFX := preload("res://fx/GangFX.gd")
const GANG_SHADER := preload("res://npc/gangster.gdshader")
const GangGrip := preload("res://npc/GangGrip.gd")
const GhettoVoice := preload("res://fx/GhettoVoice.gd")

enum Mode { ADVANCE, COVER, PEEK, FLANK, PUSH, RETREAT, THROW, HOLD }

const GANG_BODIES := [
	"Male_Adult_01", "Male_Adult_02", "Male_Adult_03", "Male_Adult_04", "Male_Adult_05", "Male_Adult_06",
	"Male_Adult_08", "Male_Adult_09", "Male_Adult_10", "Male_Adult_11", "Business_Male_02", "Construction_Male_08",
]
## Crews are told apart by the colour of what they wear and a bandana: nothing else about them differs.
const CREW_LOOK := {
	"Dock Boys": {"cloth": Color(0.42, 0.5, 0.16), "band": Color(0.95, 0.78, 0.1)},
	"Eastside Kings": {"cloth": Color(0.38, 0.16, 0.55), "band": Color(0.95, 0.95, 0.9)},
	# The warrant team (the story's raid): dark uniform, a helmet, POLICE across the vest. A role, not a crew.
	"Police": {"cloth": Color(0.14, 0.22, 0.42), "band": Color(0.08, 0.09, 0.12), "police": true},
}
## Per gun: damage per round (per pellet), rounds a second, burst (min, max), magazine, pellets, reach where the
## damage is gone (m), reload seconds, the weapon file whose model and shot it borrows.
const GUNS := {
	"pistol": {"dmg": 7.0, "rate": 3.4, "burst": [1, 3], "mag": 12, "pellets": 1, "reach": 70.0, "reload": 1.7},
	"smg": {"dmg": 4.5, "rate": 11.0, "burst": [4, 9], "mag": 30, "pellets": 1, "reach": 50.0, "reload": 2.0},
	"ar": {"dmg": 7.5, "rate": 8.0, "burst": [3, 6], "mag": 30, "pellets": 1, "reach": 100.0, "reload": 2.3},
	"shotgun": {"dmg": 4.5, "rate": 0.9, "burst": [1, 1], "mag": 6, "pellets": 7, "reach": 24.0, "reload": 2.6},
	"lmg": {"dmg": 6.5, "rate": 9.0, "burst": [8, 16], "mag": 100, "pellets": 1, "reach": 90.0, "reload": 4.0},
}
## How fast it goes (m/s): a walk, a jog, a rush.
const PACE_WALK := 1.5
const PACE_JOG := 3.0
const PACE_RUSH := 3.8
const CROUCH_PACE := 2.0
## Seconds of exposure to the player for the aim to be at its best.
const AIM_UP := 1.6
## First shots miss by this much (m) near the player, and by this once the aim has come in.
const MISS_FAR := 3.2
const MISS_NEAR := 0.5
const HEIGHT_STAND := 1.55
const HEIGHT_CROUCH := 1.0

static var cover_map: CoverMapScript
## Shared pacing so a squad does not all throw at once.
static var next_throw := 0.0

var crew := "Dock Boys"
var gun_id := "pistol"
var gun: Dictionary = GUNS["pistol"]
var wd: Resource
var skill := 0.4
var vest_hp := 0.0
var vest_max := 0.0
var wave := 1
var boss := false
var buddy: Node
var role := "support"
var title := ""

var mode: Mode = Mode.ADVANCE
var mag := 12
var cover_i := -1
var crouched := false
var retreated := false
var _goal := Vector3.INF
var _mode_t := 0.0
var _cycles := 0
var _fire_cd := 0.0
var _burst_left := 0
var _burst_rest := 0.0
var _peeks_left := 1
var _reload_t := 0.0
var _exposure := 0.0
var _react_t := 0.0
var _los := false
var _los_head := false
var _los_t := 0.0
var _sense_t := 0.0
var _last_seen := Vector3.INF
var _last_seen_t := 99.0
var _bark_cd := 0.0
var _taunt_t := randf_range(6.0, 14.0)
var _drive_by := false
var _busy_t := 0.0
var _want := Vector3.ZERO
var _pace := PACE_JOG
var _gun_node: Node3D
var _grip: SkeletonModifier3D
var _muzzle_local := Vector3.ZERO
var _lean_pos := Vector3.INF
var _throw_t := -1.0
var _throw_kind := ""
var _throw_goal := Vector3.INF
var _cover_checked := false
var _wounded_flinch := 0.0
var shots_fired := 0
var hits_landed := 0
var last_hit_chance := 0.0
var _clip := ""
## Downed: hit hard, gun dropped, crawling away and begging; bleeds out unless you finish it (it pays more).
var downed := false
var _bleed_t := 0.0
var finished_by_player := false
const BLEED_TIME := Vector2(9.0, 13.0)
const FINISH_BONUS := 150
var _skin_materials := {}
## For the tests and the spawner: sets the mood before the body exists.
var aggression := 0.5

func configure(zkind: String, round_no: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	kind = zkind
	wave = maxi(round_no, 1)
	boss = zkind == "heavy"
	max_health = float(ZombieMode.gang_health(wave))
	vest_hp = float(ZombieMode.gang_vest(wave))
	gun_id = ZombieMode.gang_gun(wave, rng.randf())
	skill = clampf(rng.randf_range(0.26, 0.4) + wave * 0.01, 0.25, 0.52)
	aggression = rng.randf_range(0.25, 0.9)
	_pace = PACE_JOG * rng.randf_range(0.92, 1.08)
	if zkind == "vest":
		vest_hp = maxf(vest_hp, 60.0)
	if boss:
		max_health = 520.0 + 60.0 * float(wave / ZombieMode.BOSS_EVERY)
		vest_hp = 400.0 + 80.0 * float(wave / ZombieMode.BOSS_EVERY)
		gun_id = "lmg" if wave >= 10 or rng.randf() < 0.5 else "shotgun"
		skill = 0.5
		_pace = PACE_WALK * 1.35
		body_scale = 1.62
		title = "TAC LEAD" if crew == "Police" else "THE ENFORCER"
	health = max_health
	vest_max = vest_hp
	gun = GUNS[gun_id]
	mag = int(gun["mag"])
	speed = _pace
	_move_clip = "ga_jog"
	_rot_amount = 0.0
	set_meta("body", GANG_BODIES[rng.randi() % GANG_BODIES.size()])
	set_meta("seed", rng.randf())

# --- The look ------------------------------------------------------------------------

func _make_anim() -> void:
	CharacterAnimator.install_zombie_library(model)
	CharacterAnimator.install_gang_library(model)
	anim = CharacterAnimator.new(model, "ga_jog")
	anim.set_clips("ga_jog", "ga_stand")

func _apply_look() -> void:
	add_to_group("gangsters")
	var look: Dictionary = CREW_LOOK.get(crew, CREW_LOOK["Dock Boys"])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var src := inst.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			inst.set_surface_override_material(i, _skin_material(src, look["cloth"], 0.93 if look.get("police", false) else 0.6))
		inst.set_instance_shader_parameter("rot", 0.0)
		inst.set_instance_shader_parameter("seed", float(get_meta("seed", 0.0)))
		_lod_meshes.append(inst)
	_attach_gear(look)

static var _mats := {}

static func _skin_material(src: BaseMaterial3D, cloth: Color, tint := 0.6) -> Material:
	var key := [src, cloth]
	for k in _mats:
		if k[0] == src and k[1] == cloth:
			return _mats[k]
	var rname := src.resource_name
	var m: Material
	if rname.ends_with("opacity"):
		m = src.duplicate()
		(m as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		(m as BaseMaterial3D).alpha_scissor_threshold = 0.45
		(m as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var sm := ShaderMaterial.new()
		sm.shader = GANG_SHADER
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("albedo_color", src.albedo_color)
		sm.set_shader_parameter("noise_tex", noise_texture())
		sm.set_shader_parameter("kind", 1 if rname.ends_with("head") else 0)
		sm.set_shader_parameter("roughness_base", src.roughness)
		sm.set_shader_parameter("crew", cloth)
		sm.set_shader_parameter("crew_tint", tint)
		m = sm
	_mats[key] = m
	return m

## The gun in the right hand and the bandana on the head: both ride bones, scaled out of the skeleton's units.
func _attach_gear(look: Dictionary) -> void:
	if _skeleton == null:
		return
	var unit := _skeleton.global_transform.basis.get_scale().x
	if unit <= 0.0:
		unit = 0.01
	wd = load("res://weapons/%s.tres" % gun_id)
	var rh := BoneAttachment3D.new()
	rh.name = "GunMount"
	rh.bone_name = "Bip01 R Hand"
	_skeleton.add_child(rh)
	_gun_node = GunModelScript.build(wd)
	_gun_node.basis = Basis(GUN_QUAT) * Basis.from_scale(Vector3.ONE / unit)
	_gun_node.position = GUN_POS / unit
	rh.add_child(_gun_node)
	for mi in _gun_node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var length := float(wd.get("model_length"))
	_muzzle_local = Vector3(0, 0, -length * (1.0 - GunModelScript.GRIP_AT))
	# The left hand: under a pistol's grip, out on the foregrip of anything longer.
	_grip = GangGrip.new()
	_grip.name = "GangGrip"
	_grip.unit = unit
	_grip.gun_pos = GUN_POS
	_grip.gun_quat = GUN_QUAT
	_grip.fore_m = Vector3(0, -0.045, -0.04) if gun_id == "pistol" else Vector3(0, -0.04, -length * (0.30 if gun_id != "lmg" else 0.34))
	_skeleton.add_child(_grip)
	if look.get("police", false):
		_attach_police_gear(unit)
		return
	# A bandana: a band round the head at the brow, in the crew's colour.
	var hd := BoneAttachment3D.new()
	hd.name = "Bandana"
	hd.bone_name = "Bip01 Head"
	_skeleton.add_child(hd)
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.104
	cyl.bottom_radius = 0.104
	cyl.height = 0.075
	cyl.cap_top = false
	cyl.cap_bottom = false
	band.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = look["band"]
	bm.roughness = 0.9
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = bm
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.scale = Vector3.ONE / unit
	band.position = BAND_POS / unit
	band.rotation_degrees = BAND_ROT
	hd.add_child(band)

## The warrant team's look: a helmet with a white stripe and POLICE on the back and the chest of the vest.
func _attach_police_gear(unit: float) -> void:
	var hd := BoneAttachment3D.new()
	hd.name = "Helmet"
	hd.bone_name = "Bip01 Head"
	_skeleton.add_child(hd)
	var shell := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.114
	sph.height = 0.114
	sph.is_hemisphere = true
	sph.radial_segments = 20
	sph.rings = 6
	shell.mesh = sph
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.05, 0.06, 0.09)
	hm.roughness = 0.4
	hm.metallic = 0.25
	shell.material_override = hm
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.scale = Vector3.ONE / unit
	shell.position = (BAND_POS + Vector3(0.03, -0.004, 0.0)) / unit
	shell.rotation_degrees = BAND_ROT
	hd.add_child(shell)
	var rim := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.116
	cyl.bottom_radius = 0.116
	cyl.height = 0.014
	cyl.cap_top = false
	cyl.cap_bottom = false
	rim.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.9, 0.9, 0.95)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim.material_override = sm
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.scale = Vector3.ONE / unit
	rim.position = (BAND_POS + Vector3(0.03, -0.004, 0.0)) / unit
	rim.rotation_degrees = BAND_ROT
	hd.add_child(rim)
	# POLICE on the vest, front and back (the chest bone's own axes: +X is up the spine, Y forward).
	var ch := BoneAttachment3D.new()
	ch.name = "VestMark"
	ch.bone_name = "Bip01 Spine2" if _skeleton.find_bone("Bip01 Spine2") >= 0 else "Bip01 Spine1"
	_skeleton.add_child(ch)
	for side in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "POLICE"
		lb.font = load("res://assets/fonts/Bungee-Regular.ttf")
		lb.font_size = 48
		lb.pixel_size = 0.0019 / unit
		lb.modulate = Color(0.93, 0.93, 0.96)
		lb.outline_size = 0
		lb.shaded = false
		lb.double_sided = false
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lb.position = Vector3(0.0, 0.15 * side, 0.0) / unit
		# The text's up is the spine's X, its face looks out along the bone's Y (front) or minus Y (back).
		lb.basis = Basis(Vector3(0, 0, side), Vector3(1, 0, 0), Vector3(0, side, 0)) * Basis.from_scale(Vector3.ONE)
		ch.add_child(lb)

## Where the gun sits in the hand (bone-local, metres) and how it is turned; tuned against the aim pose.
## (GUN_QUAT: the hand's rotation to a gun whose barrel runs along the aim pose's arm, upright, measured by
## dev-tools/gang_fit_probe.gd on the ga_stand pose; the head's X axis is up and Y forward.)
const GUN_QUAT := Quaternion(0.4014, -0.3619, -0.5198, 0.6616)
const GUN_POS := Vector3(0.05, 0.0, 0.0)
const BAND_POS := Vector3(0.062, 0.016, 0.0)
const BAND_ROT := Vector3(0, 0, -90)

# --- Brain ---------------------------------------------------------------------------

static var _roster_frame := -1
static var _roster: Array = []

static func roster(tree: SceneTree) -> Array:
	var f := Engine.get_physics_frames()
	if f != _roster_frame:
		_roster_frame = f
		_roster = tree.get_nodes_in_group("gangsters")
	return _roster

func _physics_process(delta: float) -> void:
	if state >= State.DYING:
		super._physics_process(delta)
		return
	if bool(get_meta("prewarm", false)):
		return
	_frame += 1
	_stagger = maxf(_stagger - delta, 0.0)
	_busy_t = maxf(_busy_t - delta, 0.0)
	_bark_cd = maxf(_bark_cd - delta, 0.0)
	_wounded_flinch = maxf(_wounded_flinch - delta, 0.0)
	_update_lod(delta)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	if target == null:
		return
	match state:
		State.KNEEL:
			_kneel(delta)
		State.STANDUP:
			_kneel_t -= delta
			if _kneel_t <= 0.0:
				state = State.CHASE
	_want = Vector3.ZERO
	if state == State.CHASE and _stagger <= 0.0:
		_sense(delta)
		_think(delta)
		_fire_tick(delta)
	_locomote(delta)

# -- Senses --

func eye() -> Vector3:
	return global_position + Vector3(0, HEIGHT_CROUCH if crouched else HEIGHT_STAND, 0)

func _player_head() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return target.global_position + Vector3(0, 1.6, 0)

func _player_chest() -> Vector3:
	var head := _player_head()
	return Vector3(target.global_position.x, minf(target.global_position.y + 1.05, head.y - 0.3), target.global_position.z)

func _wall_between(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	# The player's own capsule holds the camera: it is not a wall.
	var ex: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	q.exclude = ex
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _sense(delta: float) -> void:
	_last_seen_t += delta
	_sense_t -= delta
	if _sense_t > 0.0:
		return
	_sense_t = 0.12 + randf() * 0.05
	# Sight is judged from the gun: if the muzzle can see you, a round can reach you.
	var from := muzzle_pos() if _gun_node != null and not downed else eye()
	var head := _player_head()
	var chest := _player_chest()
	_los_head = not _wall_between(from, head)
	var was := _los
	_los = _los_head or not _wall_between(from, chest)
	if _los:
		_last_seen = chest
		_last_seen_t = 0.0
		_los_t += _sense_t
		if not was:
			_react_t = randf_range(0.3, 0.65)
			if _last_seen_t < 0.2:
				bark("spot")
	else:
		_los_t = 0.0
		if was and _last_seen_t < 0.5 and randf() < 0.5:
			bark("lost")

## What the warrant team says for each of the crews' events (fx/GhettoStoryScript.gd POLICE_BARKS); "" = silent.
const POLICE_EVENT := {"spot": "spot", "flank": "advance", "mock_reload": "advance", "taunt": "advance", "boss": "spot",
	"reload": "reload", "hit": "down", "ally_down": "down", "retreat": "down", "throw": "radio", "lost": "advance"}
## Where a Dock Boys event also has the story's extra lines (habit taunts, the drive-by cry).
const EXTRA_EVENT := {"taunt": "taunt_habit", "mock_reload": "mock_reload2", "begging": "cry", "spot": "drive_by"}

func bark(event: String, force := false) -> void:
	if not force and _bark_cd > 0.0:
		return
	var d := global_position.distance_to(target.global_position) if target != null else 0.0
	if d > 55.0:
		return
	if boss and event == "spot" and randf() < 0.6:
		event = "boss"
	_bark_cd = randf_range(4.0, 7.0)
	var text := ""
	var kind := ""
	if crew == "Police":
		text = GhettoVoice.pick(String(POLICE_EVENT.get(event, "")))
		kind = "police"
	else:
		var extra := String(EXTRA_EVENT.get(event, ""))
		# The drive-by men shout their own thing when they see you; the rest sometimes use the story's lines.
		if extra != "" and ((event == "spot" and _drive_by) or (event != "spot" and randf() < 0.4)):
			text = GhettoVoice.pick(extra)
		if text == "":
			text = Barks.pick(event)
	if text == "":
		return
	barked.emit(self, text)
	# Spoken from where he stands (the line's baked take follows the Mature language option), and on the feed.
	var voice := GhettoVoice.bark(self, text, global_position + Vector3(0, 1.6, 0), kind)
	if voice != null and d < 28.0:
		GhettoVoice.duck_music(voice, 4.0)
	var hud := get_tree().get_first_node_in_group("zombie_hud")
	if hud != null and hud.has_method("callout"):
		hud.callout(title if title != "" else crew, text, global_position, crew)

# -- Deciding --

func _think(delta: float) -> void:
	if downed:
		_crawl(delta)
		return
	# Talk: from cover and from the peek, now and then, the corner is theirs.
	_taunt_t -= delta
	if _taunt_t <= 0.0:
		_taunt_t = randf_range(9.0, 18.0)
		if mode == Mode.COVER or mode == Mode.PEEK:
			bark("taunt")
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_mode_t -= delta
	var holder := get_tree().get_first_node_in_group("weapon_holder")
	var player_reloading: bool = holder != null and bool(holder.get("reloading"))
	# Hurt: fall back once.
	if not retreated and health < max_health * 0.35 and mode != Mode.RETREAT and not boss:
		retreated = true
		_begin_retreat()
	match mode:
		Mode.ADVANCE, Mode.FLANK, Mode.PUSH:
			crouched = false
			if _goal == Vector3.INF and mode == Mode.ADVANCE and cover_i < 0:
				_first_orders()
			_walk_to_goal(delta, _pace * (1.25 if (mode == Mode.FLANK or dist > 35.0) else 1.0))
			if _goal == Vector3.INF or _flat_dist(_goal) < (0.45 if cover_i >= 0 else 0.9):
				_arrive()
			elif _mode_t < -22.0:
				# Not getting there: another spot (or the player's side of the street).
				_mode_t = 0.0
				if not _choose_cover(false, 0.0):
					_arrive()
			elif mode == Mode.ADVANCE and _los and dist < 14.0 and cover_i < 0:
				_arrive()
		Mode.COVER:
			crouched = cover_i >= 0
			# Settle on the spot (coming back from leaning out).
			if cover_i >= 0 and _goal != Vector3.INF and _flat_dist(_goal) > 0.3:
				_want = Vector3(_goal.x - global_position.x, 0.0, _goal.z - global_position.z).normalized()
				_pace_now = 2.2
			if _reload_t > 0.0:
				return
			if mag <= 0:
				_begin_reload()
				return
			if _mode_t > 0.0:
				return
			_decide_from_cover(dist, player_reloading)
		Mode.PEEK:
			crouched = false
			_peek(delta, dist)
		Mode.RETREAT:
			crouched = _goal == Vector3.INF or _flat_dist(_goal) < 0.9
			if not crouched:
				_walk_to_goal(delta, PACE_RUSH)
			elif _mode_t <= 0.0:
				mode = Mode.COVER
				_mode_t = 0.5
		Mode.THROW:
			_throw_tick(delta)
		Mode.HOLD:
			pass

## Fresh off the spawn point: to the best cover near the player, or at least towards them.
func _first_orders() -> void:
	if _choose_cover(false, 0.0):
		return
	var pl := target.global_position
	var away := Vector3(global_position.x - pl.x, 0, global_position.z - pl.z).normalized()
	_goal = pl + away * 14.0

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _cover() -> Dictionary:
	if cover_map == null or cover_i < 0 or cover_i >= cover_map.points.size():
		return {}
	return cover_map.points[cover_i]

## From behind cover: keep in cover a while, then shoot, move, throw, or push.
func _decide_from_cover(dist: float, player_reloading: bool) -> void:
	_cycles += 1
	var cv := _cover()
	if cv.is_empty() or not CoverMapScript.hides(cv, target.global_position):
		# The player has moved round it: find another.
		if _choose_cover(false, 0.0):
			return
	if player_reloading and aggression > 0.45 and roster(get_tree()).size() >= 2 and randf() < 0.65 and dist > 9.0:
		bark("mock_reload")
		if _choose_cover(false, 7.0):
			mode = Mode.PUSH
			return
	if role == "flank" and _cycles >= 2 and is_instance_valid(buddy) and randf() < 0.7:
		role = "support"
		bark("flank")
		if _choose_cover(true, 0.0):
			mode = Mode.FLANK
			return
	if _can_throw(dist):
		_begin_throw(dist)
		return
	# Shoot from the cover point, standing or leaning out.
	_lean_pos = _fire_spot(cv) if not cv.is_empty() else Vector3.INF
	if _lean_pos == Vector3.INF and not cv.is_empty():
		if _choose_cover(false, 0.0):
			return
	mode = Mode.PEEK
	_peeks_left = 1 + (1 if randf() < aggression else 0)
	_mode_t = randf_range(1.6, 3.2)
	_burst_left = 0
	_burst_rest = randf_range(0.0, 0.25)
	_exposure = maxf(_exposure * 0.5, 0.0)

func _peek(delta: float, dist: float) -> void:
	var dest := global_position
	if _lean_pos != Vector3.INF:
		dest = _lean_pos
	var to_dest := Vector3(dest.x - global_position.x, 0.0, dest.z - global_position.z)
	if to_dest.length() > 0.12:
		_want = to_dest.normalized()
		_pace_now = 2.6
	_face_to(_aim_point(), delta)
	if _mode_t <= 0.0 or (_burst_left <= 0 and _peeks_left <= 0 and _burst_rest <= 0.0):
		_back_to_cover()
	elif mag <= 0:
		_back_to_cover()

func _back_to_cover() -> void:
	var cv := _cover()
	mode = Mode.COVER
	_lean_pos = Vector3.INF
	_mode_t = randf_range(0.9, 2.4) * (1.5 - aggression)
	_burst_left = 0
	if not cv.is_empty():
		_goal = cv["pos"]

func _arrive() -> void:
	_goal = Vector3.INF
	if cover_i >= 0:
		mode = Mode.COVER
		_mode_t = randf_range(0.2, 1.2)
		_cycles = 0
	else:
		mode = Mode.PEEK
		_mode_t = 4.0
		_peeks_left = 3
		_lean_pos = Vector3.INF

## Picks a cover spot and sets off for it. `flank`: one that sees the player from the other side of the buddy;
## `closer`: at least that many metres nearer the player than now (a push). False if none is found.
func _choose_cover(flank: bool, closer: float) -> bool:
	if cover_map == null or cover_map.points.is_empty():
		return false
	var me := global_position
	var pl := target.global_position
	var d_now := _flat_dist(pl)
	var radius := 30.0
	var options := cover_map.candidates(pl, radius, pl, me, 8, 7.0, cover_ok)
	var best := -1
	var best_score := -INF
	var map := get_world_3d().navigation_map
	var checked := 0
	for i in options:
		var p: Dictionary = cover_map.points[i]
		var pos: Vector3 = p["pos"]
		var dp := Vector2(pos.x - pl.x, pos.z - pl.z).length()
		if closer > 0.0 and dp > d_now - closer:
			continue
		if dp < 8.0 or dp > 34.0:
			continue
		var score := -me.distance_to(pos) * 0.35 + randf() * 3.0
		score += 2.0 if p["high"] else 0.0
		if flank and is_instance_valid(buddy):
			var bp := (buddy as Node3D).global_position
			var a1 := Vector2(pos.x - pl.x, pos.z - pl.z).angle_to(Vector2(bp.x - pl.x, bp.z - pl.z))
			if absf(a1) < deg_to_rad(55.0):
				continue
			score += absf(a1) * 3.0
		if score > best_score:
			# Only a spot with a way to it counts (the path query is the dear part: the leader only).
			if checked < 5:
				checked += 1
				if not cover_map.reachable(map, me, i):
					continue
			best_score = score
			best = i
	if best < 0:
		return false
	_take_cover(best)
	return true

## A cover point is worth having only if it hides you from the player and you can shoot them from it: some
## fire position (standing over low cover, leaning out either side of high) has a clear line to their head.
func cover_ok(i: int) -> bool:
	if cover_map == null or i < 0 or i >= cover_map.points.size():
		return false
	var cv: Dictionary = cover_map.points[i]
	if not CoverMapScript.hides(cv, target.global_position):
		return false
	return _fire_spot(cv) != Vector3.INF

## Where to shoot from at a cover point: standing over low cover, else leaning out to a side (0.9 m, then 1.5 m)
## that has a clear line to the player's head. INF if there is none.
func _fire_spot(cv: Dictionary) -> Vector3:
	var head := _player_head()
	var pos: Vector3 = cv["pos"]
	if not cv["high"] and not _wall_between(pos + Vector3(0, HEIGHT_STAND, 0), head):
		return pos
	var d: Vector3 = cv["dir"]
	var side := Vector3(-d.z, 0.0, d.x)
	for lean in [0.9, 1.5]:
		for sgn in [1.0, -1.0]:
			var p: Vector3 = pos + side * float(lean) * float(sgn)
			if not _wall_between(p + Vector3(0, HEIGHT_STAND, 0), head) and _on_ground(p):
				return p
	return Vector3.INF

## Whether a spot is somewhere to stand (not inside the thing it hides behind).
func _on_ground(p: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	var c := NavigationServer3D.map_get_closest_point(map, p)
	return Vector2(c.x - p.x, c.z - p.z).length() < 0.6

func _take_cover(i: int) -> void:
	if cover_map != null and cover_i >= 0:
		cover_map.release(get_instance_id())
	cover_i = i
	cover_map.claim(i, get_instance_id())
	_goal = cover_map.points[i]["pos"]
	_path = PackedVector3Array()
	_path_i = 0
	_repath_in = 0.0
	mode = Mode.ADVANCE
	_mode_t = 0.0
	crouched = false

func _begin_retreat() -> void:
	bark("retreat", true)
	if cover_map != null:
		var pl := target.global_position
		var options := cover_map.candidates(global_position, 45.0, pl, global_position, 14, 20.0)
		for i in options:
			var pos: Vector3 = cover_map.points[i]["pos"]
			if Vector2(pos.x - pl.x, pos.z - pl.z).length() > _flat_dist(pl) + 8.0:
				_take_cover(i)
				mode = Mode.RETREAT
				_mode_t = randf_range(4.5, 7.0)
				return
	mode = Mode.COVER
	_mode_t = 4.0

func _begin_reload() -> void:
	_reload_t = float(gun["reload"])
	_burst_left = 0
	_busy_t = _reload_t
	anim.play_once("g_reload", 1.7 / _reload_t if _reload_t > 0.1 else 1.0)
	bark("reload")

# -- Downed --

func _go_down(dir: Vector3) -> void:
	downed = true
	mode = Mode.HOLD
	crouched = false
	_burst_left = 0
	_reload_t = 0.0
	_bleed_t = randf_range(BLEED_TIME.x, BLEED_TIME.y)
	if cover_map != null:
		cover_map.release(get_instance_id())
	if _gun_node != null:
		_gun_node.visible = false
	if _grip != null:
		_grip.weight = 0.0
	set_legless(true)
	_busy_t = 0.0
	_stagger = 0.0
	bark("begging", true)
	var fx := get_tree().get_first_node_in_group("gang_fx")
	if fx != null and fx.has_method("_play_at"):
		fx._play_at(global_position, "kill_thump", -6.0, 0.9)

func _crawl(delta: float) -> void:
	_bleed_t -= delta
	_bark_cd = maxf(_bark_cd - 0.0, 0.0)
	if _bleed_t <= 0.0:
		bled_out = true
		take_hit("torso", 99999.0, Vector3.DOWN)
		return
	var away := Vector3(global_position.x - target.global_position.x, 0, global_position.z - target.global_position.z)
	if away.length() > 0.1 and _flat_dist(target.global_position) < 30.0:
		_want = away.normalized()
		_pace_now = 0.55
	if _frame % 150 == 0 and randf() < 0.6:
		bark("begging", true)

var bled_out := false

# -- Moving --

var _pace_now := PACE_JOG

func _walk_to_goal(delta: float, pace: float) -> void:
	if _goal == Vector3.INF:
		return
	_repath_in -= delta
	if _repath_in <= 0.0 or _path.is_empty():
		_repath_in = randf_range(0.8, 1.6)
		var map := get_world_3d().navigation_map
		_path = NavigationServer3D.map_get_path(map, global_position, _goal, true)
		_path_i = 1 if _path.size() > 1 else 0
	var dir := _follow_path(Vector3(_goal.x - global_position.x, 0.0, _goal.z - global_position.z).normalized())
	_want = dir
	_pace_now = pace

func _face_to(p: Vector3, delta: float) -> void:
	var d := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
	if d.length() > 0.05:
		_facing = lerp_angle(_facing, atan2(d.x, d.z), clampf(9.0 * delta, 0.0, 1.0))
		_model_root.rotation.y = _facing

## Where the shot is meant to go: the player when seen, where they were last seen otherwise.
func _aim_point() -> Vector3:
	if _los:
		return _player_chest()
	if _last_seen != Vector3.INF and _last_seen_t < 4.0:
		return _last_seen
	return target.global_position

func _locomote(delta: float) -> void:
	var v := Vector3.ZERO
	var firing := (_burst_left > 0 or mode == Mode.PEEK or _throw_t >= 0.0) and state == State.CHASE
	if _want.length() > 0.01 and state == State.CHASE and _stagger <= 0.0 and _busy_t <= 0.0:
		var pace := _pace_now if mode != Mode.COVER else CROUCH_PACE
		if downed:
			pace = 0.55
		if crouched and mode != Mode.PEEK:
			pace = minf(pace, CROUCH_PACE)
		if _slow > 0.0:
			pace *= 0.5
		v = _want * pace
		if firing and mode == Mode.PEEK:
			_face_to(_aim_point(), delta)
		elif (mode == Mode.PUSH or mode == Mode.ADVANCE) and _los and _burst_left > 0:
			_face_to(_aim_point(), delta)
		else:
			_face(_want, delta)
	elif state == State.CHASE and (mode == Mode.COVER or mode == Mode.THROW):
		if _los or _last_seen_t < 3.0:
			_face_to(_aim_point(), delta)
	# A little separation from the others.
	if state == State.CHASE:
		v += _sep() * 1.2
	velocity.x = move_toward(velocity.x, v.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, v.z, 16.0 * delta)
	velocity.y = 0.0
	if _knock.length_squared() > 0.0001:
		velocity += _knock
		_knock = _knock.move_toward(Vector3.ZERO, 11.0 * delta)
	move_and_slide()
	_animate()

func _sep() -> Vector3:
	var push := Vector3.ZERO
	for o in roster(get_tree()):
		if o == self or not is_instance_valid(o):
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.9 and l > 0.001:
			push += d / l * (0.9 - l) * 3.0
	return push

func _animate() -> void:
	if state != State.CHASE or _busy_t > 0.0 or _stagger > 0.0:
		return
	var moved := Vector2(velocity.x, velocity.z).length()
	if downed:
		anim.play("z_crawl", clampf(moved / 0.6, 0.3, 1.2) if moved > 0.05 else 0.25)
		return
	var clip := "ga_stand"
	var rate := 1.0
	if moved > 0.4:
		if crouched or moved < 1.2 and mode == Mode.COVER:
			clip = "ga_crouch_walk"
		elif moved < 2.4:
			clip = "ga_walk"
		elif moved > 3.5:
			clip = "ga_sprint"
		else:
			clip = "ga_jog"
		rate = anim.stride_rate(clip, moved)
	elif crouched:
		clip = "ga_crouch"
	if clip != _clip:
		_clip = clip
	anim.play(clip, rate)

# -- Shooting --

## The chance a round that is meant to hit does. Fair: low when it first sees you, rising over AIM_UP seconds of
## exposure, lower while you sprint or slide, and with distance.
func hit_chance() -> float:
	var t := clampf(_exposure / AIM_UP, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var p := lerpf(0.03, skill, t)
	var speed_p := 0.0
	if target is CharacterBody3D:
		var vel := (target as CharacterBody3D).velocity
		speed_p = Vector2(vel.x, vel.z).length()
	p *= 1.0 - clampf((speed_p - 1.5) / 5.0, 0.0, 1.0) * 0.55
	var player := target
	if player != null and player.has_method("is_sliding") and player.is_sliding():
		p *= 0.6
	var d := _flat_dist(target.global_position)
	p *= clampf(1.3 - d / 70.0, 0.25, 1.0)
	if mode != Mode.PEEK and mode != Mode.COVER:
		p *= 0.6
	if _wounded_flinch > 0.0:
		p *= 0.55
	last_hit_chance = p
	return p

## How far wide of the player a miss goes (m).
func miss_radius() -> float:
	var t := clampf(_exposure / AIM_UP, 0.0, 1.0)
	return lerpf(MISS_FAR, MISS_NEAR, t)

func _fire_tick(delta: float) -> void:
	if downed:
		return
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			mag = int(gun["mag"])
		return
	var can := false
	match mode:
		Mode.PEEK:
			can = true
		Mode.ADVANCE, Mode.PUSH, Mode.FLANK:
			can = _los and _flat_dist(target.global_position) < 26.0 and mode != Mode.ADVANCE
		_:
			can = false
	if not can or (not _los and _last_seen_t > 2.5):
		_burst_left = 0
		if not _los:
			_exposure = maxf(_exposure - delta * 0.6, 0.0)
		return
	if _los:
		_exposure += delta
	else:
		_exposure = maxf(_exposure - delta * 0.4, 0.0)
	if _react_t > 0.0:
		_react_t -= delta
		return
	if _burst_left <= 0:
		_burst_rest -= delta
		if _burst_rest <= 0.0 and _peeks_left > 0 and _fire_cd <= 0.0:
			var b: Array = gun["burst"]
			_burst_left = randi_range(int(b[0]), int(b[1]))
			_peeks_left -= 1 if mode == Mode.PEEK else 0
		else:
			return
	if _fire_cd <= 0.0 and _burst_left > 0:
		if mag <= 0:
			_begin_reload()
			return
		_shoot()
		_burst_left -= 1
		mag -= 1
		var r: float = gun["rate"]
		_fire_cd = 1.0 / r * randf_range(0.9, 1.15)
		if _burst_left <= 0:
			_burst_rest = randf_range(0.5, 1.1) / (0.6 + aggression)
			if mode == Mode.PEEK and _peeks_left <= 0:
				_mode_t = minf(_mode_t, 0.35)

func muzzle_pos() -> Vector3:
	if _gun_node != null and is_instance_valid(_gun_node) and _gun_node.is_inside_tree():
		return _gun_node.to_global(_muzzle_local)
	return eye() + Vector3(0, -0.2, 0) + Vector3(sin(_facing), 0, cos(_facing)) * 0.5

## One round (or a shotgun's pellets): rolled against hit_chance(), the world checked on the way, a tracer
## drawn either way, the player hurt or the round cracked past them.
func _shoot() -> void:
	var muzzle := muzzle_pos()
	var aim := _aim_point()
	var p := hit_chance() if _los else 0.0
	var pellets := int(gun["pellets"])
	var dist := muzzle.distance_to(aim)
	var dmg_each := _damage_at(dist)
	var total := 0.0
	var any_hit := false
	var fx := GangFX.of(self)
	var shown := 0
	for pe in pellets:
		var hit := _los and randf() < p * (0.75 if pellets > 1 else 1.0)
		var end := aim
		if hit:
			end = aim + Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.25), randf_range(-0.12, 0.12))
		else:
			var side := (aim - muzzle).cross(Vector3.UP).normalized()
			var ang := randf() * TAU
			var rad := miss_radius() * randf_range(0.7, 1.3)
			if pellets > 1:
				rad = randf_range(0.4, 2.2)
			end = aim + side * cos(ang) * rad + Vector3.UP * sin(ang) * rad * 0.7
			if not _los:
				end = aim + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.2), randf_range(-1.5, 1.5))
		var dir := (end - muzzle).normalized()
		var far := muzzle + dir * float(gun["reach"]) * 1.5
		var q := PhysicsRayQueryParameters3D.create(muzzle, far)
		q.collision_mask = 1
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		var stop := far
		var blocked := false
		if not r.is_empty():
			stop = r.position
			blocked = true
			if hit and muzzle.distance_to(r.position) < muzzle.distance_to(end) - 2.0:
				hit = false
		if hit:
			total += dmg_each
			any_hit = true
			stop = end
		else:
			if fx != null:
				var near := _closest_on_segment(muzzle, stop, _player_head())
				if near.distance_to(_player_head()) < 3.6 and (stop - muzzle).dot(_player_head() - muzzle) > 0.0:
					fx.snap(muzzle, near)
			if blocked and fx != null and not hit:
				fx.world_hit(stop, r.normal)
		if fx != null and (shown < 3):
			fx.tracer(muzzle, stop, 1.0 if pe == 0 else 0.6)
			shown += 1
	if fx != null:
		fx.muzzle_flash(muzzle, (aim - muzzle).normalized())
		fx.shot_sound(muzzle, gun_id)
	shots_fired += 1
	_recoil()
	if any_hit and total > 0.0:
		hits_landed += 1
		_deal(total, muzzle)
	fired.emit(self, muzzle, any_hit)

func _deal(dmg: float, from: Vector3) -> void:
	if target.has_method("take_gun_hit"):
		target.take_gun_hit(dmg, from, self)
	else:
		ZombieMode.player_hit(dmg, from)

## Damage of one round at `dist` metres: full to a third of the gun's reach, falling to a quarter at the reach.
func _damage_at(dist: float) -> float:
	var reach: float = gun["reach"]
	var k := clampf((dist - reach * 0.33) / (reach * 0.67), 0.0, 1.0)
	return float(gun["dmg"]) * lerpf(1.0, 0.25, k)

static func _closest_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)

func _recoil() -> void:
	if _skeleton == null:
		return
	var f := _ensure_flinch()
	var right := _skeleton.global_transform.basis.orthonormalized().inverse() * Vector3(cos(_facing), 0, -sin(_facing))
	f.kick(_skeleton.find_bone("Bip01 Spine1"), right, deg_to_rad(-2.2), 0.18)
	f.kick(_skeleton.find_bone("Bip01 R UpperArm"), right, deg_to_rad(-3.5), 0.15)

func _ensure_flinch() -> SkeletonModifier3D:
	if _flinch == null:
		_flinch = preload("res://npc/ZombieFlinch.gd").new()
		_skeleton.add_child(_flinch)
		if _grip != null:
			_skeleton.move_child(_grip, -1)
	return _flinch

# -- Grenades and bottles --

func _can_throw(dist: float) -> bool:
	if wave < 3 or retreated or boss or dist < 9.0 or dist > 24.0:
		return false
	if Time.get_ticks_msec() * 0.001 < next_throw:
		return false
	return randf() < 0.14 * (0.5 + aggression)

func _begin_throw(_dist: float) -> void:
	mode = Mode.THROW
	crouched = false
	_throw_kind = "molotov" if randf() < 0.65 else "frag"
	_throw_goal = target.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	_throw_t = 0.0
	_busy_t = 1.4
	anim.play_once("g_throw", 1.0)
	bark("throw", true)
	next_throw = Time.get_ticks_msec() * 0.001 + 14.0

func _throw_tick(delta: float) -> void:
	_face_to(_throw_goal, delta)
	_throw_t += delta
	if _throw_t >= 0.7 and _throw_goal != Vector3.INF:
		var fx := GangFX.of(self)
		if fx != null:
			fx.throw_thing(_throw_kind, global_position + Vector3(0, 1.7, 0), _throw_goal, self)
		_throw_goal = Vector3.INF
	if _throw_t >= 1.4:
		_throw_t = -1.0
		mode = Mode.COVER
		_mode_t = randf_range(1.0, 2.0)

# -- Taking hits --

func take_hit(part: String, dmg: float, dir: Vector3, weapon: Resource = null, melee := false, at := Vector3.INF) -> void:
	if state >= State.DYING:
		return
	# A vest soaks the body and limbs (not the head or neck) until it is spent.
	if vest_hp > 0.0 and part != "head" and part != "neck":
		var soak := minf(vest_hp, dmg * 0.7)
		vest_hp -= soak
		dmg -= soak
	if part.contains("arm"):
		_wounded_flinch = 1.2
	super.take_hit(part, dmg, dir, weapon, melee, at)
	if _grip != null and _flinch != null and _skeleton != null and _skeleton.get_child(-1) != _grip:
		_skeleton.move_child(_grip, -1)
	if state < State.DYING and not downed and not boss and part != "head" and part != "neck" and health < max_health * 0.2 and randf() < 0.55:
		_go_down(dir)
		return
	if state < State.DYING:
		_burst_left = 0 if randf() < 0.6 else _burst_left
		if mode == Mode.PEEK and randf() < 0.55:
			_back_to_cover()
		if randf() < 0.3:
			bark("hit")

func _react(part: String, dmg: float) -> void:
	if downed:
		return
	if dmg < max_health * 0.1 or state == State.KNEEL or state == State.STANDUP:
		return
	if part.contains("leg") and not legless and not boss:
		_begin_kneel()
		return
	var clip := "g_hit_head" if (part == "head" or part == "neck") else "g_hit_chest"
	if dmg >= max_health * 0.3 and not boss:
		clip = "g_hit_knock"
	_stagger = 0.4 if clip != "g_hit_knock" else 0.8
	_busy_t = _stagger
	anim.play_once(clip, 1.0)
	_burst_left = 0
	_fire_cd = maxf(_fire_cd, 0.35)

func _die(part: String, melee: bool, dir: Vector3) -> void:
	if downed:
		finished_by_player = not bled_out
		var gm := get_node_or_null("/root/GhettoMode")
		if gm != null:
			gm.enemy_downed_resolved.emit(self, finished_by_player)
		if finished_by_player and melee:
			ZombieMode.add_points(FINISH_BONUS, "finisher")
	if cover_map != null:
		cover_map.release(get_instance_id())
	remove_from_group("gangsters")
	if _grip != null:
		_grip.weight = 0.0
	if buddy != null and is_instance_valid(buddy) and buddy.has_method("bark"):
		buddy.bark("ally_down")
	super._die(part, melee, dir)

func _begin_kneel() -> void:
	crouched = false
	_burst_left = 0
	super._begin_kneel()

## Spawner hook: a stuck one is put back; forget the route.
func relocated() -> void:
	super.relocated()
	_goal = Vector3.INF
	if cover_map != null and not cover_map.points.is_empty():
		_choose_cover(false, 0.0)

func _exit_tree() -> void:
	if cover_map != null:
		cover_map.release(get_instance_id())
	super._exit_tree()

## Called after it is in the tree: nothing to do yet (a hook for barks on arrival).
func bark_ready() -> void:
	pass

## The last few of a wave break cover and charge, as in COD.
func rush() -> void:
	if mode == Mode.RETREAT or mode == Mode.THROW:
		return
	aggression = 1.0
	if mode == Mode.COVER and _choose_cover(false, 6.0):
		mode = Mode.PUSH

## A man on a car's running board: shoots from the open for a few seconds while it passes, no cover.
func drive_by() -> void:
	_drive_by = true
	bark("spot", true)
	mode = Mode.PEEK
	_mode_t = 6.0
	_peeks_left = 4
	_lean_pos = Vector3.INF

## For the tests: sends it to cover i now.
func go_to_cover(i: int) -> void:
	_take_cover(i)

func is_in_cover() -> bool:
	return mode == Mode.COVER and crouched and cover_i >= 0

func is_armed() -> bool:
	return _gun_node != null
