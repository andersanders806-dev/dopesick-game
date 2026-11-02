extends SceneTree
## Dev helper: the Drowned up close under a street light, mid-street, dying, and the HUD's edge arrows
## -> .pilot/z4c_dr_*.png. One windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_drowned.gd
var out := ""
var p: Node3D
var ts: Node
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
	var lamp: Node3D = block.city.find_child("StreetlightMain2", true, false) as Node3D
	var L: Vector3 = lamp.global_position if lamp != null else Vector3(30, 0, -3)
	print("lamp at ", L)
	_stand(Vector3(L.x + 6.0, 0.0, 1.0), PI / 2.0, 0.0)
	await _wait(10)
	ts.start()
	await _wait(30)
	# the HUD's edge arrows with both far off
	await _wait(60)
	await _snap("arrows")
	var d = ts.drowned[0]
	var e = ts.drowned[1]
	e.global_position = Vector3(500, -50, 500)
	e.set_physics_process(false)
	await _wait(120)
	d.state = d.State.CHASE
	d._model_root.position.y = 0.0
	d._ghost(false)
	d.set_physics_process(false)
	d.target = null
	var spot := Vector3(L.x, 0.0, 0.8)
	d.global_position = spot
	d._facing = PI / 2.0
	d._model_root.rotation.y = PI / 2.0 * 0.0 + PI / 2.0
	# the Drowned faces +X (towards the player standing at +X): facing angle atan2(x, z) = PI/2
	d._model_root.rotation.y = PI / 2.0
	_stand(Vector3(L.x + 3.6, 0.0, 0.8), PI / 2.0, 0.12)
	await _wait(40)
	await _snap("close")
	_stand(Vector3(L.x + 3.6, 0.0, 0.8), PI / 2.0 - 0.35, 0.05)
	d.global_position = spot + Vector3(0.0, 0.0, 0.0)
	await _wait(10)
	await _snap("close_side")
	_stand(Vector3(L.x + 3.0, 0.0, 0.8), PI / 2.0, 0.28)
	await _wait(10)
	await _snap("face")
	d.global_position = spot + Vector3(-6.0, 0.0, 0.0)
	_stand(Vector3(L.x + 4.0, 0.0, 0.8), PI / 2.0, 0.05)
	await _wait(20)
	await _snap("mid")
	d.global_position = spot
	d.take_hit("head", d.helmet_max * 2.2, Vector3.LEFT)
	await _wait(25)
	await _snap("helmet_off")
	d.take_hit("torso", 1.0e9, Vector3.LEFT)
	for t in [4, 14, 30, 50]:
		await _wait(t if t == 4 else 12)
		await _snap("death_%d" % t)
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
	root.get_texture().get_image().save_png("%s/z4c_dr_%s.png" % [out, name_])
