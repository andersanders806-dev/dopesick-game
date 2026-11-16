extends SceneTree
## SHIP item 4's perf probe: one file for every scenario the gate names, one result line and one csv each.
## Needs a real window (never --headless), 1280x720, Low preset, laptop mode, withdrawal off except in `sick`.
##   flock /home/anders/dopesick-game/.gpu.lock flatpak run org.godotengine.Godot --path . --resolution 1280x720 \
##     -s res://dev-tools/perf_ship4.gd -- --no-sick <scenario> [secs=60] [tag=trunk] [night]
## Scenarios:
##   street            sprint along Main Street (the perf_street_walk route), day
##   sick              the same walk with withdrawal on (craving held at 3: the sick grade, the shakes)
##   room:<Scene>      stand 3 m in front of the nearest door inside DiveBar3D / StorePharmacy3D / StoreSupermarket3D
##   shop              the street looking at the corner shop's door (perf_door_shop_probe)
##   horde             Dead Block, round 15, the real spawner, the player walks and shoots (god mode)
##   ghetto            Ghetto Wars, wave 6, the real crew, the player walks and shoots (god mode)
##   kart              the kart race from the call to start() through the countdown and into the race
##   go:street_shop    street -> corner shop through SceneLoader.go, recorded from the call
##   go:shop_street    corner shop -> street
##   go:title_story    title screen's "New run"
##   go:title_zombies  title screen's "Zombies"
##   title             the title screen standing still (prewarm / music / backdrop)
##   floor             the title after its warm-up and prefetch are done, no input: the machine's noise floor
## Output: .pilot/ship4/<scenario>_<tag>.csv (frame ms, gpu ms, fade alpha) and .png, one RESULT line on stdout and
## in .pilot/ship4/results.txt. Every frame over 25 ms prints a SLOW line with what changed in it (pipelines
## compiled, resources and nodes made, process and physics ms) and a guess at the cause.
const SLOW_MS := 25.0
const _GUN_SOUNDS := preload("res://weapons/GunSounds.gd")
const _TITLE_WARM := preload("res://fx/TitleWarm.gd")

var scenario := "street"
var tag := "run"
var secs := 60.0
var night := false
var out_dir := ""

var gfx: Node
var gs: Node
var zm: Node
var vp: RID
var extra_vp: RID
var dts: PackedFloat32Array = PackedFloat32Array()
var gpus: PackedFloat32Array = PackedFloat32Array()
var fades: PackedFloat32Array = PackedFloat32Array()
var scales := 0.0
var recording := false
var last_us := 0
var t0_us := 0
var slow_n := 0
var slow_visible := 0
## The longest frame while the screen was not black (the gate's max; frames behind black do not count).
var vis_max := 0.0
var fired_ok := 0
var fired_try := 0
var hitches: Array = []
var _prev := {}
var _added := {}
## When the last frame's drawing began and ended (RenderingServer signals): the frame splits into scripts and
## physics (process_frame -> pre_draw), the draw (pre_draw -> post_draw), and the tail (vsync wait, present).
var _t_pre := 0
var _t_post := 0
var phase := ""
## exp=a,b,c: switch a cost off to measure it (a bisect, not part of any gate): nozombies, noshadowz (the dead and
## the crew cast no shadow), nodecals, norain, nosun (no sun shadow), noparticles, nolights, nofog, nopost.
## x=<metres>: the street scenario stands there (looking along the street, a slow sway) instead of walking.
## scale=<0.3..1>: pins the 3D render scale (the governor is overridden every frame): a bisect for what is pixel-bound.
var fixed_scale := 0.0
var stand_x := INF
## viatitle: the run starts the way the game does, on the title screen for 8 s (its prefetch and its shader warm-up run).
var via_title := false
var race: Node = null
var _prev_fa := 0.0
var exps: PackedStringArray = PackedStringArray()
var shot_at_s := -1.0
var shot_done := false
var _censused := false
## ab=<what>: every 90 frames the named cost is switched off and on again, and the GPU time, frame time and the
## renderer's counters are summed per state: an A/B inside one run, so the machine's drift (the iGPU's clock follows
## the CPU load) cancels. what: facades, props, mm, decals, lights, particles, zombies, hud, fog, far60, lod8.
var ab_what := ""
var ab_on := true
var ab_n := [0, 0]
var ab_gpu := [0.0, 0.0]
var ab_ms := [0.0, 0.0]
var ab_prims := [0.0, 0.0]
var ab_calls := [0.0, 0.0]
var ab_objs := [0.0, 0.0]
var _ab_nodes: Array = []
var _ab_saved := {}
var seg_scripts: PackedFloat32Array = PackedFloat32Array()
var seg_draws: PackedFloat32Array = PackedFloat32Array()
var cnt_prims := 0.0
var cnt_calls := 0.0
var cnt_objs := 0.0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := str(a)
		if s.begins_with("secs="):
			secs = float(s.substr(5))
		elif s.begins_with("tag="):
			tag = s.substr(4)
		elif s == "night":
			night = true
		elif s.begins_with("scale="):
			fixed_scale = float(s.substr(6))
		elif s.begins_with("ab="):
			ab_what = s.substr(3)
		elif s == "nomerge":
			Engine.set_meta("no_merge", true)
		elif s == "nobatch":
			Engine.set_meta("no_batch", true)
		elif s == "viatitle":
			via_title = true
		elif s.begins_with("x="):
			stand_x = float(s.substr(2))
		elif s.begins_with("exp="):
			exps = s.substr(4).split(",")
		elif not s.begins_with("--"):
			scenario = s
	out_dir = ProjectSettings.globalize_path("res://.pilot/ship4")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

