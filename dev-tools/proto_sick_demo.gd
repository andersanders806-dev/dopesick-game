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
##   guardaway [deg]           the shop's clerk faces that way (cone degrees, 0 = east) and barely sweeps
##   lookat guard|<path>       turn the view to the clerk or a node
##   caption <text>            a line over the picture (for the video); "caption" clears it
##   mark <label>              log a line with the time (to cut the video by)
## Everything else is pilot.gd's.

var _caption: Label

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
				g.base_facing_deg = float(parts[1]) if parts.size() > 1 else 0.0
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
