extends "res://world/WorldRoot.gd"

const PoliceScene := preload("res://npc/Police.tscn")

@onready var shopkeeper: Node2D = $Shopkeeper
@onready var police_spawn: Marker2D = $PoliceSpawn

func _ready() -> void:
	super._ready()
	shopkeeper.spotted_theft.connect(_on_spotted_theft)

func _on_spotted_theft() -> void:
	if GameState.wanted:
		return
	var police := PoliceScene.instantiate()
	add_child(police)
	police.global_position = police_spawn.global_position