## How black the screen is: SceneLoader's fade, the title's black ("GoBlack") and the kart race's veil.
func _fade_alpha() -> float:
	var a := 0.0
	var sl := root.get_node_or_null("SceneLoader")
	if sl != null:
		var b: ColorRect = sl.get("_black")
		a = b.color.a if b != null else 0.0
	if current_scene != null:
		var gb := current_scene.get_node_or_null("GoBlack") as ColorRect
		if gb != null:
			a = maxf(a, gb.color.a)
	if race != null and is_instance_valid(race) and race.get("_veil") != null and is_instance_valid(race.get("_veil")):
		var rb := (race.get("_veil") as CanvasLayer).get_child(0) as ColorRect
		if rb != null:
			a = maxf(a, rb.color.a)
	return a

func _info(i: int) -> int:
	return RenderingServer.get_rendering_info(i as RenderingServer.RenderingInfo)

func _snapshot() -> Dictionary:
	var ri := RenderingServer
	return {
		"mesh": _info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surf": _info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw": _info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"spec": _info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
		"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"mem": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}

func _on_node_added(n: Node) -> void:
	var k := n.get_class()
	_added[k] = int(_added.get(k, 0)) + 1

func _begin_recording() -> void:
	vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _t_post = Time.get_ticks_usec())
	_prev = _snapshot()
	_apply_exps()
	recording = true
	t0_us = Time.get_ticks_usec()
	last_us = t0_us
	shot_at_s = secs * (0.9 if scenario.begins_with("go:") else 0.5)
	print("== %s [%s] %.0f s, nodes %d" % [scenario, tag, secs, _prev["nodes"]])

## Call once per frame after `await process_frame` while recording. Returns this frame's ms.
func _tick() -> float:
	if fixed_scale > 0.0 and gfx != null:
		gfx.render_scale = fixed_scale
		root.scaling_3d_scale = fixed_scale
	var now := Time.get_ticks_usec()
	var dt := (now - last_us) / 1000.0
	var seg_script := (_t_pre - last_us) / 1000.0
	var seg_draw := (_t_post - _t_pre) / 1000.0
	var seg_tail := (now - _t_post) / 1000.0
	last_us = now
	if not recording:
		return dt
	var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	if extra_vp.is_valid():
		g += RenderingServer.viewport_get_measured_render_time_gpu(extra_vp)
	var fa := _fade_alpha()
	dts.append(dt)
	seg_scripts.append(seg_script)
	seg_draws.append(seg_draw)
	cnt_prims += _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	cnt_calls += _info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	cnt_objs += _info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	gpus.append(g)
	fades.append(fa)
	scales += root.scaling_3d_scale
	_ab_tick(g, dt)
	var cur := _snapshot()
	var fa_before := _prev_fa
	_prev_fa = fa
	if fa_before < 0.5:
		vis_max = maxf(vis_max, dt)
	if dt > SLOW_MS:
		slow_n += 1
		# What was on the screen while the frame stalled is what the previous frame left there.
		if fa_before < 0.5:
			slow_visible += 1
		var proc: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var nav: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
		var d_draw: int = cur["draw"] - _prev["draw"]
		var d_pipes: int = (cur["mesh"] - _prev["mesh"]) + (cur["surf"] - _prev["surf"]) + d_draw + (cur["spec"] - _prev["spec"])
		var d_res: int = cur["res"] - _prev["res"]
		var d_nodes: int = cur["nodes"] - _prev["nodes"]
		var d_mem: int = cur["mem"] - _prev["mem"]
		var cause := "unknown (cpu/os)"
		if d_draw > 0 or d_pipes > 0:
			cause = "shader/pipeline compile"
		elif g > SLOW_MS:
			cause = "gpu"
		elif d_res > 4 or d_mem > 4000000:
			cause = "resource load"
		elif d_nodes > 25:
			cause = "spawn/instantiate"
		elif phys > 12.0:
			cause = "physics"
		elif nav > 4.0:
			cause = "navigation"
		elif proc > 20.0:
			cause = "script/process"
		var added := ""
		var keys := _added.keys()
		keys.sort_custom(func(a, b): return _added[a] > _added[b])
		for i in mini(4, keys.size()):
			added += "%s x%d " % [keys[i], _added[keys[i]]]
		var voice := root.get_node_or_null("Voice")
		var vj := 0
		if voice != null and voice.get("_jobs") != null:
			vj = (voice.get("_jobs") as Array).size()
		# What the scene loader has on its worker threads (a threaded load landing is a draw-segment stall).
		var ld := ""
		var sl := root.get_node_or_null("SceneLoader")
		if sl != null and sl.get("_loading") != null:
			for k in (sl.get("_loading") as Dictionary).keys():
				ld += String(k).get_file() + " "
		var line := "  SLOW %.1f ms (scripts+physics %.1f, draw %.1f, tail %.1f) t=%.1f s [%s] black %.2f gpu %.1f proc %.1f phys %.1f nav %.1f | pipes +%d (draw +%d) res %+d nodes %+d mem %+.1f MB voice-jobs %d | added: %s=> %s | loading: %s" % [
			dt, seg_script, seg_draw, seg_tail, (now - t0_us) / 1e6, phase, fa_before, g, proc, phys, nav, d_pipes, d_draw, d_res, d_nodes, d_mem / 1e6, vj, added, cause, ld]
		print(line)
		hitches.append(line)
	_added.clear()
	_prev = cur
	return dt

