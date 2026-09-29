extends Area3D
## The walkman and the shoebox of tapes on the mattress at home. Gone once
## you've picked it up (GameState.has_walkman) for the rest of the run.

func _ready() -> void:
	if GameState.has_walkman:
		queue_free()
		return
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	GameState.has_walkman = true
	GameState.log_event("Found the walkman and the shoebox of tapes.")
	SFX.play("steal", -4.0, 1.2)
	if hud:
		player.dialogue_active = true
		hud.show_dialogue("", "Your old walkman, the foam coming off the headphones, and the shoebox: %d tapes, the punk ones on top, worn thin. You clip it to your belt and the room gets a little further away.\n[T] pick a tape    [N] next / shuffle" % GameState.tapes.size())
	remove_from_group("interactable")
	queue_free()
