extends CanvasLayer
## Full-screen illustrated cutscenes: a few stills per scene, each slowly
## drifting (a Ken Burns pan and zoom) under letterbox bars, with a caption
## typed out along the bottom. Used at the moments the game used to jump
## straight past: the first morning of a run, a bust, an overdose, and being
## sent away for good.
##
## The stills live in assets/cutscenes/<image>.png. They're painted with
## Perchance's AI image generator (prompts and import steps in
## dev-tools/cutscene_prompts.json and dev-tools/import_cutscene_art.py). A
## missing image falls back to a dark gradient, so a scene still plays --
## text only -- before its art exists.
##
## `await Cutscene.play("busted")` pauses the game for the duration and
## returns when the last panel is dismissed. Any key or click finishes the
## caption, then moves on; Escape skips the whole scene.

signal finished

const ART_DIR := "res://assets/cutscenes/"
## How much bigger than the screen a still is drawn, so the drift never
## shows an edge.
const OVERSCAN := 1.14
const TYPE_SPEED := 42.0 # characters per second
const PANEL_MIN := 2.2 # seconds a panel holds before it can auto-advance
const AUTO_ADVANCE := 5.5 # seconds after the caption finishes
const FADE := 0.6
const BAR_H := 78.0

## Each panel: the still, its caption, which way the camera drifts
## ("in", "out", "left", "right", "up", "down"), and an optional sound as
## it appears.
const SCENES := {
	"intro": [
		{"image": "intro_mattress", "drift": "in", "sound": "sleep",
			"text": "Grey light through a bedsheet nailed over the window. You're awake before you want to be."},
		{"image": "intro_sick", "drift": "left", "sound": "groan",
			"text": "The sweats have already started. Your legs ache down to the bone. You know exactly what this is."},
		{"image": "intro_street", "drift": "right",
			"text": "Nobody's going to fix this for you. You'll have to go out there and find the money."},
	],
	"busted": [
		{"image": "busted_cuffs", "drift": "in", "sound": "busted",
			"text": "A knee in your back. The cuffs go on too tight, and you stop struggling."},
		{"image": "busted_car", "drift": "right", "sound": "door",
			"text": "The back of the cruiser smells like bleach and someone else's sick."},
	],
	"sent_away": [
		{"image": "sent_away_court", "drift": "in",
			"text": "The judge has seen your name before. Three times now. Nobody in the room looks surprised."},
		{"image": "sent_away_bus", "drift": "left", "sound": "door",
			"text": "The bus pulls away from the courthouse. You watch the block slide past the window and don't know when you'll see it again."},
	],
	# The first time you score in a run.
	"first_score": [
		{"image": "first_score_corner", "drift": "in",
			"text": "He doesn't look at you while he talks. He looks up the street, then down it, then at your hands."},
		{"image": "first_score_walk", "drift": "right",
			"text": "You walk away fast with your fist closed around it. Twenty minutes ago you'd have given anything. You nearly did."},
	],
	# Walking out of the cell.
	"released": [
		{"image": "released_door", "drift": "in", "sound": "door",
			"text": "The door grinds open. Nobody says sorry and nobody says goodbye."},
		{"image": "released_steps", "drift": "down",
			"text": "Outside it's colder than you remember. Your stuff is gone. The sickness isn't."},
	],
	# Sleeping through to the next morning. %d is the new day.
	"new_day": [
		{"image": "new_day", "drift": "in", "sound": "sleep",
			"text": "Day %d. The light comes back through the sheet whether you want it or not."},
	],
	# In the program: the block pulling at you (Temptation.gd).
	"temptation": [
		{"image": "temptation_corner", "drift": "in",
			"text": "Down the block, under the light, he lifts a hand. He doesn't wave. He doesn't have to."},
	],
	"relapse": [
		{"image": "relapse", "drift": "in",
			"text": "It works. Of course it works. That's the worst part."},
	],
	"resisted": [
		{"image": "resisted", "drift": "right",
			"text": "You keep walking. It doesn't feel like winning. It feels like your legs are made of wet sand. You keep walking anyway."},
	],
	# The good ending: five clean days in the program.
	"recovered": [
		{"image": "recovered_clinic", "drift": "in",
			"text": "Every morning, the same window, the same little cup. Nobody claps. You come back anyway."},
		{"image": "recovered_window", "drift": "right",
			"text": "On the fifth morning you take the sheet down off the window. You didn't know the room got this much light."},
		{"image": "recovered_street", "drift": "left",
			"text": "It isn't over. It won't ever quite be over. But today you're walking to something instead of away from it."},
	],
	"overdose": [
		{"image": "overdose_fade", "drift": "out",
			"text": "It hits warmer than it should. Then heavier. The room tips slowly on its side."},
		{"image": "overdose_floor", "drift": "down", "sound": "sleep",
			"text": "Your breathing slows to nothing. There's nobody in the room to notice."},
		{"image": "overdose_lights", "drift": "in",
			"text": "Blue light flickers on the ceiling. They were too late."},
	],
}

