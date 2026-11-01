extends SceneTree
## Live check of autoload/DualSense.gd against a real controller: the lightbar goes red, green, blue,
## R2 gets a strong Weapon effect for 10 s (pull it and it should resist, then break), then everything
## is put back. Reports how many reports the kernel took (dd's own count). Run it with the pad plugged in:
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/dualsense_demo.gd
var DS: GDScript

func _initialize() -> void:
	await process_frame
	DS = load("res://autoload/DualSense.gd")
	var dev: Dictionary = DS.find_device()
	print("device: ", dev)
	if dev.is_empty():
		print("no DualSense found")
		quit(1)
		return
	var bt: bool = dev["bt"]
	var size: int = DS.BT_SIZE if bt else DS.USB_SIZE
	var log := ProjectSettings.globalize_path("res://dev-tools/_dd.txt")
	# Part 1: dd straight onto the node, its own count of records written kept in a file.
	var r := OS.execute_with_pipe("/bin/sh", ["-c", "dd bs=%d iflag=fullblock of='%s' 2>'%s'; echo \"exit=$?\" >> '%s'" % [size, dev["path"], log, log]])
	if r.is_empty():
		print("could not start dd")
		quit(1)
		return
	var io: FileAccess = r["stdio"]
	var sent := 0
	var seq := 0
	for col in [Vector3i(255, 0, 0), Vector3i(0, 255, 0), Vector3i(0, 0, 255)]:
		io.store_buffer(DS.build_report(bt, seq, 0, DS.F1_LIGHTBAR, DS.eff_off(), DS.eff_off(), col, 0))
		io.flush()
		seq += 1
		sent += 1
		print("lightbar ", col, " alive=", OS.is_process_running(int(r["pid"])))
		OS.delay_msec(700)
	io.store_buffer(DS.build_report(bt, seq, DS.F0_RIGHT, DS.F1_LIGHTBAR, DS.eff_weapon(2, 7, 8), DS.eff_off(), Vector3i(255, 120, 0), 0))
	io.flush()
	seq += 1
	sent += 1
	print("R2: Weapon(2..7, strength 8) for 10 s, pull the right trigger. alive=", OS.is_process_running(int(r["pid"])))
	OS.delay_msec(10000)
	io.store_buffer(DS.reset_report(bt, seq))
	io.flush()
	sent += 1
	OS.delay_msec(300)
	print("reset sent. alive=", OS.is_process_running(int(r["pid"])))
	OS.delay_msec(300)
	io.close()
	OS.delay_msec(500)
	print("dd said:\n", FileAccess.get_file_as_string(log))
	DirAccess.remove_absolute(log)
	print("reports sent: ", sent)
	# Part 2: the production path (open_device with its reset-on-exit shell line).
	var d: Node = DS.new()
	d.manual = true
	d.allow_headless = true
	d.name = "DemoDualSense"
	root.add_child(d)
	var ok: bool = d.open_device()
	var w: bool = d.write_report(DS.build_report(d.bt, 0, DS.F0_RIGHT | DS.F0_LEFT, DS.F1_LIGHTBAR, DS.eff_weapon(4, 6, 5), DS.eff_feedback(3, 2), Vector3i(120, 70, 8), 0))
	OS.delay_msec(800)
	print("production path: open=", ok, " write=", w, " writes=", d.writes)
	d.shutdown()
	print("production path closed (the shell line writes the reset as dd ends)")
	OS.delay_msec(500)
	quit(0)
