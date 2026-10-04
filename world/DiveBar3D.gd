extends "res://world/WorldRoot3D.gd"

const PATRON_NAMES := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
## A regular's body now comes from their name (npc/CharacterCast.gd's
## PATRONS), not from a shuffled pool. Previously the body was dealt out at
## random per visit, so Big Eddie could walk back in as a different person --
## and, because the pool was all female models, four of the six male-named
## regulars were wearing the wrong body anyway.

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
## The Quaternius sitting clip already sits the character on an imaginary
## chair -- feet flat on the floor, hips at seat height -- with the model
## origin still on the floor, so a seated patron needs no vertical offset.
## Kenney's old sit clip instead put the hips at floor level, which is why
## this used to raise patrons 0.32 m onto the bench; keeping that offset with
## the new bodies left them hovering above the seat.
const SIT_HEIGHT := 0.0

@onready var patrons: Array = [$Patron1, $Patron2, $Patron3]

func _ready() -> void:
	_refresh_patrons()
	_seat_patrons()
	super._ready()
	_connect_pool()
	_add_darts()
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
	var taken_items := current.map(func(p): return p["request_id"])
	var taken_seats := current.filter(func(p): return not p["fulfilled"]).map(func(p): return p["seat"])
	var name: String = PATRON_NAMES.filter(func(n): return n not in taken_names).pick_random()
	if seat < 0:
		seat = range(SEATS.size()).filter(func(s): return s not in taken_seats).pick_random()
	var order: Dictionary = GameState.REQUEST_POOL.filter(func(r): return r["id"] not in taken_items and not r.get("no_order", false)).pick_random()
	# "model" is kept in the saved entry for compatibility with runs saved
	# before looks were tied to names; nothing reads it any more.
	return {"name": name, "model": "", "seat": seat, "request_id": order["id"], "price": order["price"], "fulfilled": false}

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
		patrons[i].role = entry["name"]
		patrons[i].set_model("")
		# What they pay today: payday, and a bit extra if they like you.
		patrons[i].set_request(entry["request_id"], GameState.order_price(entry["name"], entry["price"]))
		patrons[i].order_fulfilled.connect(func():
			entry["fulfilled"] = true
			GameState.orders_delivered += 1
			GameState.log_event("Brought %s what they asked for: %s." % [entry["name"], GameState.item_name_for(entry["request_id"])])
			GameState.change_rep(entry["name"], 1))

# --- Pool for money -----------------------------------------------------

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const PoolGame := preload("res://ui/PoolGame.gd")
## Stake -> who takes you on. The more you put up, the better the player
## who wants a piece of it.
const POOL_TABLES := [
	{"bet": 5, "name": "Old Sailor", "skill": 0.25, "line": "The Old Sailor squints at the rack. \"Five bucks. I'll go easy on ya.\""},
	{"bet": 10, "name": "Big Eddie", "skill": 0.45, "line": "Big Eddie chalks up. \"Ten. And no crying when you lose.\""},
	{"bet": 20, "name": "Wiry Guy", "skill": 0.62, "line": "Wiry Guy's already racking. \"Twenty. Let's go let's go.\""},
	{"bet": 50, "name": "The Shark", "skill": 0.85, "line": "A guy in a pressed jacket nobody's seen before unscrews his own cue. \"Fifty.\""},
]

# --- Darts for money ------------------------------------------------------

const DartsGame := preload("res://ui/DartsGame.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")
const DART_TABLES := [
	{"bet": 5, "name": "Tired Woman", "skill": 0.2, "line": "The Tired Woman pulls three darts out of the board. \"Five. Don't expect much.\""},
	{"bet": 10, "name": "Quiet Kid", "skill": 0.45, "line": "The Quiet Kid nods at the board and doesn't say anything."},
	{"bet": 20, "name": "Old Sailor", "skill": 0.75, "line": "The Old Sailor rolls his shoulder. \"Twenty. Thirty years of this, son.\""},
]

## The board on the back wall had nothing to use; a trigger in front of it
## now opens the stakes.
func _add_darts() -> void:
	var board := get_node_or_null("DartboardModel") as Node3D
	if board == null:
		return
	var zone := Area3D.new()
	zone.name = "DartsZone"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.global_position = Vector3(board.global_position.x, 0.0, board.global_position.z + 0.9)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.4, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0)
	zone.add_child(shape)
	zone.interacted.connect(_on_darts)

func _on_darts(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var options: Array = DART_TABLES.map(func(t): return "$%d against %s" % [t["bet"], t["name"]])
	var disabled := []
	for i in DART_TABLES.size():
		if GameState.cash < DART_TABLES[i]["bet"]:
			disabled.append(i)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _start_darts(DART_TABLES[i], player))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Dartboard", "A cork board gone grey at the treble 20, three bent darts in it, a chalkboard beside it with last week's scores still up. Three rounds, three darts, high total wins.", options, disabled)

func _start_darts(table: Dictionary, player: Node) -> void:
	player.dialogue_active = true
	Voice.say("", table["line"])
	var game: CanvasLayer = DartsGame.new()
	get_tree().root.add_child(game)
	game.start(table["name"], table["skill"], table["bet"])
	game.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)

func _connect_pool() -> void:
	var zone := find_child("PoolZone", true, false)
	if zone:
		zone.interacted.connect(_on_pool)

## Tournament night (Headlines): one shot a day at the final, $20 in and
## the whole $80 pot to the winner.
const TOURNAMENT := {"bet": 20, "pot": 80, "name": "The Champ", "skill": 0.7,
	"line": "The tournament's down to you and a guy in a bowling shirt with CHAMP stitched on it. \"Twenty in, eighty to the winner. Break.\""}

func _on_pool(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var tables: Array = POOL_TABLES.duplicate()
	if Headlines.is_today("tournament") and GameState.daily_available("pool_tournament"):
		tables.append(TOURNAMENT)
	var options: Array = tables.map(func(t): return ("Tournament final: $%d in, $%d pot" % [t["bet"], t["pot"]]) if t.has("pot") else "$%d against %s" % [t["bet"], t["name"]])
	var disabled := []
	for i in tables.size():
		if GameState.cash < tables[i]["bet"]:
			disabled.append(i)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if tables[i].has("pot"):
			GameState.daily_available("pool_tournament", true)
		_start_pool(tables[i], player))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Pool table", "Quarters on the rail, a crooked cue rack, felt worn to the weave. Somebody's always up for a game with money on it. First to five balls.", options, disabled)

func _start_pool(table: Dictionary, player: Node) -> void:
	player.dialogue_active = true
	Voice.say("", table["line"])
	var game: CanvasLayer = PoolGame.new()
	get_tree().root.add_child(game)
	game.start(table["name"], table["skill"], table["bet"], table.get("pot", -1))
	game.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
