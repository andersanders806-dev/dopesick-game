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
	# From the kart track's spares box (world/KartCenter3D.gd), not a shop
	# shelf: nobody at the bar orders one, but the pawnshop pays for it.
	{"id": "carburetor", "name": "a kart carburetor", "price": 60, "store": "karts", "no_order": true},
	# Your own things, from the apartment. Nobody orders them; the pawnshop
	# pays their full value and holds them for a while.
	{"id": "tv", "name": "your TV", "price": 24, "store": "home", "no_order": true},
	{"id": "radio", "name": "the old radio", "price": 8, "store": "home", "no_order": true},
	{"id": "guitar", "name": "your guitar", "price": 30, "store": "home", "no_order": true},
	{"id": "coat", "name": "your winter coat", "price": 10, "store": "home", "no_order": true},
	{"id": "ring", "name": "your mother's ring", "price": 45, "store": "home", "no_order": true},
]

const STORE_NAMES := {
	"convenience": "the corner shop",
	"pharmacy": "the pharmacy",
	"supermarket": "the supermarket",
	"liquor": "the liquor store",
	"electronics": "the electronics store",
	"karts": "the kart track",
	"home": "your apartment",
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
	# Floodlit evenings; the track runs late.
	"karts": [14, 24],
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
	"KartCenter3D": "karts",
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
## What's on board and still suppressing breathing (see Drugs.LOAD_HALF_LIFE).
var resp_load: float = 0.0
## The treatment program (Outreach3D): a clinic dose every day and nothing
## off the street; RECOVERY_DAYS of that in a row and you've got out -- the
## run's third ending, and the only good one.
const RECOVERY_DAYS := 5
var in_treatment: bool = false
var treatment_streak: int = 0
var clinic_today: bool = false
var used_today: bool = false
signal treatment_changed
## The run's story so far: what the notebook's notes page shows and what the
## run-end screen tells back. Each entry: day, clock, text, and a cutscene
## still to illustrate it (or "").
var diary: Array = []
signal diary_changed

func log_event(text: String, image := "") -> void:
	diary.append({"day": day, "clock": clock_text(), "text": text, "image": image})
	diary_changed.emit()
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

## Today's word on the block (autoload/Headlines.gd) and the day it's for.
var headline: String = ""
var headline_day: int = -1
## The day the kart track's shut because someone stole a carburetor.
var sabotage_day: int = -1

## How the Dive Bar regulars feel about you, by name: -5 (you're dead to
## them) to 5 (they'd go to bat for you). Delivering what they asked for
## raises it; selling the thing they wanted to someone else lowers it.
var rep: Dictionary = {}
const REP_MIN := -5
const REP_MAX := 5
## A regular who likes you tips you off about a store; one who's sore about
## you has a word with its clerk. store id -> [suspicion multiplier, last
## day it applies].
var store_heat: Dictionary = {}
signal rep_changed(name: String, value: int)

## Your own things: id -> "home", "carried", "pawned" or "gone". Selling
## them is the slow way down, and the apartment shows it.
const BELONGINGS := ["tv", "radio", "guitar", "coat", "ring"]
var belongings: Dictionary = {}
## Pawn tickets: belonging id -> the day it went over the counter.
var pawn_tickets: Dictionary = {}
const PAWN_HOLD_DAYS := 4
const BUYBACK_MARKUP := 1.5
## The "room echoes" line plays once a run.
var apartment_echo_seen: bool = false
signal belongings_changed

## Rent: about one good order a week, due by midnight on the due day.
## Missing it is a final notice and a late fee; missing that, the lock's
## changed until you pay everything plus the locksmith.
const RENT := 35
const RENT_PERIOD := 5
const RENT_LATE_FEE := 10
const LOCKSMITH_FEE := 20
const LANDLORD_HOURS := [8, 22]
var rent_due_day: int = RENT_PERIOD
## 0 paid up, 1 final notice, 2 locked out.
var rent_stage: int = 0
var rent_owed: int = 0
signal rent_changed

## The court date after a bust. Show up in the program and drug court takes
## a strike off; otherwise probation, a test at every check-in. Miss either
## and there's a warrant: the beat cop knows your face.
const COURT_HOURS := [9, 12]
const STATION_HOURS := [9, 17]
const PROBATION_CHECKINS := 3
## Opioids show up in a test for a day or more.
const DIRTY_WINDOW_MINUTES := 24 * 60
var court_day: int = -1
## Days still to check in on, earliest first.
var probation_days: Array = []
var warrant: bool = false
## An order off the laptop at home (world/Darknet.gd), until it's played out.
var parcel: Dictionary = {}
## Mia, Ray and Dana's week (autoload/Story.gd).
var story: Dictionary = {}
## now_minutes() of the last dose off the street.
var last_street_use: float = -99999.0
signal legal_changed

## Bad batch: on its day, a lot of what's sold as opioids is cut with
## something stronger. Test strips from outreach tell you; nothing else does.
const BAD_BATCH_CHANCE := 0.4
const CONTAMINATED_RISK := 3.0
var test_strips: int = 0
## The overdose risk of the last dose taken, for tests.
var last_risk: float = 0.0
## The day after someone dies in the alley, and who it was.
var vigil_day: int = -1
var vigil_for: String = ""

## The Dive Bar's regulars (DiveBar3D.PATRON_NAMES -- a test keeps the two
## lists the same). Some nights one of them goes over behind the dumpster.
const REGULARS := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
const OD_CHANCE := 0.25
## Real seconds they've got once they're down, counted only while you're
## on the block to see it.
const OD_WINDOW := 90.0
const OD_POCKETS := Vector2i(8, 20)
## The bar seats three and needs a fourth to swap in when one goes home, so
## the alley stops taking them at four.
const MIN_LIVING_REGULARS := 4
## {day, minute, who, state, left}; state "pending", "down", "saved" or
## "dead", or {} for a night when nobody goes over.
var od_event: Dictionary = {}
var dead_regulars: Array = []
## The day the day's events (the alley) were last rolled, so a loaded save
## keeps its night instead of rolling a new one.
var events_rolled_day: int = -1
signal overdose_changed

func _ready() -> void:
	_setup_input_actions()
	start_run()
	day_changed.connect(_on_new_day)
	# Headlines is an autoload after us; the day's events depend on its roll.
	(func(): get_node("/root/Headlines").headline_changed.connect(_on_headline_rolled)).call_deferred()

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
	resp_load = 0.0
	in_treatment = false
	treatment_streak = 0
	clinic_today = false
	used_today = false
	diary.clear()
	var jobs := get_node_or_null("/root/Jobs")
	if jobs:
		jobs.reset()
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
	headline = ""
	headline_day = -1
	sabotage_day = -1
	rep.clear()
	store_heat.clear()
	belongings.clear()
	for id in BELONGINGS:
		belongings[id] = "home"
	pawn_tickets.clear()
	apartment_echo_seen = false
	rent_due_day = RENT_PERIOD
	rent_stage = 0
	rent_owed = 0
	court_day = -1
	probation_days.clear()
	warrant = false
	parcel = {}
	story = {}
	last_street_use = -99999.0
	test_strips = 0
	last_risk = 0.0
	vigil_day = -1
	vigil_for = ""
	od_event = {}
	dead_regulars.clear()
	events_rolled_day = -1
	booster_day = -1
	booster_gone = false
	booster_store = ""
	booster_hit.clear()
	booster_team = ""
	booster_cut_pending = false
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
	resp_load *= pow(0.5, delta / Drugs.LOAD_HALF_LIFE)
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
	# Tolerance fades with time off; a skipped night or a stretch in a cell
	# is time off.
	var keep := pow(0.5, minutes / Drugs.TOLERANCE_HALF_LIFE_MINUTES)
	for k in tolerance:
		tolerance[k] = tolerance[k] * keep
	while clock >= MINUTES_PER_DAY:
		clock -= MINUTES_PER_DAY
		day += 1
		day_changed.emit(day)
	_emit_clock()

func _emit_clock() -> void:
	var minute := int(clock)
	if minute != _last_minute:
		_check_overdose_start()
		if _last_minute >= 0 and minute / 60 != _last_minute / 60:
			_roll_weather()
			_check_legal_deadlines()
			_booster_hour()
			preload("res://world/Darknet.gd").hourly()
			var st := get_node_or_null("/root/Story")
			if st:
				st.hourly()
		_last_minute = minute
		clock_changed.emit(minute)

## Game minutes since the run began: days and clock on one line, so a due
## time can span midnight.
func now_minutes() -> float:
	return (day - 1) * MINUTES_PER_DAY + clock

func _roll_weather() -> void:
	var hl := _headlines()
	if hl and hl.rain_locked():
		set_raining(true)
		return
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
	var hl := _headlines()
	if hl and hl.closed_today(place):
		return false
	var hours: Array = OPENING_HOURS.get(place, [0, 24])
	if hl and hl.opens_early(place) >= 0:
		hours = [hl.opens_early(place), hours[1]]
	return hours_contain(hours, hour())

func opening_hour(place: String) -> int:
	var hl := _headlines()
	if hl and hl.opens_early(place) >= 0:
		return hl.opens_early(place)
	return OPENING_HOURS.get(place, [0, 24])[0]

## Headlines is an autoload after this one, so it isn't there during our
## own _ready.
func _headlines() -> Node:
	return get_node_or_null("/root/Headlines")

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
	var base := 1.0
	if h >= 22.0 or h < 6.0:
		base = 0.75
	elif h >= 12.0 and h < 18.0:
		base = 1.15
	var hl := _headlines()
	return base * (hl.alertness_mult() if hl else 1.0)

## staff_alertness() for one store, with whatever a regular did about it:
## a tip-off makes its clerk easier, a word in his ear makes him harder.
func store_alertness(store_id: String) -> float:
	var a := staff_alertness()
	var heat: Array = store_heat.get(store_id, [])
	if heat.size() == 2 and day <= int(heat[1]):
		a *= float(heat[0])
	return a

func set_store_heat(store_id: String, mult: float, days: int) -> void:
	store_heat[store_id] = [mult, day + days - 1]

# --- The regulars ---------------------------------------------------------

func rep_of(who: String) -> int:
	return int(rep.get(who, 0))

func change_rep(who: String, by: int, why := "") -> void:
	var before := rep_of(who)
	var after := clampi(before + by, REP_MIN, REP_MAX)
	if after == before:
		return
	rep[who] = after
	rep_changed.emit(who, after)
	if why != "":
		log_event(why)

## One word for how a regular feels about you, for the notebook.
static func rep_word(value: int) -> String:
	if value >= 4:
		return "would go to bat for you"
	if value >= 2:
		return "friendly"
	if value >= 0:
		return "neutral" if value == 0 else "warming up"
	if value >= -2:
		return "cold"
	return "won't deal with you"

## What a regular pays for an order today: payday, plus a bit extra from
## the ones who like you.
func order_price(who: String, base_price: int) -> int:
	var hl := _headlines()
	var mult: float = hl.order_pay_mult() if hl else 1.0
	return int(round(base_price * mult)) + 3 * maxi(0, rep_of(who))

## You sold `id` somewhere other than to the regular who asked for it.
## Word gets around.
func _sold_out_from_under(id: String) -> void:
	for p in bar_patrons:
		if not p.get("fulfilled", false) and p.get("request_id", "") == id:
			var was := rep_of(p["name"])
			change_rep(p["name"], -1, "%s heard you sold %s to someone else." % [p["name"], item_name_for(id)])
			# Crossing into a grudge: they have a word with the clerk at the
			# store you'd steal their kind of thing from.
			if was > -2 and rep_of(p["name"]) <= -2:
				var store: String = item_info(id).get("store", "")
				set_store_heat(store, 1.3, 2)
				log_event("%s had a word with the clerk at %s." % [p["name"], STORE_NAMES.get(store, "the store")])

# --- Your own things ------------------------------------------------------

func is_belonging(id: String) -> bool:
	return item_info(id).get("store", "") == "home"

## What you're carrying that you shouldn't be. Your own TV isn't evidence,
## and nobody on the street looks twice at a man with a guitar.
func stolen_goods() -> Array:
	return inventory.filter(func(id): return not is_belonging(id))

func carrying_stolen() -> bool:
	return not stolen_goods().is_empty()

func belongings_away() -> int:
	return BELONGINGS.filter(func(id): return belongings.get(id, "home") != "home").size()

func take_belonging(id: String) -> void:
	if belongings.get(id, "") != "home":
		return
	belongings[id] = "carried"
	inventory.append(id)
	inventory_changed.emit()
	belongings_changed.emit()
	log_event("Took %s to sell." % item_name_for(id))

## Back through the apartment door with something you'd taken: it goes
## back where it lives. Returns what was put back.
func return_belongings_home() -> Array:
	var back := []
	for id in BELONGINGS:
		if belongings.get(id, "") == "carried" and inventory.has(id):
			inventory.erase(id)
			belongings[id] = "home"
			back.append(id)
	if not back.is_empty():
		inventory_changed.emit()
		belongings_changed.emit()
	return back

## Anything "carried" that isn't in your pockets any more went some other
## way -- a shelter cot, a gift to Ray -- and isn't coming back.
func _reconcile_belongings() -> void:
	var changed := false
	for id in BELONGINGS:
		if belongings.get(id, "") == "carried" and not inventory.has(id):
			belongings[id] = "gone"
			changed = true
	if changed:
		belongings_changed.emit()
		_note_nothing_left()

func pawn_belonging(id: String) -> void:
	belongings[id] = "pawned"
	pawn_tickets[id] = day
	belongings_changed.emit()
	log_event("Pawned %s. The ticket holds till day %d." % [item_name_for(id), ticket_last_day(id)])
	_note_nothing_left()

func buyback_price(id: String) -> int:
	return int(ceil(float(item_info(id).get("price", 0)) * BUYBACK_MARKUP))

func ticket_last_day(id: String) -> int:
	return int(pawn_tickets.get(id, day)) + PAWN_HOLD_DAYS

func buy_back(id: String) -> bool:
	if not pawn_tickets.has(id) or not spend_cash(buyback_price(id)):
		return false
	pawn_tickets.erase(id)
	belongings[id] = "carried"
	inventory.append(id)
	inventory_changed.emit()
	belongings_changed.emit()
	log_event("Bought back %s." % item_name_for(id))
	return true

## Once a day, when the date turns over (sleeping, or staying up).
func _on_new_day(_d: int) -> void:
	# Last night's: still down when the night ran out, nobody came.
	if od_event.get("state", "") == "down" and int(od_event.get("day", day)) < day:
		resolve_overdose("walk")
	for id in pawn_tickets.keys():
		if day > ticket_last_day(id):
			pawn_tickets.erase(id)
			belongings[id] = "gone"
			log_event("The pawnshop sold %s. It's gone." % item_name_for(id))
			belongings_changed.emit()
	_reconcile_belongings()
	_roll_rent()
	if rent_stage == 0 and day == rent_due_day:
		Graphics._show_toast("Rent's due tonight: $%d." % RENT)

# --- Rent -----------------------------------------------------------------

func rent_amount() -> int:
	return RENT if rent_stage == 0 else rent_owed

## Only this period's rent: no paying next week's early.
func rent_payable() -> bool:
	return rent_stage > 0 or day > rent_due_day - RENT_PERIOD

func locked_out() -> bool:
	return rent_stage == 2

func pay_rent() -> bool:
	if not rent_payable() or not spend_cash(rent_amount()):
		return false
	rent_due_day = rent_due_day + RENT_PERIOD if rent_stage == 0 else day + RENT_PERIOD
	if rent_stage == 2:
		log_event("Paid the landlord everything. New lock, new key.")
	else:
		log_event("Paid the rent. Next due day %d." % rent_due_day)
	rent_stage = 0
	rent_owed = 0
	rent_changed.emit()
	return true

## The most pressing thing hanging over you, for the HUD: [text, urgent],
## or [] when there's nothing.
func status_line() -> Array:
	if warrant:
		return ["WARRANT", true]
	if day == court_day:
		return ["Court 09-12 today, police station", true]
	if not probation_days.is_empty() and int(probation_days[0]) == day:
		return ["Check in at the station by 17:00", true]
	if rent_stage == 2:
		return ["Locked out: $%d to the landlord" % rent_owed, true]
	if rent_stage == 1:
		return ["Final notice: $%d rent by midnight" % rent_owed, true]
	if day == rent_due_day:
		return ["Rent $%d due tonight" % RENT, false]
	return []

# --- Bad batch ------------------------------------------------------------

func roll_contaminated(drug_id: String) -> bool:
	var hl := _headlines()
	return hl != null and hl.is_today("bad_batch") and Drugs.info(drug_id).get("class", "") == Drugs.OPIOID and randf() < BAD_BATCH_CHANCE

## What a strip tells you about what you were handed.
func strip_reading(asked: String, got: String, contaminated: bool) -> String:
	if got == "fentanyl" and asked != "fentanyl":
		return "One line. Fentanyl. Whatever he called it, that's what it is."
	if contaminated:
		return "The strip lights up. It's cut with something, and it's strong."
	return "Two clean lines. It shows nothing it shouldn't."

# --- The alley ------------------------------------------------------------

## Today's word on the block is in: roll what else today holds. Once a day,
## so a loaded save (which doesn't reroll its headline) keeps its night.
func _on_headline_rolled(_id: String) -> void:
	if events_rolled_day == day:
		return
	events_rolled_day = day
	_roll_overdose()
	# After the alley: it reads vigil_day.
	_roll_booster()

func living_regulars() -> Array:
	return REGULARS.filter(func(n): return n not in dead_regulars)

func _roll_overdose() -> void:
	od_event = {}
	var alive := living_regulars()
	var hl := _headlines()
	var chance := 1.0 if hl and hl.is_today("bad_batch") else OD_CHANCE
	if day <= 1 or alive.size() <= MIN_LIVING_REGULARS or randf() >= chance:
		return
	od_event = {"day": day, "minute": randi_range(18 * 60, 23 * 60 + 30), "who": alive.pick_random(), "state": "pending", "left": OD_WINDOW}

## The time came: they're down, wherever you are.
func _check_overdose_start() -> void:
	if od_event.get("state", "") == "pending" and day == int(od_event["day"]) and clock >= float(od_event["minute"]):
		od_event["state"] = "down"
		log_event("Someone went down in the alley by the dumpster.")
		overdose_changed.emit()

## "naloxone", "payphone", "pockets" or "walk". Returns "saved" or "dead".
func resolve_overdose(choice: String) -> String:
	if od_event.get("state", "") != "down":
		return ""
	var who: String = od_event["who"]
	var outcome := "saved"
	match choice:
		"naloxone":
			naloxone -= 1
			inventory_changed.emit()
			change_rep(who, 3)
			log_event("Found %s in the alley, not breathing. The naloxone brought them back." % who)
		"payphone":
			change_rep(who, 2)
			log_event("Ran for the payphone. The ambulance got to %s in time." % who)
		"pockets":
			var took := randi_range(OD_POCKETS.x, OD_POCKETS.y)
			cash += took
			cash_changed.emit(cash)
			od_event["took"] = took
			outcome = "dead"
			_regular_died(who, true)
		_:
			if randf() < 1.0 / 3.0:
				log_event("Somebody else called it in for %s." % who)
			else:
				outcome = "dead"
				_regular_died(who, false)
	od_event["state"] = outcome
	# Ray's night (autoload/Story.gd): remembered past the night's own record.
	if who == "Ray" and outcome == "saved":
		story["ray"] = "saved"
	overdose_changed.emit()
	return outcome

func _regular_died(who: String, robbed: bool) -> void:
	dead_regulars.append(who)
	# The day after the night it happened -- which is today, if the night
	# ran out while they were still down.
	vigil_day = int(od_event.get("day", day)) + 1
	vigil_for = who
	log_event("%s died in the alley." % who, "overdose_floor")
	if robbed and randf() < 0.5:
		for n in living_regulars():
			change_rep(n, -2)
		log_event("Somebody saw you go through their pockets.")

# --- Tasha -----------------------------------------------------------------

## A rival booster, out some days, hitting the same stores you do: each
## hour she works one, and when she's done its staff are on edge for the
## day. Team up and she works a clerk for you, for a cut; rat her out and
## she's gone, and so is your standing on the street.
const BOOSTER_CHANCE := 0.4
const BOOSTER_HOURS := [10, 20]
const BOOSTER_STORES := ["pharmacy", "convenience", "liquor", "supermarket", "electronics"]
var booster_day: int = -1
var booster_gone: bool = false
## The store she's casing this hour, and the ones she's done today.
var booster_store: String = ""
var booster_hit: Array = []
## The store she's working for you today, or "".
var booster_team: String = ""
var booster_cut_pending: bool = false
signal booster_changed

func _roll_booster() -> void:
	booster_day = -1
	booster_hit.clear()
	booster_store = ""
	booster_team = ""
	if booster_gone or day <= 1 or day == vigil_day or randf() >= BOOSTER_CHANCE:
		return
	booster_day = day

func booster_present() -> bool:
	return not booster_gone and booster_day == day and hours_contain(BOOSTER_HOURS, hour())

## On the hour: the store she was casing is hit, and she moves on. Runs
## whether you're on the block or not.
func _booster_hour() -> void:
	if booster_team != "" or booster_gone or booster_day != day:
		return
	if booster_store != "":
		booster_hit.append(booster_store)
		set_store_heat(booster_store, 1.3, 1)
		Graphics._show_toast("Someone just hit %s. Staff will be jumpy." % STORE_NAMES[booster_store])
		log_event("Tasha hit %s." % STORE_NAMES[booster_store])
	booster_store = ""
	if booster_present():
		var left: Array = BOOSTER_STORES.filter(func(s): return s not in booster_hit)
		booster_store = left.pick_random() if not left.is_empty() else ""
	booster_changed.emit()

func booster_team_up(store: String) -> void:
	booster_team = store
	booster_store = store
	set_store_heat(store, 0.6, 1)
	booster_cut_pending = true
	log_event("Teamed up with Tasha on %s. She gets half the next order." % STORE_NAMES[store])
	booster_changed.emit()

func booster_rat() -> void:
	booster_gone = true
	for s in booster_hit:
		store_heat.erase(s)
	booster_store = ""
	if warrant:
		warrant = false
		legal_changed.emit()
	homeless_trust = 0
	for n in living_regulars():
		change_rep(n, -1)
	log_event("Gave Tasha up to the beat cop. The street will remember.")
	booster_changed.emit()

# --- Court ----------------------------------------------------------------

func _schedule_court() -> void:
	court_day = day + 2
	probation_days.clear()
	warrant = false
	legal_changed.emit()

func in_court_hours() -> bool:
	return day == court_day and hours_contain(COURT_HOURS, hour())

func tested_dirty() -> bool:
	return now_minutes() - last_street_use < DIRTY_WINDOW_MINUTES

## Returns "diverted", "probation", or "" if court isn't sitting for you now.
func appear_in_court() -> String:
	if not in_court_hours():
		return ""
	court_day = -1
	var outcome := "probation"
	if in_treatment:
		outcome = "diverted"
		strikes = maxi(0, strikes - 1)
		strikes_changed.emit(strikes)
		log_event("Drug court. The judge saw the program card and struck one off.")
	else:
		probation_days.clear()
		for i in PROBATION_CHECKINS:
			probation_days.append(day + 1 + i)
		log_event("Court. Three days' probation: check in at the station, clean every time.")
	legal_changed.emit()
	return outcome

## Returns "passed", "failed", or "" if today's check-in isn't open.
func probation_check_in() -> String:
	if probation_days.is_empty() or int(probation_days[0]) != day or not hours_contain(STATION_HOURS, hour()):
		return ""
	if tested_dirty():
		probation_days.clear()
		log_event("Failed the probation test.")
		get_busted()
		return "failed"
	probation_days.pop_front()
	log_event("Checked in clean. %d to go." % probation_days.size())
	legal_changed.emit()
	return "passed"

func turn_self_in() -> void:
	log_event("Turned yourself in on the warrant.")
	_schedule_court()
	# Walking in ends the chase too, or the cop on your heels follows you
	# into the cell and busts you there -- a strike for turning yourself in.
	set_wanted(false)

func _issue_warrant(why: String) -> void:
	warrant = true
	log_event(why + " There's a warrant out.")
	legal_changed.emit()

## Hourly: a court date or a check-in that came and went.
func _check_legal_deadlines() -> void:
	if court_day > 0 and (day > court_day or (day == court_day and hour() >= COURT_HOURS[1])):
		court_day = -1
		_issue_warrant("Missed court.")
	if not probation_days.is_empty():
		var due := int(probation_days[0])
		if day > due or (day == due and hour() >= STATION_HOURS[1]):
			probation_days.clear()
			_issue_warrant("Missed a probation check-in.")

## One step a day at most, however many days pass at once.
func _roll_rent() -> void:
	if rent_stage == 0 and day > rent_due_day:
		rent_stage = 1
		rent_owed = RENT + RENT_LATE_FEE
		rent_due_day = day
		log_event("A final notice on the door: $%d by midnight." % rent_owed)
	elif rent_stage == 1 and day > rent_due_day:
		rent_stage = 2
		rent_owed += LOCKSMITH_FEE
		log_event("Locked out. The landlord changed the lock.")
	else:
		return
	rent_changed.emit()

func _note_nothing_left() -> void:
	if belongings_away() == BELONGINGS.size() and BELONGINGS.all(func(id): return belongings[id] != "carried"):
		log_event("Nothing left to sell.")

func _setup_input_actions() -> void:
	_bind("interact", [KEY_E])
	_bind("sprint", [KEY_SHIFT])
	_bind("cancel_ui", [KEY_ESCAPE])
	_bind("pause", [KEY_ESCAPE])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("aim_left", [KEY_LEFT])
	_bind("aim_right", [KEY_RIGHT])
	_bind("aim_up", [KEY_UP])
	_bind("aim_down", [KEY_DOWN])
	_bind("look_left", [])
	_bind("look_right", [])
	_bind("look_up", [])
	_bind("look_down", [])
	_bind("fire", [KEY_SPACE])
	_bind("steady", [KEY_SHIFT])
	_bind("drift", [KEY_SPACE, KEY_SHIFT])
	_bind("throttle", [])
	_bind("brake", [])
	_bind("notebook", [KEY_J])
	_bind("walkman", [KEY_T])
	_bind("walkman_next", [KEY_N])
	_bind("page_next", [KEY_TAB, KEY_RIGHT])
	_bind("page_prev", [KEY_LEFT])
	_setup_pad()

func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)

