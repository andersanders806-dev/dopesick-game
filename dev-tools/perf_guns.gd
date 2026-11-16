extends SceneTree
## Dev helper (SHIP 16 B1 fix 1): a sustained LMG burst in Dead Block in a window, the real _process path (the fire action held),
## frame times for 60 s -> .pilot/ship16b1_fix1/perf_lmg.txt. Gate (ship-4-report.md): <= 7 frames over 25 ms a minute, max <= 40 ms.
## Run under `flock /home/anders/dopesick-game/.gpu.lock`, 1280x720 windowed:
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed -s res://dev-tools/perf_guns.gd -- --no-sick
const SECONDS := 60.0

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
	block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	gfx.set_first_person(true)
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	var h: Node = p.get_node("WeaponHolder")
	h.give(load("res://weapons/lmg.tres"))
	h.refill_all()
	# Let the first shot's pipelines compile and the loads settle before the clock starts.
	Input.action_press("fire")
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < 8.0e6:
		await process_frame
		if h.mag < 20:
			h.refill_all()
	var frames: Array = []
	var last := Time.get_ticks_usec()
	var start := last
	var shots0: int = h.feel.shots
	while float(Time.get_ticks_usec() - start) < SECONDS * 1.0e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		if h.mag < 20:
			h.refill_all()
	Input.action_release("fire")
	var slow := 0
	var worst := 0.0
	var sum := 0.0
	for f in frames:
		sum += f
		worst = maxf(worst, f)
		if f > 25.0:
			slow += 1
	var sorted := frames.duplicate()
	sorted.sort()
	var txt := "LMG sustained burst, Low, windowed: %d frames in %.0f s, %d rounds, mean %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.1f ms, frames > 25 ms: %d (gate <= 7 per minute, max <= 40 ms)\n" % [
		frames.size(), SECONDS, h.feel.shots - shots0, sum / frames.size(), sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], worst, slow]
	print(txt)
	var dir := ProjectSettings.globalize_path("res://.pilot/ship16b1_fix1")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/perf_lmg.txt", FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	quit()
