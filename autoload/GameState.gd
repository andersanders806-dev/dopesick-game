extends Node

## Persists across scene changes: money, stolen goods, craving, wanted state.

const WalkmanScript := preload("res://autoload/Walkman.gd")

signal cash_changed(new_cash: int)
signal craving_changed(new_craving: float)
signal inventory_changed
signal wanted_changed(is_wanted: bool)
signal busted
signal day_changed(new_day: int)
## What you owe the pusher changed (0 once you're square).
signal debt_changed(amount: int)
## It started or stopped raining.
signal weather_changed(raining: bool)
## The clock ticked over to a new game minute (0..1439).
signal clock_changed(minute_of_day: int)
## A run has ended (you ran out of chances). Carries the summary the run-end
## screen shows: days survived, orders delivered, cash earned, Know-How won.
signal run_ended(summary: Dictionary)
signal strikes_changed(strikes: int)
## A dose landed. `outcome` is one of "relief", "precipitated", "overdose",
## "saved" -- the HUD narrates it.
signal dose_taken(drug_id: String, outcome: String)
signal overdosed(fatal: bool)

## Everything that can be stolen, which store stocks it, and what a patron
## will pay for it. Picked from lists of what gets shoplifted to fund a habit
## (small, valuable, easy to resell: the CRAVED hot-products research):
## locked-up razors and whitening strips from pharmacies, packaged steaks and
## detergent from supermarkets (little security, and detergent trades almost
## like cash), cigarettes and phone accessories from corner shops, spirits
## from liquor stores, and headphones and phones from electronics stores --
## worth the most, and guarded the hardest.
##
## Prices are what a patron pays you, tiered by how risky the store is (see
## dev-tools/balance_sim.gd): the safe supermarket's goods pay less than one
## $20 fix, a typical pharmacy or corner-shop order covers one, and liquor
## and electronics pay enough to get ahead -- which matters as tolerance
## pushes the fix up $4 a day.
const REQUEST_POOL := [
	{"id": "cigs", "name": "a carton of cigarettes", "price": 22, "store": "convenience"},
	{"id": "charger", "name": "a phone charger", "price": 15, "store": "convenience"},
	{"id": "batteries", "name": "a pack of batteries", "price": 12, "store": "convenience"},
	{"id": "energy", "name": "a four-pack of energy drinks", "price": 12, "store": "convenience"},
	{"id": "sunglasses", "name": "a pair of sunglasses", "price": 16, "store": "convenience"},
	{"id": "razors", "name": "a pack of razor blades", "price": 28, "store": "pharmacy"},
	{"id": "whitening", "name": "a box of teeth whitening strips", "price": 32, "store": "pharmacy"},
	{"id": "coldmeds", "name": "a box of cold and allergy pills", "price": 20, "store": "pharmacy"},
	{"id": "formula", "name": "a tin of baby formula", "price": 35, "store": "pharmacy"},
	{"id": "makeup", "name": "a makeup palette", "price": 24, "store": "pharmacy"},
	{"id": "steak", "name": "a pack of steaks", "price": 18, "store": "supermarket"},
	{"id": "detergent", "name": "a big jug of laundry detergent", "price": 14, "store": "supermarket"},
	{"id": "cheese", "name": "a block of good cheese", "price": 12, "store": "supermarket"},
	{"id": "whiskey", "name": "a bottle of good whiskey", "price": 40, "store": "liquor"},
	{"id": "vodka", "name": "a bottle of vodka", "price": 30, "store": "liquor"},
	{"id": "cognac", "name": "a bottle of cognac", "price": 55, "store": "liquor"},
	{"id": "headphones", "name": "a pair of wireless headphones", "price": 60, "store": "electronics"},
	{"id": "videogame", "name": "a new video game", "price": 40, "store": "electronics"},
	{"id": "watch", "name": "a decent watch", "price": 55, "store": "electronics"},
	{"id": "smartphone", "name": "a smartphone", "price": 80, "store": "electronics"},
]

const STORE_NAMES := {
	"convenience": "the corner shop",
	"pharmacy": "the pharmacy",
	"supermarket": "the supermarket",
	"liquor": "the liquor store",
	"electronics": "the electronics store",
}

