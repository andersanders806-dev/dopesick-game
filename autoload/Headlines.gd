extends Node
## Word on the block: one thing that's different about each day, rolled at
## the start of it and announced when you're up and about. It changes the
## plan without changing the rules -- the same stores, the same pusher, the
## same cops, pushed one way or another for a day.
##
## - Crackdown: more heat. Staff watch closer, the beat cop sees further and
##   comes back sooner, and the pusher charges a risk premium.
## - Delivery strike: the supermarket's shut and there's no truck out back.
## - Pool tournament: a tournament table at the Dive Bar with a real pot.
## - Storm: rain all day. Fewer people about, and bored, slower staff.
## - Payday: people have money. Orders pay more and the street's busier.
## - Dry spell: the pusher's short. Less to choose from, and it costs more.
## - Speedway Cup: the kart track opens early and the podium pays triple.
## - Track shut: the day after someone walks off with a carburetor.
## - Quiet: nothing in particular. Day one is always quiet.
##
## The state lives in GameState (headline, headline_day) so it saves with
## the run; this node rolls it, describes it, and answers what it changes.

signal headline_changed(id: String)

const EVENTS := {
	"quiet": {"weight": 4, "title": "A quiet one",
		"text": "Nothing much on the block today. Same faces, same corners."},
	"crackdown": {"weight": 2, "title": "Crackdown",
		"text": "Two more cruisers on the block since dawn. Staff are jumpy, the beat cop's looking hard, and the pusher's charging for the risk."},
	"strike": {"weight": 2, "title": "Delivery strike",
		"text": "The drivers walked out. The supermarket's got a sign on the door and there's no truck out back today."},
	"tournament": {"weight": 2, "title": "Pool tournament",
		"text": "Chalk on the Dive Bar window: EIGHT-BALL TOURNAMENT TONIGHT, $20 IN, $80 TO THE WINNER."},
	"storm": {"weight": 2, "title": "Storm",
		"text": "It's coming down sideways and it's not stopping. Hardly anyone's out, and the clerks are just watching the clock."},
	"payday": {"weight": 2, "title": "Payday",
		"text": "First of the month. People have money in their pockets, and the regulars are paying better for what they want."},
	"drought": {"weight": 2, "title": "Dry spell",
		"text": "Word is the pusher's re-up didn't come in. He's holding less, and he knows what that means for prices."},
	"kart_cup": {"weight": 1, "title": "Speedway Cup",
		"text": "Banners over the KARTS door: SPEEDWAY CUP TONIGHT. Open from noon, triple prize money for the podium."},
	"bad_batch": {"weight": 2, "title": "Bad batch",
		"text": "Something bad's going round. Two people went over on the next block last night. Outreach is handing out test strips."},
	# The day after someone dies in the alley (forced, like the track).
	"vigil": {"weight": 0, "title": "Vigil",
		"text": "Candles at the mouth of the alley, and a name in marker on the wall. The corner's quiet today."},
	"track_shut": {"weight": 0, "title": "Track shut",
		"text": "A hand-written sign on the KARTS door: CLOSED -- SOMEBODY STOLE A CARBURETOR. YOU KNOW WHO YOU ARE."},
}

## When it was last shown, so each day's headline is announced once.
var announced_day: int = -1
## Tests pin the day's event so it can't move prices and hours under them.
var forced: String = ""

func _ready() -> void:
	GameState.day_changed.connect(_on_day_changed)
	_on_day_changed(GameState.day)

func _on_day_changed(day: int) -> void:
	# A loaded save brings its own headline for the day; don't reroll it.
	if GameState.headline_day == day and GameState.headline != "":
		return
	roll(day)

func roll(day: int) -> void:
	var id := "quiet"
	if forced != "":
		id = forced
	elif GameState.sabotage_day == day:
		id = "track_shut"
	elif GameState.vigil_day == day:
		id = "vigil"
	elif day > 1:
		id = _weighted_pick()
	GameState.headline = id
	GameState.headline_day = day
	if id == "storm":
		GameState.set_raining(true)
	GameState.log_event("Word on the block: %s." % EVENTS[id]["title"].to_lower(), "new_day" if id == "quiet" else "")
	headline_changed.emit(id)

static func _weighted_pick() -> String:
	var total := 0
	for k in EVENTS:
		total += int(EVENTS[k]["weight"])
	var r := randi() % total
	for k in EVENTS:
		r -= int(EVENTS[k]["weight"])
		if r < 0:
			return k
	return "quiet"

func today() -> String:
	return GameState.headline if GameState.headline != "" else "quiet"

func is_today(id: String) -> bool:
	return today() == id

func title() -> String:
	return EVENTS[today()]["title"]

func text() -> String:
	return EVENTS[today()]["text"]

# --- What it changes ---------------------------------------------------------

## On every shop clerk's suspicion.
func alertness_mult() -> float:
	match today():
		"crackdown":
			return 1.25
		"storm":
			return 0.85
	return 1.0

## On every drug's price at the pusher.
func pusher_price_mult() -> float:
	match today():
		"crackdown":
			return 1.25
		"drought":
			return 1.5
		"vigil":
			return 0.9
	return 1.0

## How many kinds he's holding, [min, max].
func pusher_stock_range(normal: Vector2i) -> Vector2i:
	return Vector2i(6, 8) if is_today("drought") else normal

## On what a regular pays for an order.
func order_pay_mult() -> float:
	return 1.4 if is_today("payday") else 1.0

func pedestrian_mult() -> float:
	match today():
		"storm":
			return 0.4
		"payday":
			return 1.5
	return 1.0

## The beat cop: how much further he sees, and how soon he's back.
func patrol_vision_mult() -> float:
	return 1.35 if is_today("crackdown") else 1.0

func patrol_return_mult() -> float:
	return 0.4 if is_today("crackdown") else 1.0

## Places shut for the day whatever their hours say.
func closed_today(place: String) -> bool:
	match today():
		"strike":
			return place == "supermarket"
		"track_shut":
			return place == "karts"
	return false

## Opening hour override, or -1 for the usual.
func opens_early(place: String) -> int:
	return 12 if place == "karts" and is_today("kart_cup") else -1

func kart_prize_mult() -> int:
	return 3 if is_today("kart_cup") else 1

func delivery_today() -> bool:
	return not is_today("strike")

func rain_locked() -> bool:
	return is_today("storm")
