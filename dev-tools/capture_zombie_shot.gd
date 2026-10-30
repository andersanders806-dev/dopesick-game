extends SceneTree
## Dev helper: first person, the pistol fired at a real zombie, rendered in a
## window to res://_caps/zs_*.png (before the shot, and the frames after a head hit and a kill).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_zombie_shot.gd
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	var sp: Node = block.spawner
	sp.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var out := ProjectSettings.globalize_path("res://_caps")
	root.get_node("Graphics").set_first_person(true)
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.02)
	var h := p.get_node("WeaponHolder")
	h.no_spread = true
	sp.round_no = 1
	var z: Node = sp.spawn_one("walker", Vector3(-15.0, 0.0, -3.0))
	z.set_physics_process(false)
	z._model_root.rotation.y = -PI / 2.0
	for i in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zs_before.png" % out)
	# Aim the gun at the head and shoot (camera look follows the zombie's head).
	var cam: Camera3D = p.camera
	await _look_at_head(p, cam, z)
	h.advance(10.0)
	h.fire()
	print("ZS after shot 1: health %.0f/%.0f points %d hit %s" % [z.health, z.max_health, zm.points, z.last_part])
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zs_hit.png" % out)
	await _look_at_head(p, cam, z)
	h.advance(10.0)
	h.fire()
	print("ZS after shot 2: alive %s points %d kills %d heads %d" % [z.is_alive(), zm.points, zm.kills, zm.headshots])
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zs_dead.png" % out)
	quit()

## It flinches from a hit: look at its head where it is now.
func _look_at_head(p: Node3D, cam: Camera3D, z: Node) -> void:
	for i in 3:
		z.sync_hitboxes()
		var head: Vector3 = (z.hitboxes["head"].get_child(0) as Node3D).global_position
		var d := head - cam.global_position
		p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
		for j in 3:
			await process_frame
