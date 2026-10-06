extends Node
## Your walkman and your tapes. Pick it up off the mattress at home and
## press T anywhere to choose a tape; it plays through the headphones in
## every room -- the area music drops out and the room noise sinks a little,
## the way it does with headphones on. "Shuffle the shoebox" plays through
## every tape you own in random order instead of looping one; N skips to the
## next. A little cassette in the corner shows what's in the deck, reels
## turning. You start a run with the shoebox (STARTING_TAPES, punk
## included); the rest are at Tape Deck on the block, to buy or to lift.
##
## The music is all CC0/CC-BY from OpenGameArt (assets/tapes/CREDITS.txt,
## assets/music/CREDITS.txt). Streams load when a tape goes in, not at boot.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

## id -> title, artist, file, price at Tape Deck.
const TAPES := {
	"lofi_loop": {"title": "Lofi Hip Hop Loop", "artist": "omfgdude", "file": "res://assets/music/lofi_loop.ogg", "price": 5},
	"lofi_hiphop": {"title": "lofi hip hop", "artist": "omfgdude", "file": "res://assets/music/lofi_hiphop.ogg", "price": 5},
	"friendly_trap": {"title": "Friendly Trap", "artist": "Of Far Different Nature", "file": "res://assets/music/friendly_trap.ogg", "price": 6},
	"instrumental_hip_hop_theme": {"title": "Instrumental Hip Hop Theme", "artist": "obscure music", "file": "res://assets/tapes/instrumental_hip_hop_theme.ogg", "price": 5},
	"grime_of_the_city": {"title": "Grime of the City", "artist": "section31", "file": "res://assets/tapes/grime_of_the_city.ogg", "price": 5},
	"the_groove": {"title": "The Groove", "artist": "section31", "file": "res://assets/tapes/the_groove.ogg", "price": 5},
	"night_prowler": {"title": "Night Prowler", "artist": "section31", "file": "res://assets/tapes/night_prowler.ogg", "price": 5},
	"city_loop_0": {"title": "City Loop", "artist": "wipics", "file": "res://assets/tapes/city_loop_0.ogg", "price": 4},
	"wild_jazz": {"title": "Wild Jazz", "artist": "Pro Sensory", "file": "res://assets/tapes/wild_jazz.ogg", "price": 4},
	"dub_improv": {"title": "Dub Improv", "artist": "Sudocolon", "file": "res://assets/tapes/dub_improv.ogg", "price": 5},
	# Tape Deck's stock.
	"downtempo_chase": {"title": "Downtempo, Strong", "artist": "Nostromo", "file": "res://assets/music/downtempo_chase.ogg", "price": 6},
	"jazzy_blues": {"title": "Jazzy Blues", "artist": "LushoGames", "file": "res://assets/tapes/jazzy_blues.ogg", "price": 4},
	"nighttime_solitude": {"title": "Nighttime Solitude", "artist": "celestialghost8", "file": "res://assets/tapes/nighttime_solitude.ogg", "price": 7},
	"midnight": {"title": "Midnight", "artist": "AR", "file": "res://assets/tapes/midnight.ogg", "price": 8},
	"cyberpunk_moonlight_sonata": {"title": "Cyberpunk Moonlight Sonata", "artist": "Joth", "file": "res://assets/tapes/cyberpunk_moonlight_sonata.ogg", "price": 7},
	"sewer_nightclub": {"title": "Sewer Nightclub", "artist": "section31", "file": "res://assets/tapes/sewer_nightclub.ogg", "price": 6},
	"1_up_nightclub": {"title": "1-UP Nightclub", "artist": "neonarkade", "file": "res://assets/tapes/1_up_nightclub.ogg", "price": 5},
	"drum_and_bass": {"title": "Drum and Bass", "artist": "bertsz", "file": "res://assets/tapes/drum_and_bass.ogg", "price": 7},
	"reggae": {"title": "Reggae", "artist": "Pro Sensory", "file": "res://assets/tapes/reggae.ogg", "price": 6},
	"rock_theme": {"title": "Rock Theme", "artist": "obscure music", "file": "res://assets/tapes/rock_theme.ogg", "price": 5},
	"space_synth_wave": {"title": "Cool 80's Synth Wave", "artist": "Pro Sensory", "file": "res://assets/tapes/space_synth_wave.ogg", "price": 8},
	"vivid_existence_glitch_hop": {"title": "Vivid Existence", "artist": "Deva", "file": "res://assets/tapes/vivid_existence_glitch_hop.ogg", "price": 8},
	"xenocity_digital_acid_glitch_hop": {"title": "Xenocity - Digital Acid", "artist": "Deva", "file": "res://assets/tapes/xenocity_digital_acid_glitch_hop.ogg", "price": 8},
	"emptycity_background_music": {"title": "Empty City", "artist": "yd", "file": "res://assets/tapes/emptycity_background_music.ogg", "price": 5},
	"trance_trap_electronic_237": {"title": "Vaporwave Trap", "artist": "Dizzy Crow", "file": "res://assets/tapes/trance_trap_electronic_237.ogg", "price": 7},
	"the_familiar_city": {"title": "The Familiar City", "artist": "RawGames", "file": "res://assets/tapes/the_familiar_city.ogg", "price": 5},
	"subtle_bass": {"title": "Subtle Bass", "artist": "TinyWorlds", "file": "res://assets/tapes/subtle_bass.ogg", "price": 4},
	"blueswonkybells": {"title": "Blues Wonky Bells", "artist": "Tozan", "file": "res://assets/tapes/blueswonkybells.ogg", "price": 5},
	"christian_acid_rock": {"title": "B.M.I.", "artist": "obscure music", "file": "res://assets/tapes/christian_acid_rock.ogg", "price": 6},
	"polygraph_city": {"title": "Polygraph City", "artist": "RawGames", "file": "res://assets/tapes/polygraph_city.ogg", "price": 5},
	# Punk, in the shoebox from the start.
	"flesh_and_blood": {"title": "Flesh and Blood", "artist": "Pro Sensory", "file": "res://assets/tapes/flesh_and_blood.ogg", "price": 5, "punk": true},
	"punk_rock_metal": {"title": "W4CK", "artist": "madworldgames", "file": "res://assets/tapes/punk_rock_metal.ogg", "price": 5, "punk": true},
	"fast_cheerful_punk": {"title": "Fast Song", "artist": "annandistance", "file": "res://assets/tapes/fast_cheerful_punk.ogg", "price": 5, "punk": true},
	"la_war_zone": {"title": "L.A. War Zone", "artist": "Tsorthan Grove", "file": "res://assets/tapes/la_war_zone.ogg", "price": 6, "punk": true},
	"streets_after_midnight": {"title": "Streets After Midnight", "artist": "Tsorthan Grove", "file": "res://assets/tapes/streets_after_midnight.ogg", "price": 6, "punk": true},
}
const STARTING_TAPES := ["flesh_and_blood", "punk_rock_metal", "fast_cheerful_punk", "la_war_zone",
	"streets_after_midnight", "lofi_loop", "lofi_hiphop", "friendly_trap", "instrumental_hip_hop_theme",
	"grime_of_the_city", "the_groove", "night_prowler", "city_loop_0", "wild_jazz", "dub_improv"]
