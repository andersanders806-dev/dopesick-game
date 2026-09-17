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
	_seat_patrons()
	super._ready()
	_randomize_patrons()
	_assign_requests()

func _seat_patrons() -> void:
	var seats := SEATS.duplicate()
	seats.shuffle()
	for i in range(patrons.size()):
		var seat: Dictionary = seats[i]
		var pos: Vector3 = seat["pos"]
		if seat["pose"] == "sit":
			pos.y = SIT_HEIGHT
		patrons[i].position = pos
		patrons[i].model_root.rotation_degrees.y = seat["yaw"]
		patrons[i].set_pose(seat["pose"])

## Name and model are shuffled independently, so the same name doesn't
## always wear the same body.
func _randomize_patrons() -> void:
	var names := PATRON_NAMES.duplicate()
	names.shuffle()
	var models := PATRON_MODELS.duplicate()
	models.shuffle()
	for i in range(patrons.size()):
		patrons[i].npc_name = names[i]
		patrons[i].set_model(models[i])

func _assign_requests() -> void:
	var pool := GameState.REQUEST_POOL.duplicate()
	pool.shuffle()
	for i in range(patrons.size()):
		var r = pool[i]
		patrons[i].set_request(r["id"], r["price"])
