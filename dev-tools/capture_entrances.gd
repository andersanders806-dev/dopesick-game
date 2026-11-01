extends SceneTree
## Dev helper: the dead's entrances in a window -> .pilot/z4c_*.png (a climb out of the ground, a drop off a
## fire escape and a roof, a smash through a shop front, a handful at once). Only one windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_entrances.gd
var out := ""
var p: Node3D
var spawner: Node

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
	spawner = block.spawner
	spawner.enabled = false
	block.surge.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	root.get_node("Graphics").set_first_person(true)
	p = get_first_node_in_group("player") as Node3D
	var ent = spawner.entrances
	# 1. out of the ground, 9 m ahead
	_stand(Vector3(-9.0, 0.0, 8.0), 0.0)
	await _wait(20)
	var land: Vector3 = Vector3(-9.0, 0.0, -6.0 + 2.0)
	land = ent.snap(Vector3(-9.0, 0.0, -6.0)) if ent.snap(Vector3(-9.0, 0.0, -6.0)) != Vector3.INF else Vector3(-9.0, 0.0, -4.0)
	land = Vector3(-9.0, 0.0, -1.5)
	spawner.spawn_entrance("walker", {"type": "rise", "pos": land, "start": land + Vector3(0, -2.1, 0), "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false})
	spawner.spawn_entrance("runner", {"type": "rise", "pos": land + Vector3(3.0, 0, 0.8), "start": land + Vector3(3.0, -2.1, 0.8), "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false})
	for t in [8, 20, 40, 60, 95]:
		await _wait(t - (0 if t == 8 else _last))
		_last = t
		await _snap("rise_%d" % t)
	for z in get_nodes_in_group("zombies"):
		z.free()
	# 2. a drop off the fire escape at x=-18 and from the roof
	_stand(Vector3(-18.0, 0.0, 7.0), 0.0)
	await _wait(20)
	for roof in [false, true]:
		var cands: Array = ent._candidates("drop", Vector3(-18.0, 0.0, 12.0), p.get_viewport().get_camera_3d())
		var pick: Dictionary = {}
		for c in cands:
			if abs(c["start"].x + 17.5) < 2.0 and c["roof"] == roof:
				pick = c
		if pick.is_empty():
			print("no drop pick roof=", roof)
			continue
		spawner.spawn_entrance("runner", pick)
		_last = 0
		for t in [10, 30, 50, 70, 100]:
			await _wait(t - _last)
			_last = t
			await _snap("drop_%s_%d" % ["roof" if roof else "escape", t])
		for z in get_nodes_in_group("zombies"):
			z.free()
	# 3. a smash through the pharmacy front
	_stand(Vector3(-10.5, 0.0, 3.0), 0.0)
	await _wait(20)
	for c in ent._candidates("smash", Vector3(-10.5, 0.0, 12.0), p.get_viewport().get_camera_3d()):
		if abs(c["facade"].x + 10.5) < 1.5 and abs(c["facade"].z + 4.83) < 1.0:
			spawner.spawn_entrance("runner", c)
			break
	_last = 0
	for t in [3, 6, 10, 16, 30]:
		await _wait(t - _last)
		_last = t
		await _snap("smash_%d" % t)
	for z in get_nodes_in_group("zombies"):
		z.free()
	# 4. a handful at once, the way a surge opens
	_stand(Vector3(0.0, 0.0, 2.0), 0.0)
	await _wait(20)
	for i in 14:
		spawner.spawn_entrance("runner", ent.pick(p.global_position, p.get_viewport().get_camera_3d(), ent.SURGE_WEIGHTS))
	_last = 0
	for t in [15, 40, 70, 110]:
		await _wait(t - _last)
		_last = t
		await _snap("surge_%d" % t)
	root.get_node("ZombieMode").leave()
	quit()

var _last := 0

func _stand(at: Vector3, yaw: float) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.set_look(yaw, -0.08)

func _wait(frames: int) -> void:
	for i in maxi(frames, 0):
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z4c_%s.png" % [out, name_])
