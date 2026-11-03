extends SceneTree
## Dev helper (Z5): the zombie block's night from four views -> .pilot/z5_<tag>_<view>.png
## (Main Street first person, a lamp pool, the alley mouth, the quake's cracks). Needs a window.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_atmos.gd -- <tag> [Low|Medium|High]
var out := ""
var p: Node3D
var q
var hold_pos := Vector3.ZERO
var hold_yaw := 0.0
var hold_pitch := 0.0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	var tag := args[0] if args.size() > 0 else "after"
	var preset := args[1] if args.size() > 1 else "Low"
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	gfx.set_preset(gfx.PRESET_NAMES.find(preset))
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
	gfx.set_process(false)
	gfx.set_first_person(true)
	root.scaling_3d_scale = 1.0
	p = get_first_node_in_group("player") as Node3D
	var h := p.get_node("WeaponHolder")
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	h.set_process(false)
	q = block.quake
	q.auto = false
	if tag == "yaws":
		for y in [0, 90, 180, 270]:
			await _view(Vector3(-20, 0, 0), float(y), 0.0, 40)
			await _snap(tag, "y%d" % y)
		quit()
		return
	await _view(Vector3(-20, 0, 0.3), 270.0, 0.0, 90)
	await _snap(tag, "street")
	# Standing in the road, looking at the lamp at (-7, -1.8): its pool on the sidewalk.
	await _view(Vector3(-3, 0, 1.0), 55.0, 0.12, 60)
	await _snap(tag, "lamp")
	await _view(Vector3(14, 0, -0.5), 0.0, 0.0, 60)
	await _snap(tag, "alley")
	await _view(Vector3(-20, 0, 0.3), 270.0, -1.0, 20)
	zm.surge_started.emit()
	hold_pitch = -0.3
	await _run(50)
	await _snap(tag, "dust")
	for k in 3:
		var b = q._bursts[k]
		b.global_position = hold_pos + Vector3(3.5 + k * 1.8, 0.1, -1.2 + k * 1.2)
		b.restart()
		b.emitting = true
	await _run(14)
	await _snap(tag, "burst")
	hold_pitch = -1.0
	await _run(40)
	await _snap(tag, "cracks")
	quit()

func _view(pos: Vector3, yaw_deg: float, pitch: float, frames: int) -> void:
	hold_pos = pos
	hold_yaw = deg_to_rad(yaw_deg)
	hold_pitch = pitch
	await _run(frames)

func _run(frames: int) -> void:
	for i in frames:
		p.global_position = hold_pos
		p.velocity = Vector3.ZERO
		p.set_look(hold_yaw, hold_pitch)
		q.advance(1.0 / 60.0)
		await process_frame

func _snap(tag: String, view: String) -> void:
	await RenderingServer.frame_post_draw
	for c in root.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z5_%s_%s.png" % [out, tag, view])
