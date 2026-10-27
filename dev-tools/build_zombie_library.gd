extends SceneTree
## Packs the retargeted clips (dev-tools/retarget_to_bip01.py) into the
## AnimationLibrary the zombies share. Not run by hand:
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
	DirAccess.make_dir_recursive_absolute(args[2].get_base_dir())
	var err := ResourceSaver.save(lib, args[2], ResourceSaver.FLAG_COMPRESS)
	print("saved ", args[2], " err ", err)
	scene.free()
	quit(err)
