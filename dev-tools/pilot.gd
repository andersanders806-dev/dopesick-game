extends "res://dev-tools/playtest_bot.gd"
## Pilot: drives the real game in a window from a list of steps on the
## command line, logging state and taking screenshots -- for checking that a
## change works in the game itself, not just in the smoke test. See
## .claude/skills/run-dope-sick/SKILL.md.
##
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/pilot.gd -- \
##       "scene City3D" "clock 21:00" "walk Pusher" "talk" "shot pusher"
##
## Screenshots and pilot.log go to .pilot/ in the project (gitignored;
## flatpak Godot can't write to /tmp). Runs sandboxed: nothing is saved, and
## the view starts in third person on Medium whatever settings.cfg says.
##
## Steps (one quoted argument each):
##   scene <Name|res://path>    load a room: City3D, DiveBar3D, Apartment3D,
##                              StoreLiquor3D... or "title" for the title screen
##   clock HH:MM | day N | cash N | craving N | give <item_id> | strip N
##   preset Low|Medium|High|PS5 | view first|third
##   list                       interactables in the room, nearest first
##   walk <NodeName>            walk there on the navmesh until E would use it
##   interact | talk | close    press E | E, log the dialogue, close it | close
##   choose <N>                 pick option N (0-based) in the open menu
##   key <NAME>                 tap a key: J, T, N, ESCAPE, TAB, F3, SPACE...
##   pad <BUTTON>               tap a DualSense button: CROSS CIRCLE SQUARE
##                              TRIANGLE OPTIONS TOUCHPAD L1 R1 L3 R3 DPAD_RIGHT
##   hold <action> <seconds>    hold an input action (move_up, sprint, fire...)
##   wait <seconds> | shot <label> | state

const PAD_BUTTONS := {
	"CROSS": JOY_BUTTON_A, "CIRCLE": JOY_BUTTON_B, "SQUARE": JOY_BUTTON_X, "TRIANGLE": JOY_BUTTON_Y,
	"OPTIONS": JOY_BUTTON_START, "CREATE": JOY_BUTTON_BACK, "TOUCHPAD": JOY_BUTTON_TOUCHPAD,
	"L1": JOY_BUTTON_LEFT_SHOULDER, "R1": JOY_BUTTON_RIGHT_SHOULDER, "L3": JOY_BUTTON_LEFT_STICK,
	"R3": JOY_BUTTON_RIGHT_STICK, "DPAD_UP": JOY_BUTTON_DPAD_UP, "DPAD_DOWN": JOY_BUTTON_DPAD_DOWN,
	"DPAD_LEFT": JOY_BUTTON_DPAD_LEFT, "DPAD_RIGHT": JOY_BUTTON_DPAD_RIGHT,
}

var _log: FileAccess
var _failed := false

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	t_start = Time.get_ticks_msec()
	out_dir = ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir + "/pilot.log", FileAccess.WRITE)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	gfx.set_preset(gfx.Preset.MEDIUM)
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.busted.connect(func(): log_line("BUSTED"))
	var steps := OS.get_cmdline_user_args()
	if steps.is_empty():
		log_line("no steps given; see the header of dev-tools/pilot.gd")
	for step in steps:
		log_line("> " + step)
		if not await _do(step.strip_edges()):
			_failed = true
			log_line("STEP FAILED: " + step)
			await screenshot("failed")
			break
	_state()
	log_line("PILOT %s" % ("FAILED" if _failed else "DONE"))
	_log.close()
	quit(1 if _failed else 0)

func log_line(msg: String) -> void:
	var line := "[%5.1fs] %s" % [(Time.get_ticks_msec() - t_start) / 1000.0, msg]
	print(line)
	if _log:
		_log.store_line(line)

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	shot += 1
	var path := "%s/%02d_%s.png" % [out_dir, shot, label]
	root.get_texture().get_image().save_png(path)
	log_line("screenshot " + path)

