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
	var options := ["Take a naloxone kit", "Ask about treatment (buprenorphine)", "Just talk"]
	var disabled := []
	if not GameState.daily_available("shelter_naloxone"):
		disabled.append(0)
	if not GameState.daily_available("shelter_bupe"):
		disabled.append(1)
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
			var outcome := GameState.take_drug("bupe")
			if outcome == "relief":
				hud.show_dialogue(npc_name, "A strip under the tongue, and you wait while it dissolves. The sickness backs off, slowly, and doesn't come roaring back. \"Same time tomorrow. That's all it takes. One day.\"")
			else:
				hud.show_dialogue(npc_name, "It doesn't sit right. \"...Okay. Sit down. Breathe. I've got you.\"")
		2:
			hud.show_dialogue(npc_name, TALK.pick_random())
