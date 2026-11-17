extends Control
## The title screen, and the game's main scene: a cutscene still drifting
## behind the name, a punk tape playing, and New run / Settings / Record /
## Quit. There's no Continue: every start is a fresh run.

const SettingsMenu := preload("res://ui/SettingsMenu.gd")
const PadFocus := preload("res://ui/PadFocus.gd")
const TitleWarm := preload("res://fx/TitleWarm.gd")
const U := preload("res://ui/UiStyle.gd")
const START_SCENE := "res://world/Apartment3D.tscn"
## Backdrops, one picked at random each time.
const BACKDROPS := ["intro_street", "first_score_walk", "busted_car", "released_steps", "intro_mattress"]
const MUSIC := "res://assets/tapes/la_war_zone.ogg"

var _art: TextureRect
var _buttons: VBoxContainer
var _music: AudioStreamPlayer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	# Back from Dead Block (the pause menu's quit, or its game-over screen):
	# the story's footing again.
	ZombieMode.leave()
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
	# Film grain and a vignette over the whole picture (it stays under the menu's text).
	add_child(U.grain_overlay(0.025, 0.5))

	var col := VBoxContainer.new()
	col.position = Vector2(90, 96)
	col.custom_minimum_size = Vector2(420, 0)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var logo := _label("DOPE SICK", U.FS_TITLE, U.PINK)
	U.style_label(logo, U.BUNGEE, U.FS_TITLE, U.PINK, 2)
	col.add_child(logo)
	col.add_child(_label("A run lasts as long as you do.", U.FS_BODY, Color(0.78, 0.75, 0.68)))
	if not MetaProgress.last_run.is_empty():
		col.add_child(_label(_last_time(MetaProgress.last_run), U.FS_SMALL, Color(0.62, 0.55, 0.6)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	col.add_child(gap)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	col.add_child(_buttons)
	# No Continue: it's a survival run, and every start is a fresh one --
	# you die, you start over.
	var first := _button("New run", _start_run)
	# Dead Block is a shooter: straight in (gore and damage numbers live in the pause menu).
	_button("Zombies", _start_zombies)
	# Ghetto Wars: the same block, held against a rival crew with guns.
	_button("Ghetto Wars", _start_gangs)
	_button("Settings", _on_settings)
	_button("Record", _on_record)
	_button("Credits", _on_credits)
	_button("Quit", func(): get_tree().quit())
	PadFocus.dress(_buttons)
	first.grab_focus.call_deferred()

	if MetaProgress.know_how > 0:
		var kh := _label("Know-How: %d" % MetaProgress.know_how, 14, Color(0.85, 0.78, 0.35))
		kh.position = Vector2(90, 690)
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
	# The game's own shaders compile a couple a frame (fx/TitleWarm.gd). The first time, that happens behind an
	# opening card, so the menu never stutters on screen: it shows (and takes input) once the card lifts.
	if TitleWarm.pending():
		_opening_card()
		TitleWarm.start(self, 0.2)
	else:
		TitleWarm.start(self)

## The loading card holds until everything the menu would otherwise stream in behind it is in (the street, the
## cast, the cars, the shops, the shader pass, the guns' sounds), but never longer than CARD_MAX; it shows at
## least CARD_MIN so it reads as a card and not a flicker.
const CARD_MAX := 25.0
const CARD_MIN := 1.5
const BAR_X := 90.0
const BAR_W := 1100.0
const BAR_Y := 698.0
const WARNING := [
	"Dope Sick is about addiction and withdrawal.",
	"It shows drug use, violence and a city that does not care.",
]
const HELP_LINE := "If you or someone you know is struggling, you are not alone."

var _card_fill: ColorRect
var _starting := false

## Black with the game's name, a content warning and a thin bar that follows the real loading, while the shaders
## compile and the background loads finish (autoload/SceneLoader.gd drains them). The menu underneath takes no
## input until it lifts. The card is named GoBlack like the black of a scene change, so the perf probe reads it as
## "nothing visible". It shows once per process: back on the title later, everything is already in.
func _opening_card() -> void:
	var card := ColorRect.new()
	card.name = "GoBlack"
	card.color = Color.BLACK
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	# (The card itself is opaque from the first frame; only its words and bar fade in.)
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)
	var logo := Label.new()
	U.style_label(logo, U.BUNGEE, U.FS_TITLE, U.PINK, 2)
	logo.text = "DOPE SICK"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.offset_top = -150.0
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(logo)
	var warn := VBoxContainer.new()
	warn.set_anchors_preset(Control.PRESET_FULL_RECT)
	warn.offset_top = 372.0
	warn.offset_left = 200.0
	warn.offset_right = -200.0
	warn.add_theme_constant_override("separation", 6)
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(warn)
	for line in WARNING:
		warn.add_child(_card_line(line, U.FS_BODY, Color(0.82, 0.79, 0.72)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	warn.add_child(gap)
	warn.add_child(_card_line(HELP_LINE, U.FS_SMALL, Color(0.62, 0.58, 0.58)))
	var word := Label.new()
	U.style_label(word, U.BODY, U.FS_SMALL, Color(0.55, 0.52, 0.5), 2)
	word.text = "Loading"
	word.position = Vector2(BAR_X, BAR_Y - 26.0)
	content.add_child(word)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.09)
	track.position = Vector2(BAR_X, BAR_Y)
	track.size = Vector2(BAR_W, 3.0)
	content.add_child(track)
	_card_fill = ColorRect.new()
	_card_fill.color = U.PINK
	_card_fill.size = Vector2(0.0, 3.0)
	track.add_child(_card_fill)
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.5)
	_buttons.process_mode = Node.PROCESS_MODE_DISABLED
	TitleWarm.card_up = true
	_lift_card(card)

func _card_line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	U.style_label(l, U.BODY, size, color, 0)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## How far the card's loading is, 0..1: the queued loads, and the shader pass counted as one more of them.
func _card_progress() -> float:
	var loads := SceneLoader.load_progress()
	var peak := float(maxi(SceneLoader._peak, 1))
	return clampf((loads * peak + TitleWarm.progress) / (peak + 1.0), 0.0, 1.0)

func _loaded() -> bool:
	return TitleWarm.finished and SceneLoader.pending_count() == 0

func _lift_card(card: ColorRect) -> void:
	var t0 := Time.get_ticks_msec()
	SceneLoader.drain_in_black(int(CARD_MAX * 1000.0))
	var shown := 0.0
	while is_inside_tree() and (Time.get_ticks_msec() - t0 < CARD_MIN * 1000.0 or \
			(not _loaded() and Time.get_ticks_msec() - t0 < CARD_MAX * 1000.0)):
		await get_tree().process_frame
		# Never backwards, and eased so a big load landing does not jump the bar.
		shown = maxf(shown, minf(_card_progress(), shown + 0.12))
		_card_fill.size.x = BAR_W * shown
	TitleWarm.card_ms = Time.get_ticks_msec() - t0
	if not is_inside_tree():
		TitleWarm.card_up = false
		return
	_card_fill.size.x = BAR_W
	await get_tree().create_timer(0.25).timeout
	var tw := create_tween()
	tw.tween_property(card, "color:a", 0.0, 0.6)
	tw.parallel().tween_property(card.get_child(0), "modulate:a", 0.0, 0.4)
	await tw.finished
	card.queue_free()
	TitleWarm.card_up = false
	_buttons.process_mode = Node.PROCESS_MODE_INHERIT
	if _buttons.get_child_count() > 0:
		(_buttons.get_child(0) as Control).grab_focus()

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
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	U.menu_item(b)
	b.pressed.connect(func():
		SFX.play("blip", -6.0, 0.9)
		action.call())
	_buttons.add_child(b)
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	U.style_label(l, U.BODY, size, color)
	return l

## The game is first person only, so every mode just starts: no view to choose.
func _on_new_run() -> void:
	_start_run()

## From the first press until the scene changes the menu takes no more input (a second click or Enter in the
## black would start the run twice, or a second mode on top).
func _lock_menu() -> bool:
	if _starting:
		return false
	_starting = true
	_buttons.process_mode = Node.PROCESS_MODE_DISABLED
	return true

func _start_run() -> void:
	if not _lock_menu():
		return
	SaveGame.delete()
	GameState.start_run()
	_fade_out()
	if DisplayServer.get_name() != "headless":
		# The apartment takes a second or more to build: the title goes to black first, so the screen never
		# freezes on the menu while it loads.
		await _go_black()
	get_tree().change_scene_to_file(START_SCENE)

## Fades the menu to black and holds it for two frames (so the black is what is on the screen when the load
## blocks the next frame).
func _go_black() -> void:
	var black := ColorRect.new()
	black.name = "GoBlack"
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.3)
	await tw.finished
	await get_tree().process_frame
	await get_tree().process_frame

