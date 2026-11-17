extends SceneTree
## Voice synthesis must never cost a frame: loads the street (a big process, like the game), then asks for lines
## that have no wav yet (real Piper) and records every frame. Prints the worst frame while a line was being made
## and the main-thread cost of the calls. Headless is fine (it measures CPU frames, not the GPU).
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/voice_hitch_probe.gd -- [lines=6]
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	_run.call_deferred()

func _run() -> void:
	var n := 6
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("lines="):
			n = int(str(a).substr(6))
	await process_frame
	var voice := root.get_node("Voice")
	print("piper ok: ", voice._piper_ok)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 200:
		await process_frame
	var worst := 0.0
	var worst_call := 0.0
	var played := 0
	var t_last := Time.get_ticks_usec()
	var salt := str(Time.get_ticks_msec())
	for k in n:
		var text := "Test line number %d for the perf probe %s, you owe me $%d." % [k, salt, 10 + k]
		var c0 := Time.get_ticks_usec()
		voice.say("ProbeVoice", "\"%s\"" % text)
		var call_ms := (Time.get_ticks_usec() - c0) / 1000.0
		worst_call = maxf(worst_call, call_ms)
		var t0 := Time.get_ticks_msec()
		var heard := false
		while Time.get_ticks_msec() - t0 < 6000:
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - t_last) / 1000.0
			t_last = now
			worst = maxf(worst, dt)
			if dt > 12.0:
				print("  frame %.1f ms at line %d +%d ms" % [dt, k, Time.get_ticks_msec() - t0])
			if voice.is_speaking():
				heard = true
				break
		if heard:
			played += 1
		for j in 30:
			await process_frame
		t_last = Time.get_ticks_usec()
	print("RESULT voice lines %d played %d | say() worst %.2f ms | worst frame %.1f ms" % [n, played, worst_call, worst])
	quit()
