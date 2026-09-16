extends "res://world/WorldRoot.gd"

const PATRON_NAMES := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
const PATRON_SKINS := [
	preload("res://assets/sprites/npc_brown_idle.png"),
	preload("res://assets/sprites/npc_red_idle.png"),
	preload("res://assets/sprites/npc_purple_idle.png"),
	preload("res://assets/sprites/npc_grey_idle.png"),
]

# Each layout is 3 table positions, index-matched to `tables` / `patrons`
# (TableA/B/C). A patron always sits right at their table's position.
const TABLE_LAYOUTS := [
	[Vector2(120, 236), Vector2(260, 256), Vector2(400, 216)],
	[Vector2(150, 150), Vector2(260, 150), Vector2(370, 150)],
	[Vector2(80, 180), Vector2(260, 220), Vector2(440, 180)],
]

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
		tables[i].position = layout[i]
		patrons[i].position = layout[i]

func _randomize_patrons() -> void:
	var names := PATRON_NAMES.duplicate()
	names.shuffle()
	var skins := PATRON_SKINS.duplicate()
	skins.shuffle()
	for i in range(patrons.size()):
		patrons[i].npc_name = names[i]
		patrons[i].set_skin(skins[i])

func _assign_requests() -> void:
	var pool := GameState.REQUEST_POOL.duplicate()
	pool.shuffle()
	for i in range(patrons.size()):
		var r = pool[i]
		patrons[i].set_request(r["id"], r["price"])
