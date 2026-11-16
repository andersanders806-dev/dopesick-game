extends Node
## Spoken dialogue. Whatever a character says out loud -- the parts of a
## dialogue line in quotes, or the whole line when a named character is
## talking -- is spoken in that character's own voice.
##
## Voices come from Piper (https://github.com/rhasspy/piper, MIT), a local
## neural text-to-speech engine, with the LibriTTS-R multi-speaker model:
## 904 different real-sounding voices in one file. Each cast member gets
## one of them (CAST), picked by measured pitch so the deep ones go to the
## pusher and his collector and so on. Lines are generated the first time
## they're needed, on a background thread, and kept as .wav files in
## res://assets/voice/ -- so once a line has been heard it's instant, and
## the game still speaks every cached line on a machine without Piper.

const PIPER_DIR := "res://tools/piper/"
const MODEL := "en_US-libritts_r-medium.onnx"
const VOICE_DIR := "res://assets/voice/"
## Cast ids from here up are baked-only voices (the pre-baked set of the story and the street): they are
## never sent to Piper, a line without a wav is silent text.
const BAKED_ONLY_FROM := 1000
## Decoded streams kept for lines heard again, oldest dropped first.
const KEEP_STREAMS := 48

## speaker name -> Piper speaker id, speaking rate (length_scale: >1 is
## slower), and a playback pitch nudge. Ids chosen by measured median pitch
## (dev notes: ~90 Hz is the deepest in the model, ~250 Hz the highest).
const CAST := {
	"Pusher": {"id": 36, "rate": 1.05, "pitch": 0.97},
	"Collector": {"id": 132, "rate": 1.15, "pitch": 0.9},
	"Lookout": {"id": 168, "rate": 0.95, "pitch": 1.0},
	"Ray": {"id": 48, "rate": 1.1, "pitch": 0.95},
	"Bartender": {"id": 288, "rate": 1.05, "pitch": 1.0},
	"Big Eddie": {"id": 552, "rate": 1.1, "pitch": 0.94},
	"Old Sailor": {"id": 600, "rate": 1.15, "pitch": 0.95},
	"Wiry Guy": {"id": 168, "rate": 0.9, "pitch": 1.05},
	"Nervous Dave": {"id": 636, "rate": 0.88, "pitch": 1.04},
	"Quiet Kid": {"id": 828, "rate": 1.05, "pitch": 1.03},
	"Tired Woman": {"id": 144, "rate": 1.15, "pitch": 0.98},
	"Cashier": {"id": 12, "rate": 1.0, "pitch": 1.0},
	"Pharmacist": {"id": 852, "rate": 1.0, "pitch": 1.0},
	"Clerk": {"id": 684, "rate": 1.0, "pitch": 1.0},
	"Security": {"id": 720, "rate": 1.05, "pitch": 0.95},
	"Stocker": {"id": 816, "rate": 1.0, "pitch": 1.0},
	"Assistant": {"id": 372, "rate": 0.97, "pitch": 1.02},
	"Sales": {"id": 444, "rate": 0.95, "pitch": 1.02},
	"Officer": {"id": 564, "rate": 1.05, "pitch": 0.96},
	"Booking Officer": {"id": 648, "rate": 1.05, "pitch": 0.95},
	"Intercom": {"id": 648, "rate": 1.1, "pitch": 0.95},
	"Driver": {"id": 156, "rate": 1.0, "pitch": 0.97},
	"Volunteer": {"id": 708, "rate": 1.0, "pitch": 1.0},
	"Outreach": {"id": 108, "rate": 1.0, "pitch": 1.0},
	"Dana": {"id": 108, "rate": 1.0, "pitch": 1.0},
	"Pawnbroker": {"id": 660, "rate": 1.1, "pitch": 0.96},
	"Carl": {"id": 84, "rate": 1.1, "pitch": 0.97},
	"Dee": {"id": 588, "rate": 1.05, "pitch": 1.0},
	"Marcus": {"id": 96, "rate": 1.05, "pitch": 1.0},
	# Reads the cutscene captions: low, unhurried, worn.
	"Narrator": {"id": 110, "rate": 1.12, "pitch": 0.95},
	# Unnamed staff lines (closing time, the jail door): a flat, bored voice.
	"": {"id": 684, "rate": 1.05, "pitch": 0.98},
}
## Anyone not in CAST gets a stable pick from these, by name.
const FALLBACK_IDS := [110, 115, 142, 146, 170, 172, 207, 210, 217, 220]

signal line_ready(key: String)

