extends SceneTree
## Windowed capture of Ghetto Wars' story HUD over a dark stand-in street: the chapter card, the phone/radio/scanner,
## the batch choice, the raid (flush bar and clock), the BUSTED card and the clean ending. Saves PNGs to res://.captures/.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_ghetto_story.gd

const Story := preload("res://fx/GhettoStory.gd")
const Plot := preload("res://fx/GhettoStoryScript.gd")

class FakeMode extends Node:
	signal wave_started(n: int)
	signal wave_cleared(n: int)
	signal enemy_killed(e, how)
	signal player_downed
	func spawn_wave(_spec: Dictionary) -> void:
		pass

var _story: Node
var _mode: Node
var _ppos := Vector3(0, 0, 40)

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.captures"))
	_backdrop()
	_new_story()
	# 1. chapter card
	_mode.wave_started.emit(1)
	_story.advance(0.1)
	await _wait(1.6)
	await _shot("gs_1_card")
	# 2. phone + radio + scanner, objective
	await _wait(2.0)
	_story.advance(1.0)
	_story.text("NICO", "Dock Boys. Two vans. They want our fucking corner. Hold it till I get the product moved.")
	await _wait(0.5)
	_story.text("TISH", "ok that was just the first wave. salt's whole crew is out tonight")
	_story.scan("Dispatch to all units. Reports of shots fired, Main Street. Hold at the perimeter. Do not engage.")
	_story.radio("NICO", "Eyes up, Kings. Nobody takes this corner on my watch.")
	_story.set_objective("HOLD THE CORNER")
	await _wait(2.8)
	await _shot("gs_2_comms")
	# 3. the choice
	_story.offer_choice("batch")
	await _wait(1.0)
	_story.advance(8.0)
	await _shot("gs_3_choice")
	_story.choose("sell")
	# 4. the raid
	_story.start_raid()
	_story.advance(60.0)
	_story.hud.set_flush(0.62, true)
	await _wait(1.2)
	await _shot("gs_4_raid")
	# 5. busted
	_story.bust("capture")
	await _wait(3.2)
	await _shot("gs_5_busted")
	Engine.time_scale = 1.0
	# 6. clean ending (a fresh story)
	_story.free()
	_mode.free()
	_new_story()
	_story.batch = "dumped"
	_story.bags = 0
	_story.is_flushed = true
	_story.escape()
	await _wait(5.5)
	await _shot("gs_6_clean")
	quit()

func _new_story() -> void:
	_mode = FakeMode.new()
	root.add_child(_mode)
	_story = Story.new()
	_story.audio = false
	_story.player_fn = func(): return _ppos
	root.add_child(_story)
	_story.set_process(false)
	_story.attach(_mode)

func _backdrop() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -1
	root.add_child(cl)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.03, 0.04, 0.09), Color(0.12, 0.07, 0.1), Color(0.05, 0.04, 0.05)])
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.height = 256
	gt.width = 4
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(tr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 24:
		var r := ColorRect.new()
		r.color = Color(1.0, 0.75, 0.4, 0.16) if i % 3 else Color(0.5, 0.7, 1.0, 0.12)
		r.position = Vector2(rng.randf() * 1180, 120 + rng.randf() * 420)
		r.size = Vector2(30 + rng.randf() * 90, 40 + rng.randf() * 200)
		cl.add_child(r)

func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < int(sec * 1000.0):
		await process_frame

func _shot(name_: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://.captures/%s.png" % name_))
	print("saved ", name_)
