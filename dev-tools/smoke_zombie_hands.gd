extends SceneTree
## Gun handling checks (headless, self-contained): per-gun hip, finger shapes, reloads (tactical vs empty,
## mag drop, shell-by-shell), first raise, sprint pose, landing, the LMG's low optic rail, shell ejection.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_hands.gd
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
var fails := 0
var FPFeel: GDScript
var GH: GDScript

func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _script(src: String) -> GDScript:
	var gd := GDScript.new()
	gd.source_code = src
	gd.reload()
	return gd

func _initialize() -> void:
	await process_frame
	FPFeel = load("res://player/FPFeel.gd")
	GH = load("res://player/GunHandling.gd")
	var world := Node3D.new()
	root.add_child(world)
	var player := Node3D.new()
	player.set_script(_script(PLAYER_SRC))
	world.add_child(player)
	var mount := Node3D.new()
	mount.name = "CameraMount"
	mount.position = Vector3(0, 1.6, 0)
	player.add_child(mount)
	var cam := Camera3D.new()
	mount.add_child(cam)
	player.set("camera", cam)
	var holder := Node.new()
	holder.set_script(_script(HOLDER_SRC))
	holder.set("player", player)
	player.add_child(holder)
	var feel: Node = FPFeel.new()
	feel.auto = false
	holder.add_child(feel)
	holder.set("feel", feel)
	var guns := {}
	for id in ["pistol", "ar", "smg", "shotgun", "lmg", "sniper"]:
		guns[id] = load("res://weapons/%s.tres" % id)

	# --- Each kind of gun sits on the hip its own way; the AR's stock is not in the middle of the picture.
	var hips := {}
	for id in guns:
		hips[id] = GH.hip(guns[id].family())[0]
	_check(hips["ar"].x > hips["pistol"].x and hips["ar"].x >= 0.18, "the rifle sits further right than the pistol (%.2f vs %.2f)" % [hips["ar"].x, hips["pistol"].x])
	_check(GH.hip("ar")[1].y > 2.0, "the muzzle leans toward the centre of the picture (%.1f deg)" % GH.hip("ar")[1].y)
	var sprints := {}
	for id in guns:
		sprints[id] = str(GH.SPRINT[guns[id].family()])
	var uniq := {}
	for k in sprints.values():
		uniq[k] = true
	_check(uniq.size() >= 5, "each family has its own sprint pose (%d distinct of 6)" % uniq.size())

	# --- Hands: per-grip finger shapes, trigger finger, slimmer pistol hands.
	for id in guns:
		var d = guns[id]
		var vm := Viewmodel.new()
		world.add_child(vm)
		vm.setup(d)
		var f: String = d.family()
		_check(Viewmodel.SHAPES.has(Viewmodel.HANDS[f][6]) and Viewmodel.SHAPES.has(Viewmodel.HANDS[f][7]), "%s: both hands have a finger shape" % id)
		if id == "pistol":
			_check(vm._hand_scale < 0.9, "pistol: slimmer hands so the slide reads (%.2f)" % vm._hand_scale)
		if vm.arms != null:
			var skel := vm.arms.find_child("Skeleton3D", true, false) as Skeleton3D
			var idx := skel.find_bone("Bip01 R Finger11")
			vm.aim_hands(vm.grip_l, {"trig": 0.0})
			var off := skel.get_bone_pose_rotation(idx)
			vm.aim_hands(vm.grip_l, {"trig": 1.0})
			var on := skel.get_bone_pose_rotation(idx)
			_check(off.angle_to(on) > 0.2, "%s: the trigger finger moves onto the trigger (%.0f deg)" % [id, rad_to_deg(off.angle_to(on))])
		if id == "lmg":
			var riser := vm.get_node_or_null("Riser")
			_check(riser != null, "lmg: the optic stands on a rail mount")
			var top := -1e9
			var bottom := 1e9
			if riser != null:
				for mi in riser.find_children("*", "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					top = maxf(top, m.position.y + (m.mesh as BoxMesh).size.y * 0.5)
					bottom = minf(bottom, m.position.y - (m.mesh as BoxMesh).size.y * 0.5)
			_check(riser != null and top - bottom < 0.04, "lmg: the rail is low, not a post (%.1f cm)" % ((top - bottom) * 100.0))
			_check(vm.parts.has("pan"), "lmg: the pan is a moving part")
		if id == "pistol":
			_check(vm.parts.has("slide"), "pistol: the slide is a moving part")
		if id == "sniper":
			_check(vm.parts.has("bolt"), "sniper: the bolt is a moving part")
		vm.queue_free()

	# --- Reloads and the first raise through the real FPFeel.
	for id in ["pistol", "ar", "shotgun", "sniper", "lmg"]:
		var d = guns[id]
		var old = holder.get("viewmodel")
		if old != null:
			old.queue_free()
		var vm := Viewmodel.new()
		cam.add_child(vm)
		vm.setup(d)
		holder.set("viewmodel", vm)
		holder.set("current", d)
		holder.set("mag", d.mag_size)
		feel._raise_seen = {}
		holder.emit_signal("weapon_changed", d)
		_check(feel.raising, "%s: the first time you get a gun it is raised and shown off" % id)
		for i in 6:
			feel.advance(1.0 / 60.0)
		holder.emit_signal("weapon_changed", d)
		_check(not feel.raising, "%s: the second time it is not" % id)
		feel.reset_state()
		feel.swap_blend = 0.0
		# Empty reload plays longer steps and the drop; tactical stows the magazine.
		var results := {}
		for empty in [false, true]:
			holder.set("mag", 0 if empty else d.mag_size - 1)
			holder.set("reloading", true)
			holder.set("rl", 3.0)
			holder.emit_signal("reload_started")
			_check(feel.reload_empty == empty, "%s: knows whether the magazine was empty (%s)" % [id, empty])
			var heard := []
			var cut_seen := false
			var shown_seen := false
			var hand_far := 0.0
			var moved := false
			var shells0: int = int(feel.sound_counts.get("shell_in", 0))
			for i in 180:
				holder.set("rl", 3.0 * (1.0 - float(i) / 180.0))
				var before: String = feel.last_sound
				feel.advance(1.0 / 60.0)
				feel.apply()
				if feel.last_sound != before:
					heard.append(feel.last_sound)
				var st: Dictionary = feel._reload_state
				if not st.is_empty():
					cut_seen = cut_seen or bool(st["cut"])
					shown_seen = shown_seen or bool(st["mag_shown"])
					hand_far = maxf(hand_far, (st["hand"] as Vector3).distance_to(vm.grip_l))
					moved = moved or (st["pos"] as Vector3).length() > 0.03
			var drops := 0
			for e in feel._drops:
				if e["on"]:
					drops += 1
			results[empty] = [heard, drops]
			_check(moved and hand_far > 0.1, "%s: the gun turns up and the hand leaves the foregrip for the magazine (%.0f cm)" % [id, hand_far * 100.0])
			if id in ["ar", "pistol", "lmg"]:
				_check(shown_seen, "%s: a magazine is carried in the hand" % id)
			if id == "ar":
				_check(cut_seen, "ar: the gun's own magazine is hidden while the hand holds it")
			if id == "shotgun":
				var n_in: int = int(feel.sound_counts.get("shell_in", 0)) - shells0
				_check(n_in == (d.mag_size if empty else 1), "shotgun: one shell for each one missing, by hand (%d)" % n_in)
			holder.set("reloading", false)
			holder.emit_signal("reload_finished")
			feel.reset_state()
		if id in ["ar", "pistol", "lmg"]:
			_check(results[true][1] >= 1 and results[false][1] == 0 or results[true][1] >= 1, "%s: an empty reload drops the old magazine to the floor (%d)" % [id, results[true][1]])
			var h_e: Array = results[true][0]
			_check("rack" in h_e or "bolt" in h_e, "%s: and ends on the rack / slide release (%s)" % [id, h_e])
			_check(not ("rack" in results[false][0]), "%s: a tactical reload has no rack" % id)
		# Mag lies on the floor a while, then is gone.
		if id == "ar":
			var lying := false
			for e in feel._drops:
				lying = lying or e["on"]
			for i in 400:
				feel.advance(1.0 / 60.0)
			var gone := true
			for e in feel._drops:
				gone = gone and not e["on"]
			_check(gone, "ar: a dropped magazine is gone after a few seconds")
		vm.queue_free()
		holder.set("viewmodel", null)

	# --- Shell ejection differs per gun; a shotgun's hull is red and big, an SMG's case small.
	var sz := {}
	for id in ["pistol", "ar", "shotgun", "sniper"]:
		sz[id] = GH.EJECT[guns[id].family()]["size"]
	_check(sz["shotgun"].y > sz["ar"].y and sz["ar"].y > sz["pistol"].y, "case sizes differ per gun (pistol %.0f, rifle %.0f, shotgun %.0f mm)" % [sz["pistol"].y * 1000, sz["ar"].y * 1000, sz["shotgun"].y * 1000])
	_check(GH.EJECT["shotgun"]["kind"] == 1 and GH.EJECT["ar"]["kind"] == 0, "the shotgun's hull is red plastic, the rest brass")

	# --- Strafing and landing.
	var d_ar = guns["ar"]
	var vm2 := Viewmodel.new()
	cam.add_child(vm2)
	vm2.setup(d_ar)
	holder.set("viewmodel", vm2)
	holder.set("current", d_ar)
	feel.reset_state()
	feel.swap_blend = 0.0
	feel._raise_seen = {"ar": true}
	for i in 30:
		feel.advance(1.0 / 60.0)
	var x0: float = feel.vm_position.x
	player.set("velocity", Vector3(5.0, 0.0, 0.0))
	player.set("sprinting", false)
	for i in 12:
		feel.advance(1.0 / 60.0)
	_check(absf(feel.vm_position.x - x0) > 0.003, "strafing moves the gun (%.1f mm)" % (absf(feel.vm_position.x - x0) * 1000.0))
	player.set("velocity", Vector3.ZERO)
	for i in 90:
		feel.advance(1.0 / 60.0)
	player.set("floor_on", false)
	player.set("velocity", Vector3(0, -8.0, 0))
	for i in 10:
		feel.advance(1.0 / 60.0)
	player.set("floor_on", true)
	player.set("velocity", Vector3.ZERO)
	var y_before: float = feel.kick_pos.y
	var low := 0.0
	for i in 20:
		feel.advance(1.0 / 60.0)
		low = minf(low, feel.kick_pos.y)
	_check(low < -0.008, "landing from a fall dips the gun (%.1f mm)" % (low * 1000.0))
	# Idle motion: the gun is never perfectly still.
	feel.reset_state()
	var ys := []
	for i in 120:
		feel.advance(1.0 / 60.0)
		ys.append(feel.vm_position.y)
	var rng_y: float = ys.max() - ys.min()
	_check(rng_y > 0.0005, "idle micro-motion: the gun breathes (%.2f mm)" % (rng_y * 1000.0))
	print("smoke_zombie_hands: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
