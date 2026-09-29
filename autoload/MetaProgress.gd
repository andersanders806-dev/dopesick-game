extends Node
## Everything that survives a run, saved to disk.
##
## A run is one stretch of days, from waking up on Day 1 to going down for
## good (GameState.STRIKES_PER_RUN busts). Before this, a run had no end and
## no memory: tolerance climbed until the numbers stopped working and there
## was nothing to do but keep going or quit, and a bust cost you a fine and
## nothing else. Both ends of that were the problem -- no stakes on failure,
## and no reason to start again.
##
## The fix is the standard roguelite one, which is the most consistently
## load-bearing retention mechanic in the genre: failure has to *buy*
## something permanent, or repeated failure just wears people down. So every
## run pays out Know-How whether it went well or badly, and Know-How buys
## upgrades that make the next run meaningfully different rather than merely
## easier -- the upgrades change how you can play (run quieter, grab faster,
## take a third bust) rather than just handing over bigger numbers.
##
## Thematically Know-How is what you actually keep off a bad stretch: you
## learn which shops watch the aisles, who pays, and how long you've got.

const SAVE_PATH := "user://progress.cfg"

signal know_how_changed(amount: int)
signal upgrade_bought(id: String)

## Each upgrade's cost per tier, and what each tier does. `per_tier` is read
## by the accessors at the bottom; nothing else should reach into `levels`.
const UPGRADES := {
	"steady_hands": {
		"name": "Steady Hands",
		"desc": "Grabs take less time, so you're exposed on the shelf for less of it.",
		"max_tier": 3,
		"costs": [3, 6, 11],
		"per_tier": 0.1,  # seconds off the grab
	},
	"light_touch": {
		"name": "Light Touch",
		"desc": "Staff take longer to get suspicious of you.",
		"max_tier": 3,
		"costs": [4, 8, 14],
		"per_tier": 0.15,  # fraction off suspicion build rate
	},
	"deep_pockets": {
		"name": "Deep Pockets",
		"desc": "You start each run with a little put by.",
		"max_tier": 3,
		"costs": [2, 5, 9],
		"per_tier": 15,  # starting cash
	},
	"clean_stretch": {
		"name": "Clean Stretch",
		"desc": "Withdrawal creeps in more slowly. Tolerance still builds.",
		"max_tier": 3,
		"costs": [5, 10, 17],
		"per_tier": 0.08,  # fraction off craving decay
	},
	"known_face": {
		"name": "A Known Face",
		"desc": "The regulars trust you, and pay better for what they asked for.",
		"max_tier": 3,
		"costs": [4, 9, 15],
		"per_tier": 0.12,  # fraction added to what patrons pay
	},
	"good_lawyer": {
		"name": "Someone To Call",
		"desc": "Busts cost you less, and at the top tier you get one more chance before a run ends.",
		"max_tier": 2,
		"costs": [6, 14],
		"per_tier": 0.12,  # fraction off the bust fine
	},
}

var know_how: int = 0
## upgrade id -> tier owned (0 = not bought).
var levels: Dictionary = {}
## Lifetime stats, for the run-summary screen.
var runs_completed: int = 0
var best_day: int = 0

func _ready() -> void:
	load_progress()

# --- persistence -----------------------------------------------------------

func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	know_how = cfg.get_value("meta", "know_how", 0)
	runs_completed = cfg.get_value("meta", "runs_completed", 0)
	best_day = cfg.get_value("meta", "best_day", 0)
	var saved: Dictionary = cfg.get_value("meta", "levels", {})
	# Only keep ids that still exist, so removing an upgrade can't break a
	# save made before it was removed.
	for id in saved:
		if UPGRADES.has(id):
			levels[id] = clampi(int(saved[id]), 0, UPGRADES[id]["max_tier"])

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "know_how", know_how)
	cfg.set_value("meta", "runs_completed", runs_completed)
	cfg.set_value("meta", "best_day", best_day)
	cfg.set_value("meta", "levels", levels)
	cfg.save(SAVE_PATH)

# --- upgrades --------------------------------------------------------------

func tier(id: String) -> int:
	return int(levels.get(id, 0))

func is_maxed(id: String) -> bool:
	return tier(id) >= int(UPGRADES[id]["max_tier"])

## What the next tier costs, or -1 if it's already maxed.
func next_cost(id: String) -> int:
	if not UPGRADES.has(id) or is_maxed(id):
		return -1
	return int(UPGRADES[id]["costs"][tier(id)])

func can_afford(id: String) -> bool:
	var cost := next_cost(id)
	return cost >= 0 and know_how >= cost

func buy(id: String) -> bool:
	if not can_afford(id):
		return false
	know_how -= next_cost(id)
	levels[id] = tier(id) + 1
	save_progress()
	know_how_changed.emit(know_how)
	upgrade_bought.emit(id)
	return true

## Total effect of an upgrade: its per-tier value times the tier owned.
func effect(id: String) -> float:
	if not UPGRADES.has(id):
		return 0.0
	return float(UPGRADES[id]["per_tier"]) * tier(id)

# --- what the rest of the game asks for ------------------------------------

func starting_cash() -> int:
	return 6 + int(effect("deep_pockets"))

## Seconds a grab takes, floored so it can never become instant.
func pickup_duration(base: float) -> float:
	return max(0.25, base - effect("steady_hands"))

## Multiplier on how fast guards get suspicious.
func suspicion_scale() -> float:
	return max(0.35, 1.0 - effect("light_touch"))

func craving_decay_scale() -> float:
	return max(0.5, 1.0 - effect("clean_stretch"))

func payout_scale() -> float:
	return 1.0 + effect("known_face")

func bust_fine_scale() -> float:
	return max(0.3, 1.0 - effect("good_lawyer"))

## An extra strike once "Someone To Call" is maxed.
func extra_strikes() -> int:
	return 1 if is_maxed("good_lawyer") else 0

# --- run payout ------------------------------------------------------------

## What a finished run is worth. Every run pays something -- that's the whole
## point -- but lasting longer and actually delivering orders pays much more
## than scraping through day one.
func award_for_run(days_survived: int, orders_delivered: int, cash_earned: int) -> int:
	var earned := 1 + days_survived + orders_delivered * 2 + int(cash_earned / 60.0)
	know_how += earned
	runs_completed += 1
	best_day = max(best_day, days_survived)
	save_progress()
	know_how_changed.emit(know_how)
	return earned
