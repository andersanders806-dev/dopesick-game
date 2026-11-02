extends SceneTree
## Dev helper: how long the frames are around the FIRST of each kind of event in a zombie run (windowed, Low,
## first person). The first kill / sever / head pop / ragdoll / decal / quake / tsunami used to cost a long
## frame (a shader or pipeline compiling, a resource loading, nodes made); fx/Prewarm.gd draws them all once
## behind the loading fade. This logs the frame time (process_frame to process_frame) for a window after each
## event and prints one line per event: worst frame, frames over 50 ms, then the worst three in ms.
## Only one windowed Godot at a time.
##
##   flatpak run org.godotengine.Godot --path . --socket=wayland --display-driver wayland \
##     -s res://dev-tools/hitch_probe.gd -- [Low|Medium|High] [noprewarm]
##
## `noprewarm` skips the prewarm (fx/Prewarm.gd) for the BEFORE numbers.

var _block: Node
var _holder: Node
var _player: Node3D
var _label := "load"
var _dts: Dictionary = {}
var _order: Array[String] = []
var _last := 0
var _running := true
var _aim_to := Vector3.RIGHT
var _target: Node
var _prewarm: Node
var _calls: Dictionary = {}
var _pw_info := ""
var _pw_log: Array = []
var _zm: Node

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var preset: String = args[0] if args.size() > 0 and args[0] in ["Low", "Medium", "High"] else "Low"
	if args.has("noprewarm"):
		Engine.set_meta("no_prewarm", true)
	_run(preset)

func _frame(label: String, n: int) -> void:
	_label = label

## Waits n frames, logging each frame's time under the current label.
func _wait(n: int) -> void:
	for i in n:
		await process_frame
		if _zm != null and is_instance_valid(_zm):
			_zm.health = _zm.MAX_HEALTH
		var now := Time.get_ticks_usec()
		var dt := (now - _last) / 1000.0
		_last = now
		if not _dts.has(_label):
			_dts[_label] = []
			_order.append(_label)
		_dts[_label].append(dt)

## Marks an event: the frames from here on belong to it for `n` frames.
func _event(label: String, n: int, action: Callable) -> void:
	await _wait(8)
	_label = label
	_last = Time.get_ticks_usec()
	var c0 := Time.get_ticks_usec()
	action.call()
	_calls[label] = (Time.get_ticks_usec() - c0) / 1000.0
	await _wait(n)

