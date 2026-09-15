extends Area2D

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("phone")
	if GameState.buy_fix():
		SFX.play("fix")
		hud.show_dialogue("Pusher", "\"There you go. Don't spend it all in one place.\" You feel it hit.")
	else:
		hud.show_dialogue("Pusher", "\"Cash first, then we talk.\" (need $%d)" % GameState.FIX_COST)
