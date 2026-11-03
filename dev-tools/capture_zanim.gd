extends SceneTree
## Dev helper: zombie body language in a window -> .pilot/z5_<scenario>.png contact sheets
## (a row per scenario, a frame every few ticks; side view on a bare stage, the real Zombie3D).
##   flatpak run org.godotengine.Godot --path . --resolution 640x480 --fixed-fps 30 \
##     -s res://dev-tools/capture_zanim.gd -- <sheet> [sheet ...]
## sheets: entrance (rise, drop), hits (head, arm, torso, leg), gaits (walks, limps, crawler, turn),
##         attacks (swing variants, lunge), dead (front, back, settled)
## Only one windowed Godot at a time.
var Z: GDScript
const CELL := Vector2i(300, 330)

var stage: Node3D
var cam: Camera3D
var subject: Node3D
var foe: Node3D
var out := ""
var cells: Array = []
var tick := 0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	await process_frame
	Z = load("res://npc/Zombie3D.gd")
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	zm.gore_enabled = false
	_build_stage()
	var wanted := OS.get_cmdline_user_args()
	if wanted.is_empty():
		wanted = PackedStringArray(["entrance", "hits", "gaits", "attacks", "dead"])
	for sheet in wanted:
		await Callable(self, "_sheet_" + sheet).call()
	quit()

func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.9
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.4
	stage.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.2, 0.19)
	floor_mi.material_override = fm
	stage.add_child(floor_mi)
	# A stand-in for the player the zombies hunt (and the listener for their voices).
	foe = Node3D.new()
	foe.add_to_group("player")
	stage.add_child(foe)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.current = true
	stage.add_child(cam)

func _zombie(kind := "walker", at := Vector3.ZERO, seed_ := 7, clip := "") -> Node3D:
	var z: Node3D = Z.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	z.configure(kind, 3, rng)
	if clip != "":
		z._move_clip = clip
		z._base_clip = clip
	z.target = foe
	stage.add_child(z)
	z.global_position = at
	z._facing = PI / 2.0     # facing +x, side view from -z... camera looks along +z
	z._model_root.rotation.y = z._facing
	subject = z
	return z

## Camera on the subject's side, `dist` m away, aiming at its middle.
func _aim(dist := 4.6, h := 1.0, lead := 0.0) -> void:
	var p := subject.global_position
	cam.global_position = Vector3(p.x + lead, h + 0.15, p.z - dist)
	cam.look_at(Vector3(p.x + lead, h, p.z), Vector3.UP)

func _grab(label := "") -> void:
	_aim(subject.get_meta("cam_dist", 3.4), subject.get_meta("cam_h", 0.9), subject.get_meta("cam_lead", 0.0))
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var side := mini(w, h)
	var crop := img.get_region(Rect2i((w - side) / 2, (h - side) / 2, side, side))
	crop.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	cells.append({"img": crop, "label": label})