func _finish() -> void:
	var n := dts.size()
	if n < 10:
		print("RESULT %s [%s] no frames" % [scenario, tag])
		quit()
		return
	var sorted := Array(dts)
	sorted.sort()
	var gsum := 0.0
	for g in gpus:
		gsum += g
	var fsum := 0.0
	for d in dts:
		fsum += d
	var gs2 := Array(gpus)
	gs2.sort()
	var line := "RESULT %s [%s] frames %d (%.1f s) | gpu mean %.2f p95 %.2f | frame mean %.2f p50 %.2f p95 %.2f p99 %.2f max %.1f | >25ms %d (visible %d) | scale %.2f | vmax %.1f" % [
		scenario, tag, n, fsum / 1000.0, gsum / n, gs2[int(n * 0.95)], fsum / n, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[-1], slow_n, slow_visible, scales / n, vis_max]
	print(line)
	var t0i := int(n * 0.4)
	var tg := 0.0
	var tf := 0.0
	var ts := 0.0
	var td := 0.0
	for i in range(t0i, n):
		tg += gpus[i]
		tf += dts[i]
		ts += seg_scripts[i]
		td += seg_draws[i]
	var m := float(n - t0i)
	_ab_print()
	print("GUNWARM gun sound files cached %d, sets %d, title warm-up %d ms" % [_GUN_SOUNDS._files.size(), _GUN_SOUNDS._sets.size(), _TITLE_WARM.took_ms])
	print("COUNTERS per frame: primitives %.0f draw calls %.0f objects %.0f" % [cnt_prims / n, cnt_calls / n, cnt_objs / n])
	print("TAIL gpu mean %.2f frame mean %.2f scripts+physics %.2f draw %.2f (the last 60%% of the run)" % [tg / m, tf / m, ts / m, td / m])
	var path := out_dir + "/results.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	for h in hitches:
		f.store_line(h)
	f.close()
	var c := FileAccess.open("%s/%s_%s.csv" % [out_dir, scenario.replace(":", "-"), tag], FileAccess.WRITE)
	c.store_line("ms,gpu,fade")
	for i in n:
		c.store_line("%.2f,%.2f,%.2f" % [dts[i], gpus[i], fades[i]])
	c.close()
	quit()

## One picture at the middle of the run (the save is a stall of its own: not counted).
func _maybe_shot() -> void:
	if shot_done or not recording:
		return
	if (Time.get_ticks_usec() - t0_us) / 1e6 >= shot_at_s:
		shot_done = true
		var img := root.get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out_dir, scenario.replace(":", "-"), tag])
		last_us = Time.get_ticks_usec()

# ---------------------------------------------------------------------------------------------

func _setup_story(hour: int) -> void:
	await process_frame
	gfx = root.get_node("Graphics")
	gs = root.get_node("GameState")
	zm = root.get_node("ZombieMode")
	gfx.set_first_person(true)
	gfx.set_preset(0)
	gfx.set_laptop_mode(true)
	root.get_node("Survival").enabled = false
	root.get_node("Headlines").forced = "quiet"
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = hour * 60
	if via_title:
		change_scene_to_file("res://ui/TitleScreen.tscn")
		var w0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - w0 < 8e6:
			await process_frame

