extends SceneTree
## Dev helper: Ghetto Wars' set in a window -> .pilot/gw3_*.png (the corner, a burning car, the graffiti,
## an overdosed man, the helicopter's spotlight, a drive-by, THE BUST's lights, the getaway car, pickups).
## With `-- only=name1,name2` only those. One windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_ghetto_set.gd
var out := ""
var cam: Camera3D
var set_: Node3D
var city: Node

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40:
		await process_frame
	city = current_scene
	var block := city.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.spawner.enabled = false
	block.surge.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	for c in root.get_children():
		if c is CanvasLayer and c != root.get_node("SceneLoader"):
			c.visible = false
	for c in city.get_children():
		if c is CanvasLayer:
			c.visible = false
	set_ = city.get_node("GhettoSet")
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-60, 0, 0)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 400.0
	city.add_child(cam)
	cam.make_current()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	var want := func(n: String) -> bool: return only == "" or n in only.split(",")
	await _wait(30)

	set_.set_wave(6)
	if want.call("corner"):
		await _shot("corner", Vector3(7.0, 1.65, -0.6), Vector3(14.0, 1.2, -4.0))
	if want.call("corner_close"):
		await _shot("corner_close", Vector3(12.0, 1.4, -1.0), Vector3(13.6, 0.9, -3.9))
	if want.call("burning"):
		await _shot("burning", Vector3(-8.0, 1.8, 7.0), Vector3(-1.2, 1.3, 3.3))
	if want.call("graffiti"):
		set_.set_wave(9)
		await _wait(80)
		await _shot("graffiti", Vector3(-12.0, 1.7, 0.5), Vector3(-22.0, 1.9, -4.5))
	if want.call("od"):
		await _shot("od", Vector3(-11.8, 1.3, -1.6), Vector3(-9.3, 0.8, -4.1))
	if want.call("od_tainted"):
		set_.set_chapter("TAINTED")
		await _wait(200)
		await _shot("od_tainted", Vector3(-4.0, 1.7, 1.0), Vector3(-9.0, 0.9, -4.1))
	if want.call("pickups"):
		var at := Vector3(10.6, 1.25, -2.2)
		for k in ["pills", "stash", "cash"]:
			set_.spawn_pickup(k, at)
			at.x += 0.6
		await _shot("pickups", Vector3(11.5, 1.5, 0.3), Vector3(11.4, 1.0, -2.6))
	if want.call("heli"):
		set_.set_chapter("THE SNITCH")
		set_.heli.call("set_between_waves", true)
		for i in 14:
			set_.heli._process(1.0)
		var hp: Vector3 = set_.heli.global_position
		await _shot("heli", Vector3(12.0, 1.6, 7.0), hp.lerp(Vector3(set_.heli.beam_target.x, 0, set_.heli.beam_target.z), 0.35))
	if want.call("drive"):
		set_.set_wave(4)
		var car: Node3D = set_.drive_by("main_east")
		cam.global_position = Vector3(8.0, 1.5, -1.8)
		cam.look_at(Vector3(18.0, 1.0, 0.8))
		var guard := 0
		while car.global_position.x < 11.0 and guard < 3000:
			await process_frame
			guard += 1
		await _snap("drive")
	if want.call("bust"):
		set_.set_chapter("THE BUST")
		await _wait(300)
		await _shot("bust", Vector3(30.0, 1.7, 0.4), Vector3(52.0, 1.2, 1.5))
		await _wait(7)
		await _snap("bust2")
		await _shot("getaway", Vector3(36.0, 1.8, -86.5), Vector3(44.0, 0.9, -91.2))
		set_.heli.beam_target = Vector3(10, 0, -2)
		await _shot("search", Vector3(-4.0, 1.7, -1.0), Vector3(10.0, 1.0, -2.0))
	# The laundromat, the markers, the raid and the endings (a fresh night each: `only=lm,markers,raid,endings`).
	if want.call("lm"):
		await _shot("lm_front", Vector3(30.0, 1.65, 1.6), Vector3(33.3, 1.5, -4.0))
		await _shot("lm_in", Vector3(33.3, 1.65, -3.9), Vector3(31.0, 1.0, -8.5))
		await _shot("lm_back", Vector3(32.0, 1.65, -10.8), Vector3(34.6, 1.1, -14.8))
		await _shot("lm_lane", Vector3(38.5, 1.65, -18.2), Vector3(35.2, 1.3, -15.8))
	if want.call("markers"):
		set_.set_chapter("STASH RUN")
		await _wait(60)
		await _shot("marker_door", Vector3(27.0, 1.65, 2.2), Vector3(33.3, 1.5, -3.5))
		p.global_position = Vector3(33.0, 0.0, -9.0)
		await _wait(60)
		await _shot("marker_bags", Vector3(33.0, 1.65, -10.6), Vector3(32.4, 0.6, -13.4))
		p.global_position = Vector3(-60, 0, 0)
	if want.call("raid"):
		set_.set_chapter("THE BUST")
		await _wait(240)
		await _shot("raid_front", Vector3(33.0, 1.7, 7.0), Vector3(33.3, 1.5, -3.5))
		await _shot("raid_street", Vector3(26.0, 1.7, 1.5), Vector3(40.0, 1.5, -1.0))
		await _shot("raid_in", Vector3(33.3, 1.65, -3.9), Vector3(31.5, 1.0, -8.5))
		await _shot("raid_lane", Vector3(38.5, 1.65, -18.2), Vector3(35.2, 1.2, -15.8))
		await _shot("raid_car", Vector3(52.0, 1.7, -17.6), Vector3(47.0, 0.9, -22.0))
		set_.on_story_beat("escaped")
		await _wait(70)
		await _shot("raid_car_going", Vector3(52.0, 1.7, -17.6), Vector3(47.0, 0.9, -30.0))
		await create_timer(9.0).timeout
		await _shot("raid_car_gone", Vector3(52.0, 1.7, -17.6), Vector3(47.0, 0.9, -22.0))
	if want.call("endings"):
		for k in ["clean_dumped", "bag_sold", "busted_sold"]:
			set_.on_story_ending(k)
			await create_timer(6.5).timeout
			await _shot("end_" + k.split("_")[0], Vector3(26.0, 1.7, 1.5), Vector3(38.0, 1.5, -1.5))
	quit()

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame

func _shot(name_: String, from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	await _wait(45)
	await _snap(name_)

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/gw3_%s.png" % [out, name_])
	print("shot ", name_)
