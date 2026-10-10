extends Control
## The title screen, and the game's main scene: a cutscene still drifting
## behind the name, a punk tape playing, and Continue / New run / Settings /
## Quit. Continue is there when a run is saved (SaveGame) and says where you
## left it.

const SettingsMenu := preload("res://ui/SettingsMenu.gd")
const START_SCENE := "res://world/Apartment3D.tscn"
## Backdrops, one picked at random each time.
const BACKDROPS := ["intro_street", "first_score_walk", "busted_car", "released_steps", "intro_mattress"]
const MUSIC := "res://assets/tapes/la_war_zone.ogg"

var _art: TextureRect
var _buttons: VBoxContainer
var _music: AudioStreamPlayer
var _choosing_view: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture = _backdrop()
	_art.size = Vector2(1280, 720) * 1.12
	_art.position = -Vector2(1280, 720) * 0.06
	_art.pivot_offset = _art.size * 0.5
	_art.modulate = Color(1, 1, 1, 0)
	add_child(_art)
	var drift := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	drift.tween_property(_art, "position:x", _art.position.x + 60.0, 18.0)
	drift.tween_property(_art, "position:x", _art.position.x, 18.0)
	create_tween().tween_property(_art, "modulate:a", 1.0, 2.0)

	# Darken the left third, where the text sits.
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type canvas_item;
void fragment() {
	float a = mix(0.92, 0.15, smoothstep(0.0, 0.75, UV.x));
	a = max(a, smoothstep(0.55, 1.0, distance(UV, vec2(0.6, 0.5))) * 0.8);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}"""
	shade.material = mat
	add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(90, 150)
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(_label("DOPE SICK", 84, Color(0.93, 0.35, 0.55)))
	col.add_child(_label("A run lasts as long as you do.", 17, Color(0.78, 0.75, 0.68)))
	if not MetaProgress.last_run.is_empty():
		col.add_child(_label(_last_time(MetaProgress.last_run), 13, Color(0.62, 0.55, 0.6)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	col.add_child(_buttons)
	var first: Button = null
	if SaveGame.has_save():
		first = _button("Continue", _on_continue)
		var where := _label(SaveGame.summary(), 13, Color(0.6, 0.58, 0.54))
		_buttons.add_child(where)
	var new_run := _button("New run", _on_new_run)
	if first == null:
		first = new_run
	_button("Settings", _on_settings)
	_button("Record", _on_record)
	_button("Credits", _on_credits)
	_button("Quit", func(): get_tree().quit())
	first.grab_focus.call_deferred()

	if MetaProgress.know_how > 0:
		var kh := _label("Know-How: %d" % MetaProgress.know_how, 14, Color(0.85, 0.78, 0.35))
		kh.position = Vector2(90, 660)
		add_child(kh)
	var hint := _label("Music: \"L.A. War Zone\" - Tsorthan Grove (CC0)", 11, Color(0.45, 0.43, 0.4))
	hint.position = Vector2(930, 690)
	add_child(hint)

	_music = AudioStreamPlayer.new()
	_music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	var stream: AudioStream = load(MUSIC)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -30.0
	add_child(_music)
	_music.play()
	create_tween().tween_property(_music, "volume_db", -10.0, 3.0)

func _backdrop() -> Texture2D:
	var ids := BACKDROPS.duplicate()
	ids.shuffle()
	for id in ids:
		var tex := Cutscene.art_for(id)
		if tex:
			return tex
	return null

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(func():
		SFX.play("blip", -6.0, 0.9)
		action.call())
	_buttons.add_child(b)
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _on_continue() -> void:
	_fade_out()
	SaveGame.continue_run()

## New run asks how you want to see it first: through your own eyes, or
## the camera up over the room. Back (Esc / circle) returns to the menu.
func _on_new_run() -> void:
	for b in _buttons.get_children():
		b.visible = false
	var fp := _button("First person", _start_run.bind(true))
	var tp := _button("Third person", _start_run.bind(false))
	var note := _label("Through your own eyes, or from up over the room. Settings can change it later.", 13, Color(0.6, 0.58, 0.54))
	_buttons.add_child(note)
	_choosing_view = true
	# Last time's choice is the default.
	(fp if Graphics.first_person else tp).grab_focus.call_deferred()

func _start_run(first_person: bool) -> void:
	Graphics.set_first_person(first_person)
	SaveGame.delete()
	GameState.start_run()
	_fade_out()
	get_tree().change_scene_to_file(START_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if _choosing_view and event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		_choosing_view = false
		var kids := _buttons.get_children()
		for i in kids.size():
			if i >= kids.size() - 3:
				kids[i].queue_free()
			else:
				kids[i].visible = true
		(kids[0] as Control).grab_focus()

func _on_settings() -> void:
	_buttons.visible = false
	var s := SettingsMenu.new()
	get_tree().root.add_child(s)
	s.open()
	s.closed.connect(func():
		_buttons.visible = true
		(_buttons.get_child(0) as Control).grab_focus())

static func _last_time(last: Dictionary) -> String:
	var d := int(last.get("day", 0))
	match last.get("cause", ""):
		"overdose":
			return "Last time: you went over on day %d." % d
		"recovered":
			return "Last time: you got out."
		"alone":
			return "Last time: by day %d there was no one left." % d
	return "Last time: picked up for the last time on day %d." % d

const CREDITS := """Made with Godot 4.

