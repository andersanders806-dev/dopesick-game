extends "res://world/WorldRoot3D.gd"
## Southside Speedway's front office. The marshal at the desk sells a ride:
## $5 for three laps against the Dive Bar regulars (ui/KartRace.gd). The
## day's first race pays the podium; after that it's for the board. Open
## afternoons until midnight (GameState.OPENING_HOURS), floodlit at night.

const KartRace := preload("res://ui/KartRace.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const RIDE_PRICE := 5

func _ready() -> void:
	super._ready()
	var desk := find_child("KartDesk", true, false)
	if desk:
		desk.interacted.connect(_on_desk)

func _on_desk(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var prize := "Podium pays $%d / $%d / $%d -- first race of the day only." % KartRace.PRIZES
	if not GameState.daily_available(KartRace.PRIZE_DAILY_KEY):
		prize = "Today's prize pot's gone. You'd be racing for the board."
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i == 0:
			_start_race(player)
		else:
			player.dialogue_active = false)
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Marshal", "\"Three laps, five drivers, one of them's you. %s Sign the waiver.\"" % prize,
		["Race ($%d)" % RIDE_PRICE, "Not tonight"], [] if GameState.cash >= RIDE_PRICE else [0])

func _start_race(player: Node) -> void:
	if not GameState.spend_cash(RIDE_PRICE):
		player.dialogue_active = false
		return
	SFX.play("cash")
	player.dialogue_active = true
	var race: CanvasLayer = KartRace.new()
	get_tree().root.add_child(race)
	race.start("player")
	race.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
