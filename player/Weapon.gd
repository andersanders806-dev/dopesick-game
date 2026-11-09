extends Node3D
## The player's rifle: a worn, wood-furnished street AK, full-auto by default.
##
## Hitscan from the centre of the screen with a spread cone that blooms
## while you hold the trigger, climbs with recoil the player has to pull
## down against, and tightens right up when aiming down the sights. The
## viewmodel is built from primitives in _build_model(), like the rest of the
## project's generated art, and all its motion (sway, bob, kick, sprint pose,
## reload, pulling back off a wall) is procedural in _process().
##
## Lives under the player's Camera3D; talks to the player through a handful
## of methods (can_use_weapon, is_sprinting, add_recoil, ...).

const Effects := preload("res://fx/Effects.gd")

## Two guns, switched with "weapon_switch" (Tab / D-pad left). Everything
## that used to be a flat const for "the AK" is now read off PROFILES[_profile]
## instead, so _apply_profile() can swap the whole feel -- fire rate, damage,
## reload, hip spread, and the viewmodel fit -- in one place. Model fit
## numbers (pos/rot/scale) are measured via mesh.get_aabb() the same way the
## AK's are (see the long comment below); eyeballing the raw scale is what
## put earlier attempts inside the mesh.
const PROFILES := [
	{
		"name": "AK", "rpm": 650.0, "damage": 34.0, "falloff_start": 25.0,
		"range": 160.0, "reload_time": 2.1, "spread_hip": 1.6,
		"model": "res://assets/quaternius/weapons/AssaultRifle_4.fbx",
		"gun_pos": Vector3(0, 0, -0.15), "gun_rot": Vector3(0, PI / 2.0, 0),
		"gun_scale": 0.158, "muzzle_local": Vector3(0, 0.01, -0.606),
		"eject_local": Vector3(0.03, 0.03, 0.02),
	},
	{
		# Weaker and shorter-ranged than the AK, but a much faster cyclic
		# rate and a snappier reload -- the panic-button sidearm, not a
		# straight upgrade.
		"name": "PISTOL", "rpm": 900.0, "damage": 20.0, "falloff_start": 14.0,
		"range": 90.0, "reload_time": 1.3, "spread_hip": 2.0,
		"model": "res://assets/quaternius/weapons/Pistol_2.fbx",
		"gun_pos": Vector3(0, 0, -0.05), "gun_rot": Vector3(0, PI / 2.0, 0),
		"gun_scale": 0.11, "muzzle_local": Vector3(0, 0.0185, -0.212),
		"eject_local": Vector3(0.02, 0.02, -0.03),
	},
]

var _profile: int = 0
var RPM: float
var DAMAGE: float
## Damage falls off past this range, down to half at RANGE.
var FALLOFF_START: float
var RANGE: float
var RELOAD_TIME: float
## Bullets hit the world (1), floors (16), and hitboxes (32) -- not the
## player (2) or the police's movement capsule (8), which has its own hitbox.
const RAY_MASK := 1 | 16 | 32

# Spread, in degrees of cone half-angle.
var SPREAD_HIP: float
const SPREAD_MOVING := 2.2
const SPREAD_AIR := 4.0
const SPREAD_ADS := 0.15
const SPREAD_CROUCH_MULT := 0.7
const BLOOM_PER_SHOT := 0.32
const BLOOM_MAX := 3.2
const BLOOM_RECOVERY := 7.0

# Recoil per shot, in degrees.
const RECOIL_PITCH := 0.85
const RECOIL_YAW := 0.32
const RECOIL_ADS_MULT := 0.6

const HIP_POS := Vector3(0.15, -0.165, -0.3)
## The sights' tops sit 0.086 m above the weapon origin, so this puts them
## exactly on the eye line, with the receiver dropping away below.
const ADS_POS := Vector3(0.0, -0.086, -0.24)
const SPRINT_POS := Vector3(0.1, -0.22, -0.26)
const SPRINT_ROT := Vector3(-0.25, 0.75, 0.25)

var player: Node
var camera: Camera3D

## 0 = hip, 1 = fully aimed. Smoothed, and read by the player for FOV.
var ads: float = 0.0
var auto_mode: bool = true
## Holds the sights up regardless of input; for the screenshot tool, since a
## window losing focus releases every held action.
var force_aim: bool = false

