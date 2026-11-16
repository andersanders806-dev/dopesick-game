extends SceneTree
## Dev helper (SHIP 16 B2): the sixteen new guns in Dead Block, in a window, for the eye and the contact sheet.
##   views   <ids>: hip and ADS of each gun (the first-raise flourish skipped) -> <id>_hip.png, <id>_ads.png, and
##                  the sight's offset from the screen centre at ADS on stdout ("SIGHT id dx dy" in pixels)
##   reload  <ids>: an empty reload at 15 / 30 / 45 / 60 / 75 / 90 % -> <id>_reload_NN.png
##   fire    <ids>: hip and ADS shots (fired in the window, the rounds counted) -> <id>_shot_hip.png, _shot_ads.png
##   rpg:           a rocket into a crowd -> rpg_flight.png, rpg_blast.png
##   melee <ids>:   a light and a heavy swing into a zombie -> <id>_swing_NN.png
##   buys:          the new wall boards, the box holding a gun -> wall_<id>.png, box.png
## Needs a window: under `flock /home/anders/dopesick-game/.gpu.lock`, 1280x720, never fullscreen, `--no-sick`.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed -s res://dev-tools/capture_b2.gd -- views glock ak --no-sick
const ALL := ["glock", "tec9", "uzi", "mp5", "vector", "ak", "m16", "sawnoff", "deagle", "aa12", "dmr", "amr", "saw", "rpg"]
var out := ""
var block: Node
var h: Node
var feel: Node
var p: Node3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot/ship16b2/cap")
	var mode := "views"
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = ProjectSettings.globalize_path("res://.pilot/" + a.substr(6))
		elif a.begins_with("--"):
			continue
		elif a in ["views", "reload", "fire", "rpg", "melee", "buys"]:
			mode = a
		else:
			ids.append(a)
	if ids.is_empty():
		ids = ALL
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	gfx.set_first_person(true)
	p = get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	h = p.get_node("WeaponHolder")
	h.no_spread = true
	feel = h.feel
	feel.auto = false
	h.set_process(false)
	block.spawner.round_no = 3
	match mode:
		"views":
			await _views(ids)
		"reload":
			await _reloads(ids)
		"fire":
			await _fires(ids)
		"rpg":
			await _rpg()
		"melee":
			await _melee(ids)
		"buys":
			await _buys(ids)
	quit()

func _zombies(n: int, at: Vector3, step: Vector3) -> Array:
	var made: Array = []
	for k in n:
		var z = block.spawner.spawn_one("walker", at + step * k)
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = PI / 2.0
		made.append(z)
	return made

func _give(id: String) -> void:
	var d: Resource = load("res://weapons/%s.tres" % id)
	feel._raise_seen[d.id] = true
	h.give(d)
	h.refill_all()
	h.aiming = false

func _views(ids: Array) -> void:
	_zombies(2, Vector3(-8.0, 0.0, -3.0), Vector3(5.0, 0.0, 0.6))
	for id in ids:
		_give(id)
		await _run(30)
		await _snap("%s_hip" % id)
		h.aiming = true
		await _run(40)
		await _snap("%s_ads" % id)
		var vm: Node3D = h.viewmodel
		var cam: Camera3D = p.get("camera")
		if vm != null and cam != null:
			# Where the sight's point lands on the screen, drawn with the viewmodel's own field of view.
			var sp: Vector3 = vm.global_transform * vm.sight_point
			var local := cam.global_transform.affine_inverse() * sp
			var k := tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(vm.VM_FOV) * 0.5)
			local.x *= k
			local.y *= k
			var px := cam.unproject_position(cam.global_transform * local)
			var c := Vector2(root.get_visible_rect().size) * 0.5
			print("SIGHT %s dx %.1f dy %.1f" % [id, px.x - c.x, px.y - c.y])
		h.aiming = false
		await _run(20)

