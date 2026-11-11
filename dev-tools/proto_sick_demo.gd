extends "res://dev-tools/pilot.gd"
## The pilot with the proto-sick-stealth steps added, for the windowed captures:
##   dose <drug_id>            take it (no overdose roll), as the pusher's handoff does
##   tol <N>                   opioid tolerance
##   burst [kind]              a withdrawal burst now, no tell (cough, sniff, retch, cough_fit)
##   tell [kind]               start the tell; the burst follows (held back while `stifle on`)
##   stifle on|off             hold / release the stifle button
##   fumble on|off             the next grab slips (on) or holds (off); "auto" is chance
##   quiet                     no random bursts for a while
##   guard                     log the shop's clerk: suspicion, where he looks, what he said
##   shots <label> <n> <dt>    n screenshots, dt seconds apart
##   walkpath <path>           walk to a node by its path from the scene root
##   guardaway [deg]           the shop's clerk faces away from the player (or that way, cone degrees) and barely sweeps
##   lookat guard|<path>       turn the view to the clerk or a node
##   walkitem / lookitem       walk to the goods nearest the clerk / look at them
##   caption <text>            a line over the picture (for the video); "caption" clears it
##   mark <label>              log a line with the time (to cut the video by)
## Everything else is pilot.gd's.

var _caption: Label
var _item_node: Node3D

func _ensure_caption() -> void:
	if _caption != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 128
	root.add_child(layer)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -92.0
	_caption.offset_bottom = -40.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)

## The captions are for the video; the stills are the game's own picture.
func screenshot(label: String) -> void:
	if _caption != null:
		_caption.visible = false
	await super.screenshot(label)
	if _caption != null:
		_caption.visible = true

## Walks time out on the wall clock; a capture shares the machine with other jobs, so give them room.
func walk_to(node: Node3D, stop_dist := 0.6, timeout := 25.0) -> bool:
	return await super.walk_to(node, stop_dist, maxf(timeout, 150.0))

func _shop_guard() -> Node:
	for g in get_nodes_in_group("guards"):
		if current_scene.is_ancestor_of(g) and not g.watcher_only and g.vision_range > 0.0 and not g.is_in_group("patrol"):
			return g
	return null

func _do(step: String) -> bool:
	var parts := step.split(" ", false)
	if parts.is_empty():
		return true
	var gs := root.get_node("GameState")
	var p := player()
	match parts[0].to_lower():
		"dose":
			var out: String = gs.take_drug(parts[1], 1.0, 0.0)
			log_line("dose %s -> %s, feel %.2f, tolerance %.1f" % [parts[1], out, gs.high_felt, gs.tolerance.get("opioid", 0.0)])
			return true
		"calm":
			gs.high_at = -99999.0
			gs.high_felt = 0.0
			return true
		"tol":
			gs.tolerance["opioid"] = float(parts[1])
			return true
		"burst":
			p.sick_bursts.force_burst(parts[1] if parts.size() > 1 else "")
			log_line("burst started")
			return true
		"tell":
			p.sick_bursts.begin_tell()
			if parts.size() > 1:
				p.sick_bursts._forced_kind = parts[1]
			log_line("tell started")
			return true
		"stifle":
			p.sick_bursts.stifle_override = 1 if parts[1] == "on" else 0
			return true
		"fumble":
			p.fumble_roll_override = 0.0 if parts[1] == "on" else (1.0 if parts[1] == "off" else -1.0)
			return true
		"quiet":
			p.sick_bursts._timer = 9999.0
			return true
		"guard":
			var g := _shop_guard()
			if g == null:
				log_line("no guard in this room")
				return true
			log_line("guard: suspicion %.2f, turned to noise %s (%.1f s left), last heard '%s', last bark '%s', %.1f m from player" % [
				g.suspicion, g._hear_t > 0.0, maxf(g._hear_t, 0.0), g.last_heard, g.last_bark, g.global_position.distance_to(p.global_position)])
			return true
		"shots":
			for i in int(parts[2]):
				await screenshot(parts[1])
				await _wait(float(parts[3]))
			return true
		"walkpath":
			var target := current_scene.get_node_or_null(parts[1]) as Node3D
			if target == null:
				log_line("no node " + parts[1])
				return false
			return await walk_to(target)
		"guardaway":
			var g := _shop_guard()
			if g != null:
				# He is looking the other way: what the player gets when the sweep happens to be away.
				if parts.size() > 1:
					g.base_facing_deg = float(parts[1])
				else:
					# Straight away from the player (cone degrees: 0 = +X, towards +Z at 90).
					var to_p: Vector3 = p.global_position - g.global_position
					g.base_facing_deg = rad_to_deg(atan2(-to_p.z, -to_p.x))
				g.body.rotation.y = deg_to_rad(90.0 - g.base_facing_deg)
				g.sweep_arc_deg = 10.0
				g.reset_suspicion()
			return true
		"lookat":
			var at := Vector3.ZERO
			if parts[1] == "guard":
				var g := _shop_guard()
				at = g.global_position + Vector3(0, 1.5, 0)
			else:
				at = (current_scene.get_node(parts[1]) as Node3D).global_position
			var from: Vector3 = p.global_position + Vector3(0, 1.62, 0)
			var d := at - from
			p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
			await _wait(0.3)
			return true
		"walkitem":
			# The goods nearest the clerk: close enough that his turn fills the picture.
			var g2 := _shop_guard()
			var best: Node3D = null
			for it in get_nodes_in_group("interactable"):
				if it is Node3D and "item_id" in it and current_scene.is_ancestor_of(it) and g2 != null:
					if best == null or it.global_position.distance_to(g2.global_position) < best.global_position.distance_to(g2.global_position):
						best = it
			if best == null:
				return false
			_item_node = best
			await walk_to(best)
			return true
		"lookitem":
			if is_instance_valid(_item_node):
				var from2: Vector3 = p.global_position + Vector3(0, 1.62, 0)
				var d2: Vector3 = _item_node.global_position - from2
				p.set_look(atan2(-d2.x, -d2.z), atan2(d2.y, Vector2(d2.x, d2.z).length()))
				await _wait(0.3)
			return true
		"trypath":
			# Like walkpath, but a stuck walk is only logged: the capture goes on from wherever it got to.
			var tn := current_scene.get_node_or_null(parts[1]) as Node3D
			if tn != null:
				await walk_to(tn)
			return true
		"caption":
			_ensure_caption()
			_caption.text = " ".join(parts.slice(1))
			return true
		"probe":
			var near: Node = p._nearest_interactable()
			log_line("probe: busy %s stealing %s nearest %s (%s) nearby %d inv %s fumble_roll %s" % [p.is_busy(), p.is_stealing, near.name if near else "-", near.item_id if near and "item_id" in near else "-", p.nearby.size(), gs.inventory, p.fumble_roll_override])
			return true
		"mark":
			log_line("MARK %s (frame %d)" % [" ".join(parts.slice(1)), Engine.get_frames_drawn()])
			return true
	return await super._do(step)