## The clock. Four game minutes pass per real second, so a full day is six
## real minutes: roughly two fixes' worth of craving, which keeps the hours
## meaningful without the day outrunning the meter.
const MINUTES_PER_SEC := 4.0
const WAKE_MINUTE := 8 * 60
const MINUTES_PER_DAY := 24 * 60
## [open, close) in hours; a close earlier than the open wraps past midnight.
## The corner shop is the 24/7 on the block, the bar keeps late hours, and
## everything else keeps ordinary retail hours -- so the nights are thin:
## one open store, the bar, and the pusher.
const OPENING_HOURS := {
	"convenience": [0, 24],
	"pharmacy": [9, 21],
	"supermarket": [7, 23],
	"liquor": [10, 23],
	"electronics": [10, 20],
	"bar": [11, 2],
	# Shelters turn people out in the morning and open again for dinner.
	"shelter": [17, 10],
	"pawn": [10, 19],
	"music": [10, 21],
}
## The shelter's two meal services, [start, end) hours.
const MEAL_HOURS := [[7, 10], [17, 20]]
## Street selling picks up in the afternoon and runs through the night; in
## the morning the corner is empty, which is exactly when you're sickest.
const PUSHER_HOURS := [16, 5]
## Which place a door leads into, by scene file, for the opening-hours check.
const SCENE_PLACE := {
	"StoreConvenience3D": "convenience",
	"StorePharmacy3D": "pharmacy",
	"StoreSupermarket3D": "supermarket",
	"StoreLiquor3D": "liquor",
	"StoreElectronics3D": "electronics",
	"DiveBar3D": "bar",
	"Shelter3D": "shelter",
	"Pawn3D": "pawn",
	"MusicStore3D": "music",
}

## Credit. When you're short he'll front you a dose -- at a markup, one
## front at a time, and only for something cheap -- due back a day later.
## Late, and someone comes to collect: they take what you've got, and if
## that isn't enough they hurt you, add a late fee, and give you until
## tomorrow.
const FRONT_MARKUP := 1.5
const FRONT_LIMIT := 60
const DEBT_GRACE_MINUTES := 24 * 60
const LATE_FEE := 15
const REGRACE_MINUTES := 12 * 60
const BEATING_CRAVING_COST := 25.0
const HURT_MINUTES := 4 * 60

const CRAVING_DECAY_PER_SEC := 0.55
const DECAY_INCREASE_PER_DAY := 0.04
const FIX_COST_BASE := 20
const FIX_COST_INCREASE_PER_DAY := 4
const FENCE_PRICE := 8
const BUST_FINE_FRACTION := 0.35
## How many busts a run survives. The third one ends it -- see
## autoload/MetaProgress.gd for why a run needs an end at all. "Someone To
## Call" buys one more.
const STRIKES_PER_RUN := 3

