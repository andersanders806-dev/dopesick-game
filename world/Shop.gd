extends "res://world/WorldRoot.gd"

const PoliceScene := preload("res://npc/Police.tscn")
const ITEM_IDS := ["whiskey", "cigs", "charger", "batteries", "watch"]

@onready var shopkeeper: Node2D = $Shopkeeper
@onready var police_spawn: Marker2D = $PoliceSpawn
@onready var item_slots: Array = [$ItemWhiskey, $ItemCigs, $ItemCharger, $ItemBatteries, $ItemWatch]

func _ready() -> void:
	super._ready()
	shopkeeper.spotted_theft.connect(_on_spotted_theft)
	_shuffle_items()

func _shuffle_items() -> void:
	var ids := ITEM_IDS.duplicate()
	ids.shuffle()
	for i in range(item_slots.size()):
		item_slots[i].set_item_id(ids[i])

func _on_spotted_theft() -> void:
	if GameState.wanted:
		return
	var police := PoliceScene.instantiate()
	add_child(police)
	police.global_position = police_spawn.global_position