# --- The pad ---------------------------------------------------------------

## A PS5 pad laid out like Call of Duty's default: left stick moves, right
## stick is the camera, L3 sprints, square is use, circle backs out, options
## pauses, R2 fires (throws a dart, strikes the cue ball, the kart's gas),
## L2 steadies your aim (and brakes), and the touchpad is the notebook --
## COD's map. Triangle (COD's weapon swap) opens the tapes and the d-pad
## skips one, so the d-pad doesn't walk you anywhere, as in COD.
##
## Every binding is on device -1, any pad: on Linux a DualSense often isn't
## joypad 0 (its motion sensors and touchpad can enumerate first), and the
## project's own bindings were for pad 0 only.
const PAD_DEADZONE := 0.2
const PAD := {
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"move_up": [[JOY_AXIS_LEFT_Y, -1.0]],
	"move_down": [[JOY_AXIS_LEFT_Y, 1.0]],
	"aim_left": [[JOY_AXIS_LEFT_X, -1.0], JOY_BUTTON_DPAD_LEFT],
	"aim_right": [[JOY_AXIS_LEFT_X, 1.0], JOY_BUTTON_DPAD_RIGHT],
	"aim_up": [[JOY_AXIS_LEFT_Y, -1.0], JOY_BUTTON_DPAD_UP],
	"aim_down": [[JOY_AXIS_LEFT_Y, 1.0], JOY_BUTTON_DPAD_DOWN],
	"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"interact": [JOY_BUTTON_X, JOY_BUTTON_A],
	"sprint": [JOY_BUTTON_LEFT_STICK],
	"cancel_ui": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
	"fire": [[JOY_AXIS_TRIGGER_RIGHT, 1.0], JOY_BUTTON_A],
	"steady": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"drift": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_X],
	"throttle": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"brake": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"notebook": [JOY_BUTTON_TOUCHPAD, JOY_BUTTON_BACK],
	"walkman": [JOY_BUTTON_Y],
	"walkman_next": [JOY_BUTTON_DPAD_RIGHT],
	"page_next": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_RIGHT],
	"page_prev": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_LEFT],
	"ui_up": [[JOY_AXIS_LEFT_Y, -1.0], JOY_BUTTON_DPAD_UP],
	"ui_down": [[JOY_AXIS_LEFT_Y, 1.0], JOY_BUTTON_DPAD_DOWN],
	"ui_left": [[JOY_AXIS_LEFT_X, -1.0], JOY_BUTTON_DPAD_LEFT],
	"ui_right": [[JOY_AXIS_LEFT_X, 1.0], JOY_BUTTON_DPAD_RIGHT],
	"ui_accept": [JOY_BUTTON_A, JOY_BUTTON_X],
	"ui_cancel": [JOY_BUTTON_B],
}
## The last thing touched was the pad, so hints name its buttons.
var using_pad: bool = false
signal input_device_changed(pad: bool)

