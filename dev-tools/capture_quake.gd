extends SceneTree
## Dev helper: the RICHTER 8.0 surge in a window -> .pilot/z4c_quake_*.png (warning with flicker and dust, the
## quake with the seismograph at 8.0, cracks and rubble, the tail). Only one windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_quake.gd -- [x z yaw_deg] [tp]
var out := ""
var q
var feel: Node
var p: Node3D
var hold_pos := Vector3.ZERO
var hold_yaw := 0.0
var hold_pitch := 0.0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var pos := Vector3(float(args[0]) if args.size() > 2 else -20.0, 0, float(args[1]) if args.size() > 2 else -3.0)
	var yaw := deg_to_rad(float(args[2]) if args.size() > 2 else 90.0)
	var tp := args.has("tp")
	await process_frame
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
	root.get_node("Graphics").set_first_person(not tp)
	p = get_first_node_in_group("player") as Node3D
	p.global_position = pos
	var pitch := 0.0
	if args.has("down"):
		pitch = -0.4
	if args.has("lamp"):
		# Stand 9 m from the nearest street lamp, facing it.
		var best: Node3D = null
		for l in current_scene.find_children("Streetlight*", "StaticBody3D", true, false):
			if best == null or (l as Node3D).global_position.distance_to(pos) < best.global_position.distance_to(pos):
				best = l
		var away := (pos - best.global_position)
		away.y = 0.0
		p.global_position = best.global_position + away.normalized() * 9.0
		p.global_position.y = 0.0
		yaw = atan2(away.x, away.z)
	p.set_look(yaw, pitch)
	hold_pos = p.global_position
	hold_yaw = yaw
	hold_pitch = pitch
	var h := p.get_node("WeaponHolder")
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	feel = h.feel
	h.set_process(false)
	q = block.quake
	q.auto = false
	var tag := "tp" if tp else "fp"
	await _run(20)
	zm.surge_warning.emit()
	await _run(70)
	await _snap("%s_warn_a" % tag)
	await _run(8)
	await _snap("%s_warn_b" % tag)
	for k in 6:
		await _run(2)
		await _snap("%s_flick_%d" % [tag, k])
	await _run(10)
	await _snap("%s_warn_c" % tag)
	await _run(32)
	zm.surge_started.emit()
	await _run(25)
	await _snap("%s_hit_a" % tag)
	await _run(70)
	await _snap("%s_hit_b" % tag)
	await _run(40)
	await _snap("%s_hit_c" % tag)
	await _run(120)
	await _snap("%s_hit_d" % tag)
	await _run(240)
	await _snap("%s_tail" % tag)
	zm.surge_ended.emit()
	await _run(60)
	await _snap("%s_ended" % tag)
	quit()

func _run(frames: int) -> void:
	for i in frames:
		# A stray mouse or key must not walk the camera off the shot.
		p.global_position = hold_pos
		p.velocity = Vector3.ZERO
		p.set_look(hold_yaw, hold_pitch)
		q.advance(1.0 / 60.0)
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z4c_quake_%s.png" % [out, name_])
