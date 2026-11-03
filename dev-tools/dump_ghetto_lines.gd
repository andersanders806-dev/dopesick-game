extends SceneTree
## Writes every line Ghetto Wars speaks (fx/GhettoVoice.bake_list) as JSON for dev-tools/gen_story_audio.py:
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/dump_ghetto_lines.gd (writes dev-tools/_ghetto_lines.json)

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://dev-tools/_ghetto_lines.json"
	var list: Array = load("res://fx/GhettoVoice.gd").bake_list()
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + out)
		quit(1)
		return
	f.store_string(JSON.stringify(list, "\t"))
	f.close()
	print("wrote %d lines to %s" % [list.size(), out])
	quit()
