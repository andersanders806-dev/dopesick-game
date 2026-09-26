extends RefCounted
## One-shot combat effects: impact sparks, blood, bullet holes, tracers,
## muzzle flashes, and positional gunshots. All static and all built from
## primitives in code, like the rest of the project's generated art -- there
## are no effect textures to import.
##
## Everything is parented to the current scene, so it's cleaned up with the
## room on a door transition.

const MAX_HOLES := 80

static var _spark_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D
static var _dust_mat: StandardMaterial3D
static var _tracer_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D
static var _hole_tex: Texture2D
static var _holes: Array = []

static func _unshaded(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emission > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func _mats() -> void:
	if _spark_mat:
		return
	_spark_mat = _unshaded(Color(1.0, 0.72, 0.3), 6.0)
	_blood_mat = _unshaded(Color(0.35, 0.02, 0.02))
	_blood_mat.roughness = 0.4
	_dust_mat = _unshaded(Color(0.5, 0.47, 0.42, 0.7))
	_tracer_mat = _unshaded(Color(1.0, 0.85, 0.5), 8.0)
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat = _unshaded(Color(1.0, 0.7, 0.3), 10.0)
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.95))
	g.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
	g.add_point(0.35, Color(0.03, 0.03, 0.03, 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_hole_tex = tex

static func _scene(ctx: Node) -> Node:
	var s := ctx.get_tree().current_scene
	return s if s else ctx.get_tree().root

static func _burst(ctx: Node, pos: Vector3, normal: Vector3, mat: Material, amount: int, speed: Vector2, size: float, lifetime: float, gravity := 9.8) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	_scene(ctx).add_child(p)
	p.global_position = pos + normal * 0.02
	_orient_up(p, normal)
	p.emitting = true
	ctx.get_tree().create_timer(lifetime + 0.2).timeout.connect(p.queue_free)

## Points a node's +Y along `normal`.
static func _orient_up(n: Node3D, normal: Vector3) -> void:
	var y := normal.normalized()
	if y.length() < 0.5:
		return
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	n.global_basis = Basis(x, y, z)

## A round hitting the world: sparks, a puff of dust, and a hole that stays.
static func impact(ctx: Node, pos: Vector3, normal: Vector3) -> void:
	_mats()
	_burst(ctx, pos, normal, _spark_mat, 9, Vector2(2.5, 6.0), 0.015, 0.28)
	_burst(ctx, pos, normal, _dust_mat, 6, Vector2(0.4, 1.2), 0.05, 0.6, 1.0)
	bullet_hole(ctx, pos, normal)
	sound_at(ctx, "impact_wall", pos, -8.0, randf_range(0.85, 1.2))

static func blood(ctx: Node, pos: Vector3, normal: Vector3) -> void:
	_mats()
	_burst(ctx, pos, normal, _blood_mat, 14, Vector2(1.0, 3.2), 0.035, 0.5)
	sound_at(ctx, "impact_flesh", pos, -4.0, randf_range(0.9, 1.1))

static func bullet_hole(ctx: Node, pos: Vector3, normal: Vector3) -> void:
	_mats()
	var d := Decal.new()
	d.texture_albedo = _hole_tex
	d.size = Vector3(0.07, 0.08, 0.07)
	d.cull_mask = 1
	_scene(ctx).add_child(d)
	d.global_position = pos
	_orient_up(d, normal)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	_holes.append(d)
	while _holes.size() > MAX_HOLES:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()

## A streak from muzzle to hit that's gone in a couple of frames.
static func tracer(ctx: Node, from: Vector3, to: Vector3) -> void:
	_mats()
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, minf(length, 6.0))
	mesh.material = _tracer_mat
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene(ctx).add_child(m)
	# Starts a little way out of the barrel and travels, so it reads as a round.
	var dir := (to - from) / length
	m.global_position = from + dir * minf(length, 6.0) * 0.5
	m.look_at(m.global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", to - dir * minf(length, 6.0) * 0.5, clampf(length / 300.0, 0.02, 0.12))
	tw.tween_callback(m.queue_free)

## A star-shaped flash plus a light, parented to `muzzle` so it moves with it.
static func muzzle_flash(muzzle: Node3D, scale := 1.0) -> void:
	_mats()
	var root := Node3D.new()
	muzzle.add_child(root)
	for i in 3:
		var q := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.09, 0.22) * scale
		mesh.material = _flash_mat
		q.mesh = mesh
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.rotation = Vector3(PI * 0.5, 0, i * PI / 3.0 + randf() * 0.5)
		q.position = Vector3(0, 0, -0.08 * scale)
		root.add_child(q)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 4.0 * scale
	light.omni_range = 5.0 * scale
	light.shadow_enabled = false
	root.add_child(light)
	root.rotation.z = randf() * TAU
	muzzle.get_tree().create_timer(0.045).timeout.connect(root.queue_free)

## A one-shot positional sound from SFX's table.
static func sound_at(ctx: Node, sfx_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 40.0) -> void:
	if not SFX.SOUNDS.has(sfx_name):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = SFX.SOUNDS[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = max_distance
	_scene(ctx).add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## Loot on the floor: walk over it to take it. Dropped by downed police.
static func drop_pickup(ctx: Node, pos: Vector3, ammo: int, cash: int) -> void:
	var area: Area3D = load("res://items/Pickup3D.gd").new()
	area.ammo = ammo
	area.cash = cash
	_scene(ctx).add_child(area)
	area.global_position = Vector3(pos.x, 0.0, pos.z)
