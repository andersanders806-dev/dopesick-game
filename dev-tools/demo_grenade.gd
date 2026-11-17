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
	block.spawner.round_no = 8
	block.spawner.enabled = true
	# Let the dead come: the film starts when the first of them is within 22 m.
	for i in 1200:
		await process_frame
		zm.health = 100.0
		var near := 0
		for z in get_nodes_in_group("zombies"):
			if (z as Node3D).global_position.distance_to(p.global_position) < 22.0:
				near += 1
		if near >= 6:
			break
	print("FILM START frame ", Engine.get_process_frames())
	# A beat of the empty street, then G held: the cook.
	for i in 40:
		await process_frame
		zm.health = 100.0
	Input.action_press("lethal")
	for i in 78:
		await process_frame
		zm.health = 100.0
	Input.action_release("lethal")
	for i in 120:
		await process_frame
		zm.health = 100.0
	# The second one is a tap.
	Input.action_press("lethal")
	for i in 3:
		await process_frame
	Input.action_release("lethal")
	for i in 200:
		await process_frame
		zm.health = 100.0
	print("FILM END frame ", Engine.get_process_frames())
	quit()
