extends Node
## The prewarm of Dead Block (zombie mode): everything the first kill, the first gun bought, the first
## quake or the first tsunami would otherwise build, load or compile in the middle of a fight is made and
## drawn once here, while the screen is still black (world/ZombieBlock.gd starts it at the end of setup;
## world/City3D.gd holds the fade until `critical_done`), and what is left runs in small slices behind the
## round-1 banner.
##
## Godot compiles a pipeline the first time a material is DRAWN, so "load it" is not enough: every pool is
## shown for a few frames in a bay under the street, in front of the camera, where the pavement hides it
## (depth test), one dead zombie is run through the whole gore path (wound, severed limb, head pop, ragdoll,
## pool, screen blood), every gun's viewmodel is built and flashed once, and the quake's and tsunami's
## particles, decals, water, wave and Drowned are shown. Sounds are loaded and kept. Afterwards the pools
## are put back as new (counters at zero, nothing visible), so the game cannot tell it ran.
##
## Skipped without a window (headless tests have nothing to compile) and with Engine meta "no_prewarm"
## (dev-tools/hitch_probe.gd's BEFORE runs).

const ZombieScript := preload("res://npc/Zombie3D.gd")
const GoreScript := preload("res://fx/gore/Gore.gd")
const ImpactFXScript := preload("res://fx/ImpactFX.gd")
const EntranceFXScript := preload("res://fx/EntranceFX.gd")
const ViewmodelScript := preload("res://player/Viewmodel.gd")
const DrownedScript := preload("res://npc/Drowned.gd")
const GoreRigScript := preload("res://fx/gore/GoreRig.gd")
const GunModelScript := preload("res://weapons/GunModel.gd")

