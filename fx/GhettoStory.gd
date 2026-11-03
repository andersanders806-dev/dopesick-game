extends Node
## Ghetto Wars' story layer: five chapters over the waves (fx/GhettoStoryScript.gd is the script). It listens to the
## mode (`attach(mode)`: wave_started(n), wave_cleared(n), enemy_killed(e, how), player_downed()) and plays short beats:
## phone texts sliding in, crew radio, a police scanner, chapter cards, two choices that change the ending, the stash
## run, the batch, and the raid (flush the stash at the sink, run for the car, or get cuffed). It shows itself on
## ui/GhettoStoryHud.gd, speaks through fx/GhettoVoice.gd and scores itself with assets/music/ghetto/*.ogg.
##
## The set dressing (burning cars, graffiti, helicopter, the overdoses on the street) listens to `chapter_started(id)`
## and `beat(id)`; ids: cops_circling, stash_pressure, drive_by, snitch_revealed, ods_street, ods_more, raid_start,
## heli, flushed, escaped, busted. The map can mark objective spots with a Node3D in group "ghetto_pt" with meta "pt"
## set to stash_a..stash_d, sink or car; otherwise the defaults of the script are used.
##
## Tests drive it without a window: `audio = false`, `advance(dt)` instead of the frame loop (`set_process(false)`),
## `player_fn` / `hold_fn` for where the player is and whether interact is held.

signal chapter_started(id: String)
signal chapter_ended(id: String)
signal beat(id: String)
signal text_received(from: String, body: String, stamp: String)
signal radio_line(who: String, line: String)
signal scanner_line(line: String)
signal objective_changed(text: String)
signal choice_offered(id: String, options: Array)
signal choice_made(id: String, option: String)
signal bags_changed(have: int, total: int)
signal raid_started
signal flushed
signal escaped
signal busted
signal story_finished(ending: String)

const Plot := preload("res://fx/GhettoStoryScript.gd")
const HudScript := preload("res://ui/GhettoStoryHud.gd")
const Voice3 := preload("res://fx/GhettoVoice.gd")
const SFX_DIR := "res://assets/sfx/ghetto/"
const MUSIC_DIR := "res://assets/music/ghetto/"
const PICKUP_RADIUS := 1.7
const SINK_RADIUS := 2.2
const CAR_RADIUS := 3.5

var mode: Node
var hud: Node
var audio := true
var with_hud := true
## Where story pieces (stash bags, the sink and car markers) are built; the current scene when null.
var props_parent: Node3D
var player_fn := Callable()
var hold_fn := Callable()

var chapter := ""
var chapter_index := -1
var wave := 0
var kills := 0
var batch := "" # "", "dumped", "sold"
var hesitated := false
var bags := 0
var bag_total := 4
var stash_started := false
var raid_active := false
var flush_amount := 0.0
var is_flushed := false
var escape_left := 0.0
var reinforcements := 0
var ending := ""
var finished := false
var ods := 0 # overdoses on the street that the batch is on you for
var saved := 0

## What came in, for the log and the tests.
var texts: Array[Dictionary] = []
var radios: Array[Dictionary] = []
var scans: Array[String] = []
var objective := ""
var chapters_seen: Array[String] = []
var beats_seen: Array[String] = []

var _clock := 0.0
var _timeline: Array = []
var _minutes := Plot.CLOCK_START
var _choice := ""
var _choice_left := 0.0
var _until_reinforce := 0.0
var _bags: Array[Node3D] = []
var _markers: Dictionary = {}
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music: Array[AudioStreamPlayer] = []
var _music_track := ""
var _stream_cache: Dictionary = {}
var _slow_left := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if with_hud and hud == null:
		hud = HudScript.new()
		add_child(hud)
		hud.choice_picked.connect(choose)
	if audio:
		for i in 4:
			var p := AudioStreamPlayer.new()
			p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
			add_child(p)
			_sfx.append(p)
		for i in 2:
			var m := AudioStreamPlayer.new()
			m.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
			m.volume_db = -80.0
			add_child(m)
			_music.append(m)

func _exit_tree() -> void:
	# A busted slow-mo must never outlive the story.
	if _slow_left >= 0.0:
		Engine.time_scale = 1.0
	_clear_markers()

func _process(delta: float) -> void:
	var ts := maxf(Engine.time_scale, 0.05)
	advance(delta / ts)

