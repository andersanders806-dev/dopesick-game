extends Area2D

const ICONS := {
	"whiskey": preload("res://assets/sprites/item_whiskey_icon.png"),
	"cigs": preload("res://assets/sprites/item_cigs_icon.png"),
	"charger": preload("res://assets/sprites/item_charger_icon.png"),
	"batteries": preload("res://assets/sprites/item_batteries_icon.png"),
	"watch": preload("res://assets/sprites/item_watch_icon.png"),
}

@export var item_id: String = "whiskey"
@export var theft_window: float = 1.0

@onready var sprite: Sprite2D = $Sprite

func _ready() -> void:
	add_to_group("interactable")
	set_item_id(item_id)

func set_item_id(id: String) -> void:
	item_id = id
	if ICONS.has(id):
		sprite.texture = ICONS[id]

func interact(player: Node) -> void:
	SFX.play("steal")
	GameState.steal_item(item_id)
	if player.has_method("begin_theft_window"):
		player.begin_theft_window(theft_window)
	queue_free()
