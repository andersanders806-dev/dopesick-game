extends "res://dev-tools/pilot.gd"
## Captures for the parked-car pass: the pilot's steps plus
##   rain on|off          the weather
##   hud off|on           hide the HUD and objective panels
##   cam x y z tx ty tz [fov]   a camera there, looking at that point
##   carcam <CarName> <side> <dist> [h]  a camera by a car; side: front|rear|left|right|three
## e.g. flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_cars.gd -- "scene City3D" "clock 14:00" "hud off" "carcam CarB three 4.5" "shot carB"
func _do(step: String) -> bool:
	var parts := step.split(" ", false)
	if parts.is_empty():
		return true
	match parts[0].to_lower():
		"variants":
			var row: Node3D = current_scene.get("parked_row")
			for k in row.layout:
				var car := current_scene.find_child(k, true, false) as Node3D
				log_line("  %-14s %-10s %s props=%s at %s" % [k, row.layout[k]["variant"], row.kind_of(car), row.layout[k]["props"], car.global_position.snapped(Vector3.ONE * 0.1)])
			return true
		"rain":
			root.get_node("GameState").set_raining(parts[1] == "on")
			await _wait(1.2)
			return true
		"hud":
			for n in get_nodes_in_group("hud"):
				if n is CanvasItem:
					(n as CanvasItem).visible = parts[1] == "on"
				elif n is CanvasLayer:
					(n as CanvasLayer).visible = parts[1] == "on"
			for c in root.get_children() + current_scene.get_children():
				if c is CanvasLayer and c.name != "SceneLoader" and c.name != "Graphics":
					(c as CanvasLayer).visible = parts[1] == "on"
			for ctl in root.find_children("*", "Control", true, false):
				if ctl.get_parent() is CanvasLayer or ctl.get_parent() == root:
					(ctl as Control).visible = parts[1] == "on"
			return true
		"dolly":
			# dolly x0 y0 z0 x1 y1 z1 yaw pitch seconds: a camera walking that line, with a walker's bob.
			var a := Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
			var b2 := Vector3(float(parts[4]), float(parts[5]), float(parts[6]))
			var dc := _cam()
			dc.fov = 68.0
			dc.current = true
			var total := float(parts[9])
			var t := 0.0
			var last := Time.get_ticks_usec()
			while t < total:
				await process_frame
				# A movie runs on a fixed 30 fps clock whatever the wall clock says.
				var now := Time.get_ticks_usec()
				t += 1.0 / 30.0 if OS.has_feature("movie") else (now - last) / 1e6
				last = now
				var f := clampf(t / total, 0.0, 1.0)
				dc.global_position = a.lerp(b2, f) + Vector3(0, sin(t * TAU * 1.7) * 0.02, 0)
				dc.rotation = Vector3(deg_to_rad(float(parts[8]) + sin(t * TAU * 0.85) * 0.4), deg_to_rad(float(parts[7]) + sin(t * 0.7) * 1.5), 0.0)
			return true
		"cam":
			var cam := _cam()
			cam.global_position = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
			cam.look_at(Vector3(float(parts[4]), float(parts[5]), float(parts[6])))
			cam.fov = float(parts[7]) if parts.size() > 7 else 60.0
			cam.current = true
			await _wait(0.5)
			return true
		"carcam":
			var car := current_scene.find_child(parts[1], true, false) as Node3D
			if car == null:
				log_line("no car " + parts[1])
				return false
			var side := parts[2]
			var dist := float(parts[3])
			var h := float(parts[4]) if parts.size() > 4 else 1.3
			var b := car.global_basis
			var kd: Vector3 = row_kerb(car.global_position)
			var dir: Vector3 = {"road": -kd * 0.85 + b.x * 0.55, "roadrear": -kd * 0.85 - b.x * 0.55, "roadside": -kd, "front": b.x, "rear": -b.x, "left": -b.z, "right": b.z, "three": (b.x * 0.7 - b.z * 0.9).normalized()}.get(side, b.z)
			# From the street side if the car's other side is the kerb: pick the side with more room.
			var cam := _cam()
			cam.global_position = car.global_position + dir.normalized() * dist + Vector3(0, h, 0)
			cam.look_at(car.global_position + Vector3(0, 0.75, 0))
			cam.fov = 55.0
			cam.current = true
			await _wait(0.6)
			return true
	return await super._do(step)

func row_kerb(p: Vector3) -> Vector3:
	return load("res://world/ParkedRow.gd").kerb_at(p)["dir"]

func _cam() -> Camera3D:
	var cam := current_scene.get_node_or_null("PilotCamera") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "PilotCamera"
		current_scene.add_child(cam)
	return cam
