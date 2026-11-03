extends SceneTree
## Dev helper: the real FPFeel and Viewmodel on a stub holder/player in a plain room (no city, a few
## seconds a gun), to .pilot/z5_<gun>_<state>.png. States: hip, ads, fire, sprint, rl<percent> (tactical
## reload), re<percent> (empty reload), ra<percent> (first raise), side (viewmodel from the right).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_z5_studio.gd -- pistol ar -- hip ads rl40
## (Guns first, then "--" is not needed: anything with a known state name is a state.)
var FPFeel: GDScript
const Viewmodel := preload("res://player/Viewmodel.gd")
const HOLDER_SRC := """extends Node
signal fired
signal hit(part: String, killed: bool)
signal weapon_changed(data)
signal reload_started
signal reload_finished
signal dry_fired
signal melee_swung(found: bool)
signal traced(from: Vector3, to: Vector3)
var player = null
var current = null
var viewmodel = null
var feel = null
var aiming := false
var reloading := false
var mag := 10
var rl := 0.0
func reload_left() -> float:
	return rl
"""
const PLAYER_SRC := """extends Node3D
var camera: Camera3D
var _first_person := true
var velocity := Vector3.ZERO
var _look_yaw := 0.0
var _look_pitch := 0.0
var feel = null
var BASE_SPEED := 5.0
var SPRINT_MULT := 1.6
var sprinting := false
var floor_on := true
func is_sprinting() -> bool:
	return sprinting
func is_on_floor() -> bool:
	return floor_on
"""
var out := ""

func _initialize() -> void:
	out = ProjectSettings.globalize_path("res://.pilot")
	FPFeel = load("res://player/FPFeel.gd")
	await process_frame
	var args: Array = Array(OS.get_cmdline_user_args())
	var states: Array = args.filter(func(a): return _is_state(String(a)))
	var guns: Array = args.filter(func(a): return not _is_state(String(a)) and a != "--")
	if states.is_empty():
		states = ["hip", "ads", "rl40", "rl70"]
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.8
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	# A floor and a wall so there is something to shoot at and to stand on.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.24, 0.23)
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, 0, 0)
	world.add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(12, 5, 0.3)
	wall.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.45, 0.42, 0.38)
	wall.material_override = wmat
	wall.position = Vector3(0, 2.4, -9)
	world.add_child(wall)
	var player := Node3D.new()
	player.set_script(_script(PLAYER_SRC))
	world.add_child(player)
	var mount := Node3D.new()
	mount.name = "CameraMount"
	mount.position = Vector3(0, 1.6, 0)
	player.add_child(mount)
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 70.0
	mount.add_child(cam)
	cam.current = true
	player.set("camera", cam)
	var holder := Node.new()
	holder.set_script(_script(HOLDER_SRC))
	holder.set("player", player)
	player.add_child(holder)
	var feel: Node = FPFeel.new()
	feel.auto = false
	holder.add_child(feel)
	holder.set("feel", feel)
	var side := Camera3D.new()
	side.environment = env
	side.fov = 40.0
	world.add_child(side)
	for id in guns:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var old = holder.get("viewmodel")
		if old != null:
			old.queue_free()
		var vm := Viewmodel.new()
		cam.add_child(vm)
		vm.setup(d)
		holder.set("viewmodel", vm)
		holder.set("current", d)
		holder.set("mag", d.mag_size)
		holder.emit_signal("weapon_changed", d)
		await _run(feel, holder, 90)
		for st in states:
			await _state(String(st), id, d, feel, holder, player, vm, cam, side)
	quit()

func _is_state(a: String) -> bool:
	if a in ["hip", "ads", "fire", "sprint", "side", "top", "strafe", "land"]:
		return true
	return (a.begins_with("rl") or a.begins_with("re") or a.begins_with("ra")) and a.substr(2).is_valid_int()

func _script(src: String) -> GDScript:
	var gd := GDScript.new()
	gd.source_code = src
	gd.reload()
	return gd

func _run(feel: Node, holder: Node, frames: int) -> void:
	for i in frames:
		feel.advance(1.0 / 60.0)
		feel.apply()
		await process_frame

func _state(st: String, id: String, d: Resource, feel: Node, holder: Node, player: Node, vm: Node3D, cam: Camera3D, side: Camera3D) -> void:
	feel.reset_state()
	feel.swap_blend = 0.0
	holder.set("aiming", false)
	holder.set("reloading", false)
	holder.set("mag", d.mag_size)
	player.set("sprinting", false)
	player.set("velocity", Vector3.ZERO)
	cam.current = true
	if st == "ads":
		holder.set("aiming", true)
		await _run(feel, holder, 60)
	elif st == "fire":
		holder.emit_signal("fired")
		await _run(feel, holder, 2)
	elif st == "sprint":
		player.set("sprinting", true)
		player.set("velocity", Vector3(0, 0, -5.0))
		await _run(feel, holder, 40)
	elif st.begins_with("rl") or st.begins_with("re"):
		var pc := float(st.substr(2)) / 100.0
		var total := 3.0
		holder.set("mag", 0 if st.begins_with("re") else d.mag_size - 1)
		holder.set("reloading", true)
		holder.set("rl", total)
		holder.emit_signal("reload_started")
		var steps := int(pc * total * 60.0)
		for i in steps:
			holder.set("rl", total * (1.0 - float(i) / (total * 60.0)))
			feel.advance(1.0 / 60.0)
			feel.apply()
			await process_frame
		holder.set("rl", total * (1.0 - pc))
		await _run(feel, holder, 1)
	elif st.begins_with("ra"):
		var pc := float(st.substr(2)) / 100.0
		feel.begin_raise(true)
		await _run(feel, holder, int(pc * feel.raise_duration() * 60.0) + int(d.swap_time * 36.0))
	else:
		await _run(feel, holder, 30)
	if st == "side" or st == "top":
		side.global_position = cam.global_position + vm.position + (Vector3(0.6, 0, 0) if st == "side" else Vector3(0, 0.6, 0))
		side.look_at(cam.global_position + vm.position + Vector3(0, 0, 0.12), Vector3.UP if st == "side" else Vector3.LEFT)
		side.current = true
		await _run(feel, holder, 2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z5_%s_%s.png" % [out, id, st])
	if st.begins_with("rl") or st.begins_with("re"):
		holder.set("reloading", false)
		holder.emit_signal("reload_finished")
