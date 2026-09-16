extends Area3D

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("phone")
	var cost := GameState.current_fix_cost()
	if GameState.buy_fix():
		SFX.play("fix")
		hud.show_dialogue("Pusher", "\"There you go, $%d. Don't spend it all in one place.\" You feel it hit." % cost)
	else:
		hud.show_dialogue("Pusher", "\"Cash first, then we talk.\" (need $%d)" % cost)