const VOLUME_DB := -6.0
## With the headphones on, the room around you sinks this much.
const AMBIENCE_DUCK_DB := -6.0

signal tape_changed(id: String)

const WIDGET_SIZE := Vector2(250, 58)

var current: String = ""
## Shuffle mode: the order the rest of the shoebox plays in.
var shuffle: bool = false
var _queue: Array = []
var _player: AudioStreamPlayer
var _widget: Control
var _reel_angle: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Walkman" if AudioServer.get_bus_index("Walkman") >= 0 else "Master"
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_on_track_finished)
	add_child(_player)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_widget = Control.new()
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.position = Vector2(12, 720 - WIDGET_SIZE.y - 12)
	_widget.size = WIDGET_SIZE
	_widget.visible = false
	_widget.draw.connect(_draw_widget)
	layer.add_child(_widget)
	GameState.run_ended.connect(func(_s): stop())

func _process(delta: float) -> void:
	if not _widget.visible:
		return
	# Reels only turn while the tape does: not under a cutscene's pause.
	if not get_tree().paused:
		_reel_angle = fmod(_reel_angle + delta * 2.4, TAU)
	_widget.queue_redraw()

func owned() -> Array:
	return GameState.tapes

func dealer_stock() -> Array:
	return TAPES.keys().filter(func(id): return not GameState.tapes.has(id))

func add_tape(id: String) -> bool:
	if not TAPES.has(id) or GameState.tapes.has(id):
		return false
	GameState.tapes.append(id)
	return true

func play(id: String, from_shuffle := false) -> void:
	if not TAPES.has(id):
		return
	if not from_shuffle:
		shuffle = false
		_queue.clear()
	var stream: AudioStream = load(TAPES[id]["file"])
	# One tape on repeat loops; shuffle lets each one end so the next goes in.
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = not shuffle
	_player.stream = stream
	_player.play()
	current = id
	SFX.play("latch", -8.0, 1.4)
	_widget.visible = true
	_set_duck(true)
	tape_changed.emit(id)

## Plays the whole shoebox in random order, reshuffling when it runs out.
func play_shuffle() -> void:
	shuffle = true
	_queue.clear()
	next()