var cash: int = 6
var inventory: Array[String] = []
var craving: float = 45.0
var wanted: bool = false
var day: int = 1
## Minutes since midnight. Crossing midnight starts the next day.
var clock: float = WAKE_MINUTE
## Tests stop the clock so opening hours can't change under them mid-check.
var clock_running: bool = true
## Weather. Rolled once an hour: rain sets in now and then and hangs around
## for a few hours.
var raining: bool = false
const RAIN_START_CHANCE := 0.12
const RAIN_STOP_CHANCE := 0.3
var _last_minute: int = -1
var pending_spawn: String = ""
## True from the moment you're caught until you're booked into a cell. While
## it's set nothing can spot, chase, or bust you again -- without it, a
## shopkeeper who still saw your theft window could re-trigger the alarm and
## you'd be "busted" two or three times in one catch.
var in_custody: bool = false
## Set by start_run(); the Apartment plays the opening cutscene once and
## clears it, so it runs at the top of each run but not on every wake-up.
var intro_pending: bool = false
## The first score of a run gets its own cutscene (Pusher3D._handoff).
var scored_this_run: bool = false
## Who's drinking in the Dive Bar and what they asked you for. Kept here so
## orders stick until you deliver them -- through leaving the bar, a night in
## a cell, or sleeping. Each entry: {name, model, seat, request_id, price,
## fulfilled}. Managed by DiveBar3D.gd.
var bar_patrons: Array = []
## Busts so far this run. At STRIKES_PER_RUN (plus any bought) the run ends.
var strikes: int = 0
## Tolerance per drug class, built by using and (for buprenorphine) reduced
## by it. Shared within a class, because cross-tolerance is real: a week on
## fentanyl leaves you needing more heroin too.
var tolerance: Dictionary = {}
## When each class was last taken, in seconds of run time. Drives
## buprenorphine's precipitated withdrawal and the opioid/benzo mixing risk.
var last_dose_at: Dictionary = {}
var run_time: float = 0.0
## Naloxone on hand. Each one cancels one overdose.
var naloxone: int = 0
## What you took this run, for the summary.
var doses_taken: int = 0
## Duration multiplier of whatever is currently in you: a long-acting dose
## means the craving meter falls more slowly until it wears off. 1.0 when
## there's nothing holding you.
var active_duration: float = 1.0
## What you owe the pusher, when it's due (absolute game minutes, see
## now_minutes()), and until when you're limping from the last collection.
var debt: int = 0
var debt_due: float = 0.0
var hurt_until: float = -1.0
## How much Ray, the man sitting out by the alley, owes you for the dollars
## and odds and ends you've given him. Any at all and he's on your side:
## tips, and pointing the cops the wrong way. None, and he'll give you up.
var homeless_trust: int = 0
## The walkman, once you've picked it up at home, and the tapes you own
## (autoload/Walkman.gd). You start every run with the shoebox of ten.
var has_walkman: bool = false
var tapes: Array = []
## Once-a-day things, by day number: the shelter's naloxone kit and bupe
## dose, a dumpster dive out back. And which meal service you last ate at
## (day * 2 + service), so it's one plate per sitting.
var daily_used: Dictionary = {}
var last_meal_slot: int = -1
## Tallies for the run summary.
var orders_delivered: int = 0
var cash_earned: int = 0

func _ready() -> void:
	_setup_input_actions()
	start_run()

## Wipes the per-run state and applies whatever the meta upgrades grant at
## the start of a run. Called once at boot and again after each run ends.
func start_run() -> void:
	cash = MetaProgress.starting_cash()
	inventory.clear()
	craving = 45.0
	day = 1
	clock = WAKE_MINUTE
	raining = false
	strikes = 0
	orders_delivered = 0
	cash_earned = 0
	tolerance.clear()
	last_dose_at.clear()
	run_time = 0.0
	naloxone = 0
	doses_taken = 0
	active_duration = 1.0
	wanted = false
	in_custody = false
	bar_patrons.clear()
	debt = 0
	debt_due = 0.0
	homeless_trust = 0
	has_walkman = false
	# The script, not the Walkman autoload: start_run() first runs from our
	# _ready(), before autoloads after us in the list exist.
	tapes = WalkmanScript.STARTING_TAPES.duplicate()
	daily_used.clear()
	last_meal_slot = -1
	hurt_until = -1.0
	pending_spawn = ""
	intro_pending = true
	scored_this_run = false
	cash_changed.emit(cash)
	craving_changed.emit(craving)
	inventory_changed.emit()
	day_changed.emit(day)
	_emit_clock()
	strikes_changed.emit(strikes)
	wanted_changed.emit(wanted)
	debt_changed.emit(debt)

func max_strikes() -> int:
	return STRIKES_PER_RUN + MetaProgress.extra_strikes()

func _process(delta: float) -> void:
	run_time += delta
	if clock_running:
		advance_clock(MINUTES_PER_SEC * delta)
	if craving > 0.0:
		craving = max(0.0, craving - current_craving_decay() * delta)
		craving_changed.emit(craving)

## Tolerance builds day over day: withdrawal creeps in faster the longer
## you've been using, same as a real dependency.
func current_craving_decay() -> float:
	var base := CRAVING_DECAY_PER_SEC + (day - 1) * DECAY_INCREASE_PER_DAY
	# A long-acting dose holds you longer, so the meter falls more slowly.
	return base * MetaProgress.craving_decay_scale() / active_duration

## How sick you are, 0..1, for the senses. It creeps in from SICKNESS_ONSET
## -- before withdrawal slows you down at 20 -- and is total at 0: the
## screen swims and doubles, sounds that aren't there, hands that shake.
const SICKNESS_ONSET := 35.0

func sickness() -> float:
	return clampf(1.0 - craving / SICKNESS_ONSET, 0.0, 1.0)