## The one call the mode makes: `GhettoStory.install(self, self)` once the run is up (the story node lives under
## `parent`, listens to `mode` and frees with it).
static func install(mode_node: Node, parent: Node) -> Node:
	var st: Node = load("res://fx/GhettoStory.gd").new()
	st.name = "GhettoStory"
	parent.add_child(st)
	st.attach(mode_node)
	return st

# --- the mode's hooks ------------------------------------------------------------------------

func attach(m: Node) -> void:
	mode = m
	for pair in [["wave_started", _on_wave_started], ["wave_cleared", _on_wave_cleared],
			["enemy_killed", _on_enemy_killed], ["player_downed", _on_player_downed]]:
		if m.has_signal(pair[0]) and not m.is_connected(pair[0], pair[1]):
			m.connect(pair[0], pair[1])

func detach() -> void:
	if mode == null or not is_instance_valid(mode):
		return
	for pair in [["wave_started", _on_wave_started], ["wave_cleared", _on_wave_cleared],
			["enemy_killed", _on_enemy_killed], ["player_downed", _on_player_downed]]:
		if mode.has_signal(pair[0]) and mode.is_connected(pair[0], pair[1]):
			mode.disconnect(pair[0], pair[1])
	mode = null

func mature() -> bool:
	var zm := get_node_or_null("/root/ZombieMode")
	return bool(zm.get("mature_language")) if zm != null else true

func _on_wave_started(n: int) -> void:
	if finished:
		return
	wave = n
	var idx := Plot.chapter_index_for_wave(n)
	if idx != chapter_index:
		_start_chapter(idx)
	_schedule("w%d" % n)

func _on_wave_cleared(n: int) -> void:
	if finished:
		return
	_schedule("w%d_clear" % n)

func _on_enemy_killed(_e = null, _how = null) -> void:
	kills += 1

func _on_player_downed() -> void:
	if raid_active and not finished:
		bust("downed")

# --- chapters --------------------------------------------------------------------------------

func chapter_data() -> Dictionary:
	return Plot.CHAPTERS[chapter_index] if chapter_index >= 0 else {}

func _start_chapter(idx: int) -> void:
	if chapter != "":
		chapter_ended.emit(chapter)
	chapter_index = idx
	var ch: Dictionary = Plot.CHAPTERS[idx]
	chapter = ch["id"]
	chapters_seen.append(chapter)
	chapter_started.emit(chapter)
	if hud != null:
		hud.show_chapter(idx + 1, ch["title"], Plot.pick(ch["sub"], mature()), ch["place"])
	_play_music(ch["music"])
	_play_sfx("chapter_hit")

# --- the timeline ----------------------------------------------------------------------------

func _schedule(trigger: String) -> void:
	for e in Plot.BEATS.get(trigger, []):
		_timeline.append({"at": _clock + float(e["t"]), "e": e})
	_timeline.sort_custom(func(a, b): return a["at"] < b["at"])

## Steps the story by `dt` seconds (the frame loop's, in real time; tests call it).
func advance(dt: float) -> void:
	_clock += dt
	while not _timeline.is_empty() and _timeline[0]["at"] <= _clock:
		var item: Dictionary = _timeline.pop_front()
		_do(item["e"])
	if _slow_left >= 0.0:
		_slow_left -= dt
		if _slow_left < 0.0:
			Engine.time_scale = 1.0
	if _choice != "":
		_choice_left -= dt
		if hud != null:
			hud.set_choice_time(_choice_left / Plot.CHOICE_SECONDS)
		if _choice_left <= 0.0:
			hesitated = true
			choose("sell")
	if stash_started and bags < bag_total:
		_pick_up_bags()
	if raid_active and not finished:
		_raid_step(dt)
	if hud != null:
		hud.set_clock(_clock)

func _do(e: Dictionary) -> void:
	if e.has("when") and e["when"] != batch:
		return
	match String(e["k"]):
		"text":
			text(e["from"], Plot.pick(e["body"], mature()))
		"radio":
			radio(e["who"], Plot.pick(e["line"], mature()))
		"scan":
			scan(Plot.pick(e["line"], mature()))
		"obj":
			set_objective(Plot.pick(e["text"], mature()))
		"beat":
			emit_beat(e["id"])
		"sfx":
			_play_sfx(e["name"])
		"spawn":
			spawn(e["spec"])
		"choice":
			offer_choice(e["id"])
		"stash":
			start_stash()
		"stash_report":
			var key := "all" if bags >= bag_total else ("some" if bags > 0 else "none")
			radio("NICO", Plot.pick(Plot.STASH_REPORT[key], mature()))
			set_objective("HOLD THE CORNER")
		"raid":
			start_raid()