func _setup_pad() -> void:
	for action in PAD:
		# Replace the pad-0 bindings from project.godot rather than add to them.
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)
		if not action.begins_with("ui_"):
			InputMap.action_set_deadzone(action, PAD_DEADZONE)
		for b in PAD[action]:
			var ev: InputEvent
			if b is Array:
				ev = InputEventJoypadMotion.new()
				ev.axis = b[0]
				ev.axis_value = b[1]
			else:
				ev = InputEventJoypadButton.new()
				ev.button_index = b
			ev.device = -1
			InputMap.action_add_event(action, ev)

func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != using_pad:
		using_pad = pad
		input_device_changed.emit(pad)

## What to call a control in a hint: the key, or the pad button.
func control_name(action: String) -> String:
	if using_pad:
		return PAD_NAMES.get(action, action)
	return KEY_NAMES.get(action, action)

const PAD_NAMES := {"interact": "Square", "cancel_ui": "Circle", "pause": "Options", "fire": "R2",
	"steady": "L2", "sprint": "L3", "notebook": "Touchpad", "walkman": "Triangle",
	"walkman_next": "D-pad right", "page": "L1/R1", "aim": "Left stick", "look": "Right stick",
	"drift": "R1", "throttle": "R2", "brake": "L2", "steer": "Left stick", "accept": "Cross"}
