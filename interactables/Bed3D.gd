extends Area3D

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if GameState.wanted:
		SFX.play("blip")
		hud.show_dialogue("", "Too wired to sleep. Cops are still looking for you.")
		return
	GameState.sleep()
	await Cutscene.play("new_day", [GameState.day])
	SaveGame.save()
	hud.show_dialogue("", "You black out... and wake up again. Day %d, %s." % [GameState.day, GameState.clock_text()])