func _reloads(ids: Array) -> void:
	for id in ids:
		_give(id)
		await _run(30)
		h.mag = 0
		h.reload()
		var total: float = h.reload_left()
		var done := 0.0
		for f in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
			while done < f * total:
				h.advance(1.0 / 60.0)
				feel.advance(1.0 / 60.0)
				feel.apply()
				done += 1.0 / 60.0
				await process_frame
			await _snap("%s_reload_%02d" % [id, int(f * 100.0)])
		await _run(int(total * 60.0))

func _fires(ids: Array) -> void:
	_zombies(3, Vector3(-9.0, 0.0, -3.4), Vector3(0.0, 0.0, 0.8))
	for id in ids:
		_give(id)
		await _run(30)
		var before: int = h.mag
		h._cooldown = 0.0
		h.fire()
		await _run(1)
		await _snap("%s_shot_hip" % id)
		await _run(40)
		h.aiming = true
		await _run(40)
		h._cooldown = 0.0
		h.fire()
		await _run(1)
		await _snap("%s_shot_ads" % id)
		print("FIRED %s %d rounds hip+ads, %d left" % [id, before - h.mag, h.mag])
		h.aiming = false
		await _run(60)

func _rpg() -> void:
	var crowd := _zombies(5, Vector3(-11.0, 0.0, -4.4), Vector3(0.0, 0.0, 0.7))
	for z in crowd:
		z.set_physics_process(true)
	_give("rpg")
	await _run(40)
	h.aiming = true
	await _run(30)
	h.fire()
	await _run(5)
	await _snap("rpg_flight")
	var r: Node = h._rockets[0] if not h._rockets.is_empty() else null
	var t := 0
	while r != null and r.flying and t < 120:
		await _run(1)
		t += 1
	await _run(4)
	await _snap("rpg_blast")
	await _run(10)
	await _snap("rpg_blast_b")
	var alive := 0
	for z in crowd:
		if is_instance_valid(z) and z.is_alive():
			alive += 1
	print("RPG blast at %s, %d of %d still standing" % [r.last_blast if r != null else Vector3.INF, alive, crowd.size()])
	h.aiming = false
	await _run(60)

func _melee(ids: Array) -> void:
	for id in ids:
		var z: Node3D = _zombies(1, Vector3(-21.6, 0.0, -3.0), Vector3.ZERO)[0]
		h.give_melee(load("res://weapons/%s.tres" % id))
		await _run(20)
		h._melee_cd = 0.0
		h.melee(false)
		var n := 0
		while h.swing_time() >= 0.0:
			if n % 4 == 0:
				await _snap("%s_swing_%02d" % [id, n])
			await _run(1)
			n += 1
		await _run(30)
		print("MELEE %s light: zombie alive %s" % [id, is_instance_valid(z) and z.is_alive()])
		await _run(60)

func _buys(ids: Array) -> void:
	var cam: Camera3D = p.get("camera")
	for b in block.wall_buys:
		var id: String = b.data.id
		if not ids.has(id) and not (ids == ALL and id in ["glock", "tec9", "uzi", "mp5", "ak", "m16", "sawnoff", "dmr", "bat", "machete"]):
			continue
		var t: Transform3D = b.global_transform
		var front: Vector3 = t.origin + t.basis.z * 3.2 + Vector3(0, 1.5, 0)
		p.global_position = Vector3(front.x, 0.0, front.z)
		var dir: Vector3 = -t.basis.z
		p.set_look(atan2(-dir.x, -dir.z), -0.08)
		await _run(12)
		await _snap("wall_%s" % id)
	var box: Node3D = block.mystery_box
	var bt: Transform3D = box.global_transform
	var bf: Vector3 = bt.origin + bt.basis.z * 3.0
	p.global_position = Vector3(bf.x, 0.0, bf.z)
	var bd: Vector3 = -bt.basis.z
	p.set_look(atan2(-bd.x, -bd.z), -0.12)
	box.state = box.State.OFFER
	box._t = 30.0
	box.offered = load("res://weapons/ak.tres")
	box._show(box.offered)
	await _run(30)
	await _snap("box")

func _run(frames: int) -> void:
	for i in frames:
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name_])
