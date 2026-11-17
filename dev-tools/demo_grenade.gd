extends SceneTree
## Dev helper (SHIP 16G): a short film of a cooked Mk 2 frag thrown into a horde, for the user. Dead Block in a window, a real
## round-8 horde coming down Main Street, the player holds G (the real input path: Input.action_press("lethal")), the pin is
## out, the fuse ticks in the hand, let go, and it goes off in the crowd; then a second, tapped. Recorded with Godot's movie
## maker (fixed 30 fps, the engine's own mix as the sound), then cut to mp4 with ffmpeg:
##   flock .gpu.lock flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed --write-movie .pilot/ship16g/granat.avi \
##     --fixed-fps 30 -s res://dev-tools/demo_grenade.gd -- --no-sick
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	gfx.set_first_person(true)
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	var h: Node = p.get_node("WeaponHolder")
	h.set_grenades(4)
	block.spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	# A group of the dead coming down the street from 15 m out, walked in by the script (a steady pace, so the film is the same
	# every time): they stop 7 m short of the player.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var crowd: Array = []
	for k in 11:
		var z = block.spawner.spawn_one("walker", Vector3(-4.5 + rng.randf_range(0.0, 5.0), 0.0, -3.0 + rng.randf_range(-3.0, 3.0)))
		z.set_physics_process(false)
		z.max_health = 700.0
		z.health = 700.0
		z._model_root.rotation.y = -PI / 2.0
		crowd.append(z)
	for i in 20:
		await process_frame
		zm.health = 1000.0
		_walk(crowd, p)
	print("FILM START frame ", Engine.get_process_frames())
	# A beat of the street, then G held: the cook (2 s), let go.
	for i in 24:
		await process_frame
		zm.health = 1000.0
		_walk(crowd, p)
	Input.action_press("lethal")
	for i in 60:
		await process_frame
		zm.health = 1000.0
		_walk(crowd, p)
	Input.action_release("lethal")
	for i in 130:
		await process_frame
		zm.health = 1000.0
		_walk(crowd, p)
	# The second one is a tap, if the street still holds a few at a safe distance.
	var nearest2 := 1000.0
	for z in get_nodes_in_group("zombies"):
		nearest2 = minf(nearest2, (z as Node3D).global_position.distance_to(p.global_position))
	print("second throw, nearest ", nearest2)
	if nearest2 > 7.0:
		Input.action_press("lethal")
		for i in 3:
			await process_frame
		Input.action_release("lethal")
	for i in 170:
		await process_frame
		zm.health = 1000.0
		_walk(crowd, p)
	print("FILM END frame ", Engine.get_process_frames())
	quit()

func _walk(crowd: Array, p: Node3D) -> void:
	for z in crowd:
		if is_instance_valid(z) and z.is_alive():
			var d := p.global_position - (z as Node3D).global_position
			d.y = 0.0
			if d.length() > 7.5:
				(z as Node3D).global_position += d.normalized() * 1.2 / 30.0