var _player: AudioStreamPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _jobs: Array = []
var _quit := false
var _pending_key: String = ""
var _pending_pitch: float = 1.0
var _piper_ok: bool = false
## key -> AudioStream already built (main thread only).
var _streams := {}
var _stream_order: Array = []
## key -> the wav's bytes, read by the Piper worker the moment it wrote the file (guarded by _mutex): building the
## stream from them is a copy, where reading the file was a disk wait on the frame that played the line.
var _bytes := {}
## Imported lines being read by the engine's own loader threads: key -> true.
var _loading := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	add_child(_player)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VOICE_DIR))
	_piper_ok = FileAccess.file_exists(PIPER_DIR + "piper") and FileAccess.file_exists(PIPER_DIR + MODEL)
	line_ready.connect(_on_line_ready)
	if _piper_ok:
		_thread = Thread.new()
		_thread.start(_worker)

func _exit_tree() -> void:
	if _thread:
		_quit = true
		_semaphore.post()
		_thread.wait_to_finish()

## Speak the spoken part of a dialogue box. Called by the HUD and the
## choice menu for every line they show.
func say(speaker: String, text: String) -> void:
	var line := spoken_part(speaker, text)
	stop()
	if line == "":
		return
	var cast := cast_for(speaker)
	var key := line_key(speaker, line)
	if _have(key):
		_speak_when_ready(key, cast["pitch"])
		return
	_pending_key = key
	_pending_pitch = cast["pitch"]
	_queue(key, line, cast, true)

## A cutscene caption, read in full by the narrator (say() would only
## voice the quoted parts).
func narrate(text: String) -> void:
	stop()
	var line := text.strip_edges()
	if line == "":
		return
	var cast := cast_for("Narrator")
	var key := line_key("Narrator", line)
	if _have(key):
		_speak_when_ready(key, cast["pitch"])
		return
	_pending_key = key
	_pending_pitch = cast["pitch"]
	_queue(key, line, cast, true)

## Generate lines ahead of time (e.g. an NPC's small talk as a room loads),
## so they play instantly when asked for.
func prewarm(speaker: String, lines: Array) -> void:
	warm(speaker, lines)
	if not _piper_ok:
		return
	for text in lines:
		var line := spoken_part(speaker, text)
		if line == "":
			continue
		var key := line_key(speaker, line)
		if not _have(key):
			_queue(key, line, cast_for(speaker), false)

## Lines that are already on disk, started loading on the engine's loader threads ahead of time (a room's small
## talk), so they play on the frame they are asked for.
func warm(speaker: String, lines: Array) -> void:
	for text in lines:
		var line := spoken_part(speaker, text)
		if line == "":
			continue
		var key := line_key(speaker, line)
		if _have(key) and not _streams.has(key):
			_request_load(key)

func stop() -> void:
	_pending_key = ""
	_player.stop()

func is_speaking() -> bool:
	return _player.playing

## What's said out loud: the quoted parts if there are any; otherwise the
## whole line if a named character is speaking; narration isn't voiced.
static func spoken_part(speaker: String, text: String) -> String:
	var quotes := RegEx.create_from_string("\"([^\"]+)\"")
	var parts: Array[String] = []
	for m in quotes.search_all(text):
		parts.append(m.get_string(1).strip_edges())
	if not parts.is_empty():
		return " ".join(parts)
	if speaker != "":
		return text.strip_edges()
	return ""

static func cast_for(speaker: String) -> Dictionary:
	if CAST.has(speaker):
		return CAST[speaker]
	return {"id": FALLBACK_IDS[abs(speaker.hash()) % FALLBACK_IDS.size()], "rate": 1.0, "pitch": 1.0}

static func line_key(speaker: String, line: String) -> String:
	return "%d_%s" % [cast_for(speaker)["id"], ("%s|%s" % [cast_for(speaker)["rate"], line]).md5_text().left(16)]

func _path(key: String) -> String:
	return VOICE_DIR + key + ".wav"

## A line is available either as a loose .wav on disk (generated this
## session, or in the editor) or as an imported resource (an exported build,
## where res:// is packed and there's no file to read).
func _have(key: String) -> bool:
	return FileAccess.file_exists(_path(key)) or ResourceLoader.exists(_path(key))