var _playing: bool = false
var _skip_all: bool = false
var _advance: bool = false
var _was_paused: bool = false

var _root: Control
var _art: TextureRect
var _fallback: ColorRect
var _vignette: ColorRect
var _caption: Label
var _hint: Label
var _audio: AudioStreamPlayer

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false

func is_playing() -> bool:
	return _playing

## True if the scene has at least one panel with painted art, for callers
## that want a still for something else (the run-end screen's backdrop).
func art_for(image: String) -> Texture2D:
	var path := ART_DIR + image + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

## `args` fill in a caption's % placeholders (the day number on "new_day").
func play(scene_id: String, args: Array = []) -> void:
	if not SCENES.has(scene_id):
		push_warning("Cutscene: unknown scene '%s'" % scene_id)
		return
	# Headless runs are the smoke test and the room builder; nobody's
	# watching, and a paused tree would stall them. The watchable playtest
	# (dev-tools/watch_playtest.gd) has a window but the same frame-counted
	# checks, so it opts out too.
	if DisplayServer.get_name() == "headless" or Engine.get_meta("no_cutscenes", false):
		return
	# One at a time: a bust that ends the run queues "sent_away" behind
	# nothing, but guard against two callers overlapping anyway.
	while _playing:
		await finished
	_playing = true
	_skip_all = false
	_was_paused = get_tree().paused
	get_tree().paused = true
	Voice.stop()

	_root.visible = true
	_root.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(_root, "modulate:a", 1.0, FADE)

	for panel in SCENES[scene_id]:
		if _skip_all:
			break
		await _show_panel(panel, args)

	var fade_out := create_tween()
	fade_out.tween_property(_root, "modulate:a", 0.0, FADE)
	await fade_out.finished
	_root.visible = false
	get_tree().paused = _was_paused
	_playing = false
	finished.emit()

func _show_panel(panel: Dictionary, args: Array = []) -> void:
	var tex := art_for(panel["image"])
	_art.texture = tex
	_art.visible = tex != null
	_fallback.visible = tex == null
	_caption.text = panel["text"] % args if not args.is_empty() else panel["text"]
	_caption.visible_characters = 0
	_hint.modulate.a = 0.0
	_advance = false

	var sound: String = panel.get("sound", "")
	if sound != "":
		_play_sound(sound)

	# Cross-fade from black on each panel after the first.
	_art.modulate = Color(1, 1, 1, 0)
	var t := create_tween()
	t.tween_property(_art, "modulate:a", 1.0, FADE)
	_start_drift(panel.get("drift", "in"))

	Voice.narrate(_caption.text)
	var chars := _caption.text.length()
	var elapsed := 0.0
	var typed_done_at := -1.0
	var heard := false
	var spoke_until := 0.0
	while not _skip_all:
		var dt := get_process_delta_time()
		elapsed += dt
		if _caption.visible_characters < chars:
			_caption.visible_characters = mini(chars, int(elapsed * TYPE_SPEED))
			if _advance:
				# First press finishes the line rather than skipping it.
				_caption.visible_characters = chars
				_advance = false
		else:
			if typed_done_at < 0.0:
				typed_done_at = elapsed
				create_tween().tween_property(_hint, "modulate:a", 0.7, 0.4)
			# With the narrator reading, hold until they're done and give it a
			# beat; without one (no Piper, no cached line), the old timing --
			# but wait a few seconds on a line still being generated.
			var auto: bool
			if Voice.is_speaking():
				heard = true
				spoke_until = elapsed
				auto = false
			elif heard:
				auto = elapsed >= maxf(PANEL_MIN, spoke_until + 1.2)
			else:
				var generating: bool = Voice._pending_key != "" and elapsed < 8.0
				auto = not generating and elapsed >= maxf(PANEL_MIN, typed_done_at + AUTO_ADVANCE)
			if (_advance and elapsed >= 0.35) or auto:
				break
			_advance = false
		await get_tree().process_frame

	Voice.stop()
	var out := create_tween()
	out.tween_property(_art, "modulate:a", 0.0, FADE * 0.6)
	await out.finished