const KEY_NAMES := {"interact": "E", "cancel_ui": "Esc", "pause": "Esc", "fire": "Space",
	"steady": "Shift", "sprint": "Shift", "notebook": "J", "walkman": "T", "walkman_next": "N",
	"page": "Tab/arrows", "aim": "Mouse", "look": "Wheel", "drift": "Shift/Space", "throttle": "W",
	"brake": "S", "steer": "A/D", "accept": "E/Enter"}

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
	if booster_cut_pending:
		paid = paid / 2
		booster_cut_pending = false
		log_event("Tasha took her half.")
	cash += paid
	cash_earned += paid
	inventory_changed.emit()
	cash_changed.emit(cash)
	return true

func fence_everything() -> int:
	var goods := stolen_goods()
	var count := goods.size()
	if count == 0:
		return 0
	for id in goods:
		_sold_out_from_under(id)
		inventory.erase(id)
	var earned := count * FENCE_PRICE
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
	var hl := _headlines()
	var mult: float = hl.pusher_price_mult() if hl else 1.0
	return int(round(Drugs.price_for(drug_id, tolerance_for(drug_id)) * mult))

## The fix itself, separate from paying: the 3D pusher takes your cash first
## and only hands it over after fetching it from his stash. `drug_id` is what
## you *asked* for; what you actually got was decided at purchase.
##
## Returns the outcome: "relief", "precipitated", "overdose" or "saved".
## `dose_scale` is how much of it you take (a little at a time is 0.5: half
## the relief, half the risk); `risk_mult` is what it's cut with.
func take_drug(drug_id: String, dose_scale := 1.0, risk_mult := 1.0) -> String:
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
	if drug_class != Drugs.TREATMENT and drug_class != Drugs.CANNABIS:
		used_today = true
		last_street_use = now_minutes()
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
	var risk: float = float(d["od_risk"]) * risk_mult * dose_scale
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
	var tol_factor := clampf(1.0 - tolerance_for(drug_id) * Drugs.TOLERANCE_GUARD, Drugs.TOLERANCE_GUARD_FLOOR, 1.0)
	risk *= tol_factor
	# Stacking: the dose lands on top of whatever's still working.
	if drug_class == Drugs.OPIOID or drug_class == Drugs.BENZO:
		risk *= 1.0 + Drugs.LOAD_STACK * resp_load * resp_load
		resp_load += (float(d["od_risk"]) / 0.006) * maxf(tol_factor, Drugs.LOAD_TOLERANCE_FLOOR) * dose_scale

	last_dose_at[drug_class] = run_time
	tolerance[drug_class] = max(0.0, tolerance_for(drug_id) + float(d["tolerance"]) * dose_scale)

	last_risk = risk
	if randf() < risk:
		return _overdose()

	craving = min(100.0, craving + float(d["relief"]) * dose_scale)
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
		log_event("Went over. The naloxone brought you back.", "overdose_lights")
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
	# Everything stolen is evidence; your own things you keep.
	inventory.assign(inventory.filter(func(id): return is_belonging(id)))
	# A fine, not ruin: you still walk out with most of your cash.
	var fine := int(cash * BUST_FINE_FRACTION * MetaProgress.bust_fine_scale())
	cash -= fine
	strikes += 1
	log_event("Picked up by the police. Strike %d." % strikes, "busted_cuffs")
	# A bust settles any warrant and puts you in front of a judge.
	_schedule_court()
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
	match cause:
		"overdose": log_event("Went over, alone. Nobody had naloxone.", "overdose_floor")
		"recovered": log_event("Five clean days. Got out.", "recovered_street")
		"alone": log_event("Nobody left.", "relapse")
		_: log_event("Sent away.", "sent_away_bus")
	var days_survived := day
	# Getting out is worth more than anything else a run can do.
	var earned := MetaProgress.award_for_run(days_survived + (15 if cause == "recovered" else 0), orders_delivered, cash_earned)
	run_ended.emit({
		"days": days_survived,
		"orders": orders_delivered,
		"cash": cash_earned,
		"know_how": earned,
		"strikes": strikes,
		"doses": doses_taken,
		"cause": cause,
	})

