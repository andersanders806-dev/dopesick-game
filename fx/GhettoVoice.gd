extends RefCounted
## Ghetto Wars' voices: the lines are spoken by Piper (the same engine as autoload/Voice.gd), baked ahead of time by
## dev-tools/gen_story_audio.py into assets/sfx/ghetto/voice/ and run through a filter by kind: the radio crackles, the
## scanner is thin and hard, the police shout through a bullhorn, the street barks are dry and loud, the downed cry.
## Every line has a mature and a clean take (ZombieMode.mature_language); both are baked. A line without a file is
## just text on the HUD.
##
## Gangster3D and friends: `GhettoVoice.bark(self, text, global_position)` speaks any of npc/Barks.gd's lines (or the
## extra ones here) from where the man stands.

const DIR := "res://assets/sfx/ghetto/voice/"
const Plot := preload("res://fx/GhettoStoryScript.gd")

## Piper speaker ids (LibriTTS-R, see autoload/Voice.gd) and the speaking rate (length_scale, >1 slower).
const CAST := {
	"radio": {"NICO": {"id": 170, "rate": 1.0}},
	"scan": {"DISPATCH": {"id": 372, "rate": 1.02}},
}
## A stable pick by the line's text for the rest.
const POOLS := {
	"bark": {"ids": [36, 84, 207, 210, 217, 220, 146, 115], "rate": 0.8},
	"police": {"ids": [564, 720, 156, 684], "rate": 0.9},
	"cry": {"ids": [828, 636, 110], "rate": 1.25},
}

## Mature language on (the default) unless the option is off.
static func mature() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var zm: Node = tree.root.get_node_or_null("ZombieMode") if tree != null else null
	return bool(zm.get("mature_language")) if zm != null else true

static func key(kind: String, text: String) -> String:
	return ("%s|%s" % [kind, text]).md5_text().left(12)

static func path_for(kind: String, text: String) -> String:
	return "%s%s_%s.ogg" % [DIR, kind, key(kind, text)]

## {id, rate, fx} for a line: the Piper voice, speed and the filter it goes through.
static func voice_for(kind: String, who: String, text: String) -> Dictionary:
	if CAST.has(kind) and CAST[kind].has(who):
		var c: Dictionary = CAST[kind][who]
		return {"id": c["id"], "rate": c["rate"], "fx": kind}
	var pool: Dictionary = POOLS.get(kind, POOLS["bark"])
	var ids: Array = pool["ids"]
	return {"id": ids[_h(text) % ids.size()], "rate": pool["rate"], "fx": kind}

## A hash the Python bake can reproduce: the first 8 hex digits of the md5.
static func _h(text: String) -> int:
	return ("h|" + text).md5_text().left(8).hex_to_int()

static func has(kind: String, text: String) -> bool:
	return ResourceLoader.exists(path_for(kind, text))

static func stream_for(kind: String, text: String) -> AudioStream:
	var p := path_for(kind, text)
	if ResourceLoader.exists(p):
		return load(p) as AudioStream
	return null

## The first kind that has this text spoken (a caller that only knows the text).
static func kind_of(text: String) -> String:
	for k in ["bark", "police", "cry", "radio", "scan"]:
		if has(k, text):
			return k
	return ""

## Speaks `text` from `pos` in the world; the player is freed when it ends. Null when the line has no voice.
static func bark(parent: Node, text: String, pos: Vector3, kind := "", volume_db := 0.0) -> AudioStreamPlayer3D:
	if kind == "":
		kind = kind_of(text)
	var s: AudioStream = stream_for(kind, text) if kind != "" else null
	if s == null or parent == null or not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db + 4.0
	p.unit_size = 14.0
	p.max_distance = 70.0
	p.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p

## A line in your ears (radio, scanner): a plain player on the Voice bus, freed when it ends.
static func say(parent: Node, kind: String, text: String, volume_db := 0.0) -> AudioStreamPlayer:
	var s: AudioStream = stream_for(kind, text)
	if s == null or parent == null or not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	duck_music(p, 9.0)
	return p

# --- The music gives way to the voices ----------------------------------------------------------

