extends Node3D
## A grenade or a bottle of fire thrown by a crew (fx/GangFX.gd throws it). It flies a high arc to the spot the
## thrower picked, and from the moment it leaves the hand a ring on the ground shows how far it will reach, so you
## can read it and run; a grenade then lies there with the ring shrinking to its fuse ("cooking"), a bottle bursts
## on landing and leaves a pool of fire.

const RADIUS := {"frag": 4.5, "molotov": 3.2}
const FUSE := 1.5
const FIRE_TIME := 4.5
const FLIGHT_SPEED := 13.0
const FRAG_DAMAGE := 75.0
const FIRE_DPS := 14.0

var kind := "frag"
var thrower: Node
var landing := Vector3.ZERO
var phase := "flight"
var _from := Vector3.ZERO
var _t := 0.0
var _dur := 1.0
var _ring: MeshInstance3D
var _body: MeshInstance3D
var _light: OmniLight3D
var _fire_t := 0.0
var _hurt_cd := 0.0
## For the tests.
var exploded := false
var damage_dealt := 0.0

func radius() -> float:
	return float(RADIUS[kind])

func launch(from: Vector3, to: Vector3, who: Node) -> void:
	thrower = who
	_from = from
	landing = Vector3(to.x, 0.02, to.z)
	_dur = maxf(from.distance_to(landing) / FLIGHT_SPEED, 0.8)
	global_position = from
	_body = MeshInstance3D.new()
	var m: Mesh = SphereMesh.new() if kind == "frag" else CylinderMesh.new()
	if kind == "frag":
		(m as SphereMesh).radius = 0.05
		(m as SphereMesh).height = 0.1
	else:
		(m as CylinderMesh).top_radius = 0.035
		(m as CylinderMesh).bottom_radius = 0.045
		(m as CylinderMesh).height = 0.26
	_body.mesh = m
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.28, 0.14) if kind == "frag" else Color(0.35, 0.5, 0.25, 0.85)
	bm.emission_enabled = kind == "molotov"
	bm.emission = Color(1.0, 0.45, 0.1)
	bm.emission_energy_multiplier = 1.5
	_body.material_override = bm
	add_child(_body)
	# The ring on the ground: where it will reach.
	_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius()
	disc.bottom_radius = radius()
	disc.height = 0.02
	disc.radial_segments = 40
	_ring.mesh = disc
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.3, 0.1, 0.22)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.25, 0.05)
	rm.emission_energy_multiplier = 0.6
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.top_level = true
	_ring.global_position = landing

func _process(delta: float) -> void:
	match phase:
		"flight":
			_t += delta
			var u := clampf(_t / _dur, 0.0, 1.0)
			var p := _from.lerp(landing, u)
			p.y += sin(u * PI) * (2.0 + _from.distance_to(landing) * 0.12)
			global_position = p
			_body.rotate_x(delta * 14.0)
			_pulse(0.18 + 0.08 * sin(_t * 18.0))
			if u >= 1.0:
				_land()
		"fuse":
			_t += delta
			var u := clampf(_t / FUSE, 0.0, 1.0)
			_pulse(0.18 + 0.3 * u * (0.5 + 0.5 * sin(_t * (10.0 + 20.0 * u))))
			if u >= 1.0:
				_explode()
		"fire":
			_fire_t -= delta
			_hurt_cd -= delta
			if _light:
				_light.light_energy = randf_range(1.4, 2.6)
			if _hurt_cd <= 0.0:
				_hurt_cd = 0.25
				_burn_check(0.25)
			if _fire_t <= 0.0:
				queue_free()

func _pulse(a: float) -> void:
	var m := _ring.material_override as StandardMaterial3D
	m.albedo_color.a = a

func _land() -> void:
	global_position = landing + Vector3(0, 0.05, 0)
	_t = 0.0
	if kind == "frag":
		phase = "fuse"
		SFX.play("blip", -14.0, 0.6)
	else:
		var fx := get_tree().get_first_node_in_group("gang_fx")
		if fx != null and fx.has_method("_play_at"):
			fx._play_at(landing, "glass_smash", 0.0, randf_range(0.95, 1.05))
			fx._play_at(landing, "fire_whoosh", -2.0, 1.0)
		_body.visible = false
		phase = "fire"
		_fire_t = FIRE_TIME
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.omni_range = radius() * 2.2
		_light.shadow_enabled = false
		add_child(_light)
		_light.position.y = 0.8
		_flames()
		_pulse(0.3)

func _flames() -> void:
	var flames := GPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.9
	flames.local_coords = false
	flames.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 5, 10))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius() * 0.8
	flames.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.9)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	fm.vertex_color_use_as_albedo = true
	quad.material = fm
	flames.draw_pass_1 = quad
	add_child(flames)
	flames.position.y = 0.2

func _explode() -> void:
	exploded = true
	var fx := get_tree().get_first_node_in_group("gang_fx")
	if fx != null and fx.has_method("_play_at"):
		fx._play_at(landing, "grenade_boom", 2.0, randf_range(0.95, 1.05))
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.4)
	flash.light_energy = 8.0
	flash.omni_range = 14.0
	add_child(flash)
	flash.position.y = 1.0
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(flash):
			flash.queue_free())
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var d := Vector2(player.global_position.x - landing.x, player.global_position.z - landing.z).length()
		if d < radius():
			var dmg := FRAG_DAMAGE * (1.0 - d / radius() * 0.8)
			var from := landing + Vector3(0, 0.5, 0)
			var q := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0, 1.0, 0))
			q.collision_mask = 1
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				dmg *= 0.35
			damage_dealt += dmg
			ZombieMode.player_hit(dmg, landing)
		var holder := get_tree().get_first_node_in_group("weapon_holder")
		if holder != null and holder.get("feel") != null:
			holder.feel.add_trauma(clampf(1.0 - d / 18.0, 0.0, 1.0) * 0.7)
	# Hurts the dead too: whatever of the crews' enemies is in it.
	for z in get_tree().get_nodes_in_group("gangsters"):
		pass
	_body.visible = false
	_ring.visible = false
	get_tree().create_timer(0.5).timeout.connect(queue_free)
	phase = "done"

func _burn_check(dt: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var d := Vector2(player.global_position.x - landing.x, player.global_position.z - landing.z).length()
	if d < radius():
		damage_dealt += FIRE_DPS * dt
		ZombieMode.player_hit(FIRE_DPS * dt, landing)
