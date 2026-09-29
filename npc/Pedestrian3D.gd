extends Area3D
## Someone walking the block: in one end of the street, out the other. They
## make the City feel lived in and give it a daytime/nighttime rhythm (the
## City spawns more by day). Talk to one and you're panhandling: now and
## then someone gives you a dollar or two, mostly they don't.
##
## Built entirely in code by City3D.gd -- there's no scene for it.

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")

const TURN_SPEED := 8.0
## How near you can get before they step around you.
const PERSONAL_SPACE := 1.1
const GIVE_CHANCE_DAY := 0.3
const GIVE_CHANCE_NIGHT := 0.12
const BRUSH_OFFS := [
	"They walk past like you aren't there.",
	"\"Sorry, no cash.\" They don't slow down.",
	"They look at the ground and speed up.",
	"\"Get a job.\"",
	"A shake of the head. Headphones stay in.",
]

## In the rain, some duck under the nearest shop awning and wait it out.
const AWNING_X := [-24.5, -17.5, -10.5, -3.5, 3.5, 10.5, 17.5, 24.5]
const SHELTER_Z := -4.0
const SHELTER_CHANCE := 0.5

signal left_street

var speed: float = 1.3
var lane_z: float = 0.0
## +1 walking east, -1 walking west.
var direction: float = 1.0
var end_x: float = 30.0
var look_index: int = 0

var anim: CharacterAnimator
var _model_root: Node3D
var _asked: bool = false
var _dodge: float = 0.0
## "" walking; "in" heading under an awning; "waiting" under it; "out" back to the lane.
var _shelter: String = ""
var _shelter_x: float = 0.0
var _shelter_wait: float = 0.0
var _passed_awning: float = INF

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("pedestrians")
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 1.2
	shape.shape = cyl
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	_model_root = Node3D.new()
	_model_root.scale = Vector3.ONE * 1.5
	add_child(_model_root)
	var entry: Dictionary = CharacterCast.PASSERSBY[look_index % CharacterCast.PASSERSBY.size()]
	var model: Node = load(entry["model"]).instantiate()
	_model_root.add_child(model)
	CharacterLook.apply(model, entry["look"])
	anim = CharacterAnimator.new(model)
	_model_root.rotation.y = atan2(direction, 0.0)

func _physics_process(delta: float) -> void:
	if _update_shelter(delta):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	# Step around you rather than through you: drift off the lane while
	# you're in the way, then back onto it.
	var target_dodge := 0.0
	if player:
		var ahead := (player.global_position.x - global_position.x) * direction
		if ahead > -0.3 and ahead < 2.0 and absf(player.global_position.z - (lane_z + _dodge)) < PERSONAL_SPACE:
			target_dodge = 1.2 if player.global_position.z < lane_z else -1.2
	_dodge = move_toward(_dodge, target_dodge, 1.5 * delta)
	global_position.x += direction * speed * delta
	global_position.z = lane_z + _dodge
	anim.update(speed)
	if (direction > 0.0 and global_position.x > end_x) or (direction < 0.0 and global_position.x < -end_x):
		left_street.emit()
		queue_free()

## Returns true while the rain has them off their lane.
func _update_shelter(delta: float) -> bool:
	match _shelter:
		"":
			if not GameState.raining:
				return false
			for ax: float in AWNING_X:
				# Once per awning, as they come level with it.
				if absf(global_position.x - (ax + 1.6)) < 0.15 and _passed_awning != ax:
					_passed_awning = ax
					if randf() < SHELTER_CHANCE:
						_shelter = "in"
						_shelter_x = ax + 1.6 + randf_range(-0.3, 0.3)
						_shelter_wait = randf_range(15.0, 35.0)
			return false
		"in":
			if _step_to(Vector3(_shelter_x, 0, SHELTER_Z), delta):
				_shelter = "waiting"
				_model_root.rotation.y = 0.0
		"waiting":
			anim.update(0.0)
			_shelter_wait -= delta
			if not GameState.raining or _shelter_wait <= 0.0:
				_shelter = "out"
		"out":
			if _step_to(Vector3(global_position.x + direction * 0.8, 0, lane_z), delta):
				_shelter = ""
				_model_root.rotation.y = atan2(direction, 0.0)
	return true

func _step_to(target: Vector3, delta: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.08:
		return true
	var step := to.normalized() * speed * delta
	global_position += step if step.length() < to.length() else to
	_model_root.rotation.y = atan2(to.x, to.z)
	anim.update(speed)
	return false

func interact(player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	player.dialogue_active = true
	if _asked:
		hud.show_dialogue("", "You already asked. They're walking faster now.")
		return
	_asked = true
	var chance := GIVE_CHANCE_DAY if GameState.daylight() > 0.5 else GIVE_CHANCE_NIGHT
	if randf() < chance:
		var amount := randi_range(1, 3)
		GameState.cash += amount
		GameState.cash_changed.emit(GameState.cash)
		SFX.play("cash", -10.0, 1.1)
		hud.show_dialogue("", "They stop, dig in a pocket, and hand you $%d without meeting your eyes." % amount)
	else:
		hud.show_dialogue("", BRUSH_OFFS.pick_random())
