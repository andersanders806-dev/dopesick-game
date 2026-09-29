extends Area3D

@export var target_scene: String = ""
@export var target_spawn: String = ""

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if target_scene == "":
		return
	var place := GameState.place_for_scene(target_scene)
	if place != "" and not GameState.is_open(place):
		_show_closed(player, place)
		return
	SFX.play("door")
	GameState.pending_spawn = target_spawn
	get_tree().change_scene_to_file(target_scene)

func _show_closed(player: Node, place: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	SFX.play("latch", -4.0)
	player.dialogue_active = true
	var name: String = "the bar" if place == "bar" else GameState.STORE_NAMES.get(place, "it")
	hud.show_dialogue("", "Locked. %s opens at %02d:00. It's %s." % [name.left(1).to_upper() + name.substr(1), GameState.opening_hour(place), GameState.clock_text()])
