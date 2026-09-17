extends Node

## Persists across scene changes: money, stolen goods, craving, wanted state.

signal cash_changed(new_cash: int)
signal craving_changed(new_craving: float)
signal inventory_changed
signal wanted_changed(is_wanted: bool)
signal busted
signal day_changed(new_day: int)

## Everything that can be stolen, which store stocks it, and what a patron
## will pay for it. Picked from lists of what gets shoplifted to fund a habit
## (small, valuable, easy to resell: the CRAVED hot-products research):
## locked-up razors and whitening strips from pharmacies, packaged steaks and
## detergent from supermarkets (little security, and detergent trades almost
## like cash), cigarettes and phone accessories from corner shops, spirits
## from liquor stores, and headphones and phones from electronics stores --
## worth the most, and guarded the hardest.
const REQUEST_POOL := [
	{"id": "cigs", "name": "a carton of cigarettes", "price": 15, "store": "convenience"},
	{"id": "charger", "name": "a phone charger", "price": 10, "store": "convenience"},
	{"id": "batteries", "name": "a pack of batteries", "price": 8, "store": "convenience"},
	{"id": "energy", "name": "a four-pack of energy drinks", "price": 8, "store": "convenience"},
	{"id": "sunglasses", "name": "a pair of sunglasses", "price": 12, "store": "convenience"},
	{"id": "razors", "name": "a pack of razor blades", "price": 18, "store": "pharmacy"},
	{"id": "whitening", "name": "a box of teeth whitening strips", "price": 22, "store": "pharmacy"},
	{"id": "coldmeds", "name": "a box of cold and allergy pills", "price": 12, "store": "pharmacy"},
	{"id": "formula", "name": "a tin of baby formula", "price": 25, "store": "pharmacy"},
	{"id": "makeup", "name": "a makeup palette", "price": 15, "store": "pharmacy"},
	{"id": "steak", "name": "a pack of steaks", "price": 20, "store": "supermarket"},
	{"id": "detergent", "name": "a big jug of laundry detergent", "price": 10, "store": "supermarket"},
	{"id": "cheese", "name": "a block of good cheese", "price": 9, "store": "supermarket"},
	{"id": "whiskey", "name": "a bottle of good whiskey", "price": 30, "store": "liquor"},
	{"id": "vodka", "name": "a bottle of vodka", "price": 20, "store": "liquor"},
	{"id": "cognac", "name": "a bottle of cognac", "price": 45, "store": "liquor"},
	{"id": "headphones", "name": "a pair of wireless headphones", "price": 40, "store": "electronics"},
	{"id": "videogame", "name": "a new video game", "price": 25, "store": "electronics"},
	{"id": "watch", "name": "a decent watch", "price": 40, "store": "electronics"},
	{"id": "smartphone", "name": "a smartphone", "price": 60, "store": "electronics"},
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
const FENCE_PRICE := 5

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

func _ready() -> void:
	_setup_input_actions()

func _process(delta: float) -> void:
	if craving > 0.0:
		craving = max(0.0, craving - current_craving_decay() * delta)
		craving_changed.emit(craving)

## Tolerance builds day over day: withdrawal creeps in faster the longer
## you've been using, same as a real dependency.
func current_craving_decay() -> float:
	return CRAVING_DECAY_PER_SEC + (day - 1) * DECAY_INCREASE_PER_DAY

## The pusher charges more each day too -- it takes more to get the same
## relief, so standing still gets more expensive.
func current_fix_cost() -> int:
	return FIX_COST_BASE + (day - 1) * FIX_COST_INCREASE_PER_DAY

func _setup_input_actions() -> void:
	_bind("interact", [KEY_E])
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

func sell_item(id: String, price: int) -> bool:
	if not inventory.has(id):
		return false
	inventory.erase(id)
	cash += price
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

## The fix itself, separate from paying: the 3D pusher takes your cash first
## and only hands it over after fetching it from his stash.
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
	var fine := int(cash * 0.5)
	cash -= fine
	inventory_changed.emit()
	cash_changed.emit(cash)
	set_wanted(false)
	busted.emit()

func sleep() -> void:
	day += 1
	day_changed.emit(day)
	craving = min(craving, 55.0)
	craving_changed.emit(craving)
