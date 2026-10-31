extends SceneTree
## Dev helper: firing at a wall and at zombies -> .pilot/z4_impact_*.png
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_impacts.gd
var out := ""

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
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
	block.spawner.round_no = 3
	var zs: Array = []
	for k in 3:
		var z = block.spawner.spawn_one("walker", Vector3(-15.0 + k * 1.6, 0.0, -3.0 + (k - 1) * 0.5))
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = PI / 2.0
		zs.append(z)
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	await _run(h, feel, 30)
	# Bullets into the wall on the left.
	h.aim_source = func(): return [p.global_position + Vector3(0, 1.62, 0), Vector3(-0.75, -0.15, 0.65).normalized()]
	for i in 6:
		h.fire()
		await _run(h, feel, 5)
		h._cooldown = 0.0
	var fxn := get_first_node_in_group("impact_fx")
	print("FX impacts ", fxn.impacts, " decals ", fxn.decals_shown())
	await _snap("impact_wall")
	# Hit the first zombie in the body, then the head.
	h.aim_source = func():
		var z = zs[0]
		z.sync_hitboxes()
		var c: Vector3 = (z.hitboxes["torso"].get_child(0) as Node3D).global_position
		var o: Vector3 = p.global_position + Vector3(0, 1.62, 0)
		return [o, c - o]
	h.aiming = false
	for i in 3:
		h._cooldown = 0.0
		h.fire()
		await _run(h, feel, 2)
	await _snap("impact_body")
	await _run(h, feel, 40)
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