## The pusher charges more each day too -- it takes more to get the same
## relief, so standing still gets more expensive.
func current_fix_cost() -> int:
	return FIX_COST_BASE + (day - 1) * FIX_COST_INCREASE_PER_DAY

## The cheapest thing on the street that would actually stop the sickness --
## what you need on you before it's worth walking down to the pusher.
func cheapest_opioid_cost() -> int:
	var best := 9999
	for d in Drugs.CATALOGUE:
		if d["class"] in [Drugs.OPIOID, Drugs.TREATMENT]:
			best = min(best, price_of(d["id"]))
	return best

## Moves the clock forward, rolling into the next day at midnight.
func advance_clock(minutes: float) -> void:
	clock += minutes
	while clock >= MINUTES_PER_DAY:
		clock -= MINUTES_PER_DAY
		day += 1
		day_changed.emit(day)
	_emit_clock()

func _emit_clock() -> void:
	var minute := int(clock)
	if minute != _last_minute:
		if _last_minute >= 0 and minute / 60 != _last_minute / 60:
			_roll_weather()
		_last_minute = minute
		clock_changed.emit(minute)

## Game minutes since the run began: days and clock on one line, so a due
## time can span midnight.
func now_minutes() -> float:
	return (day - 1) * MINUTES_PER_DAY + clock

func _roll_weather() -> void:
	var was := raining
	raining = (randf() > RAIN_STOP_CHANCE) if raining else (randf() < RAIN_START_CHANCE)
	if raining != was:
		weather_changed.emit(raining)

func set_raining(value: bool) -> void:
	if raining != value:
		raining = value
		weather_changed.emit(raining)

func hour() -> float:
	return clock / 60.0

func clock_text() -> String:
	return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]

static func hours_contain(hours: Array, h: float) -> bool:
	var open: float = hours[0]
	var close: float = hours[1]
	if open <= close:
		return h >= open and h < close
	return h >= open or h < close

func is_open(place: String) -> bool:
	return hours_contain(OPENING_HOURS.get(place, [0, 24]), hour())

func opening_hour(place: String) -> int:
	return OPENING_HOURS.get(place, [0, 24])[0]

func place_for_scene(scene_path: String) -> String:
	return SCENE_PLACE.get(scene_path.get_file().get_basename(), "")

## True if `what` hasn't been used yet today; marks it used when `take`.
func daily_available(what: String, take := false) -> bool:
	var free: bool = daily_used.get(what, -1) != day
	if free and take:
		daily_used[what] = day
	return free

## Which meal service is on right now (0 breakfast, 1 dinner), or -1.
func meal_service() -> int:
	for i in MEAL_HOURS.size():
		if hours_contain(MEAL_HOURS[i], hour()):
			return i
	return -1

func pusher_on_shift() -> bool:
	return hours_contain(PUSHER_HOURS, hour())

## 0 at night, 1 in full daylight, easing through dawn (5-8) and dusk
## (18-21). Drives the City's sky, sun, and streetlights.
func daylight() -> float:
	var h := hour()
	if h < 5.0 or h >= 21.0:
		return 0.0
	if h < 8.0:
		return smoothstep(5.0, 8.0, h)
	if h < 18.0:
		return 1.0
	return 1.0 - smoothstep(18.0, 21.0, h)

## How closely shop staff watch, as a multiplier on suspicion. The midday
## rush has staff on the floor and on their toes; the graveyard shift is one
## tired clerk.
func staff_alertness() -> float:
	var h := hour()
	if h >= 22.0 or h < 6.0:
		return 0.75
	if h >= 12.0 and h < 18.0:
		return 1.15
	return 1.0

func _setup_input_actions() -> void:
	_bind("interact", [KEY_E])
	_bind("sprint", [KEY_SHIFT])
	_bind("cancel_ui", [KEY_ESCAPE])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])

func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)

func item_info(id: String) -> Dictionary:
	for r in REQUEST_POOL:
		if r["id"] == id:
			return r
	return {}

func store_name_for(id: String) -> String:
	return STORE_NAMES.get(item_info(id).get("store", ""), "somewhere in town")

func item_name_for(id: String) -> String:
	for r in REQUEST_POOL:
		if r["id"] == id:
			return r["name"]
	return id

