extends SceneTree
## Packs the retargeted GANG=1 clips (dev-tools/retarget_to_bip01.py) into the
## AnimationLibrary the armed humans of Ghetto Wars share (assets/gang_anims/gang_clips.res), then
## builds the "aim" composites: the legs and pelvis of a gait with the torso, head and arms of the
## pistol aim pose (every gun is carried at the shoulder by the same upper body). Same bake as
## build_zombie_library.gd, which says how the GLB is read. Not run by hand:
##   godot --headless --path . -s res://dev-tools/build_zombie_library.gd -- <clips.glb> <meta.json> <out.res>
## The GLB sits outside the project (~/.cache/dopesick), so it is read at run
## time instead of imported; the importer's work is done here instead:
## the avatars' .import files set root_scale 0.6667, which scales position
## tracks (and the skeleton: 1 unit is 0.667 cm of avatar), and a loop clip's
## `travel` (the pace its feet cover) is kept as metadata for CharacterAnimator.

## nodes/root_scale in assets/rocketbox/*.glb.import.
const ROOT_SCALE := 0.6667

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <clips.glb> <meta.json> <out.res>")
		quit(1)
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		push_error("cannot read " + args[0])
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := AnimationLibrary.new()
	for clip in ap.get_animation_list():
		var a: Animation = ap.get_animation(clip).duplicate()
		a.loop_mode = Animation.LOOP_LINEAR if meta.get(clip, {}).get("loop", false) else Animation.LOOP_NONE
		# The exporter writes every bone's constant offset too; only the
		# pelvis moves, and the rest would pin the others to the bake's rest.
		for t in range(a.get_track_count() - 1, -1, -1):
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and not String(a.track_get_path(t)).ends_with(":Bip01 Pelvis"):
				a.remove_track(t)
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ROOT_SCALE)
		var m: Dictionary = meta.get(clip, {})
		if a.loop_mode != Animation.LOOP_NONE:
			# Already in place (the bake took the drift out), so
			# CharacterAnimator._in_place must leave it alone; `travel` is the
			# pace the feet cover in the tracks' own units per second, as it
			# would leave it. The avatars' units are centimetres at root scale.
			a.set_meta("in_place", true)
			if float(m.get("travel", 0.0)) > 0.05:
				a.set_meta("travel", float(m["travel"]) * 100.0 * ROOT_SCALE)
		a.set_meta("source", m.get("source", ""))
		a.set_meta("derived", m.get("hunch", false))
		a.set_meta("root_motion", m.get("root_motion", false))
		lib.add_animation(clip, a)
		print("clip %s  %.2fs  tracks %d  loop %s  %s" % [clip, a.length, a.get_track_count(), a.loop_mode != 0, m.get("source", "")])
	_composites(lib)
	DirAccess.make_dir_recursive_absolute(args[2].get_base_dir())
	var err := ResourceSaver.save(lib, args[2], ResourceSaver.FLAG_COMPRESS)
	print("saved ", args[2], " err ", err)
	scene.free()
	quit(err)

## gait clip -> the composite that carries a gun.
const COMPOSITES := {"ga_stand": "g_stand", "ga_walk": "g_walk", "ga_jog": "g_jog", "ga_crouch": "g_crouch_idle",
	"ga_crouch_walk": "g_crouch_walk", "ga_sprint": "g_sprint"}
const UPPER := ["Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head", "Bip01 L Clavicle", "Bip01 R Clavicle",
	"Bip01 L UpperArm", "Bip01 R UpperArm", "Bip01 L Forearm", "Bip01 R Forearm", "Bip01 L Hand", "Bip01 R Hand"]

static func _is_upper(bone: String) -> bool:
	return bone in UPPER or bone.contains("Finger")

func _composites(lib: AnimationLibrary) -> void:
	var aim: Animation = lib.get_animation("g_aim")
	for out in COMPOSITES:
		var base: Animation = lib.get_animation(COMPOSITES[out])
		var a := Animation.new()
		a.length = base.length
		a.loop_mode = base.loop_mode
		for k in base.get_meta_list():
			a.set_meta(k, base.get_meta(k))
		for t in base.get_track_count():
			var bone := String(base.track_get_path(t)).get_slice(":", 1)
			if _is_upper(bone):
				continue
			var nt := a.add_track(base.track_get_type(t))
			a.track_set_path(nt, base.track_get_path(t))
			a.track_set_interpolation_type(nt, base.track_get_interpolation_type(t))
			for k in base.track_get_key_count(t):
				a.track_insert_key(nt, base.track_get_key_time(t, k), base.track_get_key_value(t, k))
		for t in aim.get_track_count():
			if aim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(aim.track_get_path(t)).get_slice(":", 1)
			if not _is_upper(bone) or aim.track_get_key_count(t) == 0:
				continue
			var nt := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(nt, aim.track_get_path(t))
			a.track_insert_key(nt, 0.0, aim.track_get_key_value(t, 0))
		lib.add_animation(out, a)
		print("composite %s from %s  %.2fs  tracks %d" % [out, COMPOSITES[out], a.length, a.get_track_count()])