func emit_beat(id: String) -> void:
	beats_seen.append(id)
	beat.emit(id)

func text(from: String, body: String) -> void:
	_minutes += 2 + (texts.size() % 3)
	var stamp := Plot.clock_text(_minutes)
	var name_: String = Plot.WHO.get(from, {"name": from})["name"]
	texts.append({"from": from, "name": name_, "body": body, "stamp": stamp})
	text_received.emit(from, body, stamp)
	if hud != null:
		hud.show_text(from, name_, body, stamp, Plot.WHO.get(from, {"color": Color.WHITE})["color"])
	_play_sfx("text_in")

func radio(who: String, line: String) -> void:
	radios.append({"who": who, "line": line})
	radio_line.emit(who, line)
	if hud != null:
		hud.show_radio(who, line, Plot.WHO.get(who, {"color": Color.WHITE})["color"])
	if audio:
		_play_sfx("squelch_on")
		Voice3.say(self, "radio", line)

func scan(line: String) -> void:
	scans.append(line)
	scanner_line.emit(line)
	if hud != null:
		hud.show_scanner(line)
	if audio:
		_play_sfx("scanner_beep")
		Voice3.say(self, "scan", line, -3.0)

func set_objective(t: String) -> void:
	objective = t
	objective_changed.emit(t)
	if hud != null:
		hud.set_objective(t)

## Asks the mode for extra men (GhettoMode.spawn_wave): the drive-by car, the police.
func spawn(spec: Dictionary) -> void:
	if mode != null and mode.has_method("spawn_wave"):
		mode.spawn_wave(spec.duplicate(true))

# --- the stash run (chapter 2) ----------------------------------------------------------------

func _point(name_: String) -> Vector3:
	var marks: Array = get_tree().get_nodes_in_group("ghetto_pt") if is_inside_tree() else []
	for n in marks:
		if n is Node3D and String(n.get_meta("pt", "")) == name_:
			return (n as Node3D).global_position
	return Plot.POINTS[name_]

func _prop_parent() -> Node3D:
	if props_parent != null and is_instance_valid(props_parent):
		return props_parent
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene as Node3D

func start_stash() -> void:
	if stash_started:
		return
	stash_started = true
	bags = 0
	bag_total = Plot.BAG_NAMES.size()
	bags_changed.emit(bags, bag_total)
	_bag_objective()
	var parent := _prop_parent()
	if parent == null:
		return
	for nm in Plot.BAG_NAMES:
		var bag := _make_bag()
		bag.name = "StashBag_" + nm
		bag.set_meta("pt", nm)
		parent.add_child(bag)
		bag.global_position = _point(nm)
		_bags.append(bag)

func _make_bag() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.2
	bm.height = 0.7
	body.mesh = bm
	body.rotation_degrees = Vector3(0, 0, 90)
	body.position = Vector3(0, 0.22, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.14, 0.1)
	mat.roughness = 0.8
	body.material_override = mat
	n.add_child(body)
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.04, 0.46)
	strap.mesh = sm
	strap.position = Vector3(0, 0.44, 0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.7, 0.55, 0.15)
	strap.material_override = smat
	n.add_child(strap)
	# A faint amber glow so it can be found in the dark.
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.25)
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.position = Vector3(0, 0.8, 0)
	n.add_child(l)
	return n

func _player_pos() -> Vector3:
	if player_fn.is_valid():
		return player_fn.call()
	if is_inside_tree():
		var p := get_tree().get_first_node_in_group("player") as Node3D
		if p != null:
			return p.global_position
	return Vector3(INF, INF, INF)

func _pick_up_bags() -> void:
	var pp := _player_pos()
	for i in range(Plot.BAG_NAMES.size()):
		var nm: String = Plot.BAG_NAMES[i]
		if _collected.has(nm):
			continue
		if _flat(pp, _point(nm)) <= PICKUP_RADIUS:
			collect_bag(nm)

var _collected := {}

func collect_bag(nm := "") -> void:
	if nm == "":
		for b in Plot.BAG_NAMES:
			if not _collected.has(b):
				nm = b
				break
	if nm == "" or _collected.has(nm):
		return
	_collected[nm] = true
	bags += 1
	for b in _bags:
		if is_instance_valid(b) and String(b.get_meta("pt", "")) == nm:
			b.queue_free()
	_bags = _bags.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
	_play_sfx("bag_pickup")
	bags_changed.emit(bags, bag_total)
	_bag_objective()

