extends "res://world/WorldRoot.gd"

const PATRON_NAMES := ["Wiry Guy", "Tired Woman", "Big Eddie", "Quiet Kid", "Old Sailor", "Nervous Dave"]
const PATRON_SKINS := [
	preload("res://assets/sprites/npc_brown_idle.png"),
	preload("res://assets/sprites/npc_red_idle.png"),
	preload("res://assets/sprites/npc_purple_idle.png"),
	preload("res://assets/sprites/npc_grey_idle.png"),
]

@onready var patrons: Array = [$Patron1, $Patron2, $Patron3]

func _ready() -> void:
	super._ready()
	_randomize_patrons()
	_assign_requests()

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
