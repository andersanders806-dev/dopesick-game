extends SceneTree
## Dev helper for SHIP 16 B1: every gun in Dead Block in a window -> .pilot/ship16b1/<gun>_hip.png, _ads.png, _fire.png,
## a burst gun's three rounds (burst_1..3.png) and the camera's recoil per frame while each gun empties a magazine
## (recoil.json), which dev-tools/ship16b1_sheet.py turns into the contact sheet. Needs a window: run it under
## `flock /home/anders/dopesick-game/.gpu.lock`, 1280x720, never fullscreen, and `-- --no-sick`.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed -s res://dev-tools/capture_guns.gd -- --no-sick
var out := ""
const GUNS := ["pistol", "magnum", "smg", "ar", "shotgun", "sniper", "lmg"]
var traces := {}

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot/ship16b1")
	# `-- lmg --out=ship16b1_fix1`: only those guns (hip, ADS, first shot), into .pilot/<out>/.
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = ProjectSettings.globalize_path("res://.pilot/" + a.substr(6))
		elif not a.begins_with("--"):
			only.append(a)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
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
	gfx.set_first_person(true)
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	var h: Node = p.get_node("WeaponHolder")
	h.no_spread = true
	var feel: Node = h.feel
	feel.auto = false
	h.set_process(false)
	block.spawner.round_no = 3
	for k in 2:
		var z = block.spawner.spawn_one("walker", Vector3(-8.0 + k * 5.0, 0.0, -3.0 + (k * 0.6)))
		z.set_physics_process(false)
		z._anim_player.pause()
		z._model_root.rotation.y = PI / 2.0
	for id in (only if not only.is_empty() else GUNS):
		h.give(load("res://weapons/%s.tres" % id))
		h.refill_all()
		await _run(h, feel, 40)
		await _snap("%s_hip" % id)
		h.aiming = true
		await _run(h, feel, 45)
		await _snap("%s_ads" % id)
		h.fire()
		await _run(h, feel, 1)
		await _snap("%s_fire" % id)
		h.aiming = false
		await _run(h, feel, 60)
		if only.is_empty():
			await _trace(h, feel, id)
	if not only.is_empty():
		quit()
		return
	# A burst gun: the AR set to three rounds.
	var b: Resource = load("res://weapons/ar.tres").duplicate()
	b.auto = false
	b.burst_count = 3
	b.burst_delay = 0.2
	h.give(b)
	h.refill_all()
	await _run(h, feel, 40)
	h.fire()
	for r in 3:
		await _run(h, feel, 1)
		await _snap("burst_%d" % (r + 1))
		await _run(h, feel, 4)
	var f := FileAccess.open(out + "/recoil.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(traces))
	f.close()
	quit()

## The camera's recoil (degrees up and to the left) per frame while the gun empties up to 30 rounds, then comes home.
func _trace(h: Node, feel: Node, id: String) -> void:
	h.refill_all()
	feel.reset_state()
	var pts := []
	var n: int = mini(h.mag, 30)
	var fired := 0
	var frames := 0
	var gap: float = h.current.interval()
	while frames < 60 * 6:
		if fired < n and (h.current.auto or frames % maxi(int(gap * 60.0), 1) == 0):
			h._cooldown = 0.0
			if h.fire():
				fired += 1
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		pts.append([snappedf(rad_to_deg(feel.recoil.x), 0.001), snappedf(rad_to_deg(feel.recoil.y), 0.001), fired])
		frames += 1
		if fired >= n and feel.recoil.length() < 0.00002:
			break
		await process_frame
	traces[id] = pts

func _run(h: Node, feel: Node, frames: int) -> void:
	for i in frames:
		h.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		feel.apply()
		await process_frame

func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name_])