## The stream for `key`, built without waiting on the disk when it can be: from the cache, from the bytes the
## worker read, or from the loader thread's finished load; only a line nothing has touched is read here.
func _load(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var made: AudioStream = null
	_mutex.lock()
	var bytes: PackedByteArray = _bytes.get(key, PackedByteArray())
	_bytes.erase(key)
	_mutex.unlock()
	if not bytes.is_empty():
		made = AudioStreamWAV.load_from_buffer(bytes)
	if made == null and _loading.has(key) and ResourceLoader.load_threaded_get_status(_path(key)) == ResourceLoader.THREAD_LOAD_LOADED:
		made = ResourceLoader.load_threaded_get(_path(key)) as AudioStream
	_loading.erase(key)
	if made == null:
		var disk := ProjectSettings.globalize_path(_path(key))
		if FileAccess.file_exists(disk) and not OS.has_feature("template"):
			made = AudioStreamWAV.load_from_file(disk)
		elif ResourceLoader.exists(_path(key)):
			made = load(_path(key))
	if made != null:
		_streams[key] = made
		_stream_order.erase(key)
		_stream_order.append(key)
		while _stream_order.size() > KEEP_STREAMS:
			_streams.erase(_stream_order.pop_front())
	return made

## Imported (packed or editor-imported) lines go to the engine's loader threads; a loose wav (made this session,
## not imported) has nothing to request and is read when played.
func _request_load(key: String) -> void:
	if _loading.has(key) or _streams.has(key):
		return
	var path := _path(key)
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
		_loading[key] = true

## Plays `key` now if it is built, else asks for it and plays it the frame the loader has it.
func _speak_when_ready(key: String, pitch: float) -> void:
	if _streams.has(key) or not _loading.has(key) and not ResourceLoader.exists(_path(key)):
		_play(key, pitch)
		return
	_pending_key = key
	_pending_pitch = pitch
	_request_load(key)
	set_process(true)

func _process(_delta: float) -> void:
	# Only a baked line waiting on a loader thread is this node's to play; a line Piper is making is played by
	# _on_line_ready when it is done.
	if _pending_key == "" or not _loading.has(_pending_key):
		set_process(false)
		return
	if ResourceLoader.load_threaded_get_status(_path(_pending_key)) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var key := _pending_key
		_pending_key = ""
		_play(key, _pending_pitch)

func _play(key: String, pitch: float) -> void:
	var stream := _load(key)
	if stream == null:
		return
	_player.stream = stream
	_player.pitch_scale = pitch
	_player.play()

## A short line of `speaker`'s as a stream of its own, for a voice that is heard from where it
## stands (a guard's bark, npc/Guard3D.gd) instead of over the dialogue's single player. Null if
## it isn't baked yet (and it's queued, where Piper is installed).
func bark_stream(speaker: String, line: String) -> AudioStream:
	var key := line_key(speaker, line)
	if _have(key):
		return _load(key)
	_queue(key, line, cast_for(speaker), false)
	return null

func _queue(key: String, line: String, cast: Dictionary, urgent: bool) -> void:
	# Baked-only voices (ids from 1000) are never made here, and Piper may not be installed at all.
	if not _piper_ok or int(cast["id"]) >= BAKED_ONLY_FROM:
		return
	_mutex.lock()
	for j in _jobs:
		if j["key"] == key:
			_mutex.unlock()
			if urgent:
				_bump(key)
			return
	var job := {"key": key, "line": line, "id": cast["id"], "rate": cast["rate"]}
	if urgent:
		_jobs.push_front(job)
	else:
		_jobs.push_back(job)
	_mutex.unlock()
	_semaphore.post()

func _bump(key: String) -> void:
	_mutex.lock()
	for i in _jobs.size():
		if _jobs[i]["key"] == key:
			var j = _jobs[i]
			_jobs.remove_at(i)
			_jobs.push_front(j)
			break
	_mutex.unlock()

func _worker() -> void:
	var dir := ProjectSettings.globalize_path(PIPER_DIR)
	while true:
		_semaphore.wait()
		if _quit:
			return
		_mutex.lock()
		var job = _jobs.pop_front() if not _jobs.is_empty() else null
		_mutex.unlock()
		if job == null:
			continue
		var out_path := ProjectSettings.globalize_path(_path(job["key"]))
		var tmp := out_path + ".part"
		var text: String = job["line"].replace("'", "'\\''")
		var cmd := "printf '%%s' '%s' | '%spiper' -m '%s%s' -s %d --length_scale %.2f --sentence_silence 0.15 -f '%s' >/dev/null 2>&1 && mv '%s' '%s'" % [
			text, dir, dir, MODEL, job["id"], job["rate"], tmp, tmp, out_path]
		OS.execute("sh", ["-c", cmd])
		# The file's bytes are read here, on the worker, for the frame that plays the line.
		if FileAccess.file_exists(out_path):
			var data := FileAccess.get_file_as_bytes(out_path)
			if not data.is_empty():
				_mutex.lock()
				_bytes[job["key"]] = data
				_mutex.unlock()
		line_ready.emit.call_deferred(job["key"])

func _on_line_ready(key: String) -> void:
	if key == _pending_key:
		_pending_key = ""
		_play(key, _pending_pitch)
