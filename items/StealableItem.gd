extends Area2D

@export var item_id: String = "whiskey"
@export var theft_window: float = 1.0

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	GameState.steal_item(item_id)
	if player.has_method("begin_theft_window"):
		player.begin_theft_window(theft_window)
	queue_free()
