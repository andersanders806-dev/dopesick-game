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
	"Pawnbroker": {"id": 660, "rate": 1.1, "pitch": 0.96},
	"Carl": {"id": 84, "rate": 1.1, "pitch": 0.97},
	"Dee": {"id": 588, "rate": 1.05, "pitch": 1.0},
	"Marcus": {"id": 96, "rate": 1.05, "pitch": 1.0},
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
	if FileAccess.file_exists(_path(key)):
		_play(key, cast["pitch"])
		return
	_pending_key = key
	_pending_pitch = cast["pitch"]
	_queue(key, line, cast, true)

## Generate lines ahead of time (e.g. an NPC's small talk as a room loads),
## so they play instantly when asked for.
func prewarm(speaker: String, lines: Array) -> void:
	if not _piper_ok:
		return
	for text in lines:
		var line := spoken_part(speaker, text)
		if line == "":
			continue
		var key := line_key(speaker, line)
		if not FileAccess.file_exists(_path(key)):
			_queue(key, line, cast_for(speaker), false)

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

func _play(key: String, pitch: float) -> void:
	var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(_path(key)))
	if stream == null:
		return
	_player.stream = stream
	_player.pitch_scale = pitch
	_player.play()

func _queue(key: String, line: String, cast: Dictionary, urgent: bool) -> void:
	if not _piper_ok:
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
		line_ready.emit.call_deferred(job["key"])

func _on_line_ready(key: String) -> void:
	if key == _pending_key:
		_pending_key = ""
		_play(key, _pending_pitch)
