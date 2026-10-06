extends Area3D
## One of your own things in the apartment. Using it asks whether you're
## taking it to sell; the apartment (world/Apartment3D.gd) shows or hides
## the prop it belongs to.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const LINES := {
	"tv": "The TV. Mostly static these days, but it's company at four in the morning.",
	"radio": "The old radio. It only gets the one station.",
	"guitar": "Your guitar. You used to play it every night. The low E is still in tune.",
	"coat": "Your winter coat, on its hook. It's not cold yet.",
	"ring": "Your mother's ring, in its little box. You promised her you'd never sell it.",
}

@export var belonging_id: String = ""
@export var prop_path: NodePath

func _ready() -> void:
	add_to_group("interactable")

func interact(player: Node) -> void:
	if GameState.belongings.get(belonging_id, "") != "home":
		return
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int):
		if is_instance_valid(player):
			player.dialogue_active = false
		if i == 0:
			take())
	menu.cancelled.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	menu.open("", LINES.get(belonging_id, ""), ["Take it to sell", "Leave it"])

func take() -> void:
	GameState.take_belonging(belonging_id)
	SFX.play("steal")
	var room := get_tree().current_scene
	if room and room.has_method("refresh_belongings"):
		room.refresh_belongings()
