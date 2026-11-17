extends SceneTree
## SHIP 4 fix 2: captures the title's loading card (cold, first time in the process) at 1 s, mid-way and just before it lifts,
## then the menu after it. Windowed 1280x720: flock .gpu.lock flatpak run org.godotengine.Godot --path . --resolution 1280x720 \
##   --always-on-top -s res://dev-tools/capture_title_card.gd -- <out_dir>
const _TW := preload("res://fx/TitleWarm.gd")

func _init() -> void:
	_run.call_deferred()

func _shot(path: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _run() -> void:
	var out := "res://.pilot/ship4_fix2"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(0)
	gfx.set_laptop_mode(true)
	change_scene_to_file("res://ui/TitleScreen.tscn")
	var t0 := Time.get_ticks_msec()
	var n := 0
	await _frames(30)
	await _shot(out + "/card_a.png")
	var marks := [4000, 9000, 15000]
	var mi := 0
	while _TW.card_up and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		if mi < marks.size() and Time.get_ticks_msec() - t0 > marks[mi]:
			await _shot(out + "/card_%d.png" % (mi + 2))
			mi += 1
	print("CARD held %d ms" % _TW.card_ms)
	await _frames(90)
	await _shot(out + "/menu.png")
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
