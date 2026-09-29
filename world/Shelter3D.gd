extends "res://world/WorldRoot3D.gd"
## St. Jude's: a shelter with a soup kitchen and an outreach desk. Open from
## dinner until the morning, closed through the day (GameState.OPENING_HOURS).
##
## - The serving counter hands out a hot plate at breakfast and dinner. It
##   doesn't touch the sickness much, but it steadies you and takes the edge
##   off a beating.
## - The cots are a bed for the night if the apartment's out of reach --
##   but people go through your pockets while you sleep.
## - The outreach worker (npc/Outreach3D.gd) hands out naloxone and a daily
##   dose of buprenorphine: the treatment path, if you want it.

const MEAL_CRAVING := 6.0
const COT_THEFT_CHANCE := 0.3
## Lights-out: the cots are only for sleeping at night.
const COT_HOURS := [20, 8]

func _ready() -> void:
	super._ready()
	for zone in find_children("*", "Area3D", true, false):
		if zone.has_signal("interacted"):
			zone.interacted.connect(interact_zone)

func interact_zone(zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if zone.name == "ServingCounter":
		_meal(hud)
	elif zone.name.begins_with("Cot"):
		_cot(hud)

func _meal(hud: Node) -> void:
	var service := GameState.meal_service()
	if service < 0:
		hud.show_dialogue("Volunteer", "\"Kitchen's closed, hon. Breakfast is seven to ten, dinner five to eight.\"")
		return
	var slot := GameState.day * 2 + service
	if GameState.last_meal_slot == slot:
		hud.show_dialogue("Volunteer", "\"One plate each, sorry. There's a lot of folks tonight.\"")
		return
	GameState.last_meal_slot = slot
	GameState.craving = minf(100.0, GameState.craving + MEAL_CRAVING)
	GameState.craving_changed.emit(GameState.craving)
	GameState.hurt_until = -1.0
	SFX.play("blip")
	var dish: String = ["oatmeal and a boiled egg", "toast and weak coffee"][randi() % 2] if service == 0 else ["chili and cornbread", "chicken soup and a roll", "spaghetti and a slice of white bread"][randi() % 3]
	hud.show_dialogue("Volunteer", "A plastic tray: %s. You eat it at a long table without looking up. It stays down, and you feel a little more like a person." % dish)

func _cot(hud: Node) -> void:
	if GameState.wanted:
		hud.show_dialogue("", "Not with the cops out looking. They check here.")
		return
	if not GameState.hours_contain(COT_HOURS, GameState.hour()):
		hud.show_dialogue("Volunteer", "\"Beds are for the night, hon. Lights out at eight.\"")
		return
	SFX.play("sleep")
	var robbed := ""
	if randf() < COT_THEFT_CHANCE:
		if not GameState.inventory.is_empty():
			var item: String = GameState.inventory.pick_random()
			GameState.inventory.erase(item)
			GameState.inventory_changed.emit()
			robbed = " Somebody's been through your things -- %s is gone." % GameState.item_name_for(item)
		elif GameState.cash > 0:
			var taken := int(ceil(GameState.cash * 0.5))
			GameState.cash -= taken
			GameState.cash_changed.emit(GameState.cash)
			robbed = " Your pocket's lighter by $%d. Nobody saw anything." % taken
	GameState.sleep()
	hud.show_dialogue("", "A thin mattress, forty people breathing, a light that never quite goes off. Day %d, %s.%s" % [GameState.day, GameState.clock_text(), robbed])
