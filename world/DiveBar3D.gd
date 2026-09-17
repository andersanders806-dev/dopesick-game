extends "res://world/WorldRoot3D.gd"

const PATRON_NAMES := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
# Kenney's male-c is a police officer, male-a is the player, male-d is the
# bartender, male-e the shopkeeper, male-f the pusher, male-b his lookout --
# so patrons draw from the rest, and nobody at a table is dressed as a cop.
const PATRON_MODELS := [
	"res://assets/kenney/characters/character-female-a.glb",
	"res://assets/kenney/characters/character-female-b.glb",
	"res://assets/kenney/characters/character-female-c.glb",
	"res://assets/kenney/characters/character-female-d.glb",
	"res://assets/kenney/characters/character-female-e.glb",
	"res://assets/kenney/characters/character-female-f.glb",
]

# Where a patron can be: the north bench of either booth (sitting, facing the
# room), at one of the high-tops, or leaning at the end of the pool table
# (standing). Three of these are picked at random each visit. `yaw` is the
# direction they face in degrees (0 = toward the camera / +Z).
const SEATS := [
	{"pos": Vector3(-6.75, 0.0, -1.62), "yaw": 0.0, "pose": "sit"},    # BoothA
	{"pos": Vector3(-6.75, 0.0, 1.18), "yaw": 0.0, "pose": "sit"},     # BoothB
	{"pos": Vector3(-2.7, 0.0, 0.25), "yaw": 0.0, "pose": "idle"},     # HighTopA
	{"pos": Vector3(-0.6, 0.0, 2.35), "yaw": 0.0, "pose": "idle"},     # HighTopB
	{"pos": Vector3(4.95, 0.0, 1.1), "yaw": -90.0, "pose": "idle"},    # PoolTable
]
## The Kenney sit pose puts the hips at the character's feet level, so seated
## patrons are raised onto the booth bench.
const SIT_HEIGHT := 0.32

@onready var patrons: Array = [$Patron1, $Patron2, $Patron3]

func _ready() -> void:
	_refresh_patrons()
	_seat_patrons()
	super._ready()
	_apply_patrons()

## Orders stick until delivered: whoever is in GameState.bar_patrons is still
## here, asking for the same thing, in the same seat. A patron you've already
## paid off has gone home, and a newcomer with a fresh order takes their seat.
func _refresh_patrons() -> void:
	var state: Array = GameState.bar_patrons
	for i in range(state.size()):
		if state[i]["fulfilled"]:
			state[i] = _new_patron(state[i]["seat"], state)
	while state.size() < patrons.size():
		state.append(_new_patron(-1, state))

## A newcomer whose name, body, seat, and order don't clash with anyone
## already in the bar. `seat` = -1 picks a free one.
func _new_patron(seat: int, current: Array) -> Dictionary:
	# Names, bodies, and orders avoid everyone in the list -- including the
	# patron who just left, so a newcomer can't look like the same person
	# still waiting. Only seats of people still here count as taken.
	var taken_names := current.map(func(p): return p["name"])
	var taken_models := current.map(func(p): return p["model"])
	var taken_items := current.map(func(p): return p["request_id"])
	var taken_seats := current.filter(func(p): return not p["fulfilled"]).map(func(p): return p["seat"])
	var name: String = PATRON_NAMES.filter(func(n): return n not in taken_names).pick_random()
	var model: String = PATRON_MODELS.filter(func(m): return m not in taken_models).pick_random()
	if seat < 0:
		seat = range(SEATS.size()).filter(func(s): return s not in taken_seats).pick_random()
	var order: Dictionary = GameState.REQUEST_POOL.filter(func(r): return r["id"] not in taken_items).pick_random()
	return {"name": name, "model": model, "seat": seat, "request_id": order["id"], "price": order["price"], "fulfilled": false}

## Seats come from the saved state, and are placed before the navmesh bake.
func _seat_patrons() -> void:
	for i in range(patrons.size()):
		var seat: Dictionary = SEATS[GameState.bar_patrons[i]["seat"]]
		var pos: Vector3 = seat["pos"]
		if seat["pose"] == "sit":
			pos.y = SIT_HEIGHT
		patrons[i].position = pos
		patrons[i].model_root.rotation_degrees.y = seat["yaw"]
		patrons[i].set_pose(seat["pose"])

func _apply_patrons() -> void:
	for i in range(patrons.size()):
		var entry: Dictionary = GameState.bar_patrons[i]
		patrons[i].npc_name = entry["name"]
		patrons[i].set_model(entry["model"])
		patrons[i].set_request(entry["request_id"], entry["price"])
		patrons[i].order_fulfilled.connect(func(): entry["fulfilled"] = true)
