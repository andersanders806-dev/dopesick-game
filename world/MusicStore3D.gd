extends "res://world/Store3D.gd"
## Tape Deck: used cassettes, a listening booth, a clerk who's heard it all.
## The racks hold tapes you don't own yet (Walkman.dealer_stock()); lift one
## and it goes straight into your shoebox -- or pay at the counter.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

func _ready() -> void:
	super._ready()
	for zone in find_children("*", "Area3D", true, false):
		if zone.has_signal("interacted"):
			zone.interacted.connect(interact_zone)

## Instead of Store3D's catalogue shuffle: whatever you haven't got, at
## random. Racks you've cleaned out stand empty.
func _shuffle_items() -> void:
	var stock: Array = Walkman.dealer_stock()
	stock.shuffle()
	for i in item_slots.size():
		if i < stock.size():
			item_slots[i].set_item_id("tape:" + stock[i])
		else:
			item_slots[i].queue_free()

func interact_zone(zone: Area3D, player: Node) -> void:
	# The counter's trigger can't share the name "Counter" with the counter
	# itself -- Godot quietly renamed it, and buying at the till never fired.
	if zone.name != "CounterZone":
		return
	var hud := get_tree().get_first_node_in_group("hud")
	player.dialogue_active = true
	var stock: Array = Walkman.dealer_stock()
	if stock.is_empty():
		hud.show_dialogue("Clerk", "\"You've literally got everything I have. Respect.\"")
		return
	var options: Array = stock.map(func(id): return "%s - %s   $%d" % [Walkman.TAPES[id]["title"], Walkman.TAPES[id]["artist"], Walkman.TAPES[id]["price"]])
	var disabled := []
	for i in stock.size():
		if GameState.cash < Walkman.TAPES[stock[i]]["price"]:
			disabled.append(i)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _buy(stock[i], player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Clerk", "\"Everything's used, everything plays. Mostly.\"", options, disabled)

func _buy(id: String, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	if not GameState.spend_cash(Walkman.TAPES[id]["price"]):
		return
	Walkman.add_tape(id)
	SFX.play("cash", -6.0, 1.1)
	hud.show_dialogue("Clerk", "He drops %s in a paper bag. \"Good one. Rewind it before you bring it back.\" He's joking. There are no returns." % Walkman.TAPES[id]["title"])
