extends Area3D

const PORTRAITS := {
	"Bartender": preload("res://assets/portraits/bartender.png"),
	"Wiry Guy": preload("res://assets/portraits/wiry_guy.png"),
	"Tired Woman": preload("res://assets/portraits/tired_woman.png"),
	"Big Eddie": preload("res://assets/portraits/big_eddie.png"),
	"Quiet Kid": preload("res://assets/portraits/quiet_kid.png"),
	"Old Sailor": preload("res://assets/portraits/old_sailor.png"),
	"Nervous Dave": preload("res://assets/portraits/nervous_dave.png"),
}

@export var npc_name: String = "Stranger"
@export var is_patron: bool = false
@export_multiline var flavor_lines: String = "..."
@export var model_path: String = "res://assets/kenney/characters/character-male-b.glb"

@onready var model_root: Node3D = $ModelRoot

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")

var anim: CharacterAnimator

var request_id: String = ""
var request_price: int = 0
var fulfilled: bool = false

func _ready() -> void:
	add_to_group("interactable")
	set_model(model_path)

## Swappable after _ready() so a room script can re-skin a patron -- child
## nodes are ready before their parent room, so the default model is already
## in place by the time DiveBar3D randomizes who shows up.
func set_model(path: String) -> void:
	model_path = path
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	anim = null
	if path != "":
		var model: Node = load(path).instantiate()
		model_root.add_child(model)
		anim = CharacterAnimator.new(model)

func set_request(id: String, price: int) -> void:
	request_id = id
	request_price = price
	fulfilled = false

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	SFX.play("blip")

	if is_patron:
		_patron_interact(hud)
	else:
		_flavor_interact(hud)

func _portrait() -> Texture2D:
	return PORTRAITS.get(npc_name)

func _patron_interact(hud: Node) -> void:
	if request_id == "":
		hud.show_dialogue(npc_name, "Not looking for anything right now.", _portrait())
		return
	if fulfilled:
		hud.show_dialogue(npc_name, "Thanks again for that.", _portrait())
		return
	if GameState.has_item(request_id):
		GameState.sell_item(request_id, request_price)
		fulfilled = true
		SFX.play("cash")
		hud.show_dialogue(npc_name, "That's exactly it. Here's $%d." % request_price, _portrait())
	else:
		var item_name := GameState.item_name_for(request_id)
		hud.show_dialogue(npc_name, "I need %s. Get it for me and I'll pay $%d." % [item_name, request_price], _portrait())

func _flavor_interact(hud: Node) -> void:
	if not GameState.inventory.is_empty():
		var earned := GameState.fence_everything()
		SFX.play("cash")
		hud.show_dialogue(npc_name, "I'll take that off your hands. Here's $%d, no questions." % earned, _portrait())
		return
	var lines := flavor_lines.split("\n", false)
	if lines.is_empty():
		hud.show_dialogue(npc_name, "...", _portrait())
		return
	hud.show_dialogue(npc_name, lines[randi() % lines.size()], _portrait())