var _model: Node3D
var _muzzle: Node3D
var _mag: Node3D
var _eject: Node3D
var _cooldown: float = 0.0
var _bloom: float = 0.0
var _kick: float = 0.0
var _reload_t: float = -1.0
var _sway := Vector2.ZERO
var _bob_t: float = 0.0
var _sprint_w: float = 0.0
var _lower_w: float = 0.0
var _wall_w: float = 0.0
var _trigger_latched: bool = false
var _dry_clicked: bool = false
var _mat_metal: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_poly: StandardMaterial3D
var _mat_glove: StandardMaterial3D
var _mat_sleeve: StandardMaterial3D

func _ready() -> void:
	camera = get_parent() as Camera3D
	_build_model()

func weapon_name() -> String:
	return PROFILES[_profile]["name"]

## Ammo/reserve stay shared across weapons (one pool, not a loadout each) --
## switching mid-reload cancels it, same as a real reload getting interrupted.
func _switch_weapon() -> void:
	_profile = (_profile + 1) % PROFILES.size()
	_reload_t = -1.0
	_bloom = 0.0
	_model.queue_free()
	_build_model()
	SFX.play("dry_fire", -8.0, 0.85)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(weapon_name())

func is_reloading() -> bool:
	return _reload_t >= 0.0

func fire_mode_name() -> String:
	return "AUTO" if auto_mode else "SEMI"

## The current cone half-angle in degrees, for firing and the crosshair.
func current_spread() -> float:
	var base := SPREAD_HIP
	if player:
		var speed: float = player.horizontal_speed()
		base = lerpf(SPREAD_HIP, SPREAD_MOVING, clampf(speed / 4.0, 0.0, 1.0))
		if not player.is_grounded():
			base = SPREAD_AIR
		if player.is_crouching():
			base *= SPREAD_CROUCH_MULT
	return lerpf(base + _bloom, SPREAD_ADS + _bloom * 0.15, ads)

## The mouse drives a little lag in the gun so it feels like it has weight.
func add_sway(rel: Vector2) -> void:
	_sway += rel * 0.00045
	_sway = _sway.limit_length(0.05)

func _can_fire() -> bool:
	return player != null and player.can_use_weapon() and _sprint_w < 0.35 and _lower_w < 0.3

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloom = maxf(0.0, _bloom - BLOOM_RECOVERY * delta * (0.35 if Input.is_action_pressed("fire") else 1.0))

	if is_reloading():
		_reload_t += delta
		if _reload_t >= RELOAD_TIME:
			_reload_t = -1.0
			GameState.reload_mag()
			_mag.position = _mag.get_meta("rest")
			_mag.visible = true
		return

	if not _can_fire():
		_trigger_latched = false
		return

	if Input.is_action_just_pressed("reload"):
		_start_reload()
		return
	if Input.is_action_just_pressed("fire_mode"):
		auto_mode = not auto_mode
		SFX.play("dry_fire", -6.0, 1.4)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("toast"):
			hud.toast("Fire mode: %s" % fire_mode_name())
	if Input.is_action_just_pressed("weapon_switch"):
		_switch_weapon()
		return

	var trigger := Input.is_action_pressed("fire")
	if not trigger:
		_trigger_latched = false
		_dry_clicked = false
		return
	if not auto_mode and _trigger_latched:
		return
	if _cooldown > 0.0:
		return
	if GameState.ammo_mag <= 0:
		if not _dry_clicked:
			_dry_clicked = true
			SFX.play("dry_fire", -2.0)
			if GameState.ammo_reserve > 0:
				_start_reload()
		return
	_trigger_latched = true
	_cooldown = 60.0 / RPM
	_fire()

func _start_reload() -> void:
	if is_reloading() or GameState.ammo_mag >= GameState.MAG_SIZE or GameState.ammo_reserve <= 0:
		return
	_reload_t = 0.0
	SFX.play("reload", -3.0)