func steal_item(id: String) -> void:
	# A tape off Tape Deck's racks goes straight into the shoebox, not your
	# pockets -- it's yours, not something to sell.
	if id.begins_with("tape:"):
		var tape := id.trim_prefix("tape:")
		if Walkman.add_tape(tape):
			Graphics._show_toast("Lifted a tape: %s" % Walkman.TAPES[tape]["title"])
		return
	inventory.append(id)
	inventory_changed.emit()

func has_item(id: String) -> bool:
	return inventory.has(id)

## `price` is the asking price; what you actually get is scaled by how well
## the regulars know you ("A Known Face").
func sell_item(id: String, price: int) -> bool:
	if not inventory.has(id):
		return false
	inventory.erase(id)
	var paid := int(round(price * MetaProgress.payout_scale()))
	cash += paid
	cash_earned += paid
	inventory_changed.emit()
	cash_changed.emit(cash)
	return true

func fence_everything() -> int:
	var count := inventory.size()
	if count == 0:
		return 0
	var earned := count * FENCE_PRICE
	inventory.clear()
	cash += earned
	cash_earned += earned
	inventory_changed.emit()
	cash_changed.emit(cash)
	return earned

func spend_cash(amount: int) -> bool:
	if cash < amount:
		return false
	cash -= amount
	cash_changed.emit(cash)
	return true

func front_price(cost: int) -> int:
	return int(ceil(cost * FRONT_MARKUP))

func can_front(cost: int) -> bool:
	return debt == 0 and cost <= FRONT_LIMIT

## Takes a dose on credit; what you owe is the marked-up price.
func take_front(cost: int) -> void:
	debt = front_price(cost)
	debt_due = now_minutes() + DEBT_GRACE_MINUTES
	debt_changed.emit(debt)

func debt_overdue() -> bool:
	return debt > 0 and now_minutes() >= debt_due

## "Tomorrow 17:30", "today 23:00" -- when the debt is due, for the HUD.
func debt_due_text() -> String:
	var due_day := int(debt_due / MINUTES_PER_DAY) + 1
	var m := int(debt_due) % MINUTES_PER_DAY
	var when := "today" if due_day == day else ("tomorrow" if due_day == day + 1 else "day %d" % due_day)
	return "%s %02d:%02d" % [when, m / 60, m % 60]

## Pays off as much of the debt as `amount` and your cash allow.
func pay_debt(amount: int) -> int:
	var paid: int = mini(amount, mini(cash, debt))
	if paid <= 0:
		return 0
	cash -= paid
	debt -= paid
	cash_changed.emit(cash)
	debt_changed.emit(debt)
	return paid

## The collector caught up with you. Returns what he took. If it didn't
## cover it: a beating (withdrawal comes on hard, and you limp for hours), a
## late fee, and until tomorrow to find the rest.
func collect_debt() -> int:
	var taken := pay_debt(cash)
	if debt > 0:
		craving = maxf(0.0, craving - BEATING_CRAVING_COST)
		craving_changed.emit(craving)
		hurt_until = now_minutes() + HURT_MINUTES
		debt += LATE_FEE
		debt_due = now_minutes() + REGRACE_MINUTES
		debt_changed.emit(debt)
	return taken

func is_hurt() -> bool:
	return now_minutes() < hurt_until

func buy_fix() -> bool:
	if not spend_cash(current_fix_cost()):
		return false
	receive_fix()
	return true

## Tolerance in a drug's class, 0 if it's never been touched.
func tolerance_for(drug_id: String) -> float:
	return float(tolerance.get(Drugs.info(drug_id).get("class", ""), 0.0))

## What this drug costs you right now, given the tolerance you've built.
func price_of(drug_id: String) -> int:
	return Drugs.price_for(drug_id, tolerance_for(drug_id))

