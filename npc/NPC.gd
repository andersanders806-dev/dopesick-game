extends Area2D

@export var npc_name: String = "Stranger"
@export var is_patron: bool = false
@export_multiline var flavor_lines: String = "..."

@onready var sprite: Sprite2D = $Body

var request_id: String = ""
var request_price: int = 0
var fulfilled: bool = false

func _ready() -> void:
	add_to_group("interactable")

func set_request(id: String, price: int) -> void:
	request_id = id
	request_price = price
	fulfilled = false

func set_skin(texture: Texture2D) -> void:
	sprite.texture = texture

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true

	if is_patron:
		_patron_interact(hud)
	else:
		_flavor_interact(hud)

func _patron_interact(hud: Node) -> void:
	if request_id == "":
		hud.show_dialogue(npc_name, "Not looking for anything right now.")
		return
	if fulfilled:
		hud.show_dialogue(npc_name, "Thanks again for that.")
		return
	if GameState.has_item(request_id):
		GameState.sell_item(request_id, request_price)
		fulfilled = true
		hud.show_dialogue(npc_name, "That's exactly it. Here's $%d." % request_price)
	else:
		var item_name := GameState.item_name_for(request_id)
		hud.show_dialogue(npc_name, "I need %s. Get it for me and I'll pay $%d." % [item_name, request_price])

func _flavor_interact(hud: Node) -> void:
	if not GameState.inventory.is_empty():
		var earned := GameState.fence_everything()
		hud.show_dialogue(npc_name, "I'll take that off your hands. Here's $%d, no questions." % earned)
		return
	var lines := flavor_lines.split("\n", false)
	if lines.is_empty():
		hud.show_dialogue(npc_name, "...")
		return
	hud.show_dialogue(npc_name, lines[randi() % lines.size()])
