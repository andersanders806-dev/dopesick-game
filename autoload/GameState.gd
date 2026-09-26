extends Node

## Persists across scene changes: money, stolen goods, craving, wanted state.

signal cash_changed(new_cash: int)
signal craving_changed(new_craving: float)
signal inventory_changed
signal wanted_changed(is_wanted: bool)
signal busted
signal day_changed(new_day: int)
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
var pending_spawn: String = ""
## True from the moment you're caught until you're booked into a cell. While
## it's set nothing can spot, chase, or bust you again -- without it, a
## shopkeeper who still saw your theft window could re-trigger the alarm and
## you'd be "busted" two or three times in one catch.
var in_custody: bool = false
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
	pending_spawn = ""
	cash_changed.emit(cash)
	craving_changed.emit(craving)
	inventory_changed.emit()
	day_changed.emit(day)
	strikes_changed.emit(strikes)
	wanted_changed.emit(wanted)

func max_strikes() -> int:
	return STRIKES_PER_RUN + MetaProgress.extra_strikes()

func _process(delta: float) -> void:
	run_time += delta
	if craving > 0.0:
		craving = max(0.0, craving - current_craving_decay() * delta)
		craving_changed.emit(craving)

## Tolerance builds day over day: withdrawal creeps in faster the longer
## you've been using, same as a real dependency.
func current_craving_decay() -> float:
	var base := CRAVING_DECAY_PER_SEC + (day - 1) * DECAY_INCREASE_PER_DAY
	# A long-acting dose holds you longer, so the meter falls more slowly.
	return base * MetaProgress.craving_decay_scale() / active_duration

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

func sleep() -> void:
	day += 1
	day_changed.emit(day)
	craving = min(craving, 55.0)
	craving_changed.emit(craving)
