extends "res://world/WorldRoot3D.gd"

# Each layout is 6 floor spots (x, z), index-matched to `clutter`. Kept clear
# of the mattress, couch, phone crate, TV, both spawn points, and the door.
# The chair and box stack have collision; that's fine to move because this
# runs before WorldRoot3D bakes the navmesh.
const CLUTTER_LAYOUTS := [
	[Vector2(1.2, 1.0), Vector2(2.6, -3.0), Vector2(-2.8, -2.8), Vector2(0.5, 2.6), Vector2(-2.6, 2.9), Vector2(-3.1, -0.4)],
	[Vector2(-0.3, 2.2), Vector2(1.0, -3.0), Vector2(2.8, 2.6), Vector2(-2.6, -2.9), Vector2(1.8, 0.4), Vector2(-3.0, 0.0)],
	[Vector2(2.4, 1.9), Vector2(-2.8, -3.0), Vector2(0.6, -2.7), Vector2(-2.0, 2.6), Vector2(3.4, 2.9), Vector2(0.8, 1.0)],
]

const BULB_ENERGY := 1.8

@onready var clutter: Array = [$ChairOverturned, $BoxStack, $TrashA, $TrashB, $TrashC, $ClothesPile]
@onready var bulb_light: OmniLight3D = $BareBulb/Light
@onready var bulb_buzz: AudioStreamPlayer3D = $BareBulb/Buzz
@onready var bulb_crackle: AudioStreamPlayer3D = $BareBulb/Crackle

var _buzz_db: float

var _flicker_timer: float = 0.0

func _ready() -> void:
	_randomize_clutter()
	var back := GameState.return_belongings_home()
	GameState._reconcile_belongings()
	refresh_belongings()
	super._ready()
	if GameState.intro_pending:
		GameState.intro_pending = false
		_wake_up.call_deferred()
	elif not back.is_empty():
		_say.call_deferred("You put %s back where it goes." % ", ".join(back.map(func(id): return GameState.item_name_for(id))))
	elif not GameState.apartment_echo_seen and GameState.belongings_away() >= 3:
		GameState.apartment_echo_seen = true
		_say.call_deferred("The room echoes now. You can see the marks on the floor where things used to stand.")
	_buzz_db = bulb_buzz.volume_db
	$RentSlot.interacted.connect(_on_rent_slot)
	GameState.rent_changed.connect(_on_rent_changed)
	GameState.day_changed.connect(_on_day_changed)
	_on_rent_changed()

func _on_day_changed(_day: int) -> void:
	_on_rent_changed()

## The notice on the door, and the landlord at it if you're too far behind.
func _on_rent_changed() -> void:
	$RentNotice.visible = GameState.rent_stage > 0 or GameState.day == GameState.rent_due_day
	if GameState.locked_out() and not _closing:
		_closing = true
		var hud := get_tree().get_first_node_in_group("hud")
		var player := get_tree().get_first_node_in_group("player")
		if hud and player:
			player.dialogue_active = true
			hud.show_dialogue("", "Pounding on the door. \"I told you. Out. Lock's being changed today.\"")
		get_tree().create_timer(CLOSING_GRACE).timeout.connect(_show_out)

func _on_rent_slot(_zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if not GameState.rent_payable():
		hud.show_dialogue("", "Paid through day %d. Nothing to put through the slot till then." % GameState.rent_due_day)
	elif GameState.pay_rent():
		SFX.play("cash")
		hud.show_dialogue("", "You count it twice and push the envelope through the slot. Paid through day %d." % GameState.rent_due_day)
	else:
		hud.show_dialogue("", "$%d. You've got $%d. The slot just looks at you." % [GameState.rent_amount(), GameState.cash])

## Shows each belonging's prop only while it's at home, and only lets you
## take what's actually there.
func refresh_belongings() -> void:
	for zone in find_children("Belonging_*", "Area3D", false, false):
		var home: bool = GameState.belongings.get(zone.belonging_id, "home") == "home"
		var prop := zone.get_node_or_null(zone.prop_path) as Node3D
		if prop:
			prop.visible = home
			prop.process_mode = Node.PROCESS_MODE_INHERIT if home else Node.PROCESS_MODE_DISABLED
			# The TV's static goes with it (its glow goes dark with the set).
			for sound in prop.find_children("*", "AudioStreamPlayer3D"):
				sound.playing = home
		if home:
			zone.add_to_group("interactable")
		else:
			zone.remove_from_group("interactable")

func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player and not player.dialogue_active:
		player.dialogue_active = true
		hud.show_dialogue("", text)

## The first morning of a run: the opening cutscene, then a nudge toward
## the one thing in here that makes the day bearable.
func _wake_up() -> void:
	GameState.log_event("Woke up sick on the mattress.", "intro_sick")
	await Cutscene.play("intro")
	if GameState.has_walkman or not is_inside_tree():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	var player := get_tree().get_first_node_in_group("player")
	if hud and player:
		player.dialogue_active = true
		hud.show_dialogue("", "Your head's pounding and it's too quiet in here. The walkman's still where you dropped it last night, at the foot of the mattress.")

func _randomize_clutter() -> void:
	var layout: Array = CLUTTER_LAYOUTS.pick_random()
	for i in range(clutter.size()):
		var spot: Vector2 = layout[i]
		clutter[i].position.x = spot.x
		clutter[i].position.z = spot.y

## The bare bulb mostly holds steady, then every so often browns out for a
## split second, like it's on bad wiring.
func _process(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer > 0.0:
		return
	if randf() < 0.15:
		bulb_light.light_energy = BULB_ENERGY * randf_range(0.2, 0.55)
		bulb_buzz.volume_db = _buzz_db - 12.0
		bulb_crackle.pitch_scale = randf_range(0.8, 1.2)
		bulb_crackle.play()
		_flicker_timer = randf_range(0.04, 0.12)
	else:
		bulb_light.light_energy = BULB_ENERGY
		bulb_buzz.volume_db = _buzz_db
		_flicker_timer = randf_range(0.3, 2.0)