func _sheet_save(name_: String, cols: int) -> void:
	var rows := int(ceil(float(cells.size()) / cols))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	for i in cells.size():
		sheet.blit_rect(cells[i]["img"], Rect2i(0, 0, CELL.x, CELL.y), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	var path := out + "/z5_" + name_ + ".png"
	sheet.save_png(path)
	print("saved ", path, " ", cells.size(), " cells")
	cells.clear()

func _run(frames: int) -> void:
	for i in frames:
		await physics_frame

func _clear() -> void:
	for z in get_nodes_in_group("zombies"):
		z.free()
	for z in get_nodes_in_group("corpses"):
		z.free()

## `n` cells, one every `every` physics ticks, labelled by the subject's state.
func _film(n: int, every: int) -> void:
	for i in n:
		await _grab("%d" % i)
		await _run(every)

func _sheet_entrance() -> void:
	_clear()
	foe.global_position = Vector3(6, 0, 0)
	var r := _zombie("walker", Vector3(0, 0, 0))
	r.begin_entrance({"type": "rise", "pos": Vector3.ZERO, "start": Vector3(0, -2.1, 0), "out": Vector3.RIGHT, "fall": 0.0, "node": null, "roof": false})
	r.set_meta("cam_dist", 4.0)
	await _film(10, 14)
	r.free()
	var d := _zombie("walker", Vector3(0, 0, 0), 9)
	var fall := 0.55
	d.begin_entrance({"type": "drop", "pos": Vector3.ZERO, "start": Vector3(0, 3.2, 0), "out": Vector3.RIGHT, "fall": fall, "node": null, "roof": false})
	d.set_meta("cam_dist", 5.5)
	d.set_meta("cam_h", 1.5)
	await _film(10, 5)
	d.free()
	_sheet_save("entrance", 10)

func _hit(part: String, dmg_share: float, seed_ := 7, dir := Vector3.RIGHT) -> void:
	var z := _zombie("walker", Vector3(-1, 0, 0), seed_, "z_walk")
	z.max_health = 200.0
	z.health = 200.0
	z.target = foe
	foe.global_position = Vector3(12, 0, 0)
	z.set_meta("cam_lead", 1.0)
	await _run(40)
	z.take_hit(part, z.max_health * dmg_share, dir)
	await _film(8, 4)
	z.free()

func _sheet_hits() -> void:
	_clear()
	await _hit("head", 0.2)
	await _hit("upper_arm_l", 0.2)
	await _hit("torso", 0.3)
	await _hit("upper_leg_r", 0.15)
	await _hit("upper_leg_l", 0.45)
	_sheet_save("hits", 8)

func _sheet_gaits() -> void:
	_clear()
	foe.global_position = Vector3(40, 0, 0)
	for clip in ["z_walk", "z_walk2", "z_walk3", "z_walk4"]:
		var z := _zombie("walker", Vector3(-1, 0, 0), 7, clip)
		z.set_meta("cam_lead", 0.0)
		await _run(30)
		for i in 6:
			await _grab(clip)
			await _run(7)
		z.free()
	# limp (left leg beaten), dangling arm, crawler
	var l := _zombie("walker", Vector3(-1, 0, 0), 7, "z_walk")
	l.limb_damage["upper_leg_l"] = 60.0
	l.max_health = 200.0
	l._refresh_gait()
	await _run(30)
	for i in 6:
		await _grab("limp " + l.gait)
		await _run(7)
	l.free()
	var a := _zombie("walker", Vector3(-1, 0, 0), 7, "z_walk")
	a.severed["arm_r"] = true
	a.max_health = 200.0
	a._refresh_gait()
	await _run(30)
	for i in 6:
		await _grab("arm " + a.gait)
		await _run(7)
	a.free()
	var c := _zombie("walker", Vector3(-1, 0, 0), 7, "z_walk")
	c.set_legless(true)
	c.set_meta("cam_h", 0.5)
	c.set_meta("cam_dist", 3.4)
	await _run(30)
	for i in 6:
		await _grab("crawl")
		await _run(9)
	c.free()
	_sheet_save("gaits", 6)

func _sheet_attacks() -> void:
	_clear()
	for want in ["z_attack", "z_attack2", "z_attack3", "z_bite", "z_smash"]:
		foe.global_position = Vector3(1.0, 0, 0)
		var z := _zombie("walker", Vector3(0, 0, 0), 7, "z_walk")
		z.set_meta("cam_lead", 0.5)
		z._attack_cooldown = 0.0
		z._lunger = false
		for tries in 40:
			z.state = z.State.CHASE
			z._begin_attack(foe.global_position - z.global_position)
			if z._attack_clip == want:
				break
		for i in 8:
			await _grab(want)
			await _run(int(z._attack_len * 60.0 / 8.0))
		z.free()
	# The lunge.
	foe.global_position = Vector3(3.6, 0, 0)
	var l := _zombie("walker", Vector3(0, 0, 0), 7, "z_walk")
	l._lunger = true
	l._lunge_ready = true
	l.set_meta("cam_lead", 1.5)
	l.set_meta("cam_dist", 6.0)
	for i in 8:
		await _grab("lunge %d" % l.lunges)
		await _run(6)
	l.free()
	_sheet_save("attacks", 8)

func _sheet_dead() -> void:
	_clear()
	foe.global_position = Vector3(40, 0, 0)
	for dir in [Vector3.RIGHT, Vector3.LEFT]:
		var z := _zombie("walker", Vector3(-1, 0, 0), 7, "z_walk")
		z.set_meta("cam_dist", 6.0)
		z.set_meta("cam_h", 0.8)
		await _run(30)
		z.take_hit("torso", 1.0e6, dir)
		print("shot from ", dir, " -> ", z._anim_player.current_animation)
		for i in 8:
			await _grab("dead")
			await _run(20)
		z.free()
	_sheet_save("dead", 8)
