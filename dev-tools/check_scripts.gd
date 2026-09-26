extends SceneTree
## Dev helper: loads every script in the project so parse errors in files
## no test happens to touch still fail loudly.
##   godot --headless --path . -s res://dev-tools/check_scripts.gd
func _initialize() -> void:
	var bad := 0
	for path in _scripts("res://"):
		var s := load(path)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate()):
			print("  FAIL ", path)
			bad += 1
	print("%d script(s) failed" % bad)
	quit(1 if bad else 0)

func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d == "addons":
			continue
		out.append_array(_scripts(dir.path_join(d)))
	return out
