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
	_add_slots()
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
		if state[i]["fulfilled"] or state[i]["name"] in GameState.dead_regulars:
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
	var living: Array = PATRON_NAMES.filter(func(n): return n not in GameState.dead_regulars)
	var free_names := living.filter(func(n): return n not in taken_names)
	# Only ever short if the alley's taken too many: then the one going home
	# can come straight back in.
	if free_names.is_empty():
		free_names = living.filter(func(n): return n not in current.filter(func(p): return not p["fulfilled"]).map(func(p): return p["name"]))
	var name: String = free_names.pick_random()
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

# --- The slot machine -------------------------------------------------------

const SlotMachine := preload("res://ui/SlotMachine.gd")
## Against the east wall between the COLD BEER neon and the leaning cue,
## facing into the room.
const SLOT_POS := Vector3(7.12, 0.0, -1.9)
const SLOT_ATTRACT := Vector2(35.0, 80.0)  # seconds between its little tune

var _slot_bulbs: Array = []  # two materials, lit in turn
var _slot_attract: AudioStreamPlayer3D
var _slot_attract_in := 20.0

## Built here rather than by the room generator so the bar scene doesn't
## need regenerating; it goes in before the navmesh bake so people walk
## round it.
func _add_slots() -> void:
	var cab := StaticBody3D.new()
	cab.name = "SlotMachine"
	add_child(cab)
	cab.position = SLOT_POS
	cab.rotation_degrees.y = -90.0
	var body_col := _slot_mat(Color(0.5, 0.05, 0.06), 0.45)
	var chrome := _slot_mat(Color(0.8, 0.8, 0.83), 0.2, 0.0, 0.9)
	var dark := _slot_mat(Color(0.05, 0.05, 0.06), 0.6)
	_slot_box(cab, Vector3(0.66, 0.78, 0.56), Vector3(0, 0.39, 0), body_col)
	_slot_box(cab, Vector3(0.68, 0.05, 0.58), Vector3(0, 0.8, 0), chrome)
	_slot_box(cab, Vector3(0.62, 0.92, 0.44), Vector3(0, 1.26, -0.06), body_col)
	_slot_box(cab, Vector3(0.48, 0.3, 0.02), Vector3(0, 1.36, 0.165), chrome)
	# The reel window: lit paper bands with a 7 on each.
	var reels := _slot_box(cab, Vector3(0.42, 0.24, 0.02), Vector3(0, 1.36, 0.172), _slot_mat(Color(0.97, 0.94, 0.86), 0.5, 0.9))
	var bungee: Font = load("res://assets/fonts/Bungee-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/Bungee-Regular.ttf") else null
	for i in 3:
		var sym := Label3D.new()
		sym.text = ["7", "BAR", "7"][i]
		sym.font_size = 64 if i != 1 else 30
		sym.pixel_size = 0.0019
		sym.modulate = Color(0.85, 0.05, 0.08) if i != 1 else Color(0.08, 0.08, 0.1)
		sym.outline_size = 0
		if bungee:
			sym.font = bungee
		reels.add_child(sym)
		sym.position = Vector3(-0.14 + i * 0.14, 0, 0.012)
	_slot_box(cab, Vector3(0.44, 0.006, 0.01), Vector3(0, 1.36, 0.19), _slot_mat(Color(1, 0.1, 0.1), 0.5, 2.0))
	# Buttons and the coin tray.
	_slot_box(cab, Vector3(0.6, 0.06, 0.2), Vector3(0, 0.84, 0.2), dark)
	for i in 3:
		_slot_box(cab, Vector3(0.08, 0.025, 0.06), Vector3(-0.18 + i * 0.12, 0.88, 0.24), _slot_mat([Color(1, 0.75, 0.1), Color(1, 0.75, 0.1), Color(1, 0.15, 0.1)][i], 0.4, 1.2))
	_slot_box(cab, Vector3(0.36, 0.12, 0.1), Vector3(0, 0.22, 0.3), chrome)
	_slot_box(cab, Vector3(0.32, 0.08, 0.08), Vector3(0, 0.24, 0.32), dark)
	# The marquee box, glowing, with bulbs round its face.
	var marquee := _slot_box(cab, Vector3(0.68, 0.3, 0.48), Vector3(0, 1.88, -0.04), _slot_mat(Color(0.25, 0.02, 0.03), 0.5))
	var face := _slot_box(marquee, Vector3(0.58, 0.2, 0.01), Vector3(0, 0, 0.245), _slot_mat(Color(0.6, 0.05, 0.05), 0.5, 1.4))
	var title := Label3D.new()
	title.text = "LUCKY DEVIL"
	title.font_size = 56
	title.pixel_size = 0.00135
	title.modulate = Color(1.0, 0.82, 0.3)
	title.outline_modulate = Color(0.3, 0.02, 0.02)
	title.outline_size = 10
	if bungee:
		title.font = bungee
	face.add_child(title)
	title.position = Vector3(0, 0, 0.008)
	_slot_bulbs = [_slot_mat(Color(1, 0.8, 0.35), 0.4, 3.0), _slot_mat(Color(1, 0.8, 0.35), 0.4, 3.0)]
	var bulb := SphereMesh.new()
	bulb.radius = 0.018
	bulb.height = 0.036
	bulb.radial_segments = 8
	bulb.rings = 4
	for k in 14:
		var b := MeshInstance3D.new()
		b.mesh = bulb
		b.material_override = _slot_bulbs[k % 2]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marquee.add_child(b)
		var u := k / 13.0
		b.position = Vector3(lerpf(-0.31, 0.31, u), 0.125 if k % 2 == 0 else -0.125, 0.25)
	# The lever down the right side.
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.015
	arm_mesh.bottom_radius = 0.015
	arm_mesh.height = 0.42
	arm.mesh = arm_mesh
	arm.material_override = chrome
	cab.add_child(arm)
	arm.position = Vector3(0.37, 1.38, 0.0)
	arm.rotation_degrees.x = -12.0
	_slot_box(cab, Vector3(0.06, 0.16, 0.1), Vector3(0.34, 1.18, 0.0), chrome)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.045
	knob_mesh.height = 0.09
	knob.mesh = knob_mesh
	knob.material_override = _slot_mat(Color(0.85, 0.05, 0.08), 0.25, 0.4)
	cab.add_child(knob)
	knob.position = Vector3(0.37, 1.6, 0.045)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 2.0, 0.6)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	cab.add_child(shape)
	# Its glow on the floor and the wall -- no shadows, it's only a lamp's worth.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.25)
	glow.light_energy = 0.9
	glow.omni_range = 2.4
	glow.shadow_enabled = false
	cab.add_child(glow)
	glow.position = Vector3(0, 1.6, 0.6)
	# Every so often it plays its little tune to the room, to nobody.
	_slot_attract = AudioStreamPlayer3D.new()
	_slot_attract.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	if ResourceLoader.exists("res://assets/sfx/slot_win_small.wav"):
		_slot_attract.stream = load("res://assets/sfx/slot_win_small.wav")
	_slot_attract.volume_db = -14.0
	_slot_attract.unit_size = 2.0
	_slot_attract.max_distance = 14.0
	cab.add_child(_slot_attract)
	_slot_attract.position = Vector3(0, 1.6, 0.2)
	_slot_attract_in = randf_range(8.0, SLOT_ATTRACT.x)
	# Walk up to it to play.
	var zone := Area3D.new()
	zone.name = "SlotZone"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	cab.add_child(zone)
	zone.position = Vector3(0, 0, 0.75)
	var zshape := CollisionShape3D.new()
	var zbox := BoxShape3D.new()
	zbox.size = Vector3(1.0, 1.4, 0.9)
	zshape.shape = zbox
	zshape.position = Vector3(0, 0.7, 0)
	zone.add_child(zshape)
	zone.interacted.connect(_on_slots)

func _slot_mat(col: Color, rough: float, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m

func _slot_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi

func _process(delta: float) -> void:
	super._process(delta)
	if _slot_bulbs.is_empty():
		return
	# Chasing bulbs: the two halves trade places twice a second.
	var phase := int(Time.get_ticks_msec() / 450) % 2
	_slot_bulbs[0].emission_energy_multiplier = 3.0 if phase == 0 else 0.3
	_slot_bulbs[1].emission_energy_multiplier = 0.3 if phase == 0 else 3.0
	_slot_attract_in -= delta
	if _slot_attract_in <= 0.0:
		_slot_attract_in = randf_range(SLOT_ATTRACT.x, SLOT_ATTRACT.y)
		if _slot_attract.stream and not get_tree().root.get_children().any(func(n): return n is SlotMachine):
			_slot_attract.play()

func _on_slots(_zone: Area3D, player: Node) -> void:
	_start_slots(player)

func _start_slots(player: Node) -> CanvasLayer:
	player.dialogue_active = true
	var game: CanvasLayer = SlotMachine.new()
	get_tree().root.add_child(game)
	game.start()
	game.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	return game

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
