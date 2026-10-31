extends SceneTree
## Dev helper: gore in a window -> .pilot/z4_gore_*.png (wounds, a severed arm, the head pop, a crawler,
## blood on the wall and a heap of dead).  Only one windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_gore.gd
var out := ""
var h: Node
var feel: Node
var p: Node3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	zm.gore_enabled = true
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	root.get_node("Graphics").set_first_person(true)
	p = get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	h = p.get_node("WeaponHolder")
	h.no_spread = true
	feel = h.feel
	feel.auto = false
	h.set_process(false)
	block.spawner.round_no = 3
	var gore: Node3D = load("res://fx/gore/Gore.gd").of(h)
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	var mk := func(x: float, zz: float) -> Node:
		var z = block.spawner.spawn_one("walker", Vector3(x, 0.0, zz))
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = -PI / 2.0
		z.health = 1.0e5
		z.max_health = 250.0
		return z
	var eye := Vector3(-20, 1.62, -3)
	# 1. wounds
	var a: Node = mk.call(-17.0, -3.0)
	await _run(10)
	for part in ["torso", "upper_arm_l", "head"]:
		a.take_hit(part, 40.0, Vector3(1, 0, 0), null, false, Vector3.INF)
	await _run(25)
	await _snap("gore_wounds")
	a.queue_free()
	var w: Node = mk.call(-18.6, -3.0)
	await _run(5)
	for part in ["torso", "torso", "upper_arm_r"]:
		w.take_hit(part, 90.0, Vector3(1, 0, 0), null, false, Vector3.INF)
	await _run(10)
	await _snap("gore_wound_close")
	w.queue_free()
	var a2: Node = mk.call(-17.0, -3.0)
	a = a2
	# 2. a severed arm and leg, gibs in the air then on the ground
	a.queue_free()
	var b: Node = mk.call(-17.0, -3.0)
	await _run(5)
	b.take_hit("lower_arm_l", 150.0, Vector3(1, 0, 0.3), null)
	b.take_hit("upper_arm_r", 150.0, Vector3(1, 0, -0.3), null)
	await _run(14)
	await _snap("gore_arm_air")
	await _run(90)
	await _snap("gore_arm_ground")
	b.queue_free()
	# 3. head pop by a shotgun at close range
	var c: Node = mk.call(-17.5, -3.0)
	c.health = 100.0
	c.target = p
	h.give(load("res://weapons/shotgun.tres"))
	h.refill_all()
	await _run(40)
	h.aim_source = func():
		c.sync_hitboxes()
		var hc: Vector3 = (c.hitboxes["head"].get_child(0) as Node3D).global_position
		return [eye, hc - eye]
	h._cooldown = 0.0
	h.fire()
	await _run(6)
	await _snap("gore_head_pop_a")
	await _run(20)
	await _snap("gore_head_pop_b")
	await _run(80)
	await _snap("gore_head_pop_c")
	h.aim_source = Callable()
	# 4. a crawler
	var d: Node = mk.call(-16.0, -3.4)
	await _run(3)
	d.take_hit("lower_leg_l", 150.0, Vector3(1, 0, 0), null)
	d.take_hit("upper_leg_r", 200.0, Vector3(1, 0, 0), null)
	d.state = d.State.CHASE
	d._anim_player.play("zombie/z_crawl")
	await _run(70)
	d._anim_player.pause()
	await _snap("gore_crawler")
	# 5. blood on the wall and a heap
	h.give(load("res://weapons/smg.tres"))
	h.refill_all()
	for i in 6:
		var z: Node = mk.call(-17.0 + i * 0.6, -2.6 - (i % 3) * 0.4)
		z.health = 100.0
		z.take_hit("torso", 60.0, Vector3(0.5, 0, 0.8), null)
		z.take_hit("lower_leg_r" if i % 2 == 0 else "upper_arm_l", 150.0, Vector3(0.5, 0, 0.8), null)
		z.take_hit("torso", 300.0, Vector3(0.5, 0, 0.8), null)
	await _run(240)
	await _snap("gore_heap")
	print("GORE severs ", gore.severs, " heads ", gore.heads_popped, " decals ", gore.decals_shown(), " gibs ", gore.gibs.shown(), " pools ", gore.pools_shown())
	quit()

func _run(frames: int) -> void:
	for i in frames:
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z4_%s.png" % [out, name_])
