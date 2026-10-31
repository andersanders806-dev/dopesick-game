extends SceneTree
## Dev helper: a short first-person clip of full-auto fire into a walking
## horde (AR, SMG, LMG; held trigger, released between bursts so the echo tail
## plays). Run with Godot's movie writer:
##   flatpak run org.godotengine.Godot --path . --write-movie .pilot/full_auto.avi --fixed-fps 30 \
##     -s res://dev-tools/video_full_auto.gd

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin(true)
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
	zm.health = 1e9
	var h: Node = p.get_node("WeaponHolder")
	block.spawner.round_no = 4
	for gun in ["ar", "smg", "lmg"]:
		_horde(block.spawner, 9)
		h.give(load("res://weapons/%s.tres" % gun))
		h.refill_all()
		await _wait(1.0, p)
		h.aiming = gun != "lmg"
		await _wait(0.4, p)
		for burst in 4:
			Input.action_press("fire")
			await _wait(0.9 if burst < 3 else 1.6, p)
			Input.action_release("fire")
			await _wait(0.6, p)
		h.aiming = false
		await _wait(0.8, p)
		for z in get_nodes_in_group("zombies"):
			if is_instance_valid(z):
				z.queue_free()
	quit()

func _horde(spawner: Node, n: int) -> void:
	for i in n:
		var kind := "runner" if i % 3 == 0 else "walker"
		spawner.spawn_one(kind, Vector3(-6.0 + (i % 3) * 2.5, 0.0, -4.5 + (i / 3) * 1.4))

## Holds the view on the nearest living zombie's chest, as a player would.
func _wait(seconds: float, p: Node3D) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		var dt := 1.0 / 30.0
		t += dt
		var best: Node3D = null
		var best_d := 40.0
		for z in get_nodes_in_group("zombies"):
			if not is_instance_valid(z) or z.get("state") == 6 or z.get("state") == 5:
				continue
			var d: float = z.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = z
		if best == null:
			continue
		var eye := p.global_position + Vector3(0, 1.6, 0)
		var to := best.global_position + Vector3(0, 1.3, 0) - eye
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		var cy: float = p.get("_look_yaw")
		var cp: float = p.get("_look_pitch")
		p.set_look(lerp_angle(cy, yaw, 0.18), lerpf(cp, pitch, 0.18))