## How far the Music bus is down while a line plays (dB), how fast it goes down and comes back (s), and how long it
## holds after the last line (s).
const DUCK_IN := 0.18
const DUCK_OUT := 0.7
const DUCK_HOLD := 0.35
static var _duck_fx: AudioEffectAmplify
static var _duck_n := 0
static var _duck_depth := 0.0
static var _duck_tween: Tween
## For tests: the deepest the music has been taken, and how many lines have asked.
static var duck_peak_db := 0.0
static var duck_calls := 0

## The Music bus's own amplifier for this (added once at the end of its chain; found again if the buses are rebuilt).
static func _duck_effect() -> AudioEffectAmplify:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return null
	if _duck_fx != null:
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) == _duck_fx:
				return _duck_fx
	_duck_fx = AudioEffectAmplify.new()
	_duck_fx.volume_db = 0.0
	AudioServer.add_bus_effect(bus, _duck_fx)
	return _duck_fx

## Takes the music down by `depth_db` for as long as `voice` (an audio player) plays, then back up.
static func duck_music(voice: Node, depth_db := 9.0) -> void:
	var fx := _duck_effect()
	var tree := Engine.get_main_loop() as SceneTree
	if fx == null or tree == null or voice == null:
		return
	duck_calls += 1
	_duck_n += 1
	_duck_depth = maxf(_duck_depth, depth_db)
	_duck_go(tree, -_duck_depth, DUCK_IN, 0.0)
	var done := [false]
	var release := func() -> void:
		if done[0]:
			return
		done[0] = true
		_duck_n = maxi(_duck_n - 1, 0)
		if _duck_n == 0:
			_duck_depth = 0.0
			_duck_go(tree, 0.0, DUCK_OUT, DUCK_HOLD)
	if voice.has_signal("finished"):
		voice.connect("finished", release)
	voice.tree_exiting.connect(release)

static func _duck_go(tree: SceneTree, db: float, secs: float, delay: float) -> void:
	var fx := _duck_fx
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	duck_peak_db = minf(duck_peak_db, db)
	_duck_tween = tree.create_tween()
	_duck_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		_duck_tween.tween_interval(delay)
	_duck_tween.tween_property(fx, "volume_db", db, secs)

## The music is back at full (a run over, a test).
static func reset_duck() -> void:
	_duck_n = 0
	_duck_depth = 0.0
	if _duck_fx != null:
		_duck_fx.volume_db = 0.0

## The extra barks of the story and the police's, by event, as a text (mature or clean). Like npc/Barks.pick.
static func pick(event: String, rng: RandomNumberGenerator = null) -> String:
	var set_: Array = []
	if Plot.POLICE_BARKS.has(event):
		set_ = Plot.POLICE_BARKS[event]
	elif Plot.EXTRA_BARKS.has(event):
		set_ = Plot.EXTRA_BARKS[event]
	if set_.is_empty():
		return ""
	var i := (rng.randi() if rng != null else randi()) % set_.size()
	return Plot.pick(set_[i], mature())

## Every line to bake: [{kind, who, text, id, rate, fx}] with both takes, texts deduplicated per kind. Includes the
## crews' Barks.gd lines (kind "bark", "cry" for begging).
static func bake_list() -> Array:
	var out: Array = []
	var seen := {}
	var add := func(kind: String, who: String, text: String) -> void:
		var k := kind + "|" + text
		if text == "" or seen.has(k):
			return
		seen[k] = true
		var v := voice_for(kind, who, text)
		out.append({"kind": kind, "who": who, "text": text, "key": key(kind, text), "id": v["id"], "rate": v["rate"], "fx": v["fx"]})
	for item in Plot.voiced_pairs():
		for m in [true, false]:
			add.call(item["kind"], item["who"], Plot.pick(item["pair"], m))
	var barks := load("res://npc/Barks.gd")
	if barks != null:
		for ev in barks.LINES:
			for pair in barks.LINES[ev]:
				for m in [true, false]:
					add.call("cry" if ev == "begging" else "bark", "DOCK", String(pair[0] if m else pair[1]))
	return out
