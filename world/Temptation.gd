extends Node3D
## The program is five days, and the block doesn't stop being the block.
## While you're in it (GameState.in_treatment), once a day each:
##
## - The offer: walk within reach of the pusher on his shift and he calls
##   you over. "First one's on me." Taking it is using; walking away is
##   the day still counting.
## - The pull: when the withdrawal's biting (craving under PULL_BELOW), a
##   flash of his corner, and your feet already turning that way. Holding
##   on costs you -- it hurts -- and going is a relapse.
##
## Giving in plays the relapse panel and counts as using, so the day won't
## count (GameState._tally_treatment_day). Holding out plays the walking-
## away panel the first time. Both go in the diary.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const OFFER_RANGE := 5.0
const PULL_BELOW := 40.0
const PULL_CHANCE_PER_SEC := 0.02
const HOLD_ON_COST := 12.0

var _busy: bool = false

func _process(delta: float) -> void:
	if _busy or not GameState.in_treatment or get_tree().paused:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.dialogue_active:
		return
	var pusher := get_parent().get_node_or_null("Pusher") as Node3D
	if pusher and pusher.visible and GameState.pusher_on_shift() and GameState.daily_available("temptation_offer") \
			and player.global_position.distance_to(pusher.global_position) < OFFER_RANGE:
		GameState.daily_available("temptation_offer", true)
		_offer(player)
	elif GameState.craving < PULL_BELOW and GameState.daily_available("temptation_pull") and randf() < PULL_CHANCE_PER_SEC * delta:
		GameState.daily_available("temptation_pull", true)
		_pull(player)

func _offer(player: Node) -> void:
	_busy = true
	player.dialogue_active = true
	var portrait: Texture2D = load("res://assets/portraits/pusher.png")
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _decide(i == 0, player, "Took the free one he offered."))
	menu.cancelled.connect(func(): _decide(false, player, "Walked past his corner when he called out."))
	menu.open("Pusher", "He's seen you going in and out of the shelter. He doesn't make a big thing of it. \"Hey. You look rough. First one's on me -- for old times.\"", ["Take it", "Keep walking"], [], portrait)

func _pull(player: Node) -> void:
	_busy = true
	player.dialogue_active = true
	await Cutscene.play("temptation")
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _decide(i == 1, player, "Went back to his corner."))
	menu.cancelled.connect(func(): _decide(false, player, "Held on through the worst of it."))
	menu.open("", "Your feet are already turning toward his corner. You know exactly how long the walk is.", ["Hold on. Breathe. It passes.", "Go see him"])

func _decide(gave_in: bool, player: Node, line: String) -> void:
	if gave_in:
		GameState.take_drug("heroin")
		GameState.log_event(line + " The count starts over.", "relapse")
		await Cutscene.play("relapse")
	else:
		GameState.craving = maxf(0.0, GameState.craving - HOLD_ON_COST)
		GameState.craving_changed.emit(GameState.craving)
		var first: bool = GameState.daily_available("resisted_ever")
		GameState.daily_used["resisted_ever"] = -2  # once a run, not once a day
		GameState.log_event(line, "resisted" if first else "")
		if first:
			await Cutscene.play("resisted")
	if is_instance_valid(player):
		player.dialogue_active = false
	_busy = false
