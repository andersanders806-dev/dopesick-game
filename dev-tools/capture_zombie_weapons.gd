extends SceneTree
## Dev helper: renders Dead Block's purchases and the first-person gun, in a
## window, to res://_caps/zw_*.png.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_zombie_weapons.gd
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
	for i in 20:
		await process_frame
	var out := ProjectSettings.globalize_path("res://_caps")
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.current = true
	cam.fov = 60.0
	var shots := {
		"wall_smg": _wall(block, "smg"), "wall_shotgun": _wall(block, "shotgun"),
		"box": block.mystery_box, "machine": block.upgrade_machine,
	}
	for k in shots:
		var n: Node3D = shots[k]
		var t := n.global_transform
		cam.global_position = t.origin + t.basis.z * 3.0 + Vector3(0, 1.5, 0) + t.basis.x * 0.4
		cam.look_at(t.origin + Vector3(0, 1.2, 0), Vector3.UP)
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/zw_%s.png" % [out, k])
	# The box mid-spin, with a gun floating over it.
	var h := _player().get_node("WeaponHolder")
	zm.points = 5000
	var box = block.mystery_box
	box.try_open(h)
	box.advance(box.SPIN_TIME + 0.1)
	for i in 20:
		await process_frame
	var t2: Transform3D = box.global_transform
	cam.global_position = t2.origin + t2.basis.z * 2.2 + Vector3(0, 1.6, 0)
	cam.look_at(t2.origin + Vector3(0, 1.2, 0), Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zw_box_offer.png" % out)
	# First person: the pistol, then the upgraded SMG.
	cam.queue_free()
	root.get_node("Graphics").set_first_person(true)
	var p := _player()
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	h.give(load("res://weapons/ar.tres"))
	for i in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zw_fp_ar.png" % out)
	h.give(load("res://weapons/smg_up.tres"))
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/zw_fp_smg_up.png" % out)
	quit()

func _wall(block: Node, id: String) -> Node3D:
	for b in block.wall_buys:
		if b.data.id == id:
			return b
	return null

func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D
