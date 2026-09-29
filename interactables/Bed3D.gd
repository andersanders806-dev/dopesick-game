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
	var streak_before := GameState.treatment_streak
	GameState.sleep()
	if GameState.recovered():
		# Five clean days: the good ending, from the run-end screen.
		GameState.end_run("recovered")
		return
	await Cutscene.play("new_day", [GameState.day])
	SaveGame.save()
	var line := "You black out... and wake up again. Day %d, %s." % [GameState.day, GameState.clock_text()]
	if GameState.in_treatment:
		if GameState.treatment_streak > streak_before:
			line += "\n%d of %d clean days. It doesn't feel like much. It is." % [GameState.treatment_streak, GameState.RECOVERY_DAYS]
		else:
			line += "\nYesterday didn't count. The count starts over -- but you're still in the program."
	hud.show_dialogue("", line)
