extends Node

## Persists across scene changes: money, stolen goods, craving, wanted state.

signal cash_changed(new_cash: int)
signal craving_changed(new_craving: float)
signal inventory_changed
signal wanted_changed(is_wanted: bool)
signal busted

const REQUEST_POOL := [
	{"id": "whiskey", "name": "a bottle of good whiskey", "price": 30},
	{"id": "cigs", "name": "a carton of cigarettes", "price": 15},
	{"id": "charger", "name": "a phone charger", "price": 10},
	{"id": "batteries", "name": "a pack of batteries", "price": 8},
	{"id": "watch", "name": "a decent watch", "price": 40},
]

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
	craving = 100.0
	craving_changed.emit(craving)
	return true

func set_wanted(value: bool) -> void:
	if wanted == value:
		return
	wanted = value
	wanted_changed.emit(wanted)

func get_busted() -> void:
	inventory.clear()
	var fine := int(cash * 0.5)
	cash -= fine
	inventory_changed.emit()
	cash_changed.emit(cash)
	set_wanted(false)
	busted.emit()

func sleep() -> void:
	day += 1
	craving = min(craving, 55.0)
	craving_changed.emit(craving)
