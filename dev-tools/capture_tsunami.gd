extends SceneTree
## Dev helper: the tsunami in a window -> .pilot/z4c_tsu_*.png (the broadcast banner and countdown, a Drowned close up,
## the wave on the horizon at 0:20, the water seeping in, the wave hitting, the relief banner). One windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_tsunami.gd
var out := ""
var p: Node3D
var block: Node
var ts: Node

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
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
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0, -0.05)
	await _wait(20)
	# 1. banner and countdown
	ts.start()
	await _wait(40)
	await _snap("banner")
	await _wait(400)
	await _snap("countdown")
	# 2. a Drowned close up
	var d = ts.drowned[0]
	await _wait(200)
	d.state = d.State.CHASE
	d.global_position = Vector3(30.0, 0.0, -0.3)
	d._model_root.position.y = 0.0
	d._ghost(false)
	d.set_physics_process(false)
	d._model_root.rotation.y = PI / 2.0 * 3.0
	d._facing = PI * 1.5
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0, 0.02)
	d.global_position = Vector3(41.0, 0.0, -0.3)
	await _wait(30)
	await _snap("drowned_close")
	d.global_position = Vector3(38.0, 0.0, -0.3)
	await _wait(10)
	await _snap("drowned_mid")
	# helmet gone
	d.take_hit("head", d.helmet_max * 2.2, Vector3.LEFT)
	d.global_position = Vector3(42.2, 0.0, -0.2)
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0 + 0.1, 0.1)
	await _wait(30)
	await _snap("drowned_nohelmet")
	d.global_position = Vector3(500, -50, 500)
	ts.drowned[1].global_position = Vector3(500, -50, 500)
	ts.drowned[1].set_physics_process(false)
	# 3. the dread
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0, 0.3)
	ts.skip_to(58.0)
	await _wait(60)
	await _snap("dread_1m")
	ts.skip_to(24.0)
	await _wait(60)
	await _snap("wave_24")
	ts.skip_to(14.0)
	await _wait(120)
	await _snap("wave_14")
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0, -0.35)
	await _wait(30)
	await _snap("seep_ground")
	_stand(Vector3(45.0, 0.0, -0.3), PI / 2.0, 0.3)
	ts.skip_to(4.0)
	await _wait(60)
	await _snap("wave_04")
	ts.skip_to(0.05)
	await _wait(8)
	for t in [20, 40, 60, 80, 100]:
		await _wait(20)
		await _snap("hit_%d" % t)
	await _wait(60)
	await _snap("under")
	await _wait(200)
	root.get_node("ZombieMode").leave()
	paused = false
	var gos := root.get_node_or_null("ZombieGameOver")
	if gos:
		await _snap("gameover")
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
	root.get_texture().get_image().save_png("%s/z4c_tsu_%s.png" % [out, name_])
