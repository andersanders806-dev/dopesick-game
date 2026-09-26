extends Area3D

@export var target_scene: String = ""
@export var target_spawn: String = ""

func _ready() -> void:
	add_to_group("interactable")

## Where this door goes, for the "[E] ..." prompt.
const DESTINATIONS := {
	"City3D": "Go out to the street",
	"Apartment3D": "Go home",
	"DiveBar3D": "Enter the Dive Bar",
	"StorePharmacy3D": "Enter the pharmacy",
	"StoreConvenience3D": "Enter the corner shop",
	"StoreLiquor3D": "Enter the liquor store",
	"StoreSupermarket3D": "Enter the supermarket",
	"StoreElectronics3D": "Enter the electronics store",
	"Jail3D": "Enter the police station",
}

func prompt_text() -> String:
	return DESTINATIONS.get(target_scene.get_file().get_basename(), "Open door")

func interact(_player: Node) -> void:
	if target_scene == "":
		return
	SFX.play("door")
	GameState.pending_spawn = target_spawn
	get_tree().change_scene_to_file(target_scene)
