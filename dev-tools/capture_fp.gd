extends SceneTree
## Dev helper: Dead Block first person in a window -> .pilot/z4_*.png:
## hip, aimed, firing (muzzle flash), mid-reload, sprint, slide, with a real
## zombie in front. Needs a window; run only when no other windowed Godot runs.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_fp.gd -- [gun ids...]
var out := ""

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	var args: Array = Array(OS.get_cmdline_user_args())
	var specials := ["sprint", "slide", "hit", "scope", "melee", "zombies"]
	var guns: Array = args.filter(func(a): return not specials.has(a))
	if args.is_empty():
		guns = ["pistol", "ar"]
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
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
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	var h: Node = p.get_node("WeaponHolder")
	h.no_spread = true
	var feel: Node = h.feel
	feel.auto = false
	h.set_process(false)
	# Two real zombies down the street.
	block.spawner.round_no = 3
	var zs: Array = []
	for k in 2:
		var z = block.spawner.spawn_one("walker", Vector3(-8.0 + k * 5.0, 0.0, -3.0 + (k * 0.6)))
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = PI / 2.0
		zs.append(z)
	for id in guns:
		h.give(load("res://weapons/%s.tres" % id))
		h.refill_all()
		await _run(h, feel, 40)
		print("DBG vm_rot ", feel.vm_rotation, " vm_pos ", feel.vm_position, " node rot ", h.viewmodel.rotation, " pos ", h.viewmodel.position, " swap ", feel.swap_blend, " sprint ", feel.sprint_blend, " kick ", feel.kick_rot, " sway ", feel._sway)
		if OS.get_environment("NOARMS") != "":
			h.viewmodel.arms.visible = false
		await _snap("%s_hip" % id)
		h.aiming = true
		await _run(h, feel, 40)
		await _snap("%s_ads" % id)
		h.aiming = false
		await _run(h, feel, 40)
		# A shot at the zombie: the flash frame.
		h.fire()
		await _run(h, feel, 1)
		await _snap("%s_fire" % id)
		await _run(h, feel, 60)
		h.reload()
		await _run(h, feel, int(h.reload_left() * 60.0 * 0.4))
		await _snap("%s_reload40" % id)
		await _run(h, feel, int(h.reload_left() * 60.0 * 0.4))
		await _snap("%s_reload70" % id)
		await _run(h, feel, int(h.reload_left() * 60.0) + 10)
	var player := p
	if args.has("zombies"):
		h.give(load("res://weapons/ar.tres"))
		await _run(h, feel, 30)
		zs[0].global_position = Vector3(-14.0, 0.0, -3.0)
		zs[1].global_position = Vector3(-8.0, 0.0, -2.4)
		for z in zs:
			z.sync_hitboxes()
		await _run(h, feel, 20)
		await _snap("zombies_hip")
		h.aiming = true
		await _run(h, feel, 40)
		await _snap("zombies_ads")
		h.aiming = false
		await _run(h, feel, 20)
	if args.has("sprint"):
		h.give(load("res://weapons/ar.tres"))
		await _run(h, feel, 30)
		player.set_physics_process(false)
		player.set("_sprinting", true)
		player.velocity = Vector3(5.0, 0.0, 0.0)
		await _run(h, feel, 30)
		await _snap("sprint")
		player.set_physics_process(true)
		player.set("_sprinting", false)
		player.velocity = Vector3.ZERO
	if args.has("slide"):
		h.give(load("res://weapons/ar.tres"))
		await _run(h, feel, 30)
		player.set_physics_process(false)
		player.set("_sprinting", true)
		player.velocity = Vector3(5.0, 0.0, 0.0)
		feel.try_slide()
		await _run(h, feel, 30)
		print("DBG slide vm_pos ", feel.vm_position, " rot ", feel.vm_rotation, " sliding ", feel.sliding, " blend ", feel._slide_blend, " viewmodel visible ", h.viewmodel.visible)
		await _snap("slide")
		player.set_physics_process(true)
		player.set("_sprinting", false)
		feel.reset_state()
		player.velocity = Vector3.ZERO
	if args.has("hit"):
		h.give(load("res://weapons/pistol.tres"))
		h.refill_all()
		await _run(h, feel, 30)
		h.aim_source = func():
			var z = zs[0]
			z.sync_hitboxes()
			var c: Vector3 = (z.hitboxes["head"].get_child(0) as Node3D).global_position
			var o: Vector3 = p.global_position + Vector3(0, 1.62, 0)
			return [o, c - o]
		h.aiming = true
		await _run(h, feel, 30)
		h.fire()
		await _run(h, feel, 3)
		await _snap("hit_head")
		await _run(h, feel, 30)
		zs[0].health = 5.0
		h.fire()
		await _run(h, feel, 2)
		await _snap("hit_kill")
		h.aim_source = Callable()
		h.aiming = false
	if args.has("scope"):
		h.give(load("res://weapons/sniper.tres"))
		h.refill_all()
		h.aiming = true
		await _run(h, feel, 70)
		await _snap("scope")
		h.aiming = false
		await _run(h, feel, 30)
	if args.has("melee"):
		h.give(load("res://weapons/ar.tres"))
		await _run(h, feel, 30)
		h.melee()
		await _run(h, feel, 6)
		await _snap("melee")
	quit()

func _run(h: Node, feel: Node, frames: int) -> void:
	for i in frames:
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z4_%s.png" % [out, name_])
