extends SceneTree
## Stills of the story's first-person hands in the apartment: idle, sick, reaching,
## carrying, the Walkman, a pill, a shot, the dock box.
##   godot --path . --resolution 1280x720 -s res://dev-tools/shot_story_hands.gd -- <dir>

var out_dir := ""
var n := 0

func _wait(s: float) -> void:
	await create_timer(s).timeout

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	root.get_texture().get_image().save_png("%s/hands_%02d_%s.png" % [out_dir, n, label])

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out_dir = OS.get_cmdline_user_args()[0]
	var gs := root.get_node("GameState")
	root.get_node("Graphics").first_person = true
	gs.mode = "story"
	gs.intro_pending = false
	change_scene_to_file("res://world/Apartment3D.tscn")
	await _wait(2.0)
	var p := get_first_node_in_group("player")
	var h = p.story_hands
	if h == null:
		print("NO HANDS")
		quit(1)
		return
	for i in 6:
		if p.dialogue_active:
			get_first_node_in_group("hud").advance_or_close_dialogue()
			await _wait(0.4)
	for hh in get_nodes_in_group("hud"):
		hh.visible = false
	p.set_look(PI * 0.5, -0.1)
	await _wait(0.3)
	print("CAM ", p.camera.transform, p.get_node("CameraMount").rotation, p._look_pitch, p.fp_dip, p._camera_base, " cur=", root.get_viewport().get_camera_3d() == p.camera, " pos=", p.global_position, " fp=", p._first_person)
	gs.craving = 90.0
	await _wait(1.0)
	await shot("idle_well")
	gs.craving = 12.0
	await _wait(1.2)
	await shot("idle_sick_a")
	await _wait(0.37)
	await shot("idle_sick_b")
	gs.craving = 2.0
	await _wait(0.8)
	await shot("idle_very_sick")
	gs.craving = 80.0
	await _wait(1.0)
	h.reach(p.global_position + Vector3(0, 1.3, -1.0))
	await _wait(0.28)
	await shot("reach")
	await _wait(1.0)
	gs.inventory.append("charger")
	gs.inventory_changed.emit()
	await _wait(1.0)
	await shot("carry_charger")
	gs.inventory.clear()
	gs.inventory_changed.emit()
	root.get_node("Jobs").job = {"kind": "dock", "holding": true}
	await _wait(1.2)
	await shot("box")
	root.get_node("Jobs").job = {}
	await _wait(0.8)
	root.get_node("Walkman").add_tape(root.get_node("Walkman").TAPES.keys()[0])
	root.get_node("Walkman").play(root.get_node("Walkman").TAPES.keys()[0])
	await _wait(0.65)
	await shot("walkman_up")
	await _wait(1.6)
	await shot("walkman_held")
	root.get_node("Walkman").stop()
	await _wait(2.2)
	gs.dose_taken.emit("oxy", "relief")
	await _wait(0.8)
	await shot("pill_mouth")
	await _wait(2.0)
	gs.dose_taken.emit("heroin", "relief")
	await _wait(0.8)
	await shot("shot_down")
	await _wait(2.5)
	await shot("after")
	quit()
