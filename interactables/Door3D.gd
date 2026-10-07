extends Area3D

const ChoiceMenu := preload("res://ui/ChoiceMenu.gd")

@export var target_scene: String = ""
@export var target_spawn: String = ""

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("doors")

func interact(player: Node) -> void:
	if target_scene == "":
		return
	if target_scene.ends_with("Apartment3D.tscn") and GameState.locked_out():
		_locked_out(player)
		return
	var place := GameState.place_for_scene(target_scene)
	if place != "" and not GameState.is_open(place):
		_show_closed(player, place)
		return
	SFX.play("door")
	GameState.pending_spawn = target_spawn
	SceneLoader.go(target_scene, target_spawn)

func _show_closed(player: Node, place: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	SFX.play("latch", -4.0)
	player.dialogue_active = true
	var name: String = "the bar" if place == "bar" else GameState.STORE_NAMES.get(place, "it")
	hud.show_dialogue("", "Locked. %s opens at %02d:00. It's %s." % [name.left(1).to_upper() + name.substr(1), GameState.opening_hour(place), GameState.clock_text()])

## Behind on the rent long enough that the lock's been changed: buzz the
## landlord and pay everything, or walk away.
func _locked_out(player: Node) -> void:
	SFX.play("latch", -4.0)
	player.dialogue_active = true
	var awake := GameState.hours_contain(GameState.LANDLORD_HOURS, GameState.hour())
	var owed := GameState.rent_amount()
	var disabled := [] if awake and GameState.cash >= owed else [0]
	var menu: CanvasLayer = ChoiceMenu.new()
	get_tree().root.add_child(menu)
	menu.chosen.connect(func(_i: int): _pay_landlord(player))
	menu.cancelled.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false)
	var text := "Your key doesn't turn. A new lock, and a notice taped over it: $%d to the landlord, locksmith included." % owed
	if not awake:
		text += " His window's dark."
	menu.open("", text, ["Buzz the landlord -- pay $%d" % owed], disabled)

func _pay_landlord(player: Node) -> void:
	if not GameState.pay_rent():
		return
	SFX.play("cash")
	if is_instance_valid(player):
		player.dialogue_active = false
	interact(player)
