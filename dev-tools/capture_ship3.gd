extends SceneTree
## Dev helper: first-person frames for the SHIP-3 contact sheet -> <out>/<mode>.png. One mode per run (a window;
## only one windowed Godot at a time).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_ship3.gd -- <out_dir> <mode>
## modes: title, dose (the apartment, a pill taken), zombie (Dead Block, a pistol), gangs (Ghetto Wars, an AR)
var out := ""

func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, label])

func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var mode := args[1]
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gs := root.get_node("GameState")
	match mode:
		"title":
			change_scene_to_file("res://ui/TitleScreen.tscn")
			await _wait(4.0)
			await _snap("title")
		"dose":
			gs.no_sickness = true
			gs.start_run()
			gs.intro_pending = false
			change_scene_to_file("res://world/Apartment3D.tscn")
			await _wait(2.0)
			var p := get_first_node_in_group("player")
			for i in 6:
				if p.dialogue_active:
					get_first_node_in_group("hud").advance_or_close_dialogue()
					await _wait(0.3)
			p.set_look(PI * 0.5, -0.1)
			await _wait(0.5)
			gs.dose_taken.emit("oxy", "relief")
			await _wait(0.9)
			await _snap("dose")
		"zombie":
			root.get_node("ZombieMode").begin()
			change_scene_to_file("res://world/City3D.tscn")
			for i in 40:
				await process_frame
			var block := current_scene.get_node("ZombieBlock")
			while not block.purchases_ready:
				await process_frame
			block.spawner.enabled = false
			for z in get_nodes_in_group("zombies"):
				z.free()
			var p := get_first_node_in_group("player") as Node3D
			var holder := get_first_node_in_group("weapon_holder")
			p.global_position = Vector3(-9.0, 0, 8.0)
			p.set_look(0.0, 0.0)
			holder.give(load("res://weapons/ar.tres"))
			holder.refill_all()
			block.spawner.spawn_entrance("walker", {"type": "rise", "pos": Vector3(-9.0, 0.0, -2.0), "start": Vector3(-9.0, -2.1, -2.0), "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false})
			await _wait(3.0)
			await _snap("zombie")
		"gangs":
			root.get_node("ZombieMode").begin_gangs()
			change_scene_to_file("res://world/City3D.tscn")
			for i in 40:
				await process_frame
			var block := current_scene.get_node("ZombieBlock")
			while not block.purchases_ready or block.cover.points.is_empty():
				await process_frame
			var p := get_first_node_in_group("player") as Node3D
			var holder := get_first_node_in_group("weapon_holder")
			p.global_position = Vector3(-14.0, 0, 1.2)
			p.set_look(-PI / 2.0, 0.0)
			holder.give(load("res://weapons/ar.tres"))
			holder.refill_all()
			await _wait(4.0)
			await _snap("gangs")
	quit()