## The fix itself, separate from paying: the 3D pusher takes your cash first
## and only hands it over after fetching it from his stash. `drug_id` is what
## you *asked* for; what you actually got was decided at purchase.
##
## Returns the outcome: "relief", "precipitated", "overdose" or "saved".
func take_drug(drug_id: String) -> String:
	var d := Drugs.info(drug_id)
	if d.is_empty():
		return "relief"
	var drug_class: String = d["class"]

	if drug_class == Drugs.RESCUE:
		naloxone += 1
		inventory_changed.emit()
		dose_taken.emit(drug_id, "relief")
		return "relief"

	doses_taken += 1
	var since_opioid: float = run_time - float(last_dose_at.get(Drugs.OPIOID, -9999.0))

	# Buprenorphine binds harder than heroin or fentanyl and displaces them.
	# Taken too soon it doesn't relieve withdrawal, it causes it.
	if drug_id == "bupe" and since_opioid < Drugs.PRECIPITATED_WINDOW:
		craving = max(0.0, craving - 35.0)
		craving_changed.emit(craving)
		last_dose_at[drug_class] = run_time
		dose_taken.emit(drug_id, "precipitated")
		return "precipitated"

	# Opioids and benzodiazepines both suppress breathing; together they are
	# what actually kills people, far more than either alone.
	var risk: float = d["od_risk"]
	var mixing := false
	if drug_class == Drugs.OPIOID:
		mixing = run_time - float(last_dose_at.get(Drugs.BENZO, -9999.0)) < Drugs.MIX_WINDOW
	elif drug_class == Drugs.BENZO:
		mixing = since_opioid < Drugs.MIX_WINDOW
	if mixing:
		risk *= Drugs.MIX_OD_MULTIPLIER
	# Tolerance is genuinely protective, but only partially, and it can never
	# take the risk to zero. Subtracting it linearly (as this first did) let
	# a heavy fentanyl habit drive the risk negative, which made the most
	# dangerous drug in the game the safest once you'd used enough of it --
	# spamming it became the optimal strategy. It is also the wrong model:
	# what kills people on fentanyl is that no two doses are the same, and
	# your tolerance does nothing about an unusually strong one.
	risk *= clampf(1.0 - tolerance_for(drug_id) * 0.012, 0.4, 1.0)

	last_dose_at[drug_class] = run_time
	tolerance[drug_class] = max(0.0, tolerance_for(drug_id) + float(d["tolerance"]))

	if randf() < risk:
		return _overdose()

	craving = min(100.0, craving + float(d["relief"]))
	active_duration = max(0.1, float(d["hours"]))
	craving_changed.emit(craving)
	dose_taken.emit(drug_id, "relief")
	return "relief"

## Going over. Naloxone cancels it at the cost of being thrown straight into
## withdrawal, which is what reversal actually does. Without it, the run is
## over -- the second way to lose, alongside running out of strikes.
func _overdose() -> String:
	if naloxone > 0:
		naloxone -= 1
		craving = 0.0
		craving_changed.emit(craving)
		inventory_changed.emit()
		overdosed.emit(false)
		dose_taken.emit("", "saved")
		return "saved"
	overdosed.emit(true)
	dose_taken.emit("", "overdose")
	end_run("overdose")
	return "overdose"

## Back-compatible: the old single abstract fix, still used by the 2D scenes.
func receive_fix() -> void:
	craving = 100.0
	craving_changed.emit(craving)

func set_wanted(value: bool) -> void:
	if wanted == value:
		return
	wanted = value
	wanted_changed.emit(wanted)

func get_busted() -> void:
	if in_custody:
		return
	in_custody = true
	inventory.clear()
	# A fine, not ruin: you still walk out with most of your cash.
	var fine := int(cash * BUST_FINE_FRACTION * MetaProgress.bust_fine_scale())
	cash -= fine
	strikes += 1
	inventory_changed.emit()
	cash_changed.emit(cash)
	strikes_changed.emit(strikes)
	set_wanted(false)
	busted.emit()
	if strikes >= max_strikes():
		end_run()

## Out of chances. Bank what the run was worth and hand the summary to the
## run-end screen, which starts the next run once the player closes it.
func end_run(cause := "busted") -> void:
	var days_survived := day
	var earned := MetaProgress.award_for_run(days_survived, orders_delivered, cash_earned)
	run_ended.emit({
		"days": days_survived,
		"orders": orders_delivered,
		"cash": cash_earned,
		"know_how": earned,
		"strikes": strikes,
		"doses": doses_taken,
		"cause": cause,
	})

## You sleep until morning. Slept before midnight, that's the next day;
## after midnight the day has already turned over.
func sleep() -> void:
	if clock >= WAKE_MINUTE:
		day += 1
		day_changed.emit(day)
	clock = WAKE_MINUTE
	_emit_clock()
	craving = min(craving, 55.0)
	craving_changed.emit(craving)