func _bag_objective() -> void:
	if bags >= bag_total:
		set_objective("HOLD THE BACK ROOM")
	else:
		set_objective("%s  %d/%d" % ["GRAB THE STASH BAGS", bags, bag_total])

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# --- the batch (chapter 4) --------------------------------------------------------------------

func offer_choice(id: String) -> void:
	_choice = id
	_choice_left = Plot.CHOICE_SECONDS
	var opts := [
		{"key": "dump", "label": "DUMP THE BATCH", "sub": "Down the drain. Nobody on Fifth Street gets it. You eat the $%d." % Plot.DUMP_LOSS},
		{"key": "sell", "label": "SELL IT", "sub": "+%d points now. Whatever's in it goes out the door." % sell_points()},
	]
	choice_offered.emit(id, opts)
	if hud != null:
		hud.show_choice(id, "THE BATCH", opts, Plot.CHOICE_SECONDS)

func sell_points() -> int:
	return Plot.SELL_POINTS_BASE + Plot.SELL_POINTS_PER_BAG * bags

## "dump" or "sell". A choice that is not open is ignored.
func choose(option: String) -> void:
	if _choice == "":
		return
	var id := _choice
	_choice = ""
	if hud != null:
		hud.hide_choice()
	var trigger := ""
	if option == "dump":
		batch = "dumped"
		saved = 2
		trigger = "choice_batch_dump"
	else:
		option = "sell"
		batch = "sold"
		ods = 4
		var zm := get_node_or_null("/root/ZombieMode")
		if zm != null and zm.has_method("add_points"):
			zm.add_points(sell_points(), "batch")
		trigger = "choice_batch_hesitate" if hesitated else "choice_batch_sell"
	choice_made.emit(id, option)
	emit_beat("batch_" + batch)
	_schedule(trigger)

# --- the raid (chapter 5) ---------------------------------------------------------------------

func start_raid() -> void:
	if raid_active or finished:
		return
	raid_active = true
	is_flushed = false
	flush_amount = 0.0
	escape_left = Plot.ESCAPE_SECONDS
	reinforcements = 0
	_until_reinforce = Plot.REINFORCE_EVERY
	set_objective("FLUSH THE STASH, OR TAKE THE BAG AND RUN FOR THE CAR")
	_make_marker("sink", Color(0.4, 0.85, 1.0), "SINK")
	_make_marker("car", Color(0.4, 1.0, 0.5), "GETAWAY")
	spawn(Plot.POLICE_WAVE)
	raid_started.emit()
	_play_sfx("siren")

func _make_marker(nm: String, color: Color, label: String) -> void:
	var parent := _prop_parent()
	if parent == null or _markers.has(nm):
		return
	var m := Node3D.new()
	m.name = "Story_" + nm
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.0
	l.omni_range = 7.0
	l.position = Vector3(0, 1.2, 0)
	m.add_child(l)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 9.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.position = Vector3(0, 4.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.12)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = mat
	m.add_child(beam)
	var t := Label3D.new()
	t.text = label
	t.font = load("res://assets/fonts/Bungee-Regular.ttf")
	t.font_size = 96
	t.pixel_size = 0.006
	t.modulate = color
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.no_depth_test = true
	t.position = Vector3(0, 2.6, 0)
	m.add_child(t)
	parent.add_child(m)
	m.global_position = _point(nm)
	_markers[nm] = m

func _holding() -> bool:
	if hold_fn.is_valid():
		return bool(hold_fn.call())
	return Input.is_action_pressed("interact")

func _raid_step(dt: float) -> void:
	var pp := _player_pos()
	var sink := _point("sink")
	var near_sink := _flat(pp, sink) <= SINK_RADIUS
	if not is_flushed:
		if near_sink and _holding():
			flush_amount = minf(1.0, flush_amount + dt / Plot.FLUSH_SECONDS)
		else:
			flush_amount = maxf(0.0, flush_amount - dt * 0.5)
		if hud != null:
			hud.set_flush(flush_amount, near_sink or flush_amount > 0.0)
		if flush_amount >= 1.0:
			_do_flush()
	elif hud != null:
		hud.set_flush(0.0, false)
	escape_left -= dt
	if hud != null:
		hud.set_timer(maxf(escape_left, 0.0))
	if _flat(pp, _point("car")) <= CAR_RADIUS and not finished:
		escape()
		return
	if escape_left <= 0.0:
		bust("timer")
		return
	_until_reinforce -= dt
	if _until_reinforce <= 0.0 and reinforcements < Plot.MAX_REINFORCE:
		_until_reinforce = Plot.REINFORCE_EVERY
		scan(Plot.pick(Plot.REINFORCE_SCAN[reinforcements % Plot.REINFORCE_SCAN.size()], mature()))
		reinforcements += 1
		spawn(Plot.POLICE_REINFORCE)

