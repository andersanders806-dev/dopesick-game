extends Area3D
## A plain "press E here" trigger that just reports being used, for things
## whose behaviour belongs to the room rather than the object (the jail
## bench, cell door, and intercom).

signal interacted(zone: Area3D, player: Node)

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	interacted.emit(self, player)
