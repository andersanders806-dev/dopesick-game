extends "res://world/WorldRoot3D.gd"
## After a bust: booked into a holding cell. You can wait it out on the bench
## (hours pass, and the withdrawal gets worse), knock, or press the intercom
## -- or just sit tight until they come for you. Then the door slides open
## and you walk out past the booking desk.

const RELEASE_AFTER := 25.0
const WAIT_CRAVING_COST := 30.0

@onready var cell_door: StaticBody3D = $CellDoor
@onready var knock_zone: Area3D = $CellDoor/CellDoorKnock
@onready var bench: Area3D = $Bench
@onready var intercom: Area3D = $Intercom
@onready var jailer: Node3D = $Jailer

var released: bool = false
var _release_timer: float = RELEASE_AFTER

func _ready() -> void:
	super._ready()
	GameState.in_custody = false
	for zone in [knock_zone, bench, intercom]:
		zone.interacted.connect(interact_zone)
	_intro.call_deferred()

func _intro() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", "Booked. Printed. Photographed against the height chart. Everything you were carrying is evidence now, and so is half your cash. The door slams. Now you wait.")

func _process(delta: float) -> void:
	if released:
		return
	_release_timer -= delta
	if _release_timer <= 0.0:
		release("\"Hey. You. Up.\" The door grinds open. \"You're free to go.\"")

## The bench, cell door, and intercom are Interactable3D triggers; what using
## them does lives here.
func interact_zone(zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	match zone.name:
		"Bench":
			if released:
				hud.show_dialogue("", "You're not staying here a minute longer than you have to.")
				return
			SFX.play("sleep")
			GameState.craving = maxf(0.0, GameState.craving - WAIT_CRAVING_COST)
			GameState.craving_changed.emit(GameState.craving)
			release("You lie down on the plastic mattress and stare at the light. Hours crawl by. The sickness creeps in, cramps and cold sweat. Eventually the door grinds open. \"You're free to go.\"")
		"CellDoorKnock":
			if released:
				hud.show_dialogue("", "The door's open.")
			else:
				SFX.play("door", -6.0, 0.6)
				hud.show_dialogue("", "You bang on the steel door. Nobody comes any faster for it.")
		"Intercom":
			SFX.play("blip")
			hud.show_dialogue("Intercom", "\"...What.\" A long pause. \"Sit down. You'll be out when you're out.\"")

func release(message: String) -> void:
	if released:
		return
	released = true
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", message)
	SFX.play("door", 0.0, 0.5)
	var tween := create_tween()
	tween.tween_property(cell_door, "position:z", cell_door.position.z - 1.0, 1.2)
	# The navmesh was baked with the door shut; open the way out of the cell.
	tween.finished.connect(_bake_navigation)
