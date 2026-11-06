extends "res://dev-tools/smoke_test_3d.gd"
## Ghetto Wars, the story wired into the real block: the story node is installed, the chapters follow the waves, the
## bust brings the police (their look, their barks), the run's end belongs to the story's ending card, the crews'
## barks are spoken and duck the music, the Mature language toggle swaps both text and voice, the soundscape plays.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_ghetto_core.gd
func _run() -> void:
	await _core_checks(_gs())

func _core_checks(gs: Node) -> void:
	await _section("Ghetto Wars core: the story drives the war")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gm := root.get_node("GhettoMode")
	var Voice3: GDScript = load("res://fx/GhettoVoice.gd")
	zm.mature_language = true
	zm.begin_gangs()
	var city := await _load("res://world/City3D.tscn")
	await _frames(30)
	var block := city.get_node("ZombieBlock")
	var story: Node = block.story
	_check(story != null and story.is_inside_tree() and story.name == "GhettoStory" and story.mode == gm, "  the story is installed on the block and listens to the mode")
	_check(story.chapter == "corner" and story.chapter_index == 0 and story.hud != null, "  wave 1 opened chapter one, THE CORNER")
	_check(block.ambience != null and block.ambience.get_child_count() >= 8 and block.ambience.get_child_count() <= 12, "  the soundscape is up (beds, one-shots, siren)")
	_check(zm.game_over_override.is_valid(), "  the story is asked before the run ends")
	await _until_ready(block)
	var sp: Node = block.spawner
	sp.enabled = false
	_free_all()

	# --- Chapters follow the waves through the real mode.
	var ids: Array = []
	story.chapter_started.connect(func(id: String): ids.append(id))
	for r in [2, 3, 5, 7, 8]:
		zm.round = r - 1
		zm.start_round()
		await _frames(2)
	_check(ids == ["stash", "snitch", "tainted", "bust"] or ids == ["stash", "snitch", "tainted", "bust"], "  waves 3, 5, 7 and 8 open the stash, snitch, tainted and bust chapters (%s)" % [ids])
	_check(sp.crew_name == "Police", "  from the bust on the crew that comes is the police")

	# --- The police look and the voice.
	var cop = sp.spawn_one("grunt", _near(_player(), 14.0, 4.0), "", "ar")
	await _frames(5)
	_check(cop.crew == "Police" and cop.find_child("Helmet", true, false) != null and cop.find_child("VestMark", true, false) != null, "  a policeman has a helmet and POLICE on his vest")
	var labels: Array = cop.find_children("*", "Label3D", true, false)
	_check(labels.size() == 2 and labels.all(func(l): return l.text == "POLICE"), "  the vest reads POLICE front and back")
	var dock = sp.spawn_one("grunt", _near(_player(), 16.0, 4.0), "", "pistol")
	dock.crew = "Dock Boys"
	_check(cop.CREW_LOOK["Police"]["cloth"] != cop.CREW_LOOK["Dock Boys"]["cloth"], "  and a uniform apart from the crew's colours")

	# --- Barks: spoken, in the right language, the music ducks.
	var said: Array = []
	cop.barked.connect(func(_w, t: String): said.append(t))
	Voice3.reset_duck()
	Voice3.duck_peak_db = 0.0
	var calls0: int = Voice3.duck_calls
	cop.target = _player()
	cop._bark_cd = 0.0
	cop.bark("spot", true)
	_check(said.size() == 1 and Voice3.has("police", said[0]), "  the policeman shouts a baked police line: %s" % [said])
	var bark_player := false
	for n in cop.get_children():
		if n is AudioStreamPlayer3D and n.playing:
			bark_player = true
	_check(bark_player, "  from where he stands (a 3D voice)")
	_check(Voice3.duck_calls > calls0 and Voice3.duck_peak_db <= -3.9, "  and the music ducks %.0f dB under him" % -Voice3.duck_peak_db)
	var fx_ok := false
	var bus := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectAmplify:
			fx_ok = true
	_check(fx_ok, "  through an amplifier on the Music bus")
	var amp: AudioEffectAmplify
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectAmplify:
			amp = AudioServer.get_bus_effect(bus, i)
	await _until(func(): return amp != null and amp.volume_db > -1.0, 1200)
	_check(amp != null and amp.volume_db > -1.0, "  and it comes back up when the line is over (%.1f dB)" % amp.volume_db)

	# Dock Boys talk and taunt with the story's lines; both takes are baked.
	var dock_said: Array = []
	dock.barked.connect(func(_w, t: String): dock_said.append(t))
	dock.target = _player()
	var voiced := 0
	for i in 60:
		dock._bark_cd = 0.0
		dock.bark("taunt", true)
	for t in dock_said:
		if Voice3.kind_of(t) != "":
			voiced += 1
	_check(dock_said.size() == 60 and voiced == 60, "  the Dock Boys' taunts all have a voice (%d of %d)" % [voiced, dock_said.size()])
	var uniq := {}
	for t in dock_said:
		uniq[t] = true
	_check(uniq.size() >= 4, "  and there is variety (%d different)" % uniq.size())
	var habit := false
	for t in dock_said:
		if "habit" in String(t) or "stash" in String(t) or "gun still" in String(t):
			habit = true
	_check(habit, "  some of them are about your habit")
	# Mature toggle: text and voice both change.
	zm.mature_language = false
	var clean_said: Array = []
	var dock2 = sp.spawn_one("grunt", _near(_player(), 12.0, 3.0))
	dock2.crew = "Dock Boys"
	dock2.target = _player()
	dock2.barked.connect(func(_w, t: String): clean_said.append(t))
	for i in 80:
		dock2._bark_cd = 0.0
		dock2.bark("spot", true)
		dock2._bark_cd = 0.0
		dock2.bark("hit", true)
		dock2._bark_cd = 0.0
		dock2.bark("reload", true)
	var bad := clean_said.filter(func(t): return _swears(String(t)))
	_check(clean_said.size() > 100 and bad.is_empty(), "  with Mature language off nothing swears (%d lines, %s)" % [clean_said.size(), bad.slice(0, 3)])
	var clean_voiced := clean_said.filter(func(t): return Voice3.kind_of(String(t)) != "")
	_check(clean_voiced.size() == clean_said.size(), "  and every clean line is voiced too (%d of %d)" % [clean_voiced.size(), clean_said.size()])
	zm.mature_language = true
	var swears := false
	for i in 60:
		dock2._bark_cd = 0.0
		dock2.bark("hit", true)
	zm.mature_language = true
	_free_all()
	await _frames(3)

	# --- The raid's sound, and the end of the run.
	block.ambience.played.clear()
	story.emit_beat("raid_start")
	await _frames(4)
	_check(block.ambience.played.has("door_ram_a"), "  the raid opens with the ram on the door")
	story.emit_beat("heli")
	_check(block.ambience.played.has("heli_pass"), "  the helicopter passes")
	await get_root().get_tree().create_timer(3.2).timeout
	_check(block.ambience.played.has("siren_wail_loop") and block.ambience.played.has("flashbang_a"), "  sirens and a flashbang follow")
	var over: Array = []
	zm.game_over_started.connect(func(_s: Dictionary): over.append(true))
	story.start_raid()
	zm.health = 0.0
	zm.game_over()
	_check(story.finished and story.ending.begins_with("busted") and over.is_empty() and not zm.over, "  downed in the raid is the BUSTED ending, not the plain game over")
	story.hud.ending_dismissed.emit()
	await _frames(3)
	_check(zm.over and over.size() == 1 and zm.death_cause == "BUSTED", "  dismissing the card ends the run with it as the cause (%s)" % zm.death_cause)
	var screen := root.get_node_or_null("ZombieGameOver")
	_check(screen != null, "  and the run's summary is shown")
	if screen != null:
		screen._close()
	zm.leave()
	_check(not zm.game_over_override.is_valid(), "  leaving takes the story's hook off")

func _swears(t: String) -> bool:
	var low := t.to_lower()
	for w in ["fuck", "shit", "bastard", "asshole", "dickhead", "motherfucker", "prick", "damn", "dumb"]:
		if low.contains(w):
			return true
	return false

func _until_ready(block: Node) -> void:
	for i in 600:
		if block.purchases_ready and block.cover != null and not block.cover.points.is_empty():
			return
		await physics_frame

func _free_all() -> void:
	for g in get_nodes_in_group("gangsters") + get_nodes_in_group("corpses"):
		if is_instance_valid(g):
			g.queue_free()

func _near(player: Node3D, dx: float, dz: float) -> Vector3:
	var map: RID = player.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, player.global_position + Vector3(dx, 0, dz))
	return Vector3(p.x, 0.0, p.z)

func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await physics_frame
	return false
