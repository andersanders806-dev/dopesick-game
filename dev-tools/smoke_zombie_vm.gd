extends SceneTree
## Viewmodel arms and optic checks (headless, self-contained): the support hand reaches the
## handguard on every long gun, the forearms are slimmer than the avatar's, the red dot sight's
## logo is painted out and its reticle kept.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_vm.gd
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
var aiming := false
var reloading := false
func reload_left() -> float:
	return 0.0
"""
var fails := 0
var FPFeel: GDScript

func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	await process_frame
	FPFeel = load("res://player/FPFeel.gd")
	var host := Node3D.new()
	root.add_child(host)
	_check(Viewmodel.ARM_SLIM < 1.0 and Viewmodel.ARM_SLIM > 0.5, "forearms thinner than the avatar's (%.2f)" % Viewmodel.ARM_SLIM)
	for id in ["ar", "smg", "lmg", "shotgun", "pistol"]:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var vm := Viewmodel.new()
		host.add_child(vm)
		vm.setup(d)
		var b: AABB = vm.box
		if id != "pistol":
			var wraps: bool = id != "shotgun"
			# The support hand sits on the front half of the gun, beside or under it (not inside
			# the receiver where the gun hides it), within a hand's reach of the gun's box.
			var front: bool = vm.grip_l.z < b.position.z + b.size.z * 0.6
			_check(front, "%s: left hand on the front half of the gun" % id)
			var inflated := b.grow(0.12)
			_check(inflated.has_point(vm.grip_l), "%s: left hand within reach of the gun" % id)
			var beside: bool = absf(vm.grip_l.x) >= 0.02 or not wraps
			_check(beside, "%s: left hand beside the gun's axis, not inside the body (x %.3f)" % [id, vm.grip_l.x])
		else:
			_check(vm.grip_l.y < vm.grip_r.y, "pistol: support hand under the firing hand")
		_check(vm.arms != null, "%s: arms built" % id)
		if id == "ar" or id == "smg":
			_check(vm.has_optic and vm.optic != null, "%s: red dot fitted" % id)
			var painted := 0
			var dot := vm.optic.get_node_or_null("Dot") != null
			for mi in vm.optic.find_children("*", "MeshInstance3D", true, false):
				var inst := mi as MeshInstance3D
				if inst.mesh == null:
					continue
				for s in inst.mesh.get_surface_count():
					var sm := inst.get_surface_override_material(s) as ShaderMaterial
					if sm != null and sm.get_shader_parameter("blank_rect") != null:
						var r: Vector4 = sm.get_shader_parameter("blank_rect")
						if r.z > r.x and r.w > r.y:
							painted += 1
			_check(painted > 0, "%s: sight logo blanked on %d surfaces" % [id, painted])
			_check(dot, "%s: red reticle kept" % id)
		vm.queue_free()
		await process_frame
	await _auto_fire_sound(host)
	print("smoke_zombie_vm: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)

## Full-auto sound: a 2 s burst plays a short body per round and exactly one echo tail (after the last
## round), never the whole shot; a semi-auto gun keeps its whole shot and has no tail; at most
## SHOT_VOICES shot voices ever exist.
func _auto_fire_sound(host: Node) -> void:
	var src := GDScript.new()
	src.source_code = HOLDER_SRC
	src.reload()
	for id in ["smg", "ar", "lmg", "pistol"]:
		var holder: Node = Node.new()
		holder.set_script(src)
		host.add_child(holder)
		var d: Resource = load("res://weapons/%s.tres" % id)
		holder.current = d
		var feel: Node = FPFeel.new()
		holder.add_child(feel)
		feel.auto = false
		var rounds := 0
		var t := 0.0
		var since := 1.0
		var step := 1.0 / 120.0
		var most := 0
		while t < 2.0:
			t += step
			since += step
			if since >= d.interval() and (d.auto or rounds == 0 or since >= 0.3):
				holder.fired.emit()
				rounds += 1
				since = 0.0
			feel.advance(step)
			var playing := 0
			for c in feel.get_children():
				if c is AudioStreamPlayer and c.playing and String(c.stream.resource_path).contains("fire_"):
					playing += 1
			most = maxi(most, playing)
		for i in 60:
			feel.advance(step)
		var counts: Dictionary = feel.sound_counts
		var bodies := 0
		var whole := 0
		for k in counts:
			if String(k).contains("_body_"):
				bodies += int(counts[k])
			elif String(k).begins_with("fire_") and not String(k).ends_with("_tail"):
				whole += int(counts[k])
		var tails := int(counts.get("fire_%s_tail" % id, 0))
		if id == "pistol":
			_check(whole == rounds and bodies == 0 and tails == 0, "pistol: %d rounds play %d whole shots, no body, no tail" % [rounds, whole])
		else:
			_check(rounds >= 10 and bodies == rounds and whole == 0, "%s: a 2 s burst of %d rounds plays %d short bodies and no whole shot" % [id, rounds, bodies])
			_check(tails == 1, "%s: and exactly one echo tail (%d)" % [id, tails])
		_check(most <= FPFeel.SHOT_VOICES, "%s: never more than %d shot voices at once (%d)" % [id, FPFeel.SHOT_VOICES, most])
		holder.queue_free()
		await process_frame
	for id in ["smg", "ar", "lmg"]:
		for part in ["body_a", "body_b", "tail"]:
			var st: AudioStream = FPFeel.stream("fire_%s_%s" % [id, part])
			_check(st != null, "fire_%s_%s.wav is there" % [id, part])
			if st != null and part != "tail":
				_check(st.get_length() < 0.25, "%s %s is short (%.0f ms)" % [id, part, st.get_length() * 1000.0])