People: Microsoft Rocketbox avatars (MIT).
Places: Poly Haven models and textures, ambientCG materials (CC0); Kenney kits and sounds (CC0).
Cutscenes: real footage from Mixkit (Mixkit free licence), cut and regraded.
Music: OpenGameArt -- omfgdude, Nostromo, Of Far Different Nature (CC-BY), Tsorthan Grove,
Centurion_of_war, Eldritch Grim (CC0). Room tone: CC0 field recordings.
Full lists sit beside the files: assets/*/CREDITS*, LICENSE*.

If you or someone you love is using: carry naloxone, don't use alone, and
there are people whose whole job is to help. Find one."""

func _on_record() -> void:
	_buttons.visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(80, 300)
	panel.custom_minimum_size = Vector2(1000, 0)
	add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(cols)
	var runs := "Runs: %d    Best: day %d\n\n" % [MetaProgress.runs_completed, MetaProgress.best_day]
	var past: Array = MetaProgress.history.duplicate()
	past.reverse()
	if past.is_empty():
		runs += "No runs yet."
	for i in mini(past.size(), 10):
		var r: Dictionary = past[i]
		runs += "%s   ($%d, %d doses)\n" % [MetaProgress.ending_words(r["cause"], int(r["day"])), int(r.get("cash", 0)), int(r.get("doses", 0))]
	var left := _label(runs, 13, Color(0.82, 0.8, 0.75))
	left.custom_minimum_size = Vector2(380, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cols.add_child(left)
	var got := "Achievements  %d / %d\n\n" % [MetaProgress.achievements.size(), MetaProgress.ACHIEVEMENTS.size()]
	for id in MetaProgress.ACHIEVEMENTS:
		var a: Array = MetaProgress.ACHIEVEMENTS[id]
		got += ("[x] %s -- %s\n" if MetaProgress.achievements.has(id) else "[  ] %s -- %s\n") % a
	var right := _label(got, 13, Color(0.85, 0.78, 0.5))
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		panel.queue_free()
		_buttons.visible = true
		(_buttons.get_child(0) as Control).grab_focus())
	box.add_child(back)
	back.grab_focus.call_deferred()

func _on_credits() -> void:
	_buttons.visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(80, 330)
	panel.custom_minimum_size = Vector2(760, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var text := _label(CREDITS, 13, Color(0.82, 0.8, 0.75))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(740, 0)
	box.add_child(text)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		panel.queue_free()
		_buttons.visible = true
		(_buttons.get_child(0) as Control).grab_focus())
	box.add_child(back)
	back.grab_focus.call_deferred()

func _fade_out() -> void:
	create_tween().tween_property(_music, "volume_db", -40.0, 0.5)
