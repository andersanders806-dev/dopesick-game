extends SceneTree
## Dev helper (SHIP 16G): the review-I1 gate for the RPG's blast, old against new in ONE run. Dead Block in a window on Low, a
## round-12 horde, the AA-12 dumping its drum with the fire action held and a rocket every 6 s (as dev-tools/perf_b2.gd does),
## 60 s with the NEW shared explosion (fx/Explosion.gd) and then 60 s with the OLD blast (the RPG's own fire, smoke and grit as the
## B2 build drew them: 18 + 12 + 36 alpha quads and a 11 m flash, rebuilt here from the old fx/Rocket.gd), the same sound in both.
## Gate: <= 7 frames over 25 ms a minute, max <= 40 ms, against its own paired floor (perf_ship4.gd `floor`).
##   flock -x .perf.lock flock .gpu.lock flatpak run org.godotengine.Godot --path . --resolution 1280x720 --windowed \
##     -s res://dev-tools/perf_16g.gd -- --no-sick [--secs=60] [--grenades]
## --grenades: a Mk 2 frag thrown into the horde every 6 s instead of the rocket (new explosion only).
const RPG_EVERY := 6.0
var _legacy: Array = []
var _legacy_flash: OmniLight3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset.LOW)
	gfx.set_first_person(true)
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	gfx.set_first_person(true)
	var p := get_first_node_in_group("player") as Node3D
	p.global_position = Vector3(-20, 0, -3)
	p.set_look(-PI / 2.0, 0.0)
	var h: Node = p.get_node("WeaponHolder")
	block.spawner.round_no = 12
	block.spawner.enabled = true
	h.slots = [null, null]
	h.give(load("res://weapons/aa12.tres"))
	h.give(load("res://weapons/rpg.tres"))
	h.select(0)
	h.refill_all()
	var secs := 60.0
	var grenades := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
		if a == "--grenades":
			grenades = true
	var boom: Node = load("res://fx/Explosion.gd").of(current_scene)
	_build_legacy()
	h.exploded.connect(func(at: Vector3, _r: float): _legacy_blast(at))
	Input.action_press("fire")
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) < 8.0e6:
		await process_frame
		_keep_alive(zm, h)
	var out := ""
	for phase in (["new"] if grenades else ["new", "old"]):
		boom.draw_enabled = phase == "new"
		_legacy_on = phase == "old"
		var r := await _phase(phase, secs, h, p, zm, grenades)
		out += r
		print(r)
	Input.action_release("fire")
	var dir := ProjectSettings.globalize_path("res://.pilot/ship16g")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + ("/perf_16g_grenades.txt" if grenades else "/perf_16g.txt"), FileAccess.WRITE)
	f.store_string(out)
	f.close()
	quit()

var _legacy_on := false

func _phase(phase: String, secs: float, h: Node, p: Node3D, zm: Node, grenades: bool) -> String:
	var frames: Array = []
	var last := Time.get_ticks_usec()
	var start := last
	var next_rpg := RPG_EVERY
	var rockets := 0
	var zmax := 0
	var slow_at: Array = []
	var shots0: int = h.feel.shots
	while float(Time.get_ticks_usec() - start) < secs * 1.0e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		if frames[-1] > 25.0:
			slow_at.append("%.2fs:%.0fms" % [float(now - start) / 1.0e6, frames[-1]])
		last = now
		_keep_alive(zm, h)
		zmax = maxi(zmax, get_nodes_in_group("zombies").size())
		var t := float(now - start) / 1.0e6
		if t >= next_rpg:
			next_rpg += RPG_EVERY
			var cam: Camera3D = p.get("camera")
			if grenades:
				h.set_grenades(4)
				h.lethal.press()
				h.lethal.release()
			else:
				h._launch(cam.global_position, -cam.global_transform.basis.z, h.slot_data(1))
			rockets += 1
	var slow := 0
	var worst := 0.0
	var sum := 0.0
	for f in frames:
		sum += f
		worst = maxf(worst, f)
		if f > 25.0:
			slow += 1
	var sorted := frames.duplicate()
	sorted.sort()
	return "[%s blast] %s, round-12 horde, AA-12 + %s every %.0f s, Low, windowed: %d frames in %.0f s, %d blasts, up to %d zombies, mean %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.1f ms, frames > 25 ms: %d (gate <= 7 per minute, max <= 40 ms); slow at %s\n" % [
		phase, "frags" if grenades else "RPG", "a frag" if grenades else "a rocket", RPG_EVERY, frames.size(), secs, rockets, zmax, sum / frames.size(), sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], worst, slow, slow_at]

