extends SceneTree
## Dev helper (SHIP 16G phase B): the Mk 2 frag and the shared explosion in Dead Block, in a window, for the eye and the sheet.
## Frames go to .pilot/ship16g/cap/NN_name.png: the throw in the hands (draw, pin out, cook, wind-up, release), the arc and a bounce
## from the side, the blast close (3 m) and far (40 m), a zombie group gibbed, the danger arrow, an RPG blast and a crew grenade.
## Needs a window, under `flock .gpu.lock`, 1280x720, never fullscreen, `--no-sick`:
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed -s res://dev-tools/capture_grenade.gd -- --no-sick
var out := ""
var block: Node
var h: Node
var feel: Node
var p: Node3D
var lethal: Node
var n := 0
var side_cam: Camera3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot/ship16g/cap")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.spawner.enabled = false
	if block.get("surge") != null:
		block.surge.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	gfx.set_first_person(true)
	p = get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	h = p.get_node("WeaponHolder")
	h.no_spread = true
	feel = h.feel
	feel.auto = false
	h.set_process(false)
	lethal = h.lethal
	lethal.set_process(false)
	zm.health = 1000.0
	h.set_grenades(4)
	block.spawner.round_no = 3
	for i in 90:
		await process_frame
	await _hands()
	await _arc()
	await _blasts()
	await _gib()
	await _danger()
	await _rpg()
	await _crew()
	print("DONE ", n, " frames in ", out)
	quit()

func _run(frames: int) -> void:
	for i in frames:
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		lethal.advance(1.0 / 60.0)
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name_])

func _zombies(k: int, at: Vector3, step: Vector3) -> Array:
	var made: Array = []
	for i in k:
		var z = block.spawner.spawn_one("walker", at + step * i)
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = -PI / 2.0
		z.max_health = 400.0
		z.health = 400.0
		made.append(z)
	return made

func _clear() -> void:
	for z in get_nodes_in_group("zombies"):
		z.free()
	for g in lethal.live_grenades():
		g.stop()

func _hands() -> void:
	# Held and cooked: the draw, the pin, the cook, the wind-up, the release.
	h._swap_left = 0.0
	lethal.press()
	await _run(9)
	await _snap("hands_draw")
	await _run(10)
	await _snap("hands_pin_out")
	await _run(40)
	await _snap("hands_cook")
	lethal.release()
	await _run(4)
	await _snap("hands_windup")
	await _run(5)
	await _snap("hands_release")
	await _run(3)
	await _snap("hands_follow_spoon")
	await _run(30)
	_clear()

func _arc() -> void:
	# From the side: the throw and its first bounces.
	side_cam = Camera3D.new()
	current_scene.add_child(side_cam)
	side_cam.global_position = Vector3(-8.0, 1.6, 4.5)
	side_cam.look_at(Vector3(-8.0, 0.6, -3.0))
	side_cam.fov = 60.0
	h._swap_left = 0.0
	lethal.press()
	lethal.release()
	await _run(26)
	side_cam.make_current()
	side_cam.global_position = Vector3(-5.0, 1.2, 2.5)
	side_cam.look_at(Vector3(-5.0, 1.0, -3.0))
	await _run(2)
	await _snap("throw_arc_side")
	var g: Node3D = lethal.live_grenades()[0]
	var shots := 0
	var last_b: int = g.bounces
	for i in 80:
		await _run(1)
		side_cam.global_position = g.global_position + Vector3(-0.3, 0.35, 0.9)
		side_cam.look_at(g.global_position)
		if g.bounces != last_b and shots < 2:
			last_b = g.bounces
			shots += 1
			await _snap("bounce_%d" % g.bounces)
	await _run(40)
	await _snap("rolling_to_rest")
	_clear()
	get_first_node_in_group("player").get("camera").make_current()

func _blasts() -> void:
	var fx: Node3D = load("res://fx/Explosion.gd").of(current_scene)
	var cam: Camera3D = p.get("camera")
	# Close: three metres ahead on the street.
	var close := Vector3(cam.global_position.x + 3.0, 0.05, -3.0)
	fx.detonate(close, Vector3.UP, 1.0)
	h.explode(close, h.grenade_spec())
	for k in [3, 8, 16, 30]:
		await _run(k)
		await _snap("blast_close_3m_f%02d" % k)
	await _run(120)
	# Far: forty metres down the street.
	var far := Vector3(cam.global_position.x + 40.0, 0.05, -3.0)
	fx.detonate(far, Vector3.UP, 1.0)
	for k in [3, 10, 25]:
		await _run(k)
		await _snap("blast_far_40m_f%02d" % k)
	await _run(150)

func _gib() -> void:
	var crowd := _zombies(6, Vector3(-14.0, 0.0, -5.0), Vector3(0.7, 0.0, 0.7))
	var cam: Camera3D = p.get("camera")
	var at := Vector3(-12.4, 0.1, -3.0)
	await _run(10)
	await _snap("group_before")
	load("res://fx/Explosion.gd").of(current_scene).detonate(at, Vector3.UP, 1.0)
	h.explode(at, h.grenade_spec())
	for k in [3, 6, 12, 30]:
		await _run(k)
		await _snap("group_gibbed_f%02d" % k)
	var dead := 0
	for z in crowd:
		if is_instance_valid(z) and not z.is_alive():
			dead += 1
	print("GIB ", dead, " of ", crowd.size(), " down")
	await _run(90)
	_clear()

func _danger() -> void:
	var cam: Camera3D = p.get("camera")
	var g: Node3D = lethal._next_grenade()
	g.launch(cam.global_position + Vector3(1.0, -1.1, 3.5), Vector3.ZERO, 3.0, h, p)
	g.state = "rest"
	await _run(20)
	await _snap("danger_arrow")
	g.stop()

func _rpg() -> void:
	var crowd := _zombies(5, Vector3(-9.0, 0.0, -4.4), Vector3(0.0, 0.0, 0.7))
	var d: Resource = load("res://weapons/rpg.tres")
	feel._raise_seen[d.id] = true
	h.give(d)
	h.refill_all()
	await _run(int(d.swap_time * 60.0) + 24)
	h.fire()
	await _run(14)
	for k in [1, 5, 12, 30]:
		await _run(k)
		await _snap("rpg_blast_f%02d" % k)
	await _run(120)
	_clear()

func _crew() -> void:
	var cam: Camera3D = p.get("camera")
	var gg: Node3D = load("res://fx/GangGrenade.gd").new()
	gg.kind = "frag"
	current_scene.add_child(gg)
	gg.launch(cam.global_position + Vector3(10.0, 1.7, 3.0), cam.global_position + Vector3(7.0, 0, 1.5), null)
	var t := 0
	while not gg.exploded and t < 400:
		await _run(1)
		t += 1
		if t == 60:
			await _snap("crew_grenade_landed_ring")
	for k in [4, 14]:
		await _run(k)
		await _snap("crew_grenade_blast_f%02d" % k)
	await _run(60)
