extends SceneTree
## Dev helper (SHIP 16 B2): the floor gate under the heaviest new guns. Dead Block in a window on Low, a horde coming
## (round 12, the spawner on), the real _process path: the AA-12 dumps its drum with the fire action held, and every
## few seconds the RPG goes into the crowd; 60 s of frame times -> .pilot/ship16b2/perf_b2.txt.
## Gate (ship-4-report.md): <= 7 frames over 25 ms a minute, max <= 40 ms. Under the gpu lock, 1280x720, `--no-sick`:
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed -s res://dev-tools/perf_b2.gd -- --no-sick [--swap]
## (--swap: the player swaps to the launcher and back for each rocket, so the swap's own cost is in the numbers.)
const SECONDS := 60.0
const RPG_EVERY := 6.0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
	# First person before the block loads, as in the game: its prewarm draws the guns, the rockets and their blast.
	gfx.set_first_person(true)
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
	# The horde: a late round, coming down Main Street at you; you can't die in the probe.
	block.spawner.round_no = 12
	block.spawner.enabled = true
	# The drum in slot 1, the launcher in slot 2 (the pistol the block hands you is put away).
	h.slots = [null, null]
	h.give(load("res://weapons/aa12.tres"))
	h.give(load("res://weapons/rpg.tres"))
	h.select(0)
	h.refill_all()
	var swap_mode := OS.get_cmdline_user_args().has("--swap")
	# --norpg: the drum alone in the same horde (what the street costs without the launcher).
	var no_rpg := OS.get_cmdline_user_args().has("--norpg")
	# Let the loads settle and the first shots' pipelines compile before the clock starts.
	Input.action_press("fire")
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < 8.0e6:
		await process_frame
		_keep_alive(zm, h)
	var frames: Array = []
	var last := Time.get_ticks_usec()
	var start := last
	var shots0: int = h.feel.shots
	var next_rpg := RPG_EVERY
	var rockets := 0
	var zombies_max := 0
	var slow_at: Array = []
	var fired_at: Array = []
	while float(Time.get_ticks_usec() - start) < SECONDS * 1.0e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		if frames[-1] > 25.0:
			slow_at.append("%.2fs:%.0fms" % [float(now - start) / 1.0e6, frames[-1]])
		last = now
		_keep_alive(zm, h)
		zombies_max = maxi(zombies_max, get_nodes_in_group("zombies").size())
		var t := float(now - start) / 1.0e6
		if t >= next_rpg and not no_rpg:
			next_rpg += RPG_EVERY
			if swap_mode:
				# Swap to the launcher, fire it into the crowd, swap back to the drum (what a player does).
				Input.action_release("fire")
				h.select(1)
				h.refill_all()
				for i in int(h.current.swap_time * 60.0) + 6:
					await process_frame
					var n2 := Time.get_ticks_usec()
					frames.append(float(n2 - last) / 1000.0)
					if frames[-1] > 25.0:
						slow_at.append("swap %.2fs:%.0fms" % [float(n2 - start) / 1.0e6, frames[-1]])
					last = n2
				h._cooldown = 0.0
				if h.fire():
					rockets += 1
					fired_at.append("%.2f" % (float(Time.get_ticks_usec() - start) / 1.0e6))
				for i in 50:
					await process_frame
					var n3 := Time.get_ticks_usec()
					frames.append(float(n3 - last) / 1000.0)
					if frames[-1] > 25.0:
						slow_at.append("after-shot %.2fs:%.0fms" % [float(n3 - start) / 1.0e6, frames[-1]])
					last = n3
				h.select(0)
				Input.action_press("fire")
			else:
				# The launcher's rocket sent from the same eye without a swap (the blast is what is measured).
				var launcher: Resource = h.slot_data(1)
				h._launch(p.get("camera").global_position, -p.get("camera").global_transform.basis.z, launcher)
				rockets += 1
				fired_at.append("%.2f" % t)
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
	var txt := ("(with swaps) " if swap_mode else "") + ("(no rockets) " if no_rpg else "") + "AA-12 drum dumps + RPG blasts in a round-12 horde, Low, windowed: %d frames in %.0f s, %d rounds, %d rockets, up to %d zombies, mean %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.1f ms, frames > 25 ms: %d (gate <= 7 per minute, max <= 40 ms)\n" % [
		frames.size(), SECONDS, h.feel.shots - shots0, rockets, zombies_max, sum / frames.size(), sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], worst, slow]
	txt += "slow frames at %s; rockets sent at %s\n" % [slow_at, fired_at]
	print(txt)
	var dir := ProjectSettings.globalize_path("res://.pilot/ship16b2")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + ("/perf_b2_swap.txt" if swap_mode else ("/perf_b2_norpg.txt" if no_rpg else "/perf_b2.txt")), FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	quit()

func _keep_alive(zm: Node, h: Node) -> void:
	zm.health = 100.0
	if h.mag < 4:
		h.refill_all()