func _run(preset: String) -> void:
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.PRESET_NAMES.find(preset))
	var zm := root.get_node("ZombieMode")
	zm.begin(true)
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://world/City3D.tscn")
	_last = Time.get_ticks_usec()
	_label = "load"
	var frames_to_ready := 0
	while true:
		await process_frame
		frames_to_ready += 1
		if current_scene != null and current_scene.has_node("ZombieBlock") and current_scene.get_node("ZombieBlock").purchases_ready:
			break
		if frames_to_ready > 2000:
			print("HITCH: the block never came up")
			quit(1)
			return
	var load_ms := Time.get_ticks_msec() - t0
	_block = current_scene.get_node("ZombieBlock")
	_prewarm = _block.get_node_or_null("Prewarm")
	_zm = zm
	gfx.set_process(false)
	root.scaling_3d_scale = 1.0
	_label = "settle"
	_last = Time.get_ticks_usec()
	await _wait(60)
	# The prewarm (when on) runs behind the black of a scene change in the game; here, behind this wait.
	_label = "prewarm"
	while _prewarm != null and is_instance_valid(_prewarm) and not _prewarm.done and not Engine.has_meta("no_prewarm"):
		await _wait(1)
	_label = "settle"
	if _prewarm != null and is_instance_valid(_prewarm) and not Engine.has_meta("no_prewarm"):
		_pw_info = "critical %d ms (screen black), all %d ms, done %s" % [_prewarm.critical_ms, _prewarm.ms, str(_prewarm.done)]
		_pw_log = _prewarm.log.duplicate()
	await _wait(60)
	_player = get_first_node_in_group("player") as Node3D
	_holder = _player.get_node("WeaponHolder")
	_block.surge.enabled = false
	_block.tsunami.auto = false
	_block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	_player.global_position = Vector3(-20, 0, -3)
	_player.set_look(-PI / 2.0, 0.0)
	_holder.no_spread = true
	_holder.aim_source = func():
		var eye: Vector3 = _player.global_position + Vector3(0, 1.6, 0)
		if _target != null and is_instance_valid(_target):
			_target.sync_hitboxes()
			var c: Vector3 = (_target.hitboxes["torso"].get_child(0) as Node3D).global_position
			return [eye, c - eye]
		return [eye, _aim_to]
	_holder.give(load("res://weapons/pistol.tres"))
	_holder.refill_all()
	await _wait(30)
	var ar: Resource = load("res://weapons/ar.tres")
	_holder.no_spread = true

	# --- Events, in the order a run meets them ---------------------------------------------------
	await _event("quiet", 120, func(): pass)
	# The round starts; the first of the dead comes in by an entrance.
	await _event("round1", 420, func():
		_block.spawner.enabled = true
		_block.spawner.time_scale = 0.5
		zm.round = 0
		zm.start_round())
	_block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	zm.health = zm.MAX_HEALTH
	_player.global_position = Vector3(-20, 0, -3)
	_player.set_look(-PI / 2.0, 0.0)
	# The assault rifle in the hands (its optic, its glass and dot shaders), then a shot at the wall.
	await _event("gun_ar", 40, func():
		_holder.give(ar)
		_holder.refill_all()
		_holder._cooldown = 0.0)
	_aim_to = Vector3(0, 0, -1)
	await _event("shot_wall", 40, func(): _pull())
	_aim_to = Vector3.RIGHT
	# A zombie to shoot.
	var zs: Array = []
	await _event("spawn", 40, func():
		_block.spawner.round_no = 3
		for k in 4:
			var z = _block.spawner.spawn_one("walker", Vector3(-12.0 + k * 3.0, 0.0, -3.0 + k * 0.4))
			z.set_physics_process(false)
			zs.append(z))
	_target = zs[0]
	_holder.mag = 8
	_holder._cooldown = 0.0
	# First hit (not a kill): blood, wound, number.
	await _event("hit", 40, func():
		_target.health = _target.max_health * 3.0
		_pull())
	_holder._cooldown = 0.0
	# The first kill: ragdoll, decals; and 4 s on for the pool under the corpse.
	await _event("kill", 20, func():
		# (A small max health so that the shot is a real hit: 15 % of it throws the body as a ragdoll.)
		_target.max_health = 20.0
		_target.health = 1.0
		_pull())
	print("HITCH diag kill: health ", _target.health, " state ", _target.state, " ragdolls ", Gore_of().ragdolls.started, " decals ", Gore_of().decals_shown())
	await _event("kill_settle", 280, func(): pass)
	print("HITCH diag settle: pools ", Gore_of().pools_shown(), " decals ", Gore_of().decals_shown())
	# A limb comes off.
	_target = zs[1]
	var gore := Gore_of()
	await _event("sever", 60, func():
		_target.take_hit("lower_arm_l", _target.max_health * 0.5, Vector3.RIGHT, ar))
	await _event("sever_settle", 240, func(): pass)
	# A head pops.
	await _event("headpop", 60, func():
		zs[2].take_hit("head", zs[2].max_health * 5.0, Vector3.RIGHT, ar))
	await _event("headpop_settle", 240, func(): pass)
	# A claw lands: blood on the screen.
	await _event("screen_blood", 40, func(): gore.screen_blood(1.0))
	# The other guns' first shot.
	for id in ["smg", "shotgun", "magnum", "sniper", "lmg", "wonder"]:
		await _event("gun_" + id, 40, func():
			_holder.give(load("res://weapons/%s.tres" % id))
			_holder.refill_all()
			_holder._cooldown = 0.0)
		await _event("shot_" + id, 40, func():
			_aim_to = Vector3(0, 0, -1)
			_pull()
			_aim_to = Vector3.RIGHT)
	# RICHTER 8.0.
	await _event("quake", 480, func():
		_block.quake.debug_surge(0.6, 5.0))
	await _event("quake_end", 360, func(): pass)
	# The tsunami.
	var ts = _block.tsunami
	await _event("tsunami_start", 180, func(): print("HITCH diag tsunami start -> ", ts.start(), " phase ", ts.phase, " drowned ", ts.drowned.size()))
	await _event("tsunami_24", 120, func(): ts.skip_to(24.0))
	await _event("tsunami_14", 120, func(): ts.skip_to(14.0))
	await _event("tsunami_04", 120, func(): ts.skip_to(4.0))
	await _event("tsunami_hit", 240, func(): ts.skip_to(0.05))
	await _wait(60)
	_report(load_ms, preset)
	zm.leave()
	quit()

## One trigger pull, ready to go off.
func _pull() -> bool:
	_holder._cooldown = 0.0
	if _holder.reloading:
		_holder._cancel_reload()
	_holder.mag = maxi(_holder.mag, 5)
	var ok: bool = _holder.fire()
	print("HITCH diag pull: fired ", ok, " mag ", _holder.mag, " swap ", _holder._swap_left, " reloading ", _holder.reloading, " target ", _target.health if _target != null else "-", " ", _target.state if _target != null else "-")
	return ok

func Gore_of() -> Node:
	return (load("res://fx/gore/Gore.gd") as GDScript).of(_player)

func _report(load_ms: int, preset_name := "Low") -> void:
	print("HITCH probe: %s, load to ready %d ms%s" % [preset_name, load_ms, " (prewarm OFF)" if Engine.has_meta("no_prewarm") else ""])
	if _pw_info != "":
		print("HITCH prewarm: ", _pw_info)
		for e in _pw_log:
			print("HITCH   prewarm step %-34s %6.1f ms" % [e[0], e[1]])
	var worst_all := 0.0
	var over := 0
	for l in _order:
		var a: Array = _dts[l]
		if l == "load":
			continue
		var s := a.duplicate()
		s.sort()
		var med: float = s[s.size() / 2]
		var top := s.slice(maxi(s.size() - 3, 0))
		top.reverse()
		var n50 := 0
		for v in a:
			if v > 50.0:
				n50 += 1
		if l != "settle" and l != "prewarm":
			worst_all = maxf(worst_all, s[s.size() - 1])
			over += n50
		print("HITCH %-16s frames %4d  median %5.1f  worst %6.1f  >50ms: %d  call %5.1f ms  top3 %s" % [l, a.size(), med, s[s.size() - 1], n50, _calls.get(l, 0.0), str(top.map(func(v): return snappedf(v, 0.1)))])
	print("HITCH TOTAL worst %.1f ms, frames > 50 ms: %d" % [worst_all, over])
