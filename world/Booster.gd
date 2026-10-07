extends Node3D
## Tasha, on the days she's out (GameState "Tasha"): leaning by the door of
## whichever store she's casing this hour. Talk to her and you can team up
## -- she works a clerk for you and takes half your next order -- or give
## her up to the beat cop, which the street doesn't forget.

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")
## Each store's door along the block (build_rooms_3d.gd's city). She stands
## 1.6 m east of it, clear of the door's own "E".
const STORE_X := {"pharmacy": -10.5, "convenience": 3.5, "liquor": 10.5, "supermarket": 17.5, "electronics": 24.5}
const STAND_Z := -3.4

var npc: Area3D

func _ready() -> void:
	_build()
	GameState.booster_changed.connect(refresh)
	GameState.clock_changed.connect(_on_clock)
	refresh()

func _build() -> void:
	npc = Area3D.new()
	npc.name = "Tasha"
	npc.collision_layer = 4
	npc.collision_mask = 0
	npc.monitoring = false
	npc.set_script(InteractableScript)
	add_child(npc)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 1.4
	shape.shape = cyl
	shape.position = Vector3(0, 0.7, 0)
	npc.add_child(shape)
	var root := Node3D.new()
	root.scale = Vector3.ONE * 1.5
	# Side-on to the street, one eye on the door.
	root.rotation_degrees.y = -70.0
	npc.add_child(root)
	var model: Node = CharacterCast.scene_for(CharacterCast.model_for("booster")).instantiate()
	root.add_child(model)
	CharacterCast.dress(model, "booster")
	var anim := CharacterAnimator.new(model)
	npc.set_meta("anim", anim)
	npc.interacted.connect(_on_talk)

func _on_clock(_minute: int) -> void:
	refresh()

func refresh() -> void:
	var here: bool = GameState.booster_present() and GameState.booster_store != ""
	npc.visible = here
	if here:
		npc.position = Vector3(STORE_X[GameState.booster_store] + 1.6, 0, STAND_Z)
		npc.add_to_group("interactable")
	else:
		npc.remove_from_group("interactable")

func _on_talk(_zone: Area3D, player: Node) -> void:
	player.dialogue_active = true
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(_on_choice.bind(player))
	menu.cancelled.connect(_release.bind(player))
	var text := "\"Don't look at me like that. Rent's rent.\" She's watching the %s door." % GameState.STORE_NAMES[GameState.booster_store].trim_prefix("the ")
	menu.open("Tasha", text, ["Team up -- she works a clerk, she takes half your next order", "Rat her out to the beat cop", "Leave her be"], [0] if GameState.booster_team != "" else [])

func _on_choice(i: int, player: Node) -> void:
	match i:
		0:
			var menu: CanvasLayer = ChoiceMenu.new()
			get_tree().root.add_child(menu)
			var stores: Array = GameState.BOOSTER_STORES
			menu.chosen.connect(func(k: int):
				GameState.booster_team_up(stores[k])
				_say(player, "Tasha", "\"%s, then. Give me ten minutes with him.\"" % GameState.STORE_NAMES[stores[k]].capitalize()))
			menu.cancelled.connect(_release.bind(player))
			menu.open("Tasha", "\"Which one?\"", stores.map(func(s): return GameState.STORE_NAMES[s].capitalize()))
		1:
			GameState.booster_rat()
			_say(player, "", "You catch the cop's eye and tip your head at her. He's already walking.")
		_:
			_release(player)

func _say(player: Node, speaker: String, line: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and is_instance_valid(player):
		player.dialogue_active = true
		hud.show_dialogue(speaker, line)
	else:
		_release(player)

func _release(player: Node) -> void:
	if is_instance_valid(player):
		player.dialogue_active = false
