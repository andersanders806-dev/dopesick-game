extends SceneTree
## Dev helper: the high ground in a window -> .pilot/z4c_hg_*.png: the beacon from the street, the stair, the deck,
## the wave passing under it and the flood. One windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_highground.gd
var out := ""
var p: Node3D
var ts: Node
var hg: Node3D
var block: Node

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.spawner.enabled = false
	block.surge.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	p = get_first_node_in_group("player") as Node3D
	ts = block.tsunami
	hg = block.high_ground
	ts.flood_hold = 6.0
	ts.flood_recede = 3.0
	# the stair from its foot, no warning yet
	_stand(Vector3(41.0, 0.0, -24.0), -PI / 2.0 - 0.45, 0.15)
	await _wait(30)
	await _snap("stair_foot")
	# the warning: the beacon from the street
	ts.start()
	await _wait(90)
	_stand(Vector3(44.0, 0.0, -44.0), atan2(-0.95, -0.31), 0.32)
	await _wait(30)
	await _snap("beacon_a")
	await _wait(35)
	await _snap("beacon_b")
	_stand(Vector3(30.0, 0.0, -2.0), -PI / 2.0 + 0.05, 0.5)
	await _wait(20)
	await _snap("beacon_far")
	# on the deck
	for d in ts.drowned:
		d.global_position = Vector3(500, -50, 500)
		d.set_physics_process(false)
	hg.put_up(p, hg.zone_center())
	p.velocity = Vector3.ZERO
	p.set_look(PI / 2.0, -0.12)
	await _wait(30)
	await _snap("deck")
	p.set_look(-PI / 2.0 + 0.3, 0.0)
	await _wait(10)
	await _snap("deck_beacon")
	p.set_look(PI / 2.0, -0.12)
	ts.skip_to(0.25)
	for t in [60, 80, 100, 120, 140, 180, 260]:
		await _wait(20)
		await _snap("wave_%d" % t)
	root.get_node("ZombieMode").leave()
	quit()

func _stand(at: Vector3, yaw: float, pitch: float) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.set_look(yaw, pitch)

func _wait(frames: int) -> void:
	for i in maxi(frames, 0):
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z4c_hg_%s.png" % [out, name_])
