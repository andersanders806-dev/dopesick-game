extends Node
## One save slot for the run in progress: user://save.json.
##
## It's written every time you walk into a room (WorldRoot3D) and when you
## sleep, so "Continue" on the title screen puts you back in the last room
## you entered, where you stood, with everything you had. A run that ends --
## busted for good, or gone over -- deletes it: runs are meant to end, and
## the only thing that carries over is MetaProgress's Know-How.
##
## Never written while you're wanted or in custody: quitting mid-chase and
## continuing somewhere quiet would be a free escape.

const REAL_PATH := "user://save.json"
## Tests and bots (Engine meta "sandbox") save and delete a file of their
## own, so they never touch the player's run.
const SANDBOX_PATH := "user://save_sandbox.json"
var PATH: String:
	get: return SANDBOX_PATH if Engine.get_meta("sandbox", false) else REAL_PATH
const VERSION := 1
## GameState fields that make up a run. Everything else is derived, or
## per-visit, or reset on load.
const FIELDS := ["cash", "inventory", "craving", "day", "clock", "raining", "strikes",
	"tolerance", "last_dose_at", "run_time", "naloxone", "doses_taken", "active_duration",
	"debt", "debt_due", "hurt_until", "homeless_trust", "has_walkman", "tapes",
	"daily_used", "last_meal_slot", "orders_delivered", "cash_earned", "bar_patrons",
	"scored_this_run", "resp_load", "in_treatment", "treatment_streak", "clinic_today", "used_today", "diary",
	"headline", "headline_day", "sabotage_day", "rep", "store_heat",
	"belongings", "pawn_tickets", "apartment_echo_seen", "rent_due_day", "rent_stage", "rent_owed",
	"court_day", "probation_days", "warrant", "parcel", "story", "vendor", "last_street_use",
	"test_strips", "od_event", "dead_regulars", "vigil_day", "vigil_for", "events_rolled_day",
	"booster_day", "booster_gone", "booster_store", "booster_hit", "booster_team", "booster_cut_pending"]

## Where to put the player once the saved room has loaded.
var pending_position = null

func _ready() -> void:
	GameState.run_ended.connect(func(_s): delete())

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func save() -> bool:
	if GameState.wanted or GameState.in_custody:
		return false
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return false
	var data := {"version": VERSION, "scene": scene.scene_file_path, "tape": Walkman.current,
		"saved_at": Time.get_datetime_string_from_system()}
	for f in FIELDS:
		data[f] = GameState.get(f)
	data["jobs"] = {"job": Jobs.job, "bottles": Jobs.bottles, "bottle_day": Jobs.bottle_day, "bottle_spots": Jobs.bottle_spots, "shift": Jobs.shift}
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var p := player.global_position
		data["position"] = [p.x, p.y, p.z]
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true

## A one-line description for the title screen's Continue button.
func summary() -> String:
	var data := _read()
	if data.is_empty():
		return ""
	var room: String = String(data.get("scene", "")).get_file().get_basename().trim_suffix("3D")
	return "Day %d  -  $%d  -  %s" % [int(data.get("day", 1)), int(data.get("cash", 0)), room]

## Puts the saved run into GameState and loads its room.
func continue_run() -> bool:
	var data := _read()
	if data.is_empty():
		return false
	GameState.start_run()
	for f in FIELDS:
		if not data.has(f):
			continue
		var v = data[f]
		var current = GameState.get(f)
		if current is Array:
			(current as Array).assign(v)
		elif current is int:
			GameState.set(f, int(v))
		else:
			GameState.set(f, v)
	# A save from before rent: start the cycle from today, rather than
	# from day 1 with every due date long gone.
	if not data.has("rent_due_day"):
		GameState.rent_due_day = GameState.day + GameState.RENT_PERIOD
	GameState.intro_pending = false
	GameState.pending_spawn = ""
	var j: Dictionary = data.get("jobs", {})
	Jobs.job = j.get("job", {})
	Jobs.bottles = int(j.get("bottles", 0))
	Jobs.bottle_day = int(j.get("bottle_day", -1))
	Jobs.bottle_spots = j.get("bottle_spots", [])
	if j.has("shift"):
		Jobs.shift = j["shift"]
	var pos = data.get("position")
	pending_position = Vector3(pos[0], pos[1], pos[2]) if pos is Array and pos.size() == 3 else null
	GameState.cash_changed.emit(GameState.cash)
	GameState.craving_changed.emit(GameState.craving)
	GameState.inventory_changed.emit()
	GameState.day_changed.emit(GameState.day)
	GameState.strikes_changed.emit(GameState.strikes)
	GameState.debt_changed.emit(GameState.debt)
	# Loading isn't an hour going by: no weather roll, no deadline check,
	# no store hit by Tasha just for having pressed Continue.
	GameState._last_minute = -1
	GameState._emit_clock()
	SceneLoader.go(data["scene"])
	var tape: String = data.get("tape", "")
	if tape != "" and GameState.has_walkman:
		Walkman.play.call_deferred(tape)
	return true

func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func _read() -> Dictionary:
	if not has_save():
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != VERSION:
		return {}
	return parsed
