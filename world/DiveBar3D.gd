extends "res://world/WorldRoot3D.gd"

const PATRON_NAMES := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
const PATRON_MODELS := [
	"res://assets/kenney/characters/character-male-b.glb",
	"res://assets/kenney/characters/character-male-c.glb",
	"res://assets/kenney/characters/character-male-d.glb",
	"res://assets/kenney/characters/character-female-a.glb",
	"res://assets/kenney/characters/character-female-b.glb",
	"res://assets/kenney/characters/character-female-d.glb",
]

# Each layout is 3 table spots (x, z), index-matched to `tables` / `patrons`
# (TableA/B/C), converted from DiveBar.gd's 2D layouts. The patron sits on
# the west end of their table, facing the room -- not behind it, since the
# camera looks north and the tabletop would hide them.
const TABLE_LAYOUTS := [
	[Vector2(-3.5, 2.2), Vector2(0.0, 2.7), Vector2(3.5, 1.7)],
	[Vector2(-2.75, 0.4), Vector2(0.0, 0.4), Vector2(2.75, 0.4)],
	[Vector2(-4.5, 0.8), Vector2(0.0, 1.9), Vector2(4.5, 0.8)],
]
const PATRON_OFFSET := Vector3(-1.05, 0.0, -0.25)

@onready var patrons: Array = [$Patron1, $Patron2, $Patron3]
@onready var tables: Array = [$TableA, $TableB, $TableC]

func _ready() -> void:
	_randomize_layout()
	super._ready()
	_randomize_patrons()
	_assign_requests()

func _randomize_layout() -> void:
	var layout: Array = TABLE_LAYOUTS.pick_random()
	for i in range(tables.size()):
		var spot: Vector2 = layout[i]
		tables[i].position = Vector3(spot.x, 0.0, spot.y)
		patrons[i].position = tables[i].position + PATRON_OFFSET

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
