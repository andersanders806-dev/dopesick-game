extends "res://npc/NPC3D.gd"
## The pawnbroker. Pays more than the bartender's flat fence price -- half of
## what a patron would, for most things -- but he runs serial numbers on
## electronics, so those only fetch a fraction. One item at a time, over the
## counter, through the plexiglass.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const PAYOUT := 0.5
const ELECTRONICS_PAYOUT := 0.3
const PORTRAIT_NAME := "Pawnbroker"

func _ready() -> void:
	fences_items = false
	super._ready()

## What he'll give you for `id`.
static func offer_for(id: String) -> int:
	var info := GameState.item_info(id)
	# Your own things: no serial to run, and he can sell them back to you.
	if GameState.is_belonging(id):
		return int(info["price"])
	var rate := ELECTRONICS_PAYOUT if info.get("store", "") == "electronics" else PAYOUT
	return maxi(GameState.FENCE_PRICE, int(round(float(info.get("price", 0)) * rate)))

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")
	var items: Array = GameState.inventory.duplicate()
	var tickets: Array = GameState.pawn_tickets.keys()
	if items.is_empty() and tickets.is_empty():
		hud.show_dialogue(npc_name, greeting())
		return
	var options: Array = items.map(func(id): return "Sell %s -- $%d" % [GameState.item_name_for(id), offer_for(id)])
	var disabled := []
	for id in tickets:
		if GameState.cash < GameState.buyback_price(id):
			disabled.append(options.size())
		options.append("Buy back %s -- $%d (holds till day %d)" % [GameState.item_name_for(id), GameState.buyback_price(id), GameState.ticket_last_day(id)])
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i < items.size():
			_sell(items[i], player, hud)
		else:
			_buy_back(tickets[i - items.size()], player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open(npc_name, "He slides the tray out under the plexiglass. \"Let's see it. Electronics I gotta run the serial, so don't get excited.\"", options, disabled)

func _buy_back(id: String, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	if GameState.buy_back(id):
		SFX.play("cash")
		hud.show_dialogue(npc_name, "He finds the ticket, then %s on a back shelf. \"Didn't think I'd see you again.\"" % GameState.item_name_for(id))

func _sell(id: String, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	if not GameState.has_item(id):
		return
	var price := offer_for(id)
	var own := GameState.is_belonging(id)
	if not own:
		GameState._sold_out_from_under(id)
	GameState.inventory.erase(id)
	GameState.cash += price
	GameState.cash_earned += price
	GameState.inventory_changed.emit()
	GameState.cash_changed.emit(GameState.cash)
	if own:
		GameState.pawn_belonging(id)
	SFX.play("cash")
	hud.show_dialogue(npc_name, "He turns %s over under the lamp, writes something in a ledger, and counts out $%d. \"Pleasure.\"" % [GameState.item_name_for(id), price])

## Nothing to sell: the newspaper, or -- if your guitar ended last run on
## his wall -- that.
static func greeting() -> String:
	if MetaProgress.last_run.get("guitar", "home") not in ["home", "carried"]:
		return "He nods at the wall without looking up. \"Your guitar's still there from last time. Nobody wants a guitar with a cracked neck.\""
	return "He doesn't look up from his newspaper. \"You got something to sell, put it on the counter. Otherwise I'm busy.\""