func _do(step: String) -> bool:
	var parts := step.split(" ", false)
	if parts.is_empty():
		return true
	var cmd := parts[0].to_lower()
	var arg := " ".join(parts.slice(1))
	var gs := root.get_node("GameState")
	match cmd:
		"scene":
			var path := "res://ui/TitleScreen.tscn" if arg == "title" else (arg if arg.begins_with("res://") else "res://world/%s.tscn" % arg)
			if not ResourceLoader.exists(path):
				log_line("no such scene: " + path)
				return false
			change_scene_to_file(path)
			await _wait(1.5)
			if player():
				player().dialogue_active = false
			return current_scene != null
		"clock":
			var hm := arg.split(":")
			gs.clock = int(hm[0]) * 60 + (int(hm[1]) if hm.size() > 1 else 0)
			gs.advance_clock(0)
		"day":
			gs.day = int(arg)
		"cash":
			gs.cash = int(arg)
			gs.cash_changed.emit(gs.cash)
		"craving":
			gs.craving = float(arg)
			gs.craving_changed.emit(gs.craving)
		"give":
			gs.inventory.append(arg)
			gs.inventory_changed.emit()
		"strip":
			gs.test_strips = int(arg)
		"preset":
			var i: int = root.get_node("Graphics").PRESET_NAMES.find(arg)
			if i < 0:
				return false
			root.get_node("Graphics").set_preset(i)
		"view":
			root.get_node("Graphics").set_first_person(arg == "first")
		"list":
			_list()
		"walk":
			var target := current_scene.find_child(arg, true, false) as Node3D
			if target == null:
				log_line("nothing called %s here; try 'list'" % arg)
				return false
			return await walk_to(target)
		"interact":
			await press_interact()
			await _wait(0.4)
		"talk":
			log_line("said: " + await talk())
		"close":
			await close_dialogue()
		"choose":
			var menu := _open_choice()
			if menu == null:
				log_line("no menu is open")
				return false
			menu._on_pick(int(arg))
			await _wait(0.4)
		"key":
			var code := OS.find_keycode_from_string(arg)
			if code == KEY_NONE:
				log_line("unknown key " + arg)
				return false
			await _tap_key(code)
		"pad":
			if not PAD_BUTTONS.has(arg.to_upper()):
				log_line("unknown pad button " + arg)
				return false
			await _tap_pad(PAD_BUTTONS[arg.to_upper()])
		"hold":
			var a := parts[1] if parts.size() > 1 else ""
			if not InputMap.has_action(a):
				log_line("no input action " + a)
				return false
			Input.action_press(a)
			await _wait(float(parts[2]) if parts.size() > 2 else 1.0)
			Input.action_release(a)
		"wait":
			await _wait(float(arg))
		"shot":
			await screenshot(arg if arg != "" else "shot")
		"state":
			_state()
		_:
			log_line("unknown step '%s'" % cmd)
			return false
	return true

func _state() -> void:
	var gs := root.get_node("GameState")
	var p := player()
	var h := hud()
	var dialogue := ""
	if h and h.dialogue_panel.visible:
		dialogue = "%s: %s" % [h.speaker_label.text, h.text_label.text]
	var menu := _open_choice()
	log_line("state: scene=%s day=%d %s cash=$%d craving=%.0f strikes=%d wanted=%s inv=%s at=%s near=%s dialogue=[%s] menu=%s" % [
		current_scene.name if current_scene else "?", gs.day, gs.clock_text(), gs.cash, gs.craving, gs.strikes, gs.wanted, gs.inventory,
		p.global_position.snapped(Vector3.ONE * 0.1) if p else "-", p._nearest_interactable().name if p and p._nearest_interactable() else "-",
		dialogue, _menu_options(menu) if menu else "-"])

func _list() -> void:
	var p := player()
	var found: Array = get_nodes_in_group("interactable").filter(func(n): return n is Node3D and current_scene.is_ancestor_of(n))
	if p:
		found.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
	for n in found:
		log_line("  %-24s %s%s" % [n.name, n.global_position.snapped(Vector3.ONE * 0.1), "  (%.1f m)" % n.global_position.distance_to(p.global_position) if p else ""])

func _open_choice() -> CanvasLayer:
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("_on_pick"):
			return c
	return null

func _menu_options(menu: CanvasLayer) -> Array:
	return menu.find_children("*", "Button", true, false).map(func(b): return b.text)

func _tap_key(code: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame

func _tap_pad(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 1
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
