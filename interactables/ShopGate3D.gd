extends Area3D
## The doorway of a walk-in shop (world/WalkInShop.gd) while it's shut: the
## Door3D answer -- "Locked. It opens at ..." -- for a door that isn't a door.

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var shop := get_parent()
	var place: String = shop.get_meta("place", "")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or place == "":
		return
	SFX.play("latch", -4.0)
	player.dialogue_active = true
	var name: String = GameState.STORE_NAMES.get(place, "it")
	hud.show_dialogue("", "Locked. %s opens at %02d:00. It's %s." % [name.left(1).to_upper() + name.substr(1), GameState.opening_hour(place), GameState.clock_text()])
