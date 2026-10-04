extends "res://npc/NPC3D.gd"
## Big Eddie, leaning on the wall at the kart track with a roll of bills.
## He's got money on tonight's race and he'd like you to not be in the top
## three: finish fourth or worse, make it look real, and he pays $30. The
## office (world/KartCenter3D.gd) holds the deal and the race scores it.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const PAY := 30  # KartCenter3D.EDDIE_PAY

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var office := get_tree().current_scene
	if hud == null or office == null or not office.has_method("accept_throw"):
		return
	player.dialogue_active = true
	SFX.play("blip")
	if office.throw_deal_active():
		hud.show_dialogue(npc_name, "\"Fourth or worse. And not by a mile -- if it looks like you parked it, I'm not paying.\"", _portrait())
		return
	if not GameState.daily_available("kart_throw"):
		hud.show_dialogue(npc_name, "\"We're square for today. Go home.\"", _portrait())
		return
	var mood := GameState.rep_of(npc_name)
	var opener := "\"Hey. You.\" He peels a twenty and a ten off a roll and doesn't hand them over."
	if mood >= 2:
		opener = "\"My friend.\" He drapes an arm over your shoulder and lowers his voice."
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if i == 0:
			office.accept_throw(npc_name, PAY)
			hud.show_dialogue(npc_name, "\"Good. Fourth or worse. Drive it like you mean it and lose anyway.\"", _portrait())
		else:
			player.dialogue_active = false)
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open(npc_name, "%s \"I've got money on tonight's race and I need you out of the top three. Fourth or worse -- and make it look real, people are watching. Thirty bucks.\"" % opener,
		["Deal: lose for $%d" % PAY, "I race to win"])
