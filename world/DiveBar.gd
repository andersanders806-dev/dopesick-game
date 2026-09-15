extends "res://world/WorldRoot.gd"

@onready var patrons: Array = [$Patron1, $Patron2, $Patron3]

func _ready() -> void:
	super._ready()
	_assign_requests()

func _assign_requests() -> void:
	var pool := GameState.REQUEST_POOL.duplicate()
	pool.shuffle()
	for i in range(patrons.size()):
		var r = pool[i]
		patrons[i].set_request(r["id"], r["price"])
