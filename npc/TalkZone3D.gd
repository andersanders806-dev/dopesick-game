extends Area3D

@export var npc_name: String = "Stranger"
@export_multiline var flavor_lines: String = "..."
@export var portrait_path: String = ""

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")

	var portrait: Texture2D = null
	if portrait_path != "":
		portrait = load(portrait_path)

	var lines := flavor_lines.split("\n", false)
	var line := "..." if lines.is_empty() else lines[randi() % lines.size()]
	hud.show_dialogue(npc_name, line, portrait)