## Slow push, pull, or pan across the still. The TextureRect is oversized
## by OVERSCAN and centred; the drift moves it within that margin.
func _start_drift(kind: String) -> void:
	var screen := get_viewport().get_visible_rect().size
	var big := screen * OVERSCAN
	var margin := (big - screen) * 0.5
	_art.size = big
	_art.pivot_offset = big * 0.5
	var centre := -margin
	var from_pos := centre
	var to_pos := centre
	var from_scale := 1.0
	var to_scale := 1.0
	match kind:
		"in":
			from_scale = 1.0
			to_scale = 1.08
		"out":
			from_scale = 1.08
			to_scale = 1.0
		"left":
			from_pos = centre + Vector2(margin.x, 0)
			to_pos = centre - Vector2(margin.x, 0)
		"right":
			from_pos = centre - Vector2(margin.x, 0)
			to_pos = centre + Vector2(margin.x, 0)
		"up":
			from_pos = centre + Vector2(0, margin.y)
			to_pos = centre - Vector2(0, margin.y)
		"down":
			from_pos = centre - Vector2(0, margin.y)
			to_pos = centre + Vector2(0, margin.y)
	_art.position = from_pos
	_art.scale = Vector2.ONE * from_scale
	var d := 12.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_art, "position", to_pos, d)
	t.tween_property(_art, "scale", Vector2.ONE * to_scale, d)

func _play_sound(name: String) -> void:
	var stream: AudioStream = null
	if SFX.VARIANTS.has(name):
		stream = SFX.VARIANTS[name].pick_random()
	elif SFX.SOUNDS.has(name):
		stream = SFX.SOUNDS[name]
	if stream == null:
		return
	_audio.stream = stream
	_audio.volume_db = SFX.VARIANT_GAIN_DB.get(name, 0.0) - 4.0
	_audio.play()

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if not pressed:
		return
	# Leave the function keys to Graphics (F3 preset, F4 frame counter).
	if event is InputEventKey and event.physical_keycode >= KEY_F1 and event.physical_keycode <= KEY_F12:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_skip_all = true
	else:
		_advance = true

func _build() -> void:
	_root = Control.new()
	_fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var black := ColorRect.new()
	black.color = Color.BLACK
	_fill(black)
	_root.add_child(black)

	# Stand-in when a still hasn't been painted yet: a dim, cold wash rather
	# than flat black, so it reads as a deliberate frame.
	_fallback = ColorRect.new()
	_fill(_fallback)
	var grad := ShaderMaterial.new()
	grad.shader = _shader("""
shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5, 0.45));
	COLOR = vec4(mix(vec3(0.10, 0.11, 0.13), vec3(0.01), smoothstep(0.1, 0.8, d)), 1.0);
}""")
	_fallback.material = grad
	_root.add_child(_fallback)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art)

	# Vignette and film grain over the art, matching the in-game grade.
	_vignette = ColorRect.new()
	_fill(_vignette)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = _shader("""
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(0.35, 0.85, d) * 0.75;
	float grain = (hash(UV * 900.0 + fract(TIME * 7.0) * 50.0) - 0.5) * 0.10;
	COLOR = vec4(vec3(max(grain, 0.0)), vig + abs(grain));
}""")
	_vignette.material = vmat
	_root.add_child(_vignette)

	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
			bar.offset_bottom = BAR_H * 0.6
		else:
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -BAR_H * 1.6
		_root.add_child(bar)

	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -BAR_H * 1.6 + 10
	_caption.offset_bottom = -26
	_caption.offset_left = 90
	_caption.offset_right = -90
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 19)
	_caption.add_theme_color_override("font_color", Color(0.86, 0.84, 0.80))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_caption)

	_hint = Label.new()
	_hint.text = "any key  ·  esc to skip"
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -220
	_hint.offset_top = -24
	_hint.offset_right = -16
	_hint.offset_bottom = -6
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.53, 0.50))
	_root.add_child(_hint)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)

func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func _fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