func _apply_exps() -> void:
	if exps.is_empty() or current_scene == null:
		return
	if "norain" in exps:
		gfx.rain_fx = false
	if "noocc" in exps:
		root.use_occlusion_culling = false
	if "nohud" in exps:
		for l in root.find_children("*", "CanvasLayer", true, false):
			if l.name != "SceneLoader" and l.get_parent() != root.get_node_or_null("SceneLoader"):
				(l as CanvasLayer).visible = false
	if "nopostfx" in exps:
		for c in root.find_children("PostFX", "", true, false):
			c.visible = false
	if "nofsr" in exps:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if "noaa" in exps:
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		root.msaa_3d = Viewport.MSAA_DISABLED
	for we in current_scene.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env == null:
			continue
		if "noglow" in exps:
			env.glow_enabled = false
		if "noadj" in exps:
			env.adjustment_enabled = false
		if "notonemap" in exps:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		if "nosky" in exps:
			env.background_mode = Environment.BG_COLOR
			env.sky = null
	for n in current_scene.find_children("*", "", true, false):
		if "nodecals" in exps and n is Decal:
			n.visible = false
		elif "noparticles" in exps and (n is GPUParticles3D or n is CPUParticles3D):
			n.visible = false
		elif "nolights" in exps and n is Light3D and not n is DirectionalLight3D:
			n.visible = false
		elif "nofade" in exps and n is GeometryInstance3D:
			(n as GeometryInstance3D).visibility_range_begin = 0.0
			(n as GeometryInstance3D).visibility_range_end = 0.0
			(n as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		elif "nosun" in exps and n is DirectionalLight3D:
			n.shadow_enabled = false
		elif "noshadowz" in exps and n is MeshInstance3D and (n.is_in_group("zombies") or n.get_parent() != null and (n.get_parent().is_in_group("zombies") or n.get_parent().is_in_group("gangsters"))):
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for hide in ["facades", "mm", "cellprops"]:
		if ("no" + hide) in exps:
			for n in current_scene.get_children():
				var nm := String(n.name)
				if hide == "facades" and nm == "Facades":
					(n as Node3D).visible = false
				elif hide == "cellprops" and nm.begins_with("Cell_"):
					for c in n.get_children():
						if c is Node3D and not c is StaticBody3D and not c is MultiMeshInstance3D and not c is OccluderInstance3D:
							(c as Node3D).visible = false
				elif hide == "mm":
					for c in n.find_children("*", "MultiMeshInstance3D", true, false):
						(c as Node3D).visible = false
	for e in exps:
		if e.begins_with("lod"):
			root.mesh_lod_threshold = float(e.substr(3))
		if e.begins_with("far") and root.get_camera_3d() != null:
			root.get_camera_3d().far = float(e.substr(3))
	if "nofog" in exps:
		var we := current_scene.find_children("*", "WorldEnvironment", true, false)
		for w in we:
			(w as WorldEnvironment).environment.fog_enabled = false
			(w as WorldEnvironment).environment.volumetric_fog_enabled = false
	if "zfreeze" in exps or "zhide" in exps or "zanim" in exps or "zshape" in exps:
		for z in get_nodes_in_group("zombies"):
			if "zfreeze" in exps:
				z.set_physics_process(false)
				z.set_process(false)
			if "zhide" in exps:
				(z.get("_model_root") as Node3D).visible = false
			if "zanim" in exps and z.get("_anim_player") != null:
				(z.get("_anim_player") as AnimationPlayer).active = false
			if "zshape" in exps:
				for m in z.find_children("*", "MeshInstance3D", true, false):
					(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if "nozombies" in exps:
		for z in get_nodes_in_group("zombies"):
			z.queue_free()

## exp=census: what the frame is made of, from the renderer's own counters (draw calls, objects, primitives) and from the
## tree (visible meshes and surfaces per group of nodes). Printed once, 20 s into a fight; the groups are the scene's
## top-level children, with the zombies, lights, decals and particles counted on their own.
func _census() -> void:
	var ri := RenderingServer
	print("  CENSUS render: objects %d primitives %d draw calls %d" % [_info(ri.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), _info(ri.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), _info(ri.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	var cam := root.get_camera_3d()
	var groups := {}
	var lights := {"omni": 0, "omni_shadow": 0, "spot": 0, "spot_shadow": 0, "sun_shadow": 0}
	var counts := {"decal": 0, "gpu_particles": 0, "cpu_particles": 0, "skinned": 0, "skinned_prims": 0}
	for n in current_scene.find_children("*", "", true, false):
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n is Light3D:
			var l := n as Light3D
			if not (l is DirectionalLight3D) and cam != null:
				var ld := cam.global_position.distance_to(l.global_position)
				var reach := (l.distance_fade_begin + l.distance_fade_length) if l.distance_fade_enabled else 1e9
				if ld < reach:
					var rng := (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
					print("  CENSUS LIGHT %-60s d %5.1f range %4.1f energy %4.1f" % [str(current_scene.get_path_to(l)).right(60), ld, rng, l.light_energy])
			if l is OmniLight3D:
				lights["omni"] += 1
				lights["omni_shadow"] += 1 if l.shadow_enabled else 0
			elif l is SpotLight3D:
				lights["spot"] += 1
				lights["spot_shadow"] += 1 if l.shadow_enabled else 0
			elif l.shadow_enabled:
				lights["sun_shadow"] += 1
		elif n is Decal:
			counts["decal"] += 1
		elif n is GPUParticles3D:
			counts["gpu_particles"] += 1
		elif n is CPUParticles3D:
			counts["cpu_particles"] += 1
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var d := 1e9
			if cam != null:
				d = cam.global_position.distance_to(mi.global_position)
			var end := mi.visibility_range_end
			if end > 0.0 and d > end:
				continue
			var path := str(current_scene.get_path_to(n)).split("/")
			var key := path[0]
			if path.size() > 2 and not (path[0] in ["Facades", "Cell_Main"]):
				key += "/" + path[1]
			elif path[0] == "Facades":
				# By what the node is, not by which front: "Front12/Sign3" -> "Facades:Sign".
				var leaf := String(path[path.size() - 1]).rstrip("0123456789")
				key = "Facades:" + (leaf if path.size() > 2 else String(path[1]).rstrip("0123456789"))
			if mi.skin != null or mi.get_parent() is Skeleton3D:
				key = "SKINNED " + key
			var surfs := mi.mesh.get_surface_count()
			var prims := 0
			if mi.mesh is ArrayMesh:
				for si in surfs:
					var il: int = (mi.mesh as ArrayMesh).surface_get_array_index_len(si)
					prims += (il if il > 0 else (mi.mesh as ArrayMesh).surface_get_array_len(si)) / 3
			else:
				prims += mi.mesh.get_faces().size() / 9
			var g: Dictionary = groups.get(key, {"n": 0, "surf": 0, "prims": 0, "shadow": 0, "multi": 0})
			g["n"] += 1
			g["surf"] += surfs
			g["prims"] += prims
			g["shadow"] += 1 if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
			groups[key] = g
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				var key := "MULTIMESH " + str(current_scene.get_path_to(n)).get_slice("/", 0)
				var g: Dictionary = groups.get(key, {"n": 0, "surf": 0, "prims": 0, "shadow": 0, "multi": 0})
				g["n"] += 1
				g["surf"] += mm.mesh.get_surface_count()
				g["multi"] += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				groups[key] = g
	if "mergedebug" in exps:
		var why := {}
		for n in current_scene.get_node("Facades").find_children("@*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var par := String(mi.get_parent().name).rstrip("0123456789")
			var r := "ok"
			if mi.get_child_count() > 0: r = "children"
			elif mi.material_override != null: r = "override"
			elif not mi.get_groups().is_empty(): r = "groups " + str(mi.get_groups())
			elif not mi.get_meta_list().is_empty(): r = "meta " + str(mi.get_meta_list())
			elif not mi.visible: r = "hidden"
			else:
				for sidx in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(sidx)
					if mi.get_surface_override_material(sidx) != null: r = "surface override"
					elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: r = "transparent"
					elif mat is BaseMaterial3D and (mat as BaseMaterial3D).uv1_triplanar and not (mat as BaseMaterial3D).uv1_world_triplanar: r = "object triplanar"
					elif mat is ShaderMaterial: r = "shader"
			var k := "%s | %s | %s" % [par, mi.get_parent().get_class(), r]
			why[k] = int(why.get(k, 0)) + 1
		for k in why:
			print("  MERGEWHY ", k, " x", why[k])
	print("  CENSUS lights ", lights, " counts ", counts)
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a]["surf"] > groups[b]["surf"])
	for k in keys.slice(0, 30):
		print("  CENSUS %-48s meshes %4d surfaces %4d prims(1x) %8d shadow-casters %4d multi-instances %d" % [k, groups[k]["n"], groups[k]["surf"], groups[k]["prims"], groups[k]["shadow"], groups[k]["multi"]])

## Switches the named cost: on = as the game has it, off = removed.
func _ab_apply(on: bool) -> void:
	if _ab_nodes.is_empty() and ab_what != "far60" and ab_what != "lod8" and ab_what != "hud" and ab_what != "zombies" and ab_what != "fsr" and ab_what != "fxaa" and ab_what != "adj" and ab_what != "postfx" and ab_what != "fog":
		for n in current_scene.find_children("*", "", true, false):
			match ab_what:
				"facades":
					if n is Node3D and n.get_parent() == current_scene.get_node_or_null("Facades"):
						_ab_nodes.append(n)
				"props":
					var par := n.get_parent()
					if n is Node3D and par != null and String(par.name).begins_with("Cell_") and not n is StaticBody3D and not n is MultiMeshInstance3D and not n is OccluderInstance3D and not n is Light3D:
						_ab_nodes.append(n)
				"mm":
					if n is MultiMeshInstance3D:
						_ab_nodes.append(n)
				"decals":
					if n is Decal:
						_ab_nodes.append(n)
				"lights":
					if n is Light3D and not n is DirectionalLight3D:
						_ab_nodes.append(n)
				"particles":
					if n is GPUParticles3D or n is CPUParticles3D:
						_ab_nodes.append(n)
	for n in _ab_nodes:
		if is_instance_valid(n):
			(n as Node3D).visible = on
	match ab_what:
		"zombies":
			for z in get_nodes_in_group("zombies"):
				var mr = z.get("_model_root")
				if mr != null:
					(mr as Node3D).visible = on
		"hud":
			for l in root.find_children("*", "CanvasLayer", true, false):
				if l.name != "SceneLoader" and l.get_parent() != root.get_node_or_null("SceneLoader"):
					(l as CanvasLayer).visible = on
		"far60":
			if root.get_camera_3d() != null:
				root.get_camera_3d().far = 4000.0 if on else 60.0
		"lod8":
			root.mesh_lod_threshold = 4.0 if on else 8.0
		"fsr":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if on else Viewport.SCALING_3D_MODE_BILINEAR
		"fxaa":
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED
		"adj":
			for we in current_scene.find_children("*", "WorldEnvironment", true, false):
				(we as WorldEnvironment).environment.adjustment_enabled = on
		"postfx":
			for c in root.find_children("PostFX", "", true, false):
				c.visible = on
		"fog":
			for we in current_scene.find_children("*", "WorldEnvironment", true, false):
				(we as WorldEnvironment).environment.fog_enabled = on

func _ab_tick(g: float, dt: float) -> void:
	if ab_what == "":
		return
	var f := Engine.get_process_frames()
	if f % 90 == 0:
		ab_on = not ab_on
		_ab_apply(ab_on)
		return
	if f % 90 < 15:
		return  # let the switch settle (the GPU time lags a frame or two, meshes upload)
	var i := 0 if ab_on else 1
	ab_n[i] += 1
	ab_gpu[i] += g
	ab_ms[i] += dt
	ab_prims[i] += _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	ab_calls[i] += _info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	ab_objs[i] += _info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)

func _ab_print() -> void:
	if ab_what == "" or ab_n[0] == 0 or ab_n[1] == 0:
		return
	for i in 2:
		var n: float = ab_n[i]
		print("AB %s %s: frames %d gpu %.2f ms frame %.2f ms | primitives %.0f draw calls %.0f objects %.0f" % [ab_what, "ON (as is)" if i == 0 else "OFF", n, ab_gpu[i] / n, ab_ms[i] / n, ab_prims[i] / n, ab_calls[i] / n, ab_objs[i] / n])
	print("AB %s: costs %.2f ms GPU, %.0f primitives, %.0f draw calls, %.0f objects" % [ab_what, ab_gpu[0] / ab_n[0] - ab_gpu[1] / ab_n[1], ab_prims[0] / ab_n[0] - ab_prims[1] / ab_n[1], ab_calls[0] / ab_n[0] - ab_calls[1] / ab_n[1], ab_objs[0] / ab_n[0] - ab_objs[1] / ab_n[1]])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait_prefetch(limit_s := 60.0) -> void:
	var sl := root.get_node_or_null("SceneLoader")
	if sl == null:
		return
	var w0 := Time.get_ticks_usec()
	while (not sl._queue.is_empty() or not sl._loading.is_empty()) and Time.get_ticks_usec() - w0 < limit_s * 1e6:
		await process_frame

func _run() -> void:
	match scenario:
		"street":
			await _street(false)
		"sick":
			await _street(true)
		"shop":
			await _shop()
		"horde":
			await _fight(false)
		"ghetto":
			await _fight(true)
		"crowd":
			await _fight(false, true)
		"kart":
			await _kart()
		"title":
			await _title_idle()
		"floor":
			await _title_idle(true)
		_:
			if scenario.begins_with("room:"):
				await _room(scenario.substr(5))
			elif scenario.begins_with("go:"):
				await _go(scenario.substr(3))
			else:
				print("unknown scenario ", scenario)
				quit()
				return
	_finish()

func _street(sick: bool) -> void:
	await _setup_story(23 if night else 14)
	if sick:
		gs.no_sickness = false
		gs.craving = 3.0
	change_scene_to_file("res://world/City3D.tscn")
	await _frames(240)
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	player.global_position = Vector3(-60, 0, -2.6)
	player.reset_physics_interpolation()
	await _frames(30)
	# The title screen's time lets SceneLoader's background prefetch finish: standing still starts it.
	await _wait_prefetch()
	phase = "walk"
	if stand_x != INF:
		player.global_position = Vector3(stand_x, 0, -2.6)
		player.reset_physics_interpolation()
		await _frames(60)
		if "census" in exps:
			_census()
			return
		_begin_recording()
		var k := 0
		while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
			player.set_look(-PI / 2 + 0.5 * sin(k * 0.02), -0.1)
			k += 1
			await process_frame
			_tick()
			phase = "stand x=%d" % int(stand_x)
			_maybe_shot()
		return
	if "census" in exps and stand_x == INF:
		_census()
		return
	_begin_recording()
	var dir := 1.0
	var last_x := player.global_position.x
	var stuck_t := 0.0
	var nudge := 0
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		if sick:
			gs.craving = 3.0
		if player.global_position.x > 60.0:
			dir = -1.0
		elif player.global_position.x < -60.0:
			dir = 1.0
		for a in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(a)
		Input.action_press("sprint")
		if nudge > 0:
			nudge -= 1
			Input.action_press("move_down")
		player.set_look(-PI / 2 if dir > 0 else PI / 2, -0.1)
		Input.action_press("move_up")
		await process_frame
		var dt := _tick()
		if absf(player.global_position.x - last_x) < 0.02:
			stuck_t += dt
		else:
			stuck_t = 0.0
		last_x = player.global_position.x
		if stuck_t > 300.0 and nudge == 0:
			nudge = 25
			stuck_t = 0.0
		phase = "x=%d" % int(player.global_position.x)
		_maybe_shot()
	for a in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(a)

func _shop() -> void:
	await _setup_story(23 if night else 14)
	change_scene_to_file("res://world/City3D.tscn")
	await _frames(240)
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	player.global_position = Vector3(3.5, 0.0, -8.0)
	player.set_look(PI, 0.0)
	player.reset_physics_interpolation()
	await _frames(180)
	# (As in a real session: the title and the first minutes have let the background prefetch finish.)
	await _wait_prefetch()
	phase = "stand"
	_begin_recording()
	var i := 0
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		player.set_look(PI + 0.35 * sin(i * 0.02), -0.05)
		i += 1
		await process_frame
		_tick()
		_maybe_shot()

func _room(room: String) -> void:
	await _setup_story(14)
	change_scene_to_file("res://world/%s.tscn" % room)
	await _frames(200)
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	var best: Node3D = null
	var bd := 1e9
	for d in get_nodes_in_group("doors"):
		var dd := (d as Node3D).global_position.distance_to(player.global_position)
		if dd < bd:
			bd = dd
			best = d
	var away := player.global_position - best.global_position
	away.y = 0.0
	away = away.normalized()
	player.global_position = Vector3(best.global_position.x + away.x * 3.0, player.global_position.y, best.global_position.z + away.z * 3.0)
	var yaw := atan2(away.x, away.z)
	player.set_look(yaw, 0.0)
	player.reset_physics_interpolation()
	await _frames(120)
	await _wait_prefetch()
	phase = "stand"
	_begin_recording()
	var i := 0
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		player.set_look(yaw + 0.3 * sin(i * 0.02), -0.03)
		i += 1
		await process_frame
		_tick()
		_maybe_shot()

## Dead Block (gangs=false) or Ghetto Wars (gangs=true): the real rounds, the player walking a route and shooting.
func _fight(gangs: bool, crowd := false) -> void:
	await _setup_story(23)
	zm = root.get_node("ZombieMode")
	if gangs:
		zm.begin_gangs()
	else:
		zm.begin()
	change_scene_to_file("res://world/City3D.tscn")
	await _frames(60)
	var city := current_scene
	# The fade is the game's own: the prewarm holds it until the critical part is done.
	var warm := city.get_node_or_null("ZombieBlock/Prewarm")
	var w := 0
	while warm != null and not warm.critical_done and w < 1200:
		await process_frame
		w += 1
	await _frames(60)
	await _wait_prefetch()
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	var holder: Node = player.get_node_or_null("WeaponHolder")
	var aim_at := [null]
	if holder != null:
		holder.give(load("res://weapons/ar.tres"))
		holder.refill_all()
		holder.aim_source = func():
			var t = aim_at[0]
			var eye: Vector3 = player.global_position + Vector3(0, 1.6, 0)
			if t == null or not is_instance_valid(t):
				return [eye, Vector3.RIGHT]
			var c: Vector3 = (t as Node3D).global_position + Vector3(0, 1.3, 0)
			return [eye, c - eye]
	player.global_position = Vector3(-8.0, 0.0, -1.0)
	player.reset_physics_interpolation()
	zm.health = zm.MAX_HEALTH
	zm.round = 14 if not gangs else 5
	phase = "round start"
	_begin_recording()
	zm.start_round()
	var sp0 = city.get_node("ZombieBlock").spawner
	if crowd:
		# A steady crowd for A/B runs: the spawner and the surge are off, 28 walkers are kept alive 12-40 m
		# round the player, nobody shoots (no gore, no deaths), so every run draws and thinks the same.
		sp0.enabled = false
		city.get_node("ZombieBlock").surge.set_process(false)
	var shoot_in := 0.0
	var group := "gangsters" if gangs else "zombies"
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		await process_frame
		var dt := _tick()
		zm.health = zm.MAX_HEALTH
		var t := (Time.get_ticks_usec() - t0_us) / 1e6
		var u := fposmod(t * 2.0, 60.0)
		player.global_position = Vector3(-10.0 + (u if u < 30.0 else 60.0 - u), 0.0, -1.0)
		player.velocity = Vector3.ZERO
		phase = "alive %d" % get_nodes_in_group(group).size()
		if crowd:
			player.set_look(-PI / 2 + 0.7 * sin(t * 0.5), -0.05)
		if crowd and get_nodes_in_group(group).size() < 28 and Engine.get_process_frames() % 4 == 0:
			var px := player.global_position.x
			var side := 1.0 if randf() < 0.5 else -1.0
			sp0.spawn_one("walker", Vector3(px + side * randf_range(12.0, 40.0), 0.0, randf_range(-3.0, 1.0)))
		if Engine.get_process_frames() % 300 == 0:
			var sp = city.get_node("ZombieBlock").spawner
			print("  STAT t=%.0f s alive(group) %d spawner.alive %d max_alive %d round %d released %d/%d surge %s scale %.2f fired %d/%d" % [t, get_nodes_in_group(group).size(), sp.alive(), zm.max_alive, zm.round, sp.released, sp.total, zm.surge_busy, root.scaling_3d_scale, fired_ok, fired_try])
		if exps.size() > (1 if "census" in exps else 0) and Engine.get_process_frames() % 30 == 0:
			_apply_exps()
		if "census" in exps and not _censused and t > 20.0:
			_censused = true
			_census()
		if gangs and get_nodes_in_group(group).size() < 5:
			# The street is held by a crew of 5 to 8 at all times (the story's waves are 6 and 8 strong): the
			# set's own call for a crowd.
			var pp := player.global_position
			var pts: Array = []
			for k in 4:
				pts.append(Vector3(pp.x + (14.0 + k * 2.0) * (1.0 if k % 2 == 0 else -1.0), 0.0, -1.0 + (k % 3) * 1.2))
			root.get_node("GhettoMode").spawn_wave({"count": 4, "weapons": ["ar", "smg", "shotgun", "pistol", "lmg"], "from_points": pts})
		if holder != null and not crowd:
			shoot_in -= dt / 1000.0
			if shoot_in <= 0.0:
				shoot_in = 0.12
				var best: Node = null
				var best_d := 30.0
				for z in get_nodes_in_group(group):
					var dd: float = (z as Node3D).global_position.distance_to(player.global_position)
					if dd < best_d:
						best_d = dd
						best = z
				aim_at[0] = best
				holder.mag = 30
				holder._cooldown = 0.0
				if best != null:
					var bp := (best as Node3D).global_position
					player.set_look(atan2(-(bp.x - player.global_position.x), -(bp.z - player.global_position.z)), 0.0)
					fired_try += 1
					if holder.fire():
						fired_ok += 1
		_maybe_shot()
	zm.leave()

func _kart() -> void:
	await _setup_story(20)
	change_scene_to_file("res://world/KartCenter3D.tscn")
	await _frames(200)
	await _wait_prefetch()
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = true
	phase = "start()"
	_begin_recording()
	await process_frame
	_tick()
	race = load("res://ui/KartRace.gd").new()
	root.add_child(race)
	race.start("player", {})
	# (Windowed, the race is built a few frames later behind its veil: its viewport is read when it exists.)
	var pressed := false
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		await process_frame
		_tick()
		if not extra_vp.is_valid() and race.get("_vp") != null:
			extra_vp = (race.get("_vp") as SubViewport).get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(extra_vp, true)
		var t := (Time.get_ticks_usec() - t0_us) / 1e6
		phase = "race t=%.0f" % t
		if not pressed and t > 6.0:
			pressed = true
			Input.action_press("move_up", 1.0)
		_maybe_shot()
	Input.action_release("move_up")
	if is_instance_valid(race):
		race.queue_free()

func _title_idle(warmed := false) -> void:
	await process_frame
	gfx = root.get_node("Graphics")
	gfx.set_preset(0)
	gfx.set_laptop_mode(true)
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _frames(2)
	if warmed:
		# The noise floor: the title after its warm-up and the prefetch are done, no input, nothing happening.
		var w0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - w0 < 6e6 or root.get_node_or_null("TitleWarm") != null:
			await process_frame
		await _wait_prefetch()
		await _frames(120)
	phase = "title"
	_begin_recording()
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		await process_frame
		_tick()
		_maybe_shot()

func _go(which: String) -> void:
	await _setup_story(14)
	if which.begins_with("title"):
		change_scene_to_file("res://ui/TitleScreen.tscn")
		# The title's seconds: the prefetch and any prewarm run here, unrecorded, like a player reading the menu.
		await _frames(60)
		var w0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - w0 < 8e6:
			await process_frame
		await _wait_prefetch()
	else:
		var start_scene := "res://world/City3D.tscn" if which == "street_shop" else "res://world/StoreConvenience3D.tscn"
		change_scene_to_file(start_scene)
		await _frames(240)
		var player := get_first_node_in_group("player") as Node3D
		player.dialogue_active = false
		await _frames(60)
		await _wait_prefetch()
	phase = "call"
	_begin_recording()
	match which:
		"street_shop":
			root.get_node("SceneLoader").go("res://world/StoreConvenience3D.tscn")
		"shop_street":
			root.get_node("SceneLoader").go("res://world/City3D.tscn")
		"title_story":
			current_scene._start_run()
		"title_zombies":
			current_scene._start_zombies()
	while (Time.get_ticks_usec() - t0_us) < secs * 1e6:
		await process_frame
		_tick()
		phase = "busy" if root.get_node("SceneLoader").busy() else "after"
		_maybe_shot()
	if which == "title_zombies":
		root.get_node("ZombieMode").leave()
