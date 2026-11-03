extends SceneTree
## Dev helper: Ghetto Wars in a window -> .pilot/gw_*.png: a cover fight (crew behind cars), enemies firing
## (tracers, flashes), a flank in the street, the boss wave's heavy, and gore on a human. First person, plus a
## side camera for the poses. Needs a window; run only when no other windowed Godot runs.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_ghetto.gd -- [shots...]
## shots: cover fire flank boss gore all (default all)
var out := ""
var zm: Node
var block: Node
var player: Node3D
var holder: Node
var fx: Node3D
var cam2: Camera3D
var fp_cam: Camera3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	var args: Array = Array(OS.get_cmdline_user_args())
	if args.is_empty() or args.has("all"):
		args = ["cover", "fire", "flank", "boss", "gore"]
	await process_frame
	zm = root.get_node("ZombieMode")
	zm.begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready or block.cover.points.is_empty():
		await process_frame
	block.spawner.enabled = false
	fx = block.gang_fx
	for g in get_nodes_in_group("gangsters"):
		g.free()
	player = get_first_node_in_group("player") as Node3D
	holder = get_first_node_in_group("weapon_holder")
	player.global_position = Vector3(-14.0, 0, 1.2)
	player.set_look(-PI / 2.0, 0.0)
	holder.give(load("res://weapons/ar.tres"))
	holder.refill_all()
	fp_cam = root.get_viewport().get_camera_3d()
	cam2 = Camera3D.new()
	cam2.fov = 55.0
	current_scene.add_child(cam2)
	for i in 30:
		await process_frame
	if args.has("cover"):
		await _cover()
	if args.has("fire"):
		await _fire()
	if args.has("flank"):
		await _flank()
	if args.has("boss"):
		await _boss()
	if args.has("gore"):
		await _gore()
	print("done")
	quit(0)

func _keep_alive() -> void:
	zm.health = zm.MAX_HEALTH
	zm._since_hit = 0.0

func _wait(frames: int) -> void:
	for i in frames:
		_keep_alive()
		await process_frame

func _snap(name_: String, side := false) -> void:
	if side:
		cam2.current = true
	else:
		cam2.current = false
		fp_cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/gw_%s.png" % [out, name_])
	print("snap ", name_)

## A camera beside the fight, looking along the street at `at`.
func _side_cam(at: Vector3, from_off := Vector3(0, 2.2, 7.0)) -> void:
	cam2.global_position = at + from_off
	cam2.look_at(at + Vector3(0, 1.0, 0), Vector3.UP)

func _clear() -> void:
	for g in get_nodes_in_group("gangsters") + get_nodes_in_group("corpses"):
		if is_instance_valid(g):
			g.free()

func _spawn(kind: String, gun: String, at: Vector3):
	var g = block.spawner.spawn_one(kind, at, "", gun)
	g.target = player
	return g

## Cover points ahead of the player (east along the street) that hide from them and see them.
func _cover_ahead(n: int) -> Array:
	var out_: Array = []
	var cover = block.cover
	var pl := player.global_position
	var probe = _spawn("grunt", "smg", pl + Vector3(40, 0, 0))
	for i in cover.points.size():
		var pos: Vector3 = cover.points[i]["pos"]
		if pos.x < pl.x + 9.0 or pos.x > pl.x + 34.0 or absf(pos.z - pl.z) > 9.0:
			continue
		if probe.cover_ok(i) and cover.is_free(i):
			out_.append(i)
	probe.free()
	out_.shuffle()
	return out_.slice(0, n)

func _cover() -> void:
	_clear()
	var spots := _cover_ahead(5)
	print("cover spots ", spots.size())
	var gs: Array = []
	var guns := ["ar", "smg", "pistol", "ar", "smg"]
	for k in spots.size():
		var g = _spawn("grunt" if k != 2 else "vest", guns[k], block.cover.points[spots[k]]["pos"] + Vector3(14, 0, 0))
		g.go_to_cover(spots[k])
		gs.append(g)
	await _wait(60 * 12)
	await _snap("cover_fp")
	_side_cam(player.global_position + Vector3(14, 0, 0), Vector3(0, 2.4, 9.0))
	await _snap("cover_side", true)

func _fire() -> void:
	# Hold the ones in cover firing: PEEK with a long timer, no cover change, from where they are.
	var gs := get_nodes_in_group("gangsters")
	var shots := 0
	for k in 14:
		for g in gs:
			if is_instance_valid(g) and g.is_alive():
				g._mode_t = 20.0
				g._peeks_left = 5
				if g.mode == g.Mode.COVER:
					g._mode_t = 0.0
		await _wait(26)
		if fx.tracers_spawned > shots + 3:
			await _snap("fire_%02d" % k)
		shots = fx.tracers_spawned
	await _snap("fire_end")

func _flank() -> void:
	_clear()
	var pl := player.global_position
	var a = _spawn("grunt", "smg", pl + Vector3(30, 0, 5))
	var b = _spawn("grunt", "ar", pl + Vector3(32, 0, 5))
	a.buddy = b
	b.buddy = a
	b.role = "flank"
	var c = _spawn("vest", "smg", pl + Vector3(34, 0, -2))
	await _wait(60 * 5)
	_side_cam(pl + Vector3(12, 0, 0), Vector3(0, 3.0, 11.0))
	await _snap("flank_side", true)
	await _wait(60 * 2)
	await _snap("flank_fp")
	await _snap("flank_side2", true)

func _boss() -> void:
	_clear()
	zm.round = 4
	block.spawner.round_no = 5
	var pl := player.global_position
	var boss = block.spawner.spawn_one("heavy", pl + Vector3(17, 0, 2))
	boss.target = player
	var g2 = _spawn("vest", "ar", pl + Vector3(22, 0, 4))
	await _wait(60 * 4)
	await _snap("boss_fp")
	_side_cam(boss.global_position, Vector3(-4, 1.8, 6.0))
	await _snap("boss_side", true)

func _gore() -> void:
	_clear()
	var pl := player.global_position
	holder.give(load("res://weapons/shotgun.tres"))
	holder.refill_all()
	var g = _spawn("grunt", "pistol", pl + Vector3(5.5, 0, 0.3))
	g.mode = g.Mode.HOLD
	g.set_physics_process(false)
	await _wait(20)
	# A burst into the chest, then the head: through the real weapon.
	for k in 2:
		holder.fire()
		await _wait(8)
	await _wait(10)
	await _snap("gore_fp")
	_side_cam(g.global_position, Vector3(0, 1.6, 4.0))
	await _wait(40)
	await _snap("gore_side", true)
	var g2 = _spawn("grunt", "smg", pl + Vector3(3.5, 0, -0.4))
	g2.mode = g2.Mode.HOLD
	await _wait(20)
	g2.take_hit("head", 400.0, Vector3.RIGHT, load("res://weapons/shotgun.tres"), false, g2.global_position + Vector3(0, 1.6, 0))
	await _wait(14)
	await _snap("gore_head_fp")
	await _wait(50)
	_side_cam(g2.global_position, Vector3(0, 1.6, 4.0))
	await _snap("gore_head_side", true)
