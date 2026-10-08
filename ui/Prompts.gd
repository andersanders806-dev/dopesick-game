extends RefCounted
## What pressing E / Square would do to a thing, in a few words, for the
## prompt over it ("Enter the Dive Bar", "Talk to Ray"). A thing can say
## for itself with prompt_text(); the rest are worked out from what they are.

const SceneLoader := preload("res://autoload/SceneLoader.gd")
## The plain "press E here" zones (Interactable3D), by node name.
## Checked in order, by how the name starts.
const ZONES := {
	"RentSlot": "Pay the rent", "AlleyHide": "Hide", "DumpsterHide": "Hide", "HideSpot": "Hide",
	"Dumpster": "Search the dumpster", "Mattress": "Lie down", "PoolZone": "Play pool",
	"DartsZone": "Play darts", "CellDoorKnock": "Knock on the door", "Bench": "Lie down",
	"Intercom": "Press the intercom", "KartDesk": "Talk at the desk", "PartsBox": "Search the parts box",
	"CounterZone": "Talk at the counter", "ServingCounter": "Get a meal", "Cot": "Sleep",
	"Noticeboard": "Read the noticeboard", "BottleMachine": "Return bottles",
	"Bottle": "Pick up the bottle", "FlyerSpot": "Put up a flyer", "DockAsk": "Ask about work",
	"DockTruck": "Unload the truck", "DockPallet": "Stack the box", "Victim": "Help them",
}
## Who's called by what they do, not a name: "Talk to the clerk".
const ROLES := ["Bartender", "Cashier", "Clerk", "Officer", "Security", "Shopkeeper", "Pharmacist",
	"Pawnbroker", "Volunteer", "Marshal", "Lookout", "Booking Officer", "Old Sailor", "Tired Woman",
	"Stranger", "Smoker", "Wiry Guy", "Quiet Kid"]

static func text_for(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("prompt_text"):
		return node.prompt_text()
	if node.has_meta("prompt"):
		return node.get_meta("prompt")
	var script: Script = node.get_script()
	var kind := script.resource_path.get_file().get_basename() if script else ""
	match kind:
		"Door3D":
			return _door(node.target_scene)
		"PoliceDoor3D":
			return "Police station"
		"Bed3D":
			return "Sleep"
		"WalkmanPickup3D":
			return "Pick up the walkman"
		"Belonging3D":
			if GameState.belongings.get(node.belonging_id, "") != "home":
				return ""
			return "Your " + ("TV" if node.belonging_id == "tv" else node.belonging_id)
		"StealableItem3D":
			if node.item_id.begins_with("tape:"):
				return "Steal the tape: %s" % Walkman.TAPES.get(node.item_id.trim_prefix("tape:"), {}).get("title", "a tape")
			return "Steal " + str(GameState.item_info(node.item_id).get("name", node.item_id))
		"Pedestrian3D":
			return "Ask for change"
		"Pusher3D":
			return "Talk to the pusher"
	if "npc_name" in node:
		return talk_to(str(node.npc_name))
	# The name it was given, before Godot had to make it unique.
	var name := String(node.get_meta("kind", node.name))
	for key in ZONES:
		if name.begins_with(key):
			return ZONES[key]
	return name.capitalize()

static func talk_to(who: String) -> String:
	if who == "Outreach":
		return "Talk to the outreach worker"
	if who == "Security":
		return "Talk to the security guard"
	return "Talk to " + ("the " + who.to_lower() if who in ROLES else who)

static func _door(target: String) -> String:
	var room := target.get_file().get_basename()
	match room:
		"City3D":
			return "Out to the street"
		"Apartment3D":
			return "Go home"
		"Backyard3D":
			return "Through the gate"
	var place: String = SceneLoader.NAMES.get(room, "")
	if place == "":
		return "Go in"
	return "Enter " + (place if not place.begins_with("The ") else "the " + place.substr(4))