func _fire() -> void:
	GameState.use_ammo()
	GameState.report_gunfire()

	# A random direction inside the spread cone, uniform over its area.
	var half := deg_to_rad(current_spread())
	var r := tan(half) * sqrt(randf())
	var theta := randf() * TAU
	var basis := camera.global_basis
	var dir := (basis * Vector3(r * cos(theta), r * sin(theta), -1.0)).normalized()
	var from := camera.global_position
	var to := from + dir * RANGE

	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not hit.is_empty():
		end = hit.position
		var collider: Object = hit.collider
		var dist := from.distance_to(end)
		var dmg := DAMAGE * lerpf(1.0, 0.5, clampf((dist - FALLOFF_START) / (RANGE - FALLOFF_START), 0.0, 1.0))
		if collider and collider.has_method("hit"):
			var result: Dictionary = collider.hit(dmg, end, from)
			Effects.blood(self, end, hit.normal)
			var hud := get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("hitmarker"):
				hud.hitmarker(result.get("killed", false), result.get("headshot", false))
		else:
			Effects.impact(self, end, hit.normal)

	Effects.tracer(self, _muzzle.global_position, end)
	Effects.muzzle_flash(_muzzle)
	SFX.play(["rifle_shot", "rifle_shot_b"].pick_random(), -4.0, randf_range(0.95, 1.05))
	_eject_shell()

	var ads_mult := lerpf(1.0, RECOIL_ADS_MULT, ads)
	var crouch_mult := 0.8 if player.is_crouching() else 1.0
	player.add_recoil(deg_to_rad(RECOIL_PITCH * ads_mult * crouch_mult),
		deg_to_rad(randf_range(-RECOIL_YAW, RECOIL_YAW * 1.3) * ads_mult))
	_bloom = minf(BLOOM_MAX, _bloom + BLOOM_PER_SHOT)
	_kick = 1.0

## A brass casing flicked out of the ejection port.
func _eject_shell() -> void:
	var shell := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.005
	mesh.bottom_radius = 0.006
	mesh.height = 0.035
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.55, 0.2)
	mat.metallic = 0.9
	mat.roughness = 0.3
	mesh.material = mat
	shell.mesh = mesh
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(shell)
	shell.global_transform = _eject.global_transform
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var start := shell.global_position
	var vel := right * randf_range(1.6, 2.4) + up * randf_range(1.2, 1.8) - camera.global_basis.z * randf_range(-0.3, 0.2)
	var tw := shell.create_tween()
	var duration := 0.55
	tw.tween_method(func(t: float):
		shell.global_position = start + vel * t + Vector3(0, -4.9 * t * t, 0)
		shell.rotation += Vector3(0.4, 0.3, 0.5), 0.0, duration, duration)
	tw.tween_callback(func():
		if randf() < 0.5:
			SFX.play("shell", -18.0, randf_range(0.9, 1.2)))
	tw.tween_interval(3.0)
	tw.tween_callback(shell.queue_free)

func _process(delta: float) -> void:
	if player == null:
		return
	var can_act: bool = player.can_use_weapon()
	var sprinting: bool = player.is_sprinting()
	var aiming := can_act and not sprinting and not is_reloading() and (force_aim or Input.is_action_pressed("aim"))
	ads = move_toward(ads, 1.0 if aiming else 0.0, delta * 6.5)
	_sprint_w = move_toward(_sprint_w, 1.0 if sprinting and not is_reloading() else 0.0, delta * 5.0)
	# Put away while talking, grabbing something, or dead.
	_lower_w = move_toward(_lower_w, 0.0 if can_act else 1.0, delta * 4.0)
	_kick = move_toward(_kick, 0.0, delta * 14.0)
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))

	var speed: float = player.horizontal_speed()
	if player.is_grounded() and speed > 0.3:
		_bob_t += delta * speed * 2.1
	var bob_amt := (1.0 - ads * 0.85) * clampf(speed / 4.0, 0.0, 1.4)
	var bob := Vector3(sin(_bob_t) * 0.011, -absf(cos(_bob_t)) * 0.012, 0.0) * bob_amt

	# Pull back off walls you're standing against, instead of clipping through.
	_wall_w = move_toward(_wall_w, _wall_block() * (1.0 - ads), delta * 5.0)

	var ease_ads := ads * ads * (3.0 - 2.0 * ads)
	var pos := HIP_POS.lerp(ADS_POS, ease_ads)
	pos = pos.lerp(SPRINT_POS, _sprint_w)
	pos += bob
	pos += Vector3(-_sway.x, _sway.y, 0.0) * (1.0 - ads * 0.7)
	pos.z += _kick * lerpf(0.045, 0.02, ads)
	pos.y -= _lower_w * 0.35
	pos.z += _wall_w * 0.14
	var rot := SPRINT_ROT * _sprint_w
	rot.x += _kick * lerpf(0.06, 0.015, ads) + _wall_w * 0.7
	rot.y += _sway.x * 2.0
	rot.z += _sway.x * 3.0

	if is_reloading():
		var t := _reload_t / RELOAD_TIME
		var dip := sin(PI * clampf(t * 1.1, 0.0, 1.0))
		rot.z += dip * 0.55
		rot.x += dip * 0.2
		pos.y -= dip * 0.05
		_animate_mag(t)

	position = position.lerp(pos, 1.0 - exp(-22.0 * delta))
	rotation = rotation.lerp(rot, 1.0 - exp(-18.0 * delta))

