extends RefCounted
## Is this process a test, a probe, a capture or a bot rather than the game itself? One answer for every
## file the game writes in user:// (the run's save, Dead Block's save, Know-How, settings): a sandboxed
## process never touches the player's own files, it uses throw-away ones (or none) named by run_token().
##
## The game runs for real only when it is launched without a script (`-s` / `--script`) and without
## `--no-sick` or `--sandbox` in its user args. Every dev-tools run is a sandbox, whether or not the
## script remembers to say so (it may still set Engine meta "sandbox" to force it).

static func active() -> bool:
	if Engine.has_meta("sandbox"):
		return bool(Engine.get_meta("sandbox"))
	var yes := false
	for a in OS.get_cmdline_args():
		if a == "-s" or a == "--script":
			yes = true
	for a in OS.get_cmdline_user_args():
		if a == "--no-sick" or a == "--sandbox":
			yes = true
	# Remembered: the answer must not change halfway through a process.
	Engine.set_meta("sandbox", yes)
	return yes

## A random token made once per process (not the pid: every flatpak instance is in its own PID
## namespace and gets the same small one).
static func run_token() -> String:
	if not Engine.has_meta("run_token"):
		Engine.set_meta("run_token", Crypto.new().generate_random_bytes(4).hex_encode())
	return String(Engine.get_meta("run_token"))

## `path` ("user://x.cfg") with this process's token in its name ("user://x_<token>.cfg").
static func sandboxed(path: String) -> String:
	return path.get_basename() + "_" + run_token() + "." + path.get_extension()

## Before the first overwrite of one of the player's real files in this process, keep what was there as
## `<path>.bak` (one generation: the state this session started from; later saves in it don't replace it).
static func backup_once(path: String) -> void:
	var done: Dictionary = Engine.get_meta("backed_up", {})
	if done.has(path):
		return
	done[path] = true
	Engine.set_meta("backed_up", done)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
