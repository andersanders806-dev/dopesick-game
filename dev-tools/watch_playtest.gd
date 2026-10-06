extends "res://dev-tools/smoke_test_3d.gd"
## Watchable playtest: runs every scenario in smoke_test_3d.gd in a real
## window, with an overlay naming the scenario the bot is on and each check
## as it passes or fails. Same checks, same scenes -- you just get to see it.
##   godot --path . -s res://dev-tools/watch_playtest.gd [-- <pause seconds>]
## Each new scenario freezes the game for a moment (default 2.5 s) so its
## title can be read. Don't touch the mouse or keyboard while it plays.

const MAX_LINES := 12

var _pause_s := 2.5
var _total := 0
var _done := 0
var _passed := 0
var _title: Label
var _progress: Label
var _lines: VBoxContainer
var _bar: ProgressBar

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		_pause_s = float(args[0])
	# Count the scenarios from the test's own source so the overlay never
	# goes stale when one is added.
	var src := FileAccess.get_file_as_string("res://dev-tools/smoke_test_3d.gd")
	_total = src.count("await _section(\"")
	_build_overlay()
	# Cutscenes pause the tree, which would freeze the frame-counted checks.
	Engine.set_meta("no_cutscenes", true)
	super._initialize()
	# The checks count physics frames. Below ~30 FPS several physics frames
	# run per drawn frame and per-frame work (navmesh bakes, animation,
	# audio) falls behind them, so run on Low. Sandboxed: not saved.
	root.get_node("Graphics").set_preset.call_deferred(0)
	root.get_node("Graphics").set_show_fps.call_deferred(true)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_progress = Label.new()
	_progress.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_progress.text = "PLAYTEST BOT  -  starter..."
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bar = ProgressBar.new()
	_bar.max_value = maxi(1, _total)
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_lines = VBoxContainer.new()
	for c in [_progress, _title, _bar, _lines]:
		box.add_child(c)
	panel.add_child(box)
	layer.add_child(panel)
	root.add_child.call_deferred(layer)

func _section(title: String) -> void:
	super._section(title)
	_done += 1
	_progress.text = "PLAYTEST BOT  -  scenarie %d / %d  -  %d checks ok" % [_done, _total, _passed]
	_title.text = title
	_bar.value = _done
	for c in _lines.get_children():
		c.queue_free()
	# Freeze time (not pause the tree: autoloads process while paused) so
	# the title can be read. It happens between scenarios, before the next
	# one sets anything up, so no check sees time pass that it didn't ask for.
	if _pause_s > 0.0:
		Engine.time_scale = 0.0
		await create_timer(_pause_s, true, false, true).timeout
		Engine.time_scale = 1.0

func _check(ok: bool, what: String) -> void:
	super._check(ok, what)
	if ok:
		_passed += 1
	_progress.text = "PLAYTEST BOT  -  scenarie %d / %d  -  %d checks ok" % [_done, _total, _passed]
	var line := Label.new()
	line.text = ("OK    " if ok else "FAIL  ") + what.strip_edges()
	line.add_theme_color_override("font_color", Color(0.45, 0.9, 0.45) if ok else Color(1, 0.35, 0.3))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(536, 0)
	_lines.add_child(line)
	while _lines.get_child_count() > MAX_LINES:
		var old := _lines.get_child(0)
		_lines.remove_child(old)
		old.queue_free()

func _finished() -> void:
	var failed := _failures
	_title.text = "FÆRDIG: %s" % ("alt bestået" if failed == 0 else "%d fejl" % failed)
	_progress.text = "PLAYTEST BOT  -  %d scenarier  -  %d checks ok, %d fejl" % [_done, _passed, failed]
	Engine.time_scale = 0.0
	await create_timer(10.0, true, false, true).timeout
