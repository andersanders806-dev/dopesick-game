extends "res://dev-tools/video_high_ground.gd"
## Dev helper: a scripted run in a real window for the Z5 realism pass -> .pilot/z5play_*.png (then
## dev-tools/contact_sheet.py makes the contact sheet). Round 1 opens, a reload of each gun (the empty
## reloads too), a zombie climbs out of the street and takes hits on head, arm, leg and torso, then the
## round is fought for a while. The bot can't die (a demo, not a test).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 --fixed-fps 30 -s res://dev-tools/demo_z5.gd
const GUNS := ["pistol", "smg", "ar", "shotgun", "lmg", "sniper", "magnum"]
const BASE := Vector3(10.0, 0.0, 1.5)
var shots := 0
var look_at: Node3D = null
var hold_yaw := -PI / 2.0
var hold_pitch := 0.0
var out := ""

## Holds the view where the script wants it (a pad lying on the desk would let it drift).
func _hold_look() -> void:
	if look_at != null and is_instance_valid(look_at):
		var to := look_at.global_position + Vector3(0, 1.1, 0) - (p.global_position + Vector3(0, 1.6, 0))
		hold_yaw = atan2(-to.x, -to.z)
		hold_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	p.set_look(hold_yaw, hold_pitch)

func _wait(s: float) -> void:
	await _secs(s, _hold_look)

func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	shots += 1
	img.save_png("%s/z5play_%02d_%s.png" % [out, shots, label])

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	await process_frame
	zm = root.get_node("ZombieMode")
	root.get_node("GameState").no_sickness = true
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	p = get_first_node_in_group("player") as CharacterBody3D
	var spawner: Node = block.spawner
	block.surge.enabled = false
	zm.health = 1e9
	var h: Node = p.get_node("WeaponHolder")
	h.give(load("res://weapons/pistol.tres"))
	h.refill_all()
	p.global_position = BASE
	p.set_look(-PI / 2.0, 0.0)
	# Round 1 opens: its banner, then the street in front of the player.
	await _wait(1.2)
	await _snap("round1_banner")
	await _wait(2.5)
	await _snap("round1_street")
	# A reload of each gun: half a magazine (tactical) for most, empty for the AR, the shotgun and the sniper.
	spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	var only_climb := OS.get_cmdline_user_args().has("climb")
	for g in ([] if only_climb else GUNS):
		h.give(load("res://weapons/%s.tres" % g))
		h.refill_all()
		await _wait(1.4)  # the first raise
		await _snap("%s_raise" % g)
		var empty: bool = g in ["ar", "shotgun", "sniper"]
		h.mag = 0 if empty else maxi(h.current.mag_size / 2, 1)
		await _wait(0.3)
		if not h.reload():
			print("DEMO reload refused for ", g)
			continue
		var dur: float = h.reload_left()
		print("DEMO %s reload %s %.2f s" % [g, "empty" if empty else "tactical", dur])
		var last := 0.0
		for f in [0.12, 0.32, 0.52, 0.72, 0.92]:
			await _wait(maxf(dur * f - last, 0.03))
			last = dur * f
			await _snap("%s_reload_%d" % [g, int(f * 100)])
		await _wait(maxf(dur - last, 0.0) + 0.3)
	# A zombie climbing out of the street ahead.
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	await _wait(1.2)
	var land := BASE + Vector3(6.0, 0.0, 0.0)
	var rz = spawner.spawn_entrance("walker", {"type": "rise", "pos": land, "start": land + Vector3(0, -2.1, 0), "out": Vector3.RIGHT, "fall": 0.0, "node": null, "roof": false})
	look_at = rz
	h.aiming = false
	Input.action_release("fire")
	for i in 8:
		await _wait(0.5)
		await _snap("climb_%d" % i)
	# Hit reactions: the hits we choose, then bullets.
	var hurt := 0
	for part in ["head", "upper_arm_l", "lower_leg_l", "torso"]:
		if not is_instance_valid(rz) or int(rz.get("state")) >= 6:
			break
		rz.take_hit(part, 12.0, Vector3.LEFT, null)
		hurt += 1
		await _wait(0.2)
		await _snap("hit_%s_a" % part)
		await _wait(0.35)
		await _snap("hit_%s_b" % part)
		await _wait(0.5)
	look_at = null
	# The round, with the horde.
	spawner.enabled = true
	var t := 0.0
	while t < 40.0:
		await _wait(0.5)
		t += 0.5
		_fight(h, 45.0)
		if int(t * 2) % 8 == 0:
			await _snap("round_fight_%d" % int(t))
	Input.action_release("fire")
	print("DEMO done: %d snaps, round %d, kills %d" % [shots, zm.round, zm.kills])
	zm.leave()
	quit()

func _fight(h: Node, reach: float) -> void:
	if h.mag <= 3:
		h.refill_all()
	if not _shoot_nearest(h, reach):
		Input.action_release("fire")
		p.set_look(float(p.get("_look_yaw")) + 0.01, lerpf(float(p.get("_look_pitch")), 0.0, 0.05))
