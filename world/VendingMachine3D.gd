extends StaticBody3D
## A lit vending machine against the wall by the apartment door: the one
## place on the block that always sells food, and bandages behind the snacks
## (autoload/Survival.gd). Built in code, like the bar's slot machine.

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")

## [id, label, price, effect]
const STOCK := [
	{"id": "chips", "label": "Chips", "price": 2, "food": 18.0, "line": "A bag of salt-and-vinegar. You eat them walking."},
	{"id": "sandwich", "label": "Sandwich", "price": 5, "food": 50.0, "line": "Egg salad in a plastic wedge. It's food."},
	{"id": "coffee", "label": "Hot coffee", "price": 2, "rest": 18.0, "warm": 15.0, "line": "Too hot, too sweet, and your hands finally warm up."},
	{"id": "bandages", "label": "Bandages", "price": 4, "bandage": true, "line": "A first-aid strip pack. You tape yourself up in the reflection of the glass."},
]

func _ready() -> void:
	name = "VendingMachine"
	var body := _mat(Color(0.12, 0.14, 0.2), 0.35)
	_box(Vector3(0.9, 1.9, 0.75), Vector3(0, 0.95, 0), body)
	# The lit window full of rows, and the selection panel beside it.
	_box(Vector3(0.58, 1.2, 0.02), Vector3(-0.1, 1.15, 0.38), _mat(Color(0.85, 0.92, 1.0), 0.2, 1.4))
	for row in 5:
		for col in 4:
			var c: Color = [Color(1, 0.3, 0.2), Color(1, 0.8, 0.2), Color(0.3, 0.8, 0.4), Color(0.9, 0.9, 0.95)][(row + col) % 4]
			_box(Vector3(0.1, 0.13, 0.04), Vector3(-0.32 + col * 0.145, 0.68 + row * 0.22, 0.4), _mat(c, 0.6, 0.3))
	_box(Vector3(0.18, 0.5, 0.02), Vector3(0.32, 1.25, 0.38), _mat(Color(0.05, 0.05, 0.06), 0.4))
	_box(Vector3(0.12, 0.08, 0.02), Vector3(0.32, 1.42, 0.395), _mat(Color(0.2, 1.0, 0.4), 0.4, 2.0))
	_box(Vector3(0.6, 0.16, 0.04), Vector3(-0.1, 0.32, 0.38), _mat(Color(0.03, 0.03, 0.04), 0.5))
	var sign := Label3D.new()
	sign.text = "SNACKS · DRINKS · FIRST AID"
	sign.font_size = 40
	sign.pixel_size = 0.0017
	sign.modulate = Color(1.0, 0.95, 0.85)
	sign.outline_size = 6
	add_child(sign)
	sign.position = Vector3(0, 1.82, 0.38)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.9, 0.75)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.75, 0.85, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 2.6
	add_child(glow)
	glow.position = Vector3(0, 1.3, 0.8)
	var zone := Area3D.new()
	zone.name = "VendingZone"
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.position = Vector3(0, 0, 0.9)
	var zshape := CollisionShape3D.new()
	var zbox := BoxShape3D.new()
	zbox.size = Vector3(1.2, 1.4, 1.0)
	zshape.shape = zbox
	zshape.position = Vector3(0, 0.7, 0)
	zone.add_child(zshape)
	zone.interacted.connect(_on_use)

func _on_use(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var options: Array = STOCK.map(func(s): return "%s  -  $%d" % [s["label"], s["price"]])
	var disabled := []
	for i in STOCK.size():
		if GameState.cash < STOCK[i]["price"]:
			disabled.append(i)
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(i: int): buy(i, player))
	menu.cancelled.connect(func(): player.dialogue_active = false)
	menu.open("Vending machine", "The glass hums. Half the rows are empty; the coin slot's been jimmied and fixed twice.", options, disabled)

## Buys STOCK[i] and uses it on the spot. False if you can't afford it.
func buy(i: int, player: Node = null) -> bool:
	var s: Dictionary = STOCK[i]
	if not GameState.spend_cash(s["price"]):
		return false
	if s.has("food"):
		Survival.eat(s["food"])
	if s.has("rest"):
		Survival.refresh(s["rest"])
	if s.has("warm"):
		Survival.warm(s["warm"])
	if s.get("bandage", false):
		Survival.bandage()
	SFX.play("cash", -8.0)
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud and player:
		hud.show_dialogue("", s["line"])
	elif player:
		player.dialogue_active = false
	return true

func _mat(col: Color, rough: float, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
