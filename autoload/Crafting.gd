extends Node
## Scavenging and crafting, after Project Zomboid and The Long Dark: the
## block's trash bags and parked cars give up rags, scrap and tape (once a
## day each), and C turns them into what keeps you going -- a rag bandage, a
## bedroll for the cold, a shiv.
##
## Materials and what you make from them live in GameState.inventory like
## anything else; they're yours, not stolen (GameState.SCAVENGED).

const MATERIALS := ["rags", "scrap", "tape"]
const RECIPES := [
	{"id": "rag_bandage", "label": "Rag bandage", "needs": {"rags": 2},
		"text": "Tear the rags into strips and bind the cut. Stops the bleeding."},
	{"id": "bedroll", "label": "Bedroll", "needs": {"rags": 3, "tape": 1},
		"text": "Rags taped into a roll. Carried, the cold bites less; slept in outside, it keeps the worst off."},
	{"id": "shiv", "label": "Shiv", "needs": {"scrap": 1, "tape": 1},
		"text": "A strip of scrap with a taped grip. Something to hold when someone comes at you."},
]
## What a search turns up: [weight, result]. "food" is eaten on the spot.
const TRASH_FINDS := [[35, "rags"], [22, "scrap"], [13, "tape"], [18, "food"], [12, ""]]
const CAR_FINDS := [[25, "coins"], [20, "tape"], [20, "scrap"], [10, "rags"], [10, "alarm"], [15, ""]]
const FOUND_FOOD := 15.0
## Bedroll: how much of the cold it keeps off, carried and slept in.
const BEDROLL_COLD := 0.75
const BEDROLL_SLEEP := 0.5

var _told_craft := false

func count(id: String) -> int:
	return GameState.inventory.count(id)

func can_make(recipe: Dictionary) -> bool:
	for id in recipe["needs"]:
		if count(id) < recipe["needs"][id]:
			return false
	if recipe["id"] == "rag_bandage" and not Survival.bleeding:
		return false
	return true

## Uses up the parts and makes it. The bandage goes straight on.
func make(i: int) -> bool:
	var r: Dictionary = RECIPES[i]
	if not can_make(r):
		return false
	for id in r["needs"]:
		for k in r["needs"][id]:
			GameState.inventory.erase(id)
	if r["id"] == "rag_bandage":
		Survival.bandage()
	else:
		GameState.inventory.append(r["id"])
	GameState.inventory_changed.emit()
	SFX.play("steal", -8.0, 1.2)
	GameState.log_event("Made %s." % GameState.item_name_for(r["id"]))
	return true

func has_bedroll() -> bool:
	return GameState.inventory.has("bedroll")

func has_shiv() -> bool:
	return GameState.inventory.has("shiv")

## Searches a spot (once a day each). Returns what to say.
func search(spot: String, car := false) -> String:
	if not GameState.daily_available("scav_" + spot, true):
		return "You've already been through it today." if not car else "You've already tried this one today."
	var found := _roll(CAR_FINDS if car else TRASH_FINDS)
	match found:
		"":
			return ["Nothing worth taking.", "Wet paper and someone's bad day.", "Picked clean already."].pick_random()
		"food":
			Survival.eat(FOUND_FOOD)
			return ["Half a burger in a foil wrap. You eat it.", "A bruised apple and a pack of crackers. Dinner, sort of."].pick_random()
		"coins":
			var n := randi_range(1, 3)
			GameState.cash += n
			GameState.cash_changed.emit(GameState.cash)
			return "The door's unlocked. Coins in the cup holder: $%d." % n
		"alarm":
			SFX.play("car_horn", -2.0)
			return "You try the handle and the alarm goes off. You walk away fast, like it wasn't you."
	GameState.inventory.append(found)
	GameState.inventory_changed.emit()
	var line := "You come away with %s." % GameState.item_name_for(found)
	if not _told_craft:
		_told_craft = true
		line += " (C to craft.)"
	return line

func _roll(table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[0])
	var r := randi() % total
	for e in table:
		r -= int(e[0])
		if r < 0:
			return e[1]
	return ""
