extends Node
## Your own corner of the lot out back (world/Backyard3D.gd), after the
## camps of 7 Days to Die and Don't Starve: a fire barrel to warm up at, a
## lean-to over the old mattress, and a stash box nobody else knows about.
## Built from what you scavenge (autoload/Crafting.gd).
##
## - Fire barrel: lit with rags, it burns FIRE_HOURS; standing in the lot
##   while it burns warms you up instead of freezing you (Survival.tick).
## - Lean-to: sleeping on the mattress under it keeps most of the cold off
##   and halves the chance someone goes through your pockets.
## - Stash box: what's in it isn't on you -- a cot thief or a mugger can't
##   take it, and a bust can't either.

const BUILDS := [
	{"id": "fire", "label": "Fire barrel", "needs": {"scrap": 2},
		"text": "A rusted drum, holes punched round the bottom. Something to burn things in."},
	{"id": "leanto", "label": "Lean-to over the mattress", "needs": {"rags": 3, "tape": 1, "scrap": 1},
		"text": "A tarp of taped rags on scrap poles. It keeps the wind and the frost off."},
	{"id": "stash", "label": "Stash box", "needs": {"scrap": 2, "tape": 1},
		"text": "A box wedged behind the dumpster. What's in it isn't on you."},
]
const FIRE_HOURS := 4.0
const FIRE_WARM_PER_H := 25.0
const LEANTO_SLEEP := 0.3
const LEANTO_ROB := 0.5

var built: Dictionary = {}
var fire_until := -1.0
var stash: Array = []

signal changed

func reset() -> void:
	built = {}
	fire_until = -1.0
	stash = []
	changed.emit()

func has(id: String) -> bool:
	return built.get(id, false)

func can_build(i: int) -> bool:
	var b: Dictionary = BUILDS[i]
	if has(b["id"]):
		return false
	for id in b["needs"]:
		if GameState.inventory.count(id) < b["needs"][id]:
			return false
	return true

func build(i: int) -> bool:
	if not can_build(i):
		return false
	var b: Dictionary = BUILDS[i]
	for id in b["needs"]:
		for k in b["needs"][id]:
			GameState.inventory.erase(id)
	built[b["id"]] = true
	GameState.inventory_changed.emit()
	GameState.log_event("Built %s in the lot out back." % b["label"].to_lower())
	changed.emit()
	return true

func fire_lit() -> bool:
	return has("fire") and GameState.now_minutes() < fire_until

## Burns a rag for FIRE_HOURS of heat.
func light_fire() -> bool:
	if not has("fire") or not GameState.inventory.has("rags"):
		return false
	GameState.inventory.erase("rags")
	GameState.inventory_changed.emit()
	fire_until = maxf(fire_until, GameState.now_minutes()) + FIRE_HOURS * 60.0
	changed.emit()
	return true

## Moves one of `id` between your pockets and the box.
func put(id: String) -> bool:
	if not has("stash") or not GameState.inventory.has(id):
		return false
	GameState.inventory.erase(id)
	stash.append(id)
	GameState.inventory_changed.emit()
	changed.emit()
	return true

func take(id: String) -> bool:
	if not has("stash") or not stash.has(id):
		return false
	stash.erase(id)
	GameState.inventory.append(id)
	GameState.inventory_changed.emit()
	changed.emit()
	return true

## Are you at the camp right now (the backyard)?
func here() -> bool:
	var scene := get_tree().current_scene if is_inside_tree() else null
	return scene != null and scene.scene_file_path.ends_with("Backyard3D.tscn")
