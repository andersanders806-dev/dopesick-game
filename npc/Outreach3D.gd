extends "res://npc/NPC3D.gd"
## The outreach worker at St. Jude's. Harm reduction, not judgment: a free
## naloxone kit, and -- once a day, if you're actually in withdrawal -- a
## dose of buprenorphine from the clinic program. She won't give it to you
## too soon after an opioid, because that's what precipitates withdrawal
## (GameState.take_drug handles the real thing if you get it on the street).

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const TALK := [
	"\"Nobody here's going to lecture you. I just want you alive next week.\"",
	"\"If you use, don't use alone. And carry the naloxone. Please.\"",
	"\"The strips aren't magic. But people get their lives back on them. I've seen it.\"",
	"\"Test your stuff if you can. Everything out there's got fentanyl in it now.\"",
]

func _ready() -> void:
	fences_items = false
	super._ready()

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")
	var program := "Your clinic dose  (program: %d/%d clean days)" % [GameState.treatment_streak, GameState.RECOVERY_DAYS] if GameState.in_treatment else "Ask about treatment (start the program)"
	var options := ["Take a naloxone kit", program, "Take test strips", "Just talk"]
	var disabled := []
	if not GameState.daily_available("shelter_naloxone"):
		disabled.append(0)
	if not GameState.daily_available("shelter_bupe"):
		disabled.append(1)
	if not GameState.daily_available("shelter_strips"):
		disabled.append(2)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): _on_choice(i, player, hud))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open(npc_name, "She looks up from a stack of pamphlets. \"Hey. What do you need?\"", options, disabled)

func _on_choice(i: int, player: Node, hud: Node) -> void:
	player.dialogue_active = true
	match i:
		0:
			GameState.daily_available("shelter_naloxone", true)
			GameState.naloxone += 1
			GameState.inventory_changed.emit()
			hud.show_dialogue(npc_name, "She presses a kit into your hand. \"Nasal spray. Tilt the head back, one spray, call it in. It's free, take one every day if you want.\"")
		1:
			var since := GameState.run_time - float(GameState.last_dose_at.get(Drugs.OPIOID, -9999.0))
			if since < Drugs.PRECIPITATED_WINDOW:
				hud.show_dialogue(npc_name, "She looks at your eyes. \"You've used recently. If I give you this now it'll knock the rest off the receptors and make you sicker than you've ever been. Come back when you're in withdrawal.\"")
				return
			GameState.daily_available("shelter_bupe", true)
			var first := not GameState.in_treatment
			var outcome := GameState.take_drug("bupe")
			GameState.clinic_dose()
			if outcome == "relief" and first:
				hud.show_dialogue(npc_name, "She signs you in on a clipboard. A strip under the tongue, and you wait while it dissolves. The sickness backs off, slowly. \"Here's the deal. Come every day, take it here, and stay off everything else. %d days straight and you're out of the woods -- not cured, out. If you slip, you start the count again. Nobody's keeping score but you.\"" % GameState.RECOVERY_DAYS)
			elif outcome == "relief":
				var left := GameState.RECOVERY_DAYS - GameState.treatment_streak
				hud.show_dialogue(npc_name, "A strip under the tongue. \"%s\"" % ("Day %d. %d more after today. Keep your head down tonight." % [GameState.treatment_streak + 1, left - 1] if left > 1 else "Last one. Get some sleep. I mean it."))
			else:
				hud.show_dialogue(npc_name, "It doesn't sit right. \"...Okay. Sit down. Breathe. I've got you.\"")
		2:
			if not GameState.daily_available("shelter_strips", true):
				hud.show_dialogue(npc_name, "\"I gave you some this morning. Use them -- that's what they're for.\"")
				return
			GameState.test_strips += 2
			hud.show_dialogue(npc_name, "Two strips in a little baggie. \"Dissolve a few grains in water, dip it, wait. One line means fentanyl. It won't tell you how much. Use less, go slow, don't use alone.\"")
		3:
			hud.show_dialogue(npc_name, TALK.pick_random())