const SOUND_DIRS := ["res://assets/sfx/guns/", "res://assets/sfx/quake/", "res://assets/sfx/tsunami/"]
const TEXTURE_DIRS := ["res://assets/decals/"]
const WEAPON_DIR := "res://weapons/"
## The guns that can be bought (the pistol is in the hand already).
const GUNS := ["smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]
## Microseconds of work per frame: in the black of a scene change, and behind the banner.
const BUDGET_BLACK_US := 45000
const BUDGET_US := 6000
## The bay: this far ahead of the camera and this far under the street.
const BAY_AHEAD := 7.0
const BAY_DEPTH := 2.6
## The tsunami's looping sounds (fx/Tsunami.gd makes a looping copy of each on first use).
const TSUNAMI_LOOPS := ["tsunami_siren_far", "tsunami_siren", "wind_rise_loop", "broadcast_static", "wave_roar_far",
	"heartbeat_loop", "heartbeat_fast_loop", "water_rush_loop", "underwater"]
## Frames each batch stays drawn (a pipeline compiles on the first, the second makes sure).
const HOLD := 3

## All of it is done / the part that must be before the screen clears is.
var done := false
var critical_done := false
## Milliseconds from start to critical_done / done.
var critical_ms := 0
var ms := 0
## [step, milliseconds] in the order they ran (the probe prints it).
var log: Array = []

var block: Node
var city: Node3D
var _hold: Array = []
var _requested: Array = []
var _bay: Node3D
var _bay_pos := Vector3.ZERO
var _t0 := 0
var _step_t := 0
var _frame_t := 0
var _muted_before := false
var _muted := false

## No window, no compiling: nothing to do.
static func skipped() -> bool:
	return Engine.has_meta("no_prewarm") or DisplayServer.get_name() == "headless"

func start(b: Node) -> void:
	block = b
	city = b.get("city") as Node3D
	name = "Prewarm"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if skipped() or city == null:
		done = true
		critical_done = true
		return
	_run()

func _exit_tree() -> void:
	_mute(false)

func _budget() -> int:
	return BUDGET_BLACK_US if SceneLoader.busy() else BUDGET_US

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	_frame_t = Time.get_ticks_usec()

## Lets the frame go when this step has used its share of it.
func _slice() -> void:
	if Time.get_ticks_usec() - _frame_t > _budget():
		await _frames(1)

func _begin_step() -> void:
	_step_t = Time.get_ticks_usec()

func _end_step(label: String) -> void:
	log.append([label, snappedf((Time.get_ticks_usec() - _step_t) / 1000.0, 0.1)])

func _alive() -> bool:
	return is_inside_tree() and is_instance_valid(city)

func _mute(on: bool) -> void:
	if on == _muted:
		return
	if on:
		_muted_before = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
	else:
		AudioServer.set_bus_mute(0, _muted_before)
	_muted = on

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	await _frames(1)
	if not _alive():
		return
	_mute(true)
	_begin_step()
	_body_tables()
	_end_step("gore tables of the bodies")
	_begin_step()
	_load_everything()
	_end_step("load sounds, textures, guns")
	await _slice()
	_begin_step()
	var gore: Node3D = GoreScript.of(city)
	await _slice()
	var fx: Node3D = ImpactFXScript.of(city)
	await _slice()
	var entrance: Node3D = EntranceFXScript.of(city)
	gore.warm_textures()
	# Every zombie that comes out has its body's gore tables and limb gibs built a step a frame.
	var spawner: Node = block.get("spawner")
	if spawner != null and not spawner.spawned.is_connected(gore.warm_body):
		spawner.spawned.connect(gore.warm_body)
	_end_step("pools")
	await _frames(1)
	if not _alive():
		return
	_make_bay()
	# 1. one dead zombie through the whole gore path, and the shot's own pieces
	_begin_step()
	await _gore_path(gore, fx)
	_end_step("gore path")
	if not _alive():
		return
	# 2. every pooled particle, decal and hidden piece of the shot, the gore, the entrances
	_begin_step()
	var items: Array = []
	_collect(gore, items)
	_collect(fx, items)
	_collect(entrance, items)
	var feel := _feel()
	if feel != null:
		items.append_array(feel.warm(_bay_pos))
	_reveal(items)
	await _frames(HOLD)
	_restore(items)
	if feel != null:
		feel.unwarm()
	_end_step("pools drawn")
	_begin_step()
	await _finish_loads()
	_end_step("collect loads")
	# 3. every gun's viewmodel and muzzle flash
	await _viewmodels()
	if not _alive():
		return
	critical_ms = Time.get_ticks_msec() - _t0
	# (Nothing after this makes a sound: the street may be heard again.)
	_mute(false)
	critical_done = true
	# The rest runs behind the banner.
	await _quake()
	if not _alive():
		return
	await _tsunami()
	if not _alive():
		return
	_put_back(gore, fx, entrance)
	ms = Time.get_ticks_msec() - _t0
	done = true

# --- Loading ------------------------------------------------------------------------------------

## The skin table of every body for the gore (reading the mesh back from the renderer: 17 to 75 ms the
## first time a wound or a limb of that body is wanted), from the dummies world/ZombieBlock.gd draws for
## the same reason (they are freed three frames after setup; this runs in the first).
func _body_tables() -> void:
	var bay := city.get_node_or_null("ZombiePrewarm")
	if bay == null:
		return
	for z in bay.get_children():
		if z.get("_skeleton") != null:
			GoreRigScript.table(z)

## Sounds, decal pictures, the guns' data and models: requested on worker threads now and kept (the
## first fight would otherwise load them one by one on the main thread, 40 to 500 ms for a gun model).
## finish_loads() collects them.
func _load_everything() -> void:
	for dir in SOUND_DIRS:
		for f in _files(dir, ".wav"):
			_request(dir + f)
	for dir in TEXTURE_DIRS:
		for f in _files(dir, ".png"):
			_request(dir + f)
	_request(ViewmodelScript.OPTIC_MODEL)
	for f in _files(WEAPON_DIR, ".tres"):
		var d := load(WEAPON_DIR + f)
		if d == null:
			continue
		_hold.append(d)
		var model := String(d.get("model")) if d.get("model") != null else ""
		if model != "":
			_request(model)

func _request(path: String) -> void:
	if ResourceLoader.exists(path) and not _requested.has(path):
		_requested.append(path)
		ResourceLoader.load_threaded_request(path)

## Takes what the workers have loaded (waits for the rest a frame at a time).
func _finish_loads() -> void:
	for path in _requested:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await _frames(1)
			if not _alive():
				return
		var r := ResourceLoader.load_threaded_get(path)
		if r == null:
			continue
		_hold.append(r)
		if r is PackedScene:
			GunModelScript.keep(path, r)
	_requested.clear()

## The names in `dir` ending in `ext` (an exported game lists them as .import / .remap).
func _files(dir: String, ext: String) -> Array:
	var out: Array = []
	for f in ResourceLoader.list_directory(dir):
		var n: String = f
		for tail in [".import", ".remap"]:
			n = n.trim_suffix(tail)
		if n.ends_with(ext) and not out.has(n):
			out.append(n)
	return out

# --- The bay ------------------------------------------------------------------------------------

func _make_bay() -> void:
	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var ground := player.global_position.y if player != null else 0.0
	var origin := Vector3.ZERO
	var fwd := Vector3.FORWARD
	if cam != null:
		origin = cam.global_position
		fwd = -cam.global_transform.basis.z
	elif player != null:
		origin = player.global_position
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_bay_pos = Vector3(origin.x, ground - BAY_DEPTH, origin.z) + fwd * BAY_AHEAD
	_bay = Node3D.new()
	_bay.name = "PrewarmBay"
	city.add_child(_bay)
	_bay.global_position = _bay_pos

func _feel() -> Node:
	var holder: Node = block.get("holder")
	return holder.get("feel") if holder != null else null

# --- The gore path ------------------------------------------------------------------------------

## One body, run through what the first kill does: flinch, a wound, a limb off (stump, gib, burst,
## bleeder), the head off (chunks, fountain), the ragdoll, the pool, blood on the lens, and a bullet
## into the wall and into flesh.
func _gore_path(gore: Node3D, fx: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var z: CharacterBody3D = ZombieScript.new()
	z.configure("walker", 1, rng)
	z.set_meta("body", ZombieScript.BODIES[0])
	z.set_meta("prewarm", true)
	_bay.add_child(z)
	z.global_position = _bay_pos
	await _frames(1)
	if not _alive():
		return
	var dir := Vector3.RIGHT
	var chest := _bay_pos + Vector3(0.0, 1.1, 0.0)
	z.sync_hitboxes()
	z._flinch_part("torso", dir, 20.0)
	gore._wound(z, "torso", z.max_health * 0.3, chest)
	gore._wound(z, "head", z.max_health * 0.3, _bay_pos + Vector3(0.0, 1.6, 0.0))
	fx.bullet_hit(_bay_pos, Vector3.UP)
	fx.blood_hit(chest, dir, "torso", true, 2.0)
	fx.muzzle_smoke(chest, dir, 1.0)
	fx.damage_number(chest, 20.0, "torso", false)
	await _slice()
	gore.sever(z, "forearm_l", dir)
	await _slice()
	gore.sever(z, "leg_r", dir)
	await _slice()
	gore.pop_head(z, dir)
	await _slice()
	gore.ragdoll(z, dir, 3.0)
	gore.pool_under(z)
	gore.screen_blood(1.0)
	await _frames(HOLD)
	if is_instance_valid(z):
		z.queue_free()

# --- Showing what is pooled ---------------------------------------------------------------------

## The pooled drawables under `root`: [node, kind, state...]. Particles and decals show whatever they
## are; a hidden node with something to draw in it (a chunk, a gib, the water, the wave) is shown as a
## whole.
func _collect(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Light3D or c is AudioStreamPlayer3D or c is AudioStreamPlayer:
			continue
		if c is CPUParticles3D:
			var p := c as CPUParticles3D
			out.append({"n": p, "kind": "p", "vis": p.visible, "xf": p.global_transform, "mode": p.process_mode, "emit": p.emitting})
		elif c is Decal:
			var d := c as Decal
			out.append({"n": d, "kind": "d", "vis": d.visible, "xf": d.global_transform, "mode": d.process_mode})
		elif c is Node3D and not (c as Node3D).visible and _draws(c):
			var h := c as Node3D
			out.append({"n": h, "kind": "h", "vis": false, "xf": h.global_transform, "mode": h.process_mode})
		elif c is Node3D or c is CanvasLayer:
			_collect(c, out)

## Whether `n` has a mesh or a multimesh in it to draw.
func _draws(n: Node) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return true
	if n is MultiMeshInstance3D:
		return true
	for c in n.get_children():
		if _draws(c):
			return true
	return false

func _reveal(items: Array) -> void:
	var i := 0
	for e in items:
		i += 1
		var n: Node = e["n"]
		if not is_instance_valid(n):
			continue
		var at := _bay_pos + Vector3(fmod(i * 0.37, 3.0) - 1.5, 0.0, fmod(i * 0.23, 2.0) - 1.0)
		match e["kind"]:
			"p":
				var p := n as CPUParticles3D
				p.process_mode = Node.PROCESS_MODE_ALWAYS
				p.visible = true
				p.global_position = at
				p.restart()
				p.emitting = true
			"d":
				var d := n as Decal
				d.visible = true
				d.global_position = at
			"h":
				var h := n as Node3D
				h.process_mode = Node.PROCESS_MODE_ALWAYS
				h.visible = true
				h.global_position = at
			"node":
				pass

func _restore(items: Array) -> void:
	for e in items:
		var n: Node = e["n"]
		if not is_instance_valid(n):
			continue
		match e["kind"]:
			"p":
				var p := n as CPUParticles3D
				p.emitting = false
				p.visible = e["vis"]
				p.global_transform = e["xf"]
				p.process_mode = e["mode"]
			"d":
				var d := n as Decal
				d.visible = e["vis"]
				d.global_transform = e["xf"]
			"h":
				var h := n as Node3D
				h.visible = e["vis"]
				h.global_transform = e["xf"]
				h.process_mode = e["mode"]

# --- Viewmodels and muzzle flashes --------------------------------------------------------------

## Every gun that can be bought, built and flashed once: the model, the optic's glass and dot, the arms,
## the flash. Bought mid-fight these used to cost 40 to 470 ms.
func _viewmodels() -> void:
	var holder: Node = block.get("holder")
	# (Third person has no viewmodel; swapping to first person builds the gun in hand.)
	if holder == null or not Graphics.first_person:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var made: Array = []
	for id in GUNS:
		_begin_step()
		var d: Resource = load("%s%s.tres" % [WEAPON_DIR, id])
		var vm: Node3D = ViewmodelScript.new().setup(d)
		_bay.add_child(vm)
		vm.global_position = _bay_pos + Vector3(0.0, 1.0, 0.0)
		vm.show_flash(rng, 1.6)
		made.append(vm)
		_end_step("viewmodel " + id)
		await _slice()
		if not _alive():
			return
	# All drawn together for a couple of frames, then put away.
	_begin_step()
	await _frames(2)
	for vm in made:
		if is_instance_valid(vm):
			vm.hide_flash()
			vm.queue_free()
	_end_step("viewmodels drawn")

# --- RICHTER 8.0 ----------------------------------------------------------------------------------

func _quake() -> void:
	var quake: Node = block.get("quake")
	if quake == null:
		return
	_begin_step()
	var items: Array = []
	_collect(quake, items)
	_reveal(items)
	await _frames(HOLD)
	_restore(items)
	_end_step("quake")

# --- The tsunami --------------------------------------------------------------------------------

func _tsunami() -> void:
	var ts: Node = block.get("tsunami")
	if ts == null:
		return
	_begin_step()
	# The water's shader is built on the first countdown; build it now. So are the loops' streams
	# (a looping copy of a long wav is made on first use).
	ts._build_water()
	ts.set("spread_spawn", true)
	for n in TSUNAMI_LOOPS:
		ts.call("_load", n, true)
	var items: Array = []
	_collect(ts, items)
	var wave: Node3D = ts.get("wave")
	var ui := ts.get("hud") as CanvasLayer
	var ui_state := _show_ui(ui)
	_reveal(items)
	if wave != null:
		wave.show_debris(true)
	# A Drowned: the skin, the helmet's and the weed's shaders, the eyes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var dz: CharacterBody3D = DrownedScript.new()
	dz.set_meta("prewarm", true)
	dz.setup_drowned(1, rng)
	_bay.add_child(dz)
	dz.global_position = _bay_pos
	# (Its _ready skips its own look for a prewarm dummy, so that it is not one of the dead: put that on by hand.)
	for m in ["_wet_skin", "_build_gear", "_build_drips"]:
		if dz.has_method(m):
			dz.call(m)
	await _frames(HOLD)
	if wave != null:
		wave.show_debris(false)
	_restore(items)
	_hide_ui(ui_state)
	if is_instance_valid(dz):
		dz.queue_free()
	_end_step("tsunami")

## The HUD's shaded rectangles, drawn once at a sliver of opacity.
func _show_ui(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	if root is CanvasLayer:
		out.append([root, "layer", (root as CanvasLayer).visible])
		(root as CanvasLayer).visible = true
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.material is ShaderMaterial:
			# (Its parents too: a hidden parent draws nothing.)
			var up: Node = ctl
			while up != null and up != root:
				if up is Control:
					out.append([up, "ctl", (up as Control).visible, (up as Control).modulate])
					(up as Control).visible = true
					(up as Control).modulate.a = 0.02
				up = up.get_parent()
	return out

func _hide_ui(state: Array) -> void:
	# (Backwards: a parent shared by two is recorded twice, and the first record is the true state.)
	state.reverse()
	for e in state:
		if not is_instance_valid(e[0]):
			continue
		if e[1] == "layer":
			(e[0] as CanvasLayer).visible = e[2]
		else:
			(e[0] as Control).visible = e[2]
			(e[0] as Control).modulate = e[3]

# --- Putting it back ------------------------------------------------------------------------------

## The pools as new: nothing shown, nothing counted.
func _put_back(gore: Node3D, fx: Node3D, entrance: Node3D) -> void:
	if is_instance_valid(gore):
		gore.reset()
	if is_instance_valid(fx):
		fx.reset()
	if is_instance_valid(entrance):
		entrance.reset()
	if is_instance_valid(_bay):
		_bay.queue_free()
