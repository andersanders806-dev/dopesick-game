extends "res://world/Store3D.gd"
## The lot behind the block, through the gate by the police station end.
## Nobody's in charge back here, which cuts both ways:
##
## - Mornings (DELIVERY_HOURS) a supermarket delivery sits on the loading
##   dock with only the driver keeping half an eye on it -- it's a Store3D
##   so the pallet's goods steal and get spotted like any shelf's.
## - The dumpster: dig through it once a day for whatever got thrown out.
## - Behind the dumpster: somewhere to crouch out of sight. Police lose you
##   if they can't see you, and back here they can't.
## - The old mattress under the tarp: a night's sleep, if you don't mind
##   waking up to your pockets turned out.

const DELIVERY_HOURS := [6, 10]
const DUMPSTER_CASH_CHANCE := 0.4
const DUMPSTER_ITEM_CHANCE := 0.3
## Things people actually throw out that are still worth something.
const DUMPSTER_FINDS := ["batteries", "charger", "energy", "sunglasses", "cheese"]
const ROUGH_SLEEP_ROB_CHANCE := 0.35

func _ready() -> void:
	# No delivery outside the morning: take the pallet, its goods, and the
	# driver out before Store3D goes looking for fixtures and guards.
	if not GameState.hours_contain(DELIVERY_HOURS, GameState.hour()):
		for n in ["Fixture1", "Item1", "Fixture2", "Item2", "Driver", "DeliveryTruck"]:
			var node := get_node_or_null(n)
			if node:
				remove_child(node)
				node.queue_free()
	super._ready()
	var life: Node3D = preload("res://world/StreetLife.gd").new()
	life.traffic = false
	add_child(life)
	for zone in find_children("*", "Area3D", true, false):
		if zone.has_signal("interacted"):
			zone.interacted.connect(interact_zone)

func interact_zone(zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	match zone.name:
		"Dumpster":
			player.dialogue_active = true
			_dumpster(hud)
		"HideSpot":
			player.set_hiding(not player.hiding)
			if player.hiding:
				SFX.play("steal", -8.0, 0.8)
		"Mattress":
			player.dialogue_active = true
			_rough_sleep(hud)

func _dumpster(hud: Node) -> void:
	if not GameState.daily_available("dumpster", true):
		hud.show_dialogue("", "You've already been through it today. Wet cardboard and coffee grounds.")
		return
	SFX.play("steal", -4.0, 0.7)
	var roll := randf()
	if roll < DUMPSTER_CASH_CHANCE:
		var amount := randi_range(1, 4)
		GameState.cash += amount
		GameState.cash_changed.emit(GameState.cash)
		hud.show_dialogue("", "Elbow-deep in garbage bags, your fingers close on a crumpled bill. $%d." % amount)
	elif roll < DUMPSTER_CASH_CHANCE + DUMPSTER_ITEM_CHANCE:
		var id: String = DUMPSTER_FINDS.pick_random()
		GameState.steal_item(id)
		hud.show_dialogue("", "Under a split bag: %s, barely used. Somebody'll pay for that." % GameState.item_name_for(id))
	else:
		hud.show_dialogue("", "Nothing. Rotten lettuce, broken glass, a smell that follows you out.")

func _rough_sleep(hud: Node) -> void:
	if GameState.wanted:
		hud.show_dialogue("", "Not now. Not with sirens going.")
		return
	if GameState.hour() >= 9.0 and GameState.hour() < 19.0:
		hud.show_dialogue("", "In broad daylight, in the delivery lot? Somebody'd call it in.")
		return
	SFX.play("sleep")
	var robbed := ""
	if GameState.cash > 0 and randf() < ROUGH_SLEEP_ROB_CHANCE:
		var taken := GameState.cash
		GameState.cash = 0
		GameState.cash_changed.emit(0)
		robbed = " Your pockets are inside out. All $%d, gone." % taken
	GameState.sleep()
	hud.show_dialogue("", "Cold comes up through the mattress all night. You wake up stiff, damp, on day %d, %s.%s" % [GameState.day, GameState.clock_text(), robbed])
