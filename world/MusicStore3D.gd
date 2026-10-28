extends "res://world/Store3D.gd"
## Tape Deck: used cassettes, a listening booth, a clerk who's heard it all.
## The racks and the till are world/TapeCounter.gd's (the shop on Main
## Street, world/WalkInShop.gd, shares them).

const TapeCounter := preload("res://world/TapeCounter.gd")

func _ready() -> void:
	super._ready()
	TapeCounter.wire_zones(self)

func _shuffle_items() -> void:
	TapeCounter.stock_racks(item_slots)

func interact_zone(zone: Area3D, player: Node) -> void:
	TapeCounter.interact_zone(self, zone, player)

func _buy(id: String, player: Node, hud: Node) -> void:
	TapeCounter.buy(id, player, hud)