func _do_flush() -> void:
	is_flushed = true
	flush_amount = 1.0
	flushed.emit()
	emit_beat("flushed")
	set_objective("THE STASH IS GONE. GET TO THE CAR!")
	_play_sfx("flush_done")
	radio("NICO", "Gone! It's gone — now the car, the car!" if mature() else "Gone! It's gone. Now the car, the car!")

func escape() -> void:
	if finished:
		return
	raid_active = false
	escaped.emit()
	emit_beat("escaped")
	var how := "clean" if (is_flushed or bags == 0) else "bag"
	_finish(how)

func bust(_why := "") -> void:
	if finished:
		return
	raid_active = false
	busted.emit()
	emit_beat("busted")
	_finish("busted")
	# Slow motion for the cuffs.
	Engine.time_scale = 0.25
	_slow_left = 3.0 # real seconds (the frame loop feeds advance() unscaled time)

func _finish(how: String) -> void:
	finished = true
	var b := batch if batch != "" else "sold"
	ending = "%s_%s" % [how, b]
	_clear_markers()
	set_objective("")
	if hud != null:
		hud.set_timer(-1.0)
		hud.set_flush(0.0, false)
		hud.show_ending(ending, ending_data())
	_play_sfx("sting_" + how)
	_play_music("end_" + how)
	story_finished.emit(ending)

## The ending card's content: title, tone, lines (mature or clean), the tally.
func ending_data() -> Dictionary:
	var e: Dictionary = Plot.ENDINGS.get(ending, {})
	return {
		"key": ending, "title": e.get("title", ""), "tone": e.get("tone", "dawn"),
		"lines": Plot.ending_lines(ending, mature()),
		"tally": [
			["BAGS CARRIED", str(bags)],
			["OVERDOSES ON YOUR BATCH", str(ods)],
			["SAVED BY NARCAN", str(saved)],
			["KILLS", str(kills)],
		],
	}

func _clear_markers() -> void:
	for k in _markers:
		if is_instance_valid(_markers[k]):
			_markers[k].queue_free()
	_markers.clear()
	for b in _bags:
		if is_instance_valid(b):
			b.queue_free()
	_bags.clear()

# --- sound -------------------------------------------------------------------------------------

func _load_audio(path_base: String) -> AudioStream:
	if _stream_cache.has(path_base):
		return _stream_cache[path_base]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(path_base + ext):
			s = load(path_base + ext) as AudioStream
			break
	_stream_cache[path_base] = s
	return s

## Where a sound lives: our own folder, else the guns' (the mode's car pass, the helicopter) ("" when nowhere).
func sfx_path(name_: String) -> String:
	for dir in [SFX_DIR, "res://assets/sfx/guns/"]:
		for ext in [".ogg", ".wav"]:
			if ResourceLoader.exists(dir + name_ + ext):
				return dir + name_ + ext
	return ""

func _play_sfx(name_: String, volume_db := 0.0) -> void:
	if not audio or _sfx.is_empty():
		return
	var p0 := sfx_path(name_)
	var s: AudioStream = load(p0) as AudioStream if p0 != "" else null
	if s == null:
		return
	var p := _sfx[_sfx_next % _sfx.size()]
	_sfx_next += 1
	p.stream = s
	p.volume_db = volume_db
	p.play()

func _play_music(track: String) -> void:
	_music_track = track
	if not audio or _music.size() < 2:
		return
	var s := _load_audio(MUSIC_DIR + track)
	var old := _music[0] if _music[0].playing and _music[0].volume_db > -60.0 else _music[1]
	var new := _music[1] if old == _music[0] else _music[0]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -80.0, 2.0)
	tw.chain().tween_callback(old.stop)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = not track.begins_with("end_")
	new.stream = s
	new.volume_db = -80.0
	new.play()
	create_tween().tween_property(new, "volume_db", -13.0, 2.0)