func next() -> void:
	if current == "" and not shuffle:
		return
	if not shuffle:
		# Skipping out of a single tape starts shuffling from there.
		shuffle = true
		_queue.clear()
	if _queue.is_empty():
		_queue = GameState.tapes.duplicate()
		_queue.shuffle()
		# Never the same tape twice in a row across a reshuffle.
		if _queue.size() > 1 and _queue[0] == current:
			_queue.push_back(_queue.pop_front())
	play(_queue.pop_front(), true)

func _on_track_finished() -> void:
	if shuffle and current != "":
		next()

func stop() -> void:
	if current == "":
		return
	_player.stop()
	current = ""
	shuffle = false
	_queue.clear()
	_widget.visible = false
	_set_duck(false)
	tape_changed.emit("")

func is_playing() -> bool:
	return current != ""

func _set_duck(on: bool) -> void:
	var amb := AudioServer.get_bus_index("Ambience")
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, -2.0 + (AMBIENCE_DUCK_DB if on else 0.0))
	SFX._update_music.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("walkman"):
		open_menu()
	elif event.is_action("walkman_next") and GameState.has_walkman and not get_tree().paused:
		next()

## The shoebox of tapes: pick one, shuffle them all, or stop.
func open_menu() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not GameState.has_walkman or player == null or player.dialogue_active or get_tree().paused:
		return
	for c in get_tree().root.get_children():
		if c is CanvasLayer and (c.has_method("open") or c.has_method("open_with")):
			return
	player.dialogue_active = true
	# Punk first -- it's what's been worn thin.
	var ids: Array = GameState.tapes.duplicate()
	ids.sort_custom(func(a, b): return TAPES[a].get("punk", false) and not TAPES[b].get("punk", false))
	var options: Array = ["Shuffle the shoebox" + ("  (on)" if shuffle else "")]
	options.append_array(ids.map(func(id): return ("> " if id == current else "") + "%s  -  %s%s" % [
		TAPES[id]["title"], TAPES[id]["artist"], "   [punk]" if TAPES[id].get("punk", false) else ""]))
	var disabled := []
	options.append("Stop the tape")
	if current == "":
		disabled.append(options.size() - 1)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		player.dialogue_active = false
		if i == 0:
			play_shuffle()
		elif i <= ids.size():
			play(ids[i - 1])
		else:
			stop())
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Walkman", "%d tapes in the shoebox. What's going in?  (N skips to the next)" % ids.size(), options, disabled)

## A little cassette: shell, label with the title, two reels turning, and
## the key hints underneath.
func _draw_widget() -> void:
	var c := _widget
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, WIDGET_SIZE)
	var punk: bool = current != "" and TAPES[current].get("punk", false)
	var shell := Color(0.09, 0.09, 0.1, 0.92)
	var label_col := Color(0.93, 0.35, 0.55) if punk else Color(0.95, 0.78, 0.38)
	c.draw_rect(r, shell)
	c.draw_rect(r, Color(0, 0, 0, 0.9), false, 2.0)
	# Paper label across the top.
	var lab := Rect2(6, 5, WIDGET_SIZE.x - 12, 20)
	c.draw_rect(lab, label_col.darkened(0.15))
	c.draw_rect(Rect2(lab.position + Vector2(0, lab.size.y - 3), Vector2(lab.size.x, 3)), label_col.darkened(0.45))
	if current != "":
		var title := "%s - %s" % [TAPES[current]["title"], TAPES[current]["artist"]]
		c.draw_string(font, lab.position + Vector2(5, 14), title, HORIZONTAL_ALIGNMENT_LEFT, lab.size.x - 10, 12, Color(0.08, 0.06, 0.05))
	# Tape window with two reels.
	var win := Rect2(58, 29, WIDGET_SIZE.x - 116, 22)
	c.draw_rect(win, Color(0.03, 0.03, 0.035))
	for i in 2:
		var centre := Vector2(win.position.x + 18 + i * (win.size.x - 36), win.get_center().y)
		c.draw_circle(centre, 9.0 if i == 0 else 7.0, Color(0.32, 0.22, 0.15))  # wound tape
		c.draw_circle(centre, 4.5, Color(0.85, 0.85, 0.82))
		for k in 3:
			var a := _reel_angle * (1.0 if i == 0 else 1.25) + k * TAU / 3.0
			c.draw_line(centre, centre + Vector2.from_angle(a) * 4.0, Color(0.1, 0.1, 0.1), 1.5)
	c.draw_string(font, Vector2(8, 46), "[%s]" % GameState.control_name("walkman"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.58))
	c.draw_string(font, Vector2(WIDGET_SIZE.x - 50, 46), "[N] >>" if shuffle else "[N] shfl", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.58))