## Called at bedtime: did today count?
func _tally_treatment_day() -> void:
	if in_treatment:
		if clinic_today and not used_today:
			treatment_streak += 1
			log_event("A clean day. %d of %d." % [treatment_streak, RECOVERY_DAYS])
		else:
			treatment_streak = 0
			log_event("The day didn't count. Back to zero -- still in the program.")
		treatment_changed.emit()
	clinic_today = false
	used_today = false

## The clinic dose from the outreach worker: enrolls you on the first one.
func clinic_dose() -> void:
	if not in_treatment:
		log_event("Signed up for the program at the shelter.", "recovered_clinic")
	in_treatment = true
	clinic_today = true
	treatment_changed.emit()

func recovered() -> bool:
	return in_treatment and treatment_streak >= RECOVERY_DAYS

## You sleep until morning. Slept before midnight, that's the next day;
## after midnight the day has already turned over.
func sleep() -> void:
	# The hours asleep count as time off, for tolerance and what's on board.
	var slept := fposmod(WAKE_MINUTE - clock, float(MINUTES_PER_DAY))
	var keep := pow(0.5, slept / Drugs.TOLERANCE_HALF_LIFE_MINUTES)
	for k in tolerance:
		tolerance[k] = tolerance[k] * keep
	resp_load = 0.0
	_tally_treatment_day()
	if clock >= WAKE_MINUTE:
		day += 1
		day_changed.emit(day)
	clock = WAKE_MINUTE
	_emit_clock()
	log_event("Woke up. Day %d." % day, "new_day")
	craving = min(craving, 55.0)
	craving_changed.emit(craving)
