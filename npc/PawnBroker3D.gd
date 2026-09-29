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
	var rate := ELECTRONICS_PAYOUT if info.get("store", "") == "electronics" else PAYOUT
	return maxi(GameState.FENCE_PRICE, int(round(float(info.get("price", 0)) * rate)))

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")
	if GameState.inventory.is_empty():
		hud.show_dialogue(npc_name, "He doesn't look up from his newspaper. \"You got something to sell, put it on the counter. Otherwise I'm busy.\"")
		return
	var items: Array = GameState.inventory.duplicate()
	var options := items.map(func(id): return "Sell %s -- $%d" % [GameState.item_name_for(id), offer_for(id)])
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _sell(items[i], player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open(npc_name, "He slides the tray out under the plexiglass. \"Let's see it. Electronics I gotta run the serial, so don't get excited.\"", options)

func _sell(id: String, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	if not GameState.has_item(id):
		return
	var price := offer_for(id)
	GameState.inventory.erase(id)
	GameState.cash += price
	GameState.cash_earned += price
	GameState.inventory_changed.emit()
	GameState.cash_changed.emit(GameState.cash)
	SFX.play("cash")
	hud.show_dialogue(npc_name, "He turns %s over under the lamp, writes something in a ledger, and counts out $%d. \"Pleasure.\"" % [GameState.item_name_for(id), price])
