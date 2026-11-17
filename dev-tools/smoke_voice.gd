extends SceneTree
## Voice (autoload/Voice.gd): the cache naming is unchanged, baked-only ids never reach Piper, and a line that
## is on disk is read and decoded on a worker and plays without the calling frame touching the file.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_voice.gd
var fails := 0

func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var v := root.get_node("Voice")
	var key: String = v.line_key("Cashier", "Hello there")
	_check(key == "12_" + ("1.0|Hello there").md5_text().left(16), "cache name stays <cast id>_<16 hex of md5(rate|text)> (%s)" % key)
	_check(v.BAKED_ONLY_FROM == 1000, "cast ids from 1000 are baked-only")
	v._jobs.clear()
	v._queue("1000_x", "Hello", {"id": 1000, "rate": 1.0}, false)
	_check(v._jobs.is_empty(), "a baked-only id is never queued for Piper")
	# A line on disk (a copy of any baked wav under the probe speaker's name) plays from a worker's decode.
	var src := ""
	for f in DirAccess.get_files_at("res://assets/voice/"):
		if f.ends_with(".wav"):
			src = "res://assets/voice/" + f
			break
	_check(src != "", "there is a baked wav to borrow")
	var probe_key: String = v.line_key("SmokeVoice", "Hello probe")
	var dst: String = v._path(probe_key)
	var ok_copy := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst)) == OK
	_check(ok_copy, "copied a wav to %s" % probe_key)
	v.stop()
	v.say("SmokeVoice", "\"Hello probe\"")
	var t0 := Time.get_ticks_msec()
	while not v.is_speaking() and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	_check(v.is_speaking(), "a line on disk plays (%d ms)" % (Time.get_ticks_msec() - t0))
	_check(v._streams.has(probe_key), "...and its decoded stream is kept for the next time")
	v.stop()
	v.say("SmokeVoice", "\"Hello probe\"")
	_check(v.is_speaking(), "heard again, it starts in the same call")
	v.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
	# An imported (baked) line is read by the engine's loader threads and plays the frame they are done.
	var baked := src.get_file().trim_suffix(".wav")
	v.stop()
	v._speak_when_ready(baked, 1.0)
	t0 = Time.get_ticks_msec()
	while not v.is_speaking() and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	_check(v.is_speaking(), "a baked line plays once the loader thread has it (%d ms)" % (Time.get_ticks_msec() - t0))
	v.stop()
	print("PASS" if fails == 0 else "FAIL (%d failure(s))" % fails)
	quit(1 if fails > 0 else 0)