## Old mag drops out, a fresh one comes up and seats with the click at 50%.
func _animate_mag(t: float) -> void:
	var rest: Vector3 = _mag.get_meta("rest")
	if t < 0.12:
		_mag.position = rest
	elif t < 0.3:
		_mag.position = rest + Vector3(0, -0.35 * (t - 0.12) / 0.18, 0.02)
	elif t < 0.36:
		_mag.visible = false
	elif t < 0.5:
		_mag.visible = true
		_mag.position = rest + Vector3(0, -0.2 * (1.0 - (t - 0.36) / 0.14), 0.01)
	else:
		_mag.position = rest

func _wall_block() -> float:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 0.75, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return clampf(1.0 - from.distance_to(hit.position) / 0.75, 0.0, 1.0)

# --- Viewmodel ----------------------------------------------------------------

func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	m.mesh = mesh
	m.position = pos
	m.rotation_degrees = rot_deg
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

## A cylinder along -Z (the barrel axis).
func _tube(parent: Node3D, radius: float, length: float, center: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.material = mat
	m.mesh = mesh
	m.position = center
	m.rotation_degrees = Vector3(90, 0, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

## A forearm from `a` to `b`.
func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.15
	mesh.height = a.distance_to(b)
	mesh.material = mat
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	var up := (a - b).normalized()
	var helper := Vector3.FORWARD if absf(up.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := helper.cross(up).normalized()
	var z := x.cross(up).normalized()
	m.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)

func _build_model() -> void:
	_mat_metal = _mat(Color(0.075, 0.075, 0.085), 0.85, 0.38)
	_mat_wood = _mat(Color(0.33, 0.15, 0.06), 0.0, 0.5)
	_mat_poly = _mat(Color(0.05, 0.05, 0.05), 0.0, 0.8)
	_mat_glove = _mat(Color(0.07, 0.065, 0.06), 0.0, 0.9)
	_mat_sleeve = _mat(Color(0.09, 0.095, 0.1), 0.0, 0.95)

	var prof: Dictionary = PROFILES[_profile]
	RPM = prof["rpm"]
	DAMAGE = prof["damage"]
	FALLOFF_START = prof["falloff_start"]
	RANGE = prof["range"]
	RELOAD_TIME = prof["reload_time"]
	SPREAD_HIP = prof["spread_hip"]

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var g := _model

	# Real gun mesh (Quaternius, CC0 -- see assets/quaternius/weapons/LICENSE.txt)
	# replaces the old procedurally-boxed receiver/handguard/barrel/stock/grip.
	# Each profile's gun_pos/gun_rot/gun_scale were fitted against this rig's
	# HIP_POS/ADS_POS anchors using mesh.get_aabb() measurements (see PROFILES
	# above), not eyeballed -- change them together if a model is swapped.
	var gun_pos: Vector3 = prof["gun_pos"]
	var gun_scene: PackedScene = load(prof["model"])
	var gun: Node3D = gun_scene.instantiate()
	gun.name = "GunMesh"
	gun.position = gun_pos
	gun.rotation = prof["gun_rot"]
	gun.scale = Vector3.ONE * float(prof["gun_scale"])
	for mesh in gun.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(gun)

	# The real mesh's magazine is baked in and can't detach, but reloading
	# still needs a "rest" anchor to animate without erroring -- kept as an
	# empty node so _animate_mag() no-ops harmlessly instead of crashing.
	_mag = Node3D.new()
	_mag.position = Vector3(0, -0.04, -0.075)
	_mag.set_meta("rest", _mag.position)
	g.add_child(_mag)

	# Gloved hands and sleeves, angled back toward where the shoulders are.
	_box(g, Vector3(0.07, 0.055, 0.1), Vector3(0, -0.02, -0.26), _mat_glove)
	_limb(g, Vector3(-0.025, -0.045, -0.25), Vector3(-0.3, -0.36, 0.02), 0.036, _mat_sleeve)
	_box(g, Vector3(0.055, 0.065, 0.075), Vector3(0.0, -0.08, 0.085), _mat_glove, Vector3(-18, 0, 0))
	_limb(g, Vector3(0.02, -0.1, 0.11), Vector3(0.16, -0.32, 0.4), 0.04, _mat_sleeve)

	_muzzle = Node3D.new()
	_muzzle.position = gun_pos + (prof["muzzle_local"] as Vector3)
	g.add_child(_muzzle)
	_eject = Node3D.new()
	_eject.position = gun_pos + (prof["eject_local"] as Vector3)
	g.add_child(_eject)

	position = HIP_POS
