extends SceneTree
## Quality check for the zombie clips: plays each one on a Rocketbox avatar in
## a window, saves a contact sheet (side row, front row) and prints the foot
## numbers the .pilot/feet.gd way -- a planted foot, once the body moves at the
## clip's own pace, drops to ~0 m/s.
##   flatpak run org.godotengine.Godot --path . --socket=wayland --display-driver wayland \
##     -s res://dev-tools/zombie_anim_probe.gd -- <out_dir> [clip ...]
const LIB := "res://assets/zombie_anims/zombie_clips.res"
const AVATAR := "res://assets/rocketbox/Male_Adult_04.glb"
const CELL := Vector2i(220, 300)
const SHOTS := 6   # frames per strip; "shots=N" on the command line overrides

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp"
	var lib_path := LIB
	var names: Array = []
	var focus := ""
	var shots := SHOTS
	for a in args.slice(1):
		if str(a).begins_with("shots="):
			shots = int(str(a).substr(6))
		elif str(a).begins_with("focus="):
			focus = str(a).substr(6)   # close-up on a bone (e.g. "Bip01 R Hand") instead of the whole body
		elif str(a).begins_with("lib="):
			lib_path = str(a).substr(4)   # try a library without touching the shipped one
		else:
			names.append(a)
	var lib := load(lib_path) as AnimationLibrary
	var clips: Array = names if names.size() > 0 else Array(lib.get_animation_list())
	var vp := SubViewport.new()
	vp.size = CELL
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var holder := Node3D.new()
	vp.add_child(holder)
	var model: Node3D = (load(AVATAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * 1.5
	holder.add_child(model)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.add_animation_library("zombie", lib)
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.27, 0.25)
	plane.material = fm
	holder.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	holder.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	holder.add_child(env)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	for _w in 10:   # warm-up: let the viewport settle at CELL size before the first shot
		await process_frame

	# Which way the avatar faces, from its own toes.
	var foot_l := sk.find_bone("Bip01 L Foot")
	var toe_l := sk.find_bone("Bip01 L Toe0")
	var fwd := (sk.global_transform * sk.get_bone_global_pose(toe_l)).origin - (sk.global_transform * sk.get_bone_global_pose(foot_l)).origin
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var bad := 0
	for clip in clips:
		var full: String = "zombie/" + str(clip)
		if not ap.has_animation(full):
			print("NO CLIP ", clip)
			bad += 1
			continue
		var anim := ap.get_animation(full)
		# Every track must land on a bone of this avatar.
		var dead := 0
		for t in anim.get_track_count():
			if not model.has_node(String(anim.track_get_path(t)).get_slice(":", 0)) or sk.find_bone(String(anim.track_get_path(t)).get_slice(":", 1)) < 0:
				dead += 1
		ap.play(full)
		ap.speed_scale = 0.0
		var sheet := Image.create(CELL.x * shots, CELL.y * 2, false, Image.FORMAT_RGB8)
		for i in shots:
			ap.seek(anim.length * float(i) / float(shots), true)
			ap.advance(0.0)
			for view in 2:
				var c := Vector3(0, 0.9, 0)
				if anim.get_meta("root_motion", false) and i > 0:
					c.y = 1.2
				var dist := 4.2
				# Lying clips (crawl, death): the pelvis near the floor, so frame the floor, closer.
				sk.force_update_all_bone_transforms()
				if (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Pelvis"))).origin.y < 0.45:
					c.y = 0.3
					dist = 3.2
				if focus != "":
					sk.force_update_all_bone_transforms()
					c = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(focus))).origin
					dist = 1.1
				var dir := right if view == 0 else fwd
				cam.global_position = c + dir * dist + Vector3(0, 0.3 if focus == "" else 0.1, 0)
				cam.look_at(c, Vector3.UP)
				# The viewport renders a frame behind the camera, and the very
				# first renders come out stale (a cell at the wrong size): let
				# several frames pass for every cell, more for the first.
				for _w in (5 if i == 0 else 3):
					await process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, CELL.y * view))
		sheet.save_png("%s/%s%s.png" % [out_dir, str(clip), "_focus" if focus != "" else ""])
		print(_feet(ap, sk, full, anim, fwd))
		if dead > 0:
			print("  !! %d tracks do not land on this avatar" % dead)
			bad += 1
	quit(bad)

## Foot numbers: lowest point, and for loops the slowest each foot gets when the
## body walks at the clip's pace.
func _feet(ap: AnimationPlayer, sk: Skeleton3D, full: String, anim: Animation, fwd: Vector3) -> String:
	var bones := {}
	for n in ["Bip01 L Foot", "Bip01 R Foot", "Bip01 L Toe0", "Bip01 R Toe0"]:
		bones[n] = sk.find_bone(n)
	var steps := int(anim.length * 30.0)
	var prev := {}
	var mins := {"Bip01 L Foot": 99.0, "Bip01 R Foot": 99.0}
	var floor_y := 99.0
	var travel: float = anim.get_meta("travel", 0.0) * sk.global_transform.basis.get_scale().x
	var dt := 1.0 / 30.0
	ap.play(full)
	ap.speed_scale = 0.0
	var spread := 0.0
	for s in steps + 1:
		ap.seek(float(s) * dt, true)
		ap.advance(0.0)
		sk.force_update_all_bone_transforms()
		for n in bones:
			var p := (sk.global_transform * sk.get_bone_global_pose(bones[n])).origin
			floor_y = minf(floor_y, p.y)
			if prev.has(n) and mins.has(n) and s > 0:
				var v: Vector3 = (p - prev[n]) / dt + fwd * travel
				v.y = 0.0
				mins[n] = minf(mins[n], v.length())
			prev[n] = p
		var pl := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Pelvis"))).origin
		spread = maxf(spread, absf(pl.y))
	var line := "%-16s %.2fs  lowest foot/toe y %.3f m" % [full.get_slice("/", 1), anim.length, floor_y]
	if anim.loop_mode != Animation.LOOP_NONE:
		line += "  pace %.2f m/s  slowest foot L %.2f R %.2f (planted ~0)" % [travel, mins["Bip01 L Foot"], mins["Bip01 R Foot"]]
	return line