func _keep_alive(zm: Node, h: Node) -> void:
	zm.health = 100.0
	if h.mag < 4:
		h.refill_all()

# --- The B2 build's blast, as it was (fx/Rocket.gd at 682f2c6): 18 fire, 12 smoke, 36 grit quads, a flash of 14 over 11 m ----------

func _build_legacy() -> void:
	var ImpactFX = load("res://fx/ImpactFX.gd")
	var fire_mat = ImpactFX._particle_material(Color(1.0, 0.65, 0.3, 1.0), true, true)
	var cloud_mat = ImpactFX._particle_material(Color(1.0, 1.0, 1.0, 1.0), false, false)
	var grit_mat = ImpactFX._particle_material(Color(1.0, 1.0, 1.0, 1.0), false, false)
	for spec in [[fire_mat, 18, 0.7, 1.8, 3.2, 2.0, 7.0, 180.0, Vector3(0, 2.5, 0), Color(1.0, 0.9, 0.62, 1.0), Color(0.7, 0.22, 0.04, 0.0), 1.6],
			[cloud_mat, 12, 2.8, 1.9, 3.2, 1.2, 3.6, 60.0, Vector3(0, 1.3, 0), Color(0.46, 0.43, 0.4, 0.8), Color(0.32, 0.31, 0.3, 0.0), 2.0],
			[grit_mat, 36, 1.2, 0.07, 0.17, 6.0, 15.0, 75.0, Vector3(0, -12.0, 0), Color(0.42, 0.37, 0.32, 1.0), Color(0.3, 0.27, 0.24, 0.0), 0.0]]:
		var pr := CPUParticles3D.new()
		pr.emitting = false
		pr.one_shot = true
		pr.amount = spec[1]
		pr.lifetime = spec[2]
		pr.explosiveness = 0.95
		pr.local_coords = false
		pr.direction = Vector3.UP
		pr.spread = spec[7]
		pr.initial_velocity_min = spec[5]
		pr.initial_velocity_max = spec[6]
		pr.gravity = spec[8]
		pr.damping_min = 2.0
		pr.damping_max = 4.0
		pr.scale_amount_min = spec[3]
		pr.scale_amount_max = spec[4]
		if spec[11] > 0.0:
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 0.5))
			curve.add_point(Vector2(1.0, minf(0.5 + spec[11] * 0.5, 1.0)))
			pr.scale_amount_curve = curve
		var g := Gradient.new()
		g.set_color(0, spec[9])
		g.set_color(1, spec[10])
		pr.color_ramp = g
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.material = spec[0]
		pr.mesh = q
		pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		current_scene.add_child(pr)
		_legacy.append(pr)
	_legacy_flash = OmniLight3D.new()
	_legacy_flash.light_color = Color(1.0, 0.7, 0.4)
	_legacy_flash.light_energy = 0.0
	_legacy_flash.omni_range = 11.0
	_legacy_flash.shadow_enabled = false
	_legacy_flash.visible = false
	current_scene.add_child(_legacy_flash)

var _legacy_after := 0.0

func _legacy_blast(at: Vector3) -> void:
	if not _legacy_on:
		return
	for pr in _legacy:
		(pr as CPUParticles3D).global_position = at
		(pr as CPUParticles3D).restart()
	_legacy_flash.global_position = at + Vector3(0, 0.8, 0)
	_legacy_flash.visible = true
	_legacy_flash.light_energy = 14.0
	_legacy_after = 2.8

func _process(delta: float) -> bool:
	if _legacy_after > 0.0:
		_legacy_after -= delta
		_legacy_flash.light_energy = maxf(_legacy_flash.light_energy - delta * 60.0, 0.0)
		if _legacy_flash.light_energy <= 0.0:
			_legacy_flash.visible = false
	return false
