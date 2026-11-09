extends Area3D
## E on a HingedDoor3D: the player's reach to it. A door you walk through
## shows no prompt; a locked one says so, by the crosshair (ui/Prompts.gd).

var door: Node3D

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if door == null:
		return
	if door.locked:
		door.rattle()
		return
	door.push_open((player as Node3D).global_position)

func prompt_text() -> String:
	return "Locked door" if door != null and door.locked else ""
