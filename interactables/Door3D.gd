extends Area3D

@export var target_scene: String = ""
@export var target_spawn: String = ""

func _ready() -> void:
	add_to_group("interactable")

func interact(_player: Node) -> void:
	if target_scene == "":
		return
	SFX.play("door")
	GameState.pending_spawn = target_spawn
	get_tree().change_scene_to_file(target_scene)