## Dead Block: the block at night, the dead, and rounds (autoload/ZombieMode.gd).
## Its own save; the story's run is left as it is.
func _start_zombies() -> void:
	if not _lock_menu():
		return
	_fade_out()
	ZombieMode.start()

func _start_gangs() -> void:
	if not _lock_menu():
		return
	_fade_out()
	ZombieMode.start_gangs()

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

People: Microsoft Rocketbox avatars (MIT), also the first-person arms.
Places: Poly Haven models and textures, ambientCG materials (CC0); Kenney kits and sounds (CC0).
Cars (Sketchfab, CC BY 4.0): 8sianDude -- Crown Victoria taxi and police; Daniel Zhabotinsky -- Shvan '92;
Comrade1280 -- Generic passenger car pack; Rashad Ibrahimli -- abandoned sedan, crashed car; Renafox -- burned-out cars.
Guns (Poly Haven, CC0; Sketchfab, CC BY 4.0, creativecommons.org/licenses/by/4.0): nebula075 -- MPX SMG (sketchfab.com/nebula075);
AK -- Mossberg500 Shotgun low-poly (sketchfab.com/skaf13); Michael Makivic -- FPS Red Dot Sight (sketchfab.com/makivic); Derek Flanagan -- HK 416 Low Poly (sketchfab.com/derek_flanagan);
austincford -- Low Poly Magnum Revolver (sketchfab.com/austincford); MaX3Dd -- DP28 Low-poly PBR (sketchfab.com/MaX3Dd);
OKacin Creative -- OWK 19 Pistol; wallon -- Tec-9; creationwasteland -- UZI; quick_loop -- HK MP5; h1ggs -- KRSV VECTOR; Billy Jackman -- AK-47 Game Ready;
notcplkerry -- low-poly M16A4; HenRi -- Sawed-Off Dirty / Double Barrel; ELIZION -- Desert Eagle; D_U -- low-poly AA-12 and Barrett M82 A1; Ecler -- M14 Rifle;
yeetuseleetus -- M249 saw; javadbayat -- RPG 7; DVLT -- Baseball bat; Belonosoff -- Machete.
Model links: assets/guns/LICENSE.md.
Gun sounds (OpenGameArt): The Free Firearm Sound Library by Still North Media (CC0); KuraiWolf -- Light Machine Gun (CC BY 4.0); Michel Baradari, Mike Koenig (CC BY 3.0);
SpringySpringo, BMacZero, zer0_sol, LFA, kurt (CC0), layered and level-matched for this game. Lists: assets/sfx/CREDITS/guns-recorded.md.
Launcher and melee sounds (OpenGameArt): dklon -- Rocket Launch Pack, CGEffex -- Punch Slap n Kick (CC BY 3.0); will_leamon -- Fleshy Fight Sounds (OGA-BY 3.0);
Joth, NenadSimic, artisticdude, Independent.nu, qubodup (CC0).
Animation: Quaternius -- Universal Animation Library 1 and 2 (CC0), retargeted onto the Rocketbox rig.
Zombie and kick animations: generated with NVIDIA Kimodo (NVIDIA Open Model License) through kimodo.cpp (Apache-2.0); built with Meta Llama 3.
Cutscenes: real footage from Mixkit (Mixkit free licence), cut and regraded.
Music: OpenGameArt -- omfgdude, Nostromo, Of Far Different Nature (CC-BY), Tsorthan Grove,
Centurion_of_war, Eldritch Grim (CC0). Room tone: CC0 field recordings.
Fonts: Bungee by David Jonathan Ross, Barlow by Jeremy Tribby, DSEG by keshikan (SIL OFL).
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
