extends Area3D
## The police station's front door. You can't walk in, but you can walk
## up: court in the mornings, probation check-ins, and turning yourself in
## on a warrant. The cell is the jail scene, same as a bust.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if GameState.warrant:
		_offer_surrender(player)
	elif GameState.in_court_hours():
		match GameState.appear_in_court():
			"diverted":
				hud.show_dialogue("Judge", "\"I see you're in the program at St. Jude's. Keep going. I'm dismissing one of these.\"")
			"probation":
				hud.show_dialogue("Judge", "\"Three days' probation. You check in every day, and you test clean. Next.\"")
	elif not GameState.probation_days.is_empty() and int(GameState.probation_days[0]) == GameState.day:
		match GameState.probation_check_in():
			"passed":
				hud.show_dialogue("Desk sergeant", "\"Clean. Same time tomorrow.\"" if not GameState.probation_days.is_empty() else "\"Clean. That's your last one. Don't come back.\"")
			"failed":
				hud.show_dialogue("Desk sergeant", "He looks at the strip, then at you. \"Hands behind your back.\"")
				_cell_after(1.2)
			_:
				hud.show_dialogue("", "Check-ins are nine to five. It's %s." % GameState.clock_text())
	elif GameState.court_day > 0:
		hud.show_dialogue("", "Court's day %d, nine till noon. Be here." % GameState.court_day)
	else:
		hud.show_dialogue("", "The station's front door. Nobody comes here on purpose.")

func _offer_surrender(player: Node) -> void:
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(_i: int): to_cell())
	menu.cancelled.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	menu.open("", "There's a warrant with your name on it. Walk in now and it's a night in a cell and a new court date. Get picked up and it's a strike.", ["Turn yourself in"])

## Turning yourself in: no strike, no fine, a fresh court date, the cell.
func to_cell() -> void:
	GameState.turn_self_in()
	_cell_after(0.0)

func _cell_after(delay: float) -> void:
	var tree := get_tree()
	# A failed test that was your last strike: the run-end screen takes it.
	if GameState.strikes >= GameState.max_strikes():
		return
	GameState.pending_spawn = "SpawnCell"
	if delay > 0.0:
		await tree.create_timer(delay).timeout
	tree.change_scene_to_file("res://world/Jail3D.tscn")
