extends RefCounted
## Tape Deck's racks and till, which are the same whether the shop is a room
## of its own (MusicStore3D.gd) or a room on Main Street (WalkInShop.gd).
## The racks hold tapes you don't own yet (Walkman.dealer_stock()); lift one
## and it goes straight into your shoebox -- or pay at the counter.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

## Instead of Store3D's catalogue shuffle: whatever you haven't got, at
## random. Racks you've cleaned out stand empty.
static func stock_racks(item_slots: Array) -> void:
	var stock: Array = Walkman.dealer_stock()
	stock.shuffle()
	for i in item_slots.size():
		if i < stock.size():
			item_slots[i].set_item_id("tape:" + stock[i])
		else:
			item_slots[i].queue_free()

## Hooks every interact zone of `shop` up to `interact_zone`.
static func wire_zones(shop: Node) -> void:
	for zone in shop.find_children("*", "Area3D", true, false):
		if zone.has_signal("interacted"):
			zone.interacted.connect(func(z: Area3D, player: Node): interact_zone(shop, z, player))

static func interact_zone(shop: Node, zone: Area3D, player: Node) -> void:
	# The counter's trigger can't share the name "Counter" with the counter
	# itself -- Godot quietly renamed it, and buying at the till never fired.
	if zone.name != "CounterZone":
		return
	var hud := shop.get_tree().get_first_node_in_group("hud")
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
	shop.get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): buy(stock[i], player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Clerk", "\"Everything's used, everything plays. Mostly.\"", options, disabled)

static func buy(id: String, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	if not GameState.spend_cash(Walkman.TAPES[id]["price"]):
		return
	Walkman.add_tape(id)
	SFX.play("cash", -6.0, 1.1)
	hud.show_dialogue("Clerk", "He drops %s in a paper bag. \"Good one. Rewind it before you bring it back.\" He's joking. There are no returns." % Walkman.TAPES[id]["title"])
