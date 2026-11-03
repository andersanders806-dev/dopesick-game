extends SceneTree
## Ghetto Wars' story layer, headless (no scene, a fake mode): chapters follow the waves, texts and radio queue, the
## stash run, the batch choice changes the ending, the raid (flush, escape timer, reinforcements, the car), the busted
## path, the mature toggle swaps the lines, the hard lines hold, every voiced line has its file, no orphan nodes.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_ghetto_story.gd

const Story := preload("res://fx/GhettoStory.gd")
const Plot := preload("res://fx/GhettoStoryScript.gd")
const Voice3 := preload("res://fx/GhettoVoice.gd")

class FakeMode extends Node:
	signal wave_started(n: int)
	signal wave_cleared(n: int)
	signal enemy_killed(e, how)
	signal player_downed
	var spawns: Array = []
	func spawn_wave(spec: Dictionary) -> void:
		spawns.append(spec)

var _checks := 0
var _failed := 0
var _ppos := Vector3(0, 0, 40)
var _hold := false

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("  FAIL: ", what)

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	await _run()
	print("GHETTO STORY: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)

func _make(world: Node3D) -> Array:
	var mode := FakeMode.new()
	root.add_child(mode)
	var story := Story.new()
	story.audio = false
	story.props_parent = world
	story.player_fn = func(): return _ppos
	story.hold_fn = func(): return _hold
	root.add_child(story)
	story.set_process(false)
	story.hud.set_process(false)
	story.attach(mode)
	_ppos = Vector3(0, 0, 40)
	_hold = false
	return [story, mode]

func _free(story: Node, mode: Node) -> void:
	story.free()
	mode.free()

func _wave(story: Node, mode: Node, n: int, secs := 20.0) -> void:
	mode.wave_started.emit(n)
	story.advance(secs)

func _clear(story: Node, mode: Node, n: int, secs := 20.0) -> void:
	mode.wave_cleared.emit(n)
	story.advance(secs)

## A whole run to the raid with `choice` ("dump" / "sell" / "" to let it time out) and `grab` bags.
func _to_raid(story: Node, mode: Node, choice: String, grab: int) -> void:
	for n in 6:
		_wave(story, mode, n + 1, 3.0)
		if n + 1 == 3:
			story.advance(4.0)
			for b in grab:
				story.collect_bag()
		_clear(story, mode, n + 1, 14.0)
	_wave(story, mode, 7, 16.0)
	if choice != "":
		story.choose(choice)
	else:
		story.advance(Plot.CHOICE_SECONDS + 1.0)
	_clear(story, mode, 7, 20.0)
	mode.wave_started.emit(8)
	story.advance(6.0)

func _run() -> void:
	var zm := root.get_node("ZombieMode")
	var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mature0: bool = zm.mature_language
	zm.mature_language = true
	zm.active = true
	var world := Node3D.new()
	root.add_child(world)

	# --- chapters advance with the waves
	print("-- chapters follow the waves")
	var pair := _make(world)
	var story: Node = pair[0]
	var mode: Node = pair[1]
	var started: Array[String] = []
	story.chapter_started.connect(func(id: String): started.append(id))
	var beats: Array[String] = []
	story.beat.connect(func(id: String): beats.append(id))
	_check(story.chapter == "", "no chapter before a wave")
	_wave(story, mode, 1)
	_check(story.chapter == "corner" and started == ["corner"], "wave 1 starts THE CORNER")
	_wave(story, mode, 2)
	_check(story.chapter == "corner" and started.size() == 1, "wave 2 stays in chapter 1")
	_wave(story, mode, 3)
	_check(story.chapter == "stash", "wave 3 starts STASH RUN")
	_wave(story, mode, 5)
	_check(story.chapter == "snitch", "wave 5 starts THE SNITCH")
	_wave(story, mode, 7, 1.0)
	_check(story.chapter == "tainted", "wave 7 starts TAINTED")
	_free(story, mode)
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	started.clear()
	story.chapter_started.connect(func(id: String): started.append(id))
	story.beat.connect(func(id: String): beats.append(id))
	for n in range(1, 9):
		_wave(story, mode, n, 2.0)
		if n < 8:
			_clear(story, mode, n, 20.0)
	_check(started == ["corner", "stash", "snitch", "tainted", "bust"], "five chapters in order: %s" % [started])
	_check(story.hud.cards_shown == ["THE CORNER", "STASH RUN", "THE SNITCH", "TAINTED", "THE BUST"], "a chapter card for each")
	_check(story.chapters_seen.size() == 5, "chapters seen")
	_check(Plot.chapter_index_for_wave(12) == 4 and Plot.chapter_index_for_wave(1) == 0, "late waves stay in THE BUST")
	_free(story, mode)

	# --- texts, radio and the scanner queue
	print("-- texts, radio, scanner")
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	mode.wave_started.emit(1)
	story.advance(0.5)
	_check(story.texts.is_empty(), "nothing before its time")
	story.advance(1.0)
	_check(story.texts.size() == 1 and story.texts[0]["from"] == "NICO", "Nico's first text lands at 1 s")
	_check(story.hud.texts_shown.size() == 1, "and it is on the phone")
	story.advance(6.0)
	_check(story.radios.size() == 1 and story.radios[0]["who"] == "NICO", "the radio line follows")
	story.advance(3.0)
	_check(story.objective == "HOLD THE CORNER", "objective set")
	_clear(story, mode, 1, 3.0)
	_check(story.texts.size() == 2 and story.texts[1]["from"] == "TISH", "Tish texts after the wave")
	_check(story.texts[0]["stamp"] != story.texts[1]["stamp"], "the stamps move on (%s -> %s)" % [story.texts[0]["stamp"], story.texts[1]["stamp"]])
	_check(story.texts[0]["name"] == "NICO", "sender name")
	mode.wave_started.emit(2)
	story.advance(3.0)
	_clear(story, mode, 2, 10.0)
	_check(story.scans.size() == 1 and "shots fired" in story.scans[0], "the scanner crackles after wave 2")
	_check("cops_circling" in story.beats_seen, "the set gets cops_circling")
	mode.wave_started.emit(5)
	story.advance(20.0)
	_check(story.texts.size() == 3 + 3, "wave 5: three texts queue up, in order (%d)" % story.texts.size())
	_check(story.texts[3]["from"] == "UNKNOWN" and story.texts[4]["from"] == "TISH" and story.texts[5]["from"] == "NICO", "senders in order")
	_free(story, mode)

	# --- the stash run
	print("-- stash run")
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	mode.wave_started.emit(3)
	story.advance(5.0)
	_check(story.stash_started, "stash run starts with wave 3")
	var bag_nodes := world.find_children("StashBag_*", "Node3D", true, false)
	_check(bag_nodes.size() == 4, "four stash bags in the back room (%d)" % bag_nodes.size())
	_check("0/4" in story.objective, "objective counts 0/4: %s" % story.objective)
	_ppos = Plot.POINTS["stash_b"]
	story.advance(0.2)
	_check(story.bags == 1, "walking onto a bag picks it up")
	_ppos = Plot.POINTS["stash_a"]
	story.advance(0.2)
	_ppos = Plot.POINTS["stash_c"]
	story.advance(0.2)
	_ppos = Plot.POINTS["stash_d"]
	story.advance(0.2)
	_check(story.bags == 4 and story.objective == "HOLD THE BACK ROOM", "all four: hold the back room")
	_check(world.find_children("StashBag_*", "Node3D", true, false).filter(func(n): return not n.is_queued_for_deletion()).is_empty(), "bags gone from the room")
	mode.wave_started.emit(4)
	story.advance(1.0)
	_clear(story, mode, 4, 12.0)
	_check(story.radios.any(func(r): return String(r["line"]).contains("all four")), "Nico reports all four")
	_free(story, mode)
	_ppos = Vector3(0, 0, 40)
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	mode.wave_started.emit(3)
	story.advance(5.0)
	mode.wave_started.emit(4)
	story.advance(1.0)
	_clear(story, mode, 4, 12.0)
	_check(story.bags == 0 and story.radios.any(func(r): return String(r["line"]).contains("nothing")), "no bags: Nico notices")
	_free(story, mode)
	await process_frame

	# --- the drive-by
	print("-- the drive-by")
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	beats.clear()
	story.beat.connect(func(id: String): beats.append(id))
	_wave(story, mode, 6, 5.0)
	_check(mode.spawns.size() == 1 and mode.spawns[0].get("drive_by", false) == true, "wave 6 asks the mode for a drive-by")
	_check("drive_by" in beats, "and the set gets the beat")
	_clear(story, mode, 6, 10.0)
	_check(story.texts.back()["from"] == "DEX", "Dex confesses")
	_check("snitch_revealed" in beats, "snitch_revealed beat")
	_free(story, mode)

	# --- the batch: dump
	print("-- the batch")
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	var offered: Array = []
	story.choice_offered.connect(func(id, opts): offered.append(id))
	var pts0: int = zm.points
	_wave(story, mode, 7, 3.0)
	_check("ods_street" in story.beats_seen, "ods_street beat for the dressing")
	_check(story.texts.size() == 1 and story.texts[0]["from"] == "DANA", "Dana's text opens the chapter")
	story.advance(13.0)
	_check(offered == ["batch"] and story.hud.choice_active, "the choice is offered")
	story.choose("dump")
	story.advance(2.0)
	_check(story.batch == "dumped" and not story.hud.choice_active, "dumped")
	_check(story.radios.back()["line"].contains("Gone"), "Nico: gone")
	_clear(story, mode, 7, 5.0)
	_check(story.texts.back()["body"].contains("Narcan") and zm.points == pts0, "dumping: Narcan, no points")
	_free(story, mode)
	# sell
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_wave(story, mode, 7, 16.0)
	var sp: int = story.sell_points()
	story.choose("sell")
	_check(story.batch == "sold" and zm.points == pts0 + sp, "selling pays %d points (%d)" % [sp, zm.points - pts0])
	_clear(story, mode, 7, 5.0)
	_check(story.texts.back()["body"].contains("nineteen") and "ods_more" in story.beats_seen and story.ods == 4, "selling: the consequence is on the street")
	_free(story, mode)
	# hesitate
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_wave(story, mode, 7, 16.0)
	story.advance(Plot.CHOICE_SECONDS + 1.0)
	story.advance(2.0)
	_check(story.batch == "sold" and story.hesitated, "no answer sells it")
	_check(story.radios.back()["line"].contains("didn't pick"), "and Nico says so")
	_free(story, mode)

	# --- the raid: clean (flushed), with the bag, busted by timer and by being downed
	print("-- the raid")
	var cars := Plot.POINTS["car"]
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_to_raid(story, mode, "dump", 4)
	_check(story.raid_active and story.chapter == "bust", "the bust: raid on")
	_check(mode.spawns.size() >= 1 and mode.spawns.back().get("crew") == "Police", "police wave ordered: %s" % [mode.spawns.back()])
	_check("raid_start" in story.beats_seen and "heli" in story.beats_seen, "raid_start and heli beats")
	_check(story.scans.size() >= 1 and story.hud.scanner_texts.size() >= 1, "the scanner calls the warrant")
	_check(story.hud.timer_shown > 100.0, "the escape clock runs (%.0f)" % story.hud.timer_shown)
	# hold at the sink
	_ppos = Plot.POINTS["sink"]
	_hold = true
	story.advance(Plot.FLUSH_SECONDS * 0.5)
	_check(story.flush_amount > 0.4 and story.flush_amount < 0.6, "half way flushed (%.2f)" % story.flush_amount)
	_hold = false
	story.advance(2.0)
	_check(story.flush_amount < 0.5, "letting go lets it drain")
	_hold = true
	story.advance(Plot.FLUSH_SECONDS + 1.0)
	_check(story.is_flushed and "flushed" in story.beats_seen, "flushed")
	_ppos = cars
	story.advance(0.1)
	_check(story.finished and story.ending == "clean_dumped", "to the car after flushing: %s" % story.ending)
	_check(story.hud.ending_key == "clean_dumped" and story.ending_data()["lines"].size() == 3, "ending card up")
	_check(story.finished and not story.raid_active, "raid over")
	var fin: String = story.ending
	story.advance(60.0)
	_check(story.ending == fin, "the ending sticks")
	_free(story, mode)
	_hold = false

	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_to_raid(story, mode, "sell", 3)
	_ppos = cars
	story.advance(0.1)
	_check(story.ending == "bag_sold", "to the car without flushing: %s" % story.ending)
	_check(story.ending_data()["tally"][1][1] == "4" and story.ending_data()["tally"][0][1] == "3", "the tally: 3 bags, 4 overdoses")
	_free(story, mode)

	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_to_raid(story, mode, "sell", 2)
	var spawns0: int = mode.spawns.size()
	var scans0: int = story.scans.size()
	story.advance(Plot.REINFORCE_EVERY + 1.0)
	_check(mode.spawns.size() == spawns0 + 1 and story.scans.size() == scans0 + 1, "reinforcements at 30 s with a scanner call")
	story.advance(Plot.ESCAPE_SECONDS)
	_check(story.finished and story.ending == "busted_sold", "the clock runs out: %s" % story.ending)
	_check(mode.spawns.size() <= 1 + Plot.MAX_REINFORCE, "reinforcements are capped (%d)" % mode.spawns.size())
	_check(story.hud.ending_key == "busted_sold" and story.ending_data()["title"] == "BUSTED", "BUSTED card")
	_check(is_equal_approx(Engine.time_scale, 0.25), "slow motion for the cuffs")
	story.advance(3.5)
	_check(is_equal_approx(Engine.time_scale, 1.0), "and back to normal")
	_free(story, mode)

	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_to_raid(story, mode, "dump", 0)
	mode.player_downed.emit()
	_check(story.ending == "busted_dumped", "downed in the raid: busted (%s)" % story.ending)
	_check(is_equal_approx(Engine.time_scale, 0.25), "slow-mo on")
	_free(story, mode)
	_check(is_equal_approx(Engine.time_scale, 1.0), "the story never leaves the game in slow motion")
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	mode.player_downed.emit()
	_check(story.ending == "", "downed outside the raid is the mode's business")
	_free(story, mode)

	# --- the mature toggle
	print("-- mature language")
	var banned_hits := 0
	for m in [true, false]:
		for line in Plot.every_line(m):
			var low := String(line).to_lower()
			for w in Plot.BANNED:
				if w in low:
					banned_hits += 1
					print("  banned fragment '%s' in: %s" % [w, line])
	_check(banned_hits == 0, "no slurs or hate in either set")
	var dirty := 0
	for line in Plot.every_line(false):
		var low := String(line).to_lower()
		for w in Plot.PROFANITY:
			if w in low:
				dirty += 1
				print("  clean set has '%s': %s" % [w, line])
	_check(dirty == 0, "the clean set is clean")
	var swears := 0
	for line in Plot.every_line(true):
		if "fuck" in String(line).to_lower() or "shit" in String(line).to_lower():
			swears += 1
	_check(swears >= 8, "the mature set swears (%d lines)" % swears)
	var barks_swear := 0
	for ev in Plot.POLICE_BARKS:
		for p in Plot.POLICE_BARKS[ev]:
			if p[0] != p[1]:
				barks_swear += 1
	_check(barks_swear >= 2, "police commands have a mature take")
	zm.mature_language = true
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_wave(story, mode, 1, 3.0)
	var mature_text: String = story.texts[0]["body"]
	_free(story, mode)
	zm.mature_language = false
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	_wave(story, mode, 1, 3.0)
	var clean_text: String = story.texts[0]["body"]
	_check(mature_text != clean_text and "fucking" in mature_text and not "fucking" in clean_text, "the toggle swaps the text: '%s' / '%s'" % [mature_text, clean_text])
	_wave(story, mode, 2, 3.0)
	_check(story.hud.cards_shown.size() >= 1 and not "fuck" in story.hud.radio_text.to_lower(), "radio is clean too")
	_free(story, mode)
	zm.mature_language = true
	_check(Voice3.pick("spot", null) != "" and Voice3.pick("taunt_habit", null) != "", "GhettoVoice.pick gives police and extra barks")

	# --- the voice and the sounds are all baked
	print("-- baked audio")
	var missing := 0
	var list: Array = Voice3.bake_list()
	for item in list:
		if not Voice3.has(item["kind"], item["text"]):
			missing += 1
			if missing <= 5:
				print("  no voice file: ", item["kind"], " '", item["text"], "'")
	_check(list.size() > 100 and missing == 0, "%d voiced lines, %d without a file" % [list.size(), missing])
	pair = _make(world)
	story = pair[0]
	mode = pair[1]
	for nm in ["chapter_hit", "text_in", "squelch_on", "scanner_beep", "bag_pickup", "flush_done", "siren", "car_pass",
			"sting_clean", "sting_bag", "sting_busted"]:
		_check(story.sfx_path(nm) != "", "sfx %s" % nm)
	_free(story, mode)
	for ch in Plot.CHAPTERS:
		_check(ResourceLoader.exists("res://assets/music/ghetto/%s.ogg" % ch["music"]), "music %s" % ch["music"])
	for e in ["end_clean", "end_bag", "end_busted"]:
		_check(ResourceLoader.exists("res://assets/music/ghetto/%s.ogg" % e), "music %s" % e)

	# --- clean up
	world.free()
	zm.active = false
	zm.mature_language = mature0
	await process_frame
	await process_frame
	var orphans1 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans1 <= orphans0, "no orphan nodes left (%d -> %d)" % [orphans0, orphans1])
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale is 1")
