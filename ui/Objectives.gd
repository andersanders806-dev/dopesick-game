extends RefCounted
## What to do next, worked out from where things stand -- the one line under
## the "Carrying" panel (ui/HUD.gd). Worst first: the thing that'll end the
## run soonest wins. A new player always has an answer to "what now?".

const Darknet := preload("res://world/Darknet.gd")

static func current() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var sv: Node = tree.root.get_node_or_null("Survival") if tree else null
	if GameState.wanted:
		return "Lose the police -- get indoors, or hide in an alley"
	if sv and sv.enabled:
		if sv.bleeding:
			return "Stop the bleeding -- bandages (vending machine) or 2 rags (C)"
		if sv.health < 30.0:
			return "You're badly hurt -- eat, get warm and sleep to heal"
	if GameState.sickness() >= 0.5:
		return "You're dope sick -- the pusher's on the corner %02d:00-%02d:00, or Dana's program" % [GameState.PUSHER_HOURS[0], GameState.PUSHER_HOURS[1]]
	if sv and sv.enabled:
		if sv.warmth < sv.LOW and sv.outside():
			return "Get warm -- any building, or a fire out back"
		if sv.hunger < sv.LOW:
			return "Eat -- vending machine by your door; shelter meals 7-10 and 17-20"
		if sv.rest < sv.LOW:
			return "Sleep -- your bed at home, or a shelter cot at night"
	var st: Array = GameState.status_line()
	if not st.is_empty():
		return st[0]
	if Darknet.arrived() and GameState.parcel.get("fate", "") == "ok":
		return "Your order's in the mailbox by your door"
	if GameState.debt_overdue():
		return "The collector wants his $%d -- pay it or stay ahead of him" % GameState.debt
	if GameState.cash < GameState.RENT and GameState.day < GameState.rent_due_day + 1:
		return "Make rent ($%d by day %d) -- the bar regulars want things, or wash dishes" % [GameState.RENT, GameState.rent_due_day]
	return "Get through the day -- keep fed, warm, and ahead of the sickness"

## The very first run's walk-through, one toast at a time (HUD), never again
## once seen (MetaProgress.hints_seen).
const FIRST_STEPS := [
	["move", "WASD to walk, Shift to run. E uses whatever's in front of you."],
	["craving", "Top left: CRAVING. When it runs out you're dope sick -- shaking, slow, seeing things."],
	["body", "Under it: HEALTH, fed by FOOD, WARMTH and REST. Let them all run out and you die."],
	["keys", "J opens your notebook. C crafts from what you scavenge. Esc pauses."],
	["goal", "The line on the right always says what's most urgent. Start there."],
]
